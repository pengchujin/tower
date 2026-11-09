import Foundation
import Darwin

/// Expands resource payloads into policy-free conditions. A provider's behavior
/// belongs to the resource, rather than being guessed by the output client.
enum RuleResourceContent {
    static func normalized(_ lines: [String], behavior: String? = nil) -> [String] {
        lines.map { raw in
            let line = RoutingRuleSyntax.removingComment(raw)
            if let fields = RoutingRuleSyntax.fields(line), fields.count >= 2 {
                let aliases = ["HOST": "DOMAIN", "HOST-SUFFIX": "DOMAIN-SUFFIX", "HOST-KEYWORD": "DOMAIN-KEYWORD", "HOST-WILDCARD": "DOMAIN-WILDCARD", "IP6-CIDR": "IP-CIDR6"]
                let type = fields[0].uppercased()
                // QuanX resources include an embedded policy; the binding's
                // policy overrides it, just as force-policy does in QuanX.
                let tail = fields.dropFirst(type.hasPrefix("HOST") ? 3 : 2)
                return ([aliases[type] ?? type, fields[1]] + tail).joined(separator: ",")
            }
            let value = RoutingRuleSyntax.unquote(line)
            let address = String(value.split(separator: "/", maxSplits: 1).first ?? "")
            var v4 = in_addr(), v6 = in6_addr()
            if inet_pton(AF_INET, address, &v4) == 1 { return "IP-CIDR,\(value)" }
            if inet_pton(AF_INET6, address, &v6) == 1 { return "IP-CIDR6,\(value)" }
            if behavior == "domain" || behavior == "domain-text" {
                if value.hasPrefix("+.") { return "DOMAIN-SUFFIX,\(value.dropFirst(2))" }
                if value.hasPrefix(".") { return "DOMAIN-SUFFIX,\(value.dropFirst())" }
                return "\(value.contains("*") || value.contains("?") ? "DOMAIN-WILDCARD" : "DOMAIN"),\(value)"
            }
            return line
        }.filter { !$0.isEmpty }
    }

    /// Whether a list is written the way a `domain` / `ipcidr` provider
    /// reads it: bare values (`+.example.com`, `203.0.113.0/24`), not typed
    /// rules (`DOMAIN-SUFFIX,example.com`). Declarations can be wrong —
    /// DustinWin's INI says `clash-domain:` for lists of typed rules — and
    /// mihomo then matches nothing from them (issue #50).
    static func isBare(_ lines: [String]) -> Bool {
        !lines.isEmpty && lines.allSatisfy { raw in
            let line = RoutingRuleSyntax.removingComment(raw).trimmingCharacters(in: .whitespaces)
            guard let fields = RoutingRuleSyntax.fields(line) else { return false }
            return fields.count < 2
        }
    }

    /// The provider declaration a list can honestly be referenced with:
    /// a `domain` / `ipcidr` declaration over typed rules becomes classical.
    /// Nil behavior lets the writer pick classical from the list's format.
    static func provider(_ declared: RuleProviderMetadata?, for lines: [String]) -> RuleProviderMetadata? {
        guard let declared, let behavior = declared.behavior?.lowercased(),
              ["domain", "ipcidr", "domain-text", "ipcidr-text"].contains(behavior),
              !lines.isEmpty, !isBare(lines) else { return declared }
        return RuleProviderMetadata(behavior: nil, format: declared.format, interval: declared.interval)
    }

    /// Surge rejects the whole profile when a rule carries an option its type
    /// does not take ("marked for pre-matching, but the rule type doesn't
    /// support this"), so a list's options reach only the lines that accept
    /// them (manual.nssurge.com/rules/overview.html).
    static let preMatchingTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD",
        "IP-CIDR", "IP-CIDR6", "GEOIP", "IP-ASN", "SRC-IP", "DEST-PORT", "SRC-PORT",
        "SUBNET", "CELLULAR-CARRIER", "CELLULAR-RADIO", "AND", "OR", "NOT"
    ]
    static let extendedMatchingTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "URL-REGEX"
    ]

    static func applying(_ options: [String], to line: String) -> String {
        guard let condition = RoutingRuleSyntax.condition(line) else { return line }
        let inherited = options.filter { option in
            switch RoutingRuleCapabilities.optionKey(option) {
            case "no-resolve": return ["IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP"].contains(condition.type)
            case "pre-matching": return preMatchingTypes.contains(condition.type)
            case "extended-matching": return extendedMatchingTypes.contains(condition.type)
            case "update-interval": return false
            default: return true
            }
        }.filter { !condition.options.contains($0) }
        return ([line] + inherited).joined(separator: ",")
    }
}
