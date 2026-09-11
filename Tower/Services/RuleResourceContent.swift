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

    static func applying(_ options: [String], to line: String) -> String {
        guard let condition = RoutingRuleSyntax.condition(line) else { return line }
        let inherited = options.filter { option in
            if option == "no-resolve" {
                return ["IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP"].contains(condition.type)
            }
            return !option.hasPrefix("update-interval=")
        }.filter { !condition.options.contains($0) }
        return ([line] + inherited).joined(separator: ",")
    }
}
