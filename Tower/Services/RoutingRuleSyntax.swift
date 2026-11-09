import Foundation
import Darwin

/// Rules are CSV at the top level, with quoted values and recursively nested
/// conditions. Keep options separate from the policy, including on FINAL.
enum RoutingRuleSyntax {
    struct Condition {
        var type: String
        var value: String
        var options: [String]
        var children: [Condition]?

        var body: String {
            let payload = children.map { "(" + $0.map { "(" + $0.body + ")" }.joined(separator: ",") + ")" } ?? value
            return ([type, payload] + options).joined(separator: ",")
        }
    }

    static let logical: Set<String> = ["AND", "OR", "NOT"]

    static func fields(_ text: String) -> [String]? {
        guard text.utf8.count <= 131_072, !text.contains("\n"), !text.contains("\r") else { return nil }
        var result: [String] = [], field = ""
        var quote: Character?, escaped = false, depth = 0
        for character in text {
            if escaped { field.append(character); escaped = false; continue }
            if character == "\\" { field.append(character); escaped = true; continue }
            if let active = quote {
                field.append(character)
                if character == active { quote = nil }
                continue
            }
            if character == "\"" || character == "'" { quote = character }
            if character == "(" { depth += 1; if depth > 64 { return nil } }
            if character == ")" { depth -= 1; if depth < 0 { return nil } }
            if character == ",", depth == 0 {
                result.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else { field.append(character) }
        }
        guard quote == nil, depth == 0 else { return nil }
        result.append(field.trimmingCharacters(in: .whitespaces))
        return result
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, ["\"", "'"].contains(first), value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }

    static func removingComment(_ text: String) -> String {
        let chars = Array(text)
        var quote: Character?, escaped = false
        for i in chars.indices {
            let c = chars[i]
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if let active = quote { if c == active { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c; continue }
            // Require a boundary so URL schemes, regex fragments and literal
            // semicolons remain part of the value rather than becoming comments.
            if i == 0 || chars[i - 1].isWhitespace {
                if c == "#" || c == ";" || (c == "/" && i + 1 < chars.count && chars[i + 1] == "/") {
                    return String(chars[..<i]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return text
    }

    static func condition(_ body: String, depth: Int = 0) -> Condition? {
        guard depth <= 10, let parts = fields(body), parts.count >= 2,
              !parts[1].isEmpty else { return nil }
        let type = parts[0].uppercased()
        guard type != "FINAL", type != "MATCH", !type.isEmpty else { return nil }
        var condition = Condition(type: type, value: parts[1], options: Array(parts.dropFirst(2)))
        if logical.contains(type) {
            guard parts[1].first == "(", parts[1].last == ")",
                  let branches = fields(String(parts[1].dropFirst().dropLast())),
                  !branches.isEmpty, type != "NOT" || branches.count == 1 else { return nil }
            var children: [Condition] = []
            for branch in branches {
                guard branch.first == "(", branch.last == ")",
                      let child = self.condition(String(branch.dropFirst().dropLast()), depth: depth + 1) else { return nil }
                children.append(child)
            }
            condition.children = children
        }
        return condition
    }
}

enum RoutingRuleCapabilities {
    static let mihomoTargets: Set<ClientTarget> = [.clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing]
    static let compiledTargets = mihomoTargets.union(surgeTargets).union([.clash, .loon, .shadowrocket])
    static let surgeTargets: Set<ClientTarget> = [.surge, .surgeMac]
    static let common: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP", "PROCESS-NAME", "SRC-PORT", "IN-PORT"]
    // UID is left out: mihomo implements it only on Linux and Android, and on
    // every other platform `uid rule not support this platform` fails the
    // whole profile. Tower's mihomo targets run on macOS, iOS and Windows.
    static let mihomo = common.union(["DOMAIN-REGEX", "GEOSITE", "IP-SUFFIX", "SRC-GEOIP", "SRC-IP-ASN", "SRC-IP-CIDR", "SRC-IP-SUFFIX", "DST-PORT", "NETWORK", "IN-TYPE", "IN-USER", "IN-NAME", "REMATCH-NAME", "PROCESS-PATH", "PROCESS-PATH-WILDCARD", "PROCESS-PATH-REGEX", "PROCESS-NAME-WILDCARD", "PROCESS-NAME-REGEX", "DSCP"])
    static let surge = common.union(["DOMAIN-SET", "RULE-SET", "DEST-PORT", "SRC-IP", "PROTOCOL", "USER-AGENT", "URL-REGEX", "SUBNET", "DEVICE-NAME", "MAC-ADDRESS", "HOSTNAME-TYPE", "CELLULAR-RADIO", "CELLULAR-CARRIER"])
    // stash.wiki/en/rules/rule-types. SRC-PORT and IN-PORT are not listed.
    static let stash: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "DOMAIN-REGEX", "GEOSITE", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP", "DST-PORT", "NETWORK", "PROTOCOL", "PROCESS-NAME", "PROCESS-PATH", "USER-AGENT", "URL-REGEX", "SRC-IP"]
    // nsloon.app/docs/Rule: domain, IP, HTTP, port (3.1.7+), protocol (3.1.7+)
    // and logical (3.1.7+) rules; DOMAIN-WILDCARD since build 1008 (3.5.3).
    // PROCESS-NAME, SRC-IP and SUBNET are not documented, so they are not
    // written.
    static let loon: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "IP-CIDR", "IP-CIDR6", "GEOIP", "IP-ASN", "URL-REGEX", "USER-AGENT", "SRC-PORT", "DEST-PORT", "PROTOCOL"]
    static let loonProtocols: Set<String> = ["HTTP", "HTTPS", "TCP", "QUIC", "STUN", "UDP"]
    // Shadowrocket has no official reference; this follows the maintained
    // manual (github.com/LOWERTOP/Shadowrocket, 规则类型). PROTOCOL is valid
    // only inside a logical rule, and the port rule is spelled DST-PORT.
    static let shadowrocket: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "USER-AGENT", "URL-REGEX", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP", "DST-PORT", "PROTOCOL"]
    static let surgeOptions: Set<String> = ["no-resolve", "dns-failed", "extended-matching", "pre-matching", "notification-text", "notification-interval", "always-capture", "update-interval"]
    /// Surge options that only change how or when a rule is evaluated, never
    /// what it matches, so a client without them can drop them and keep the
    /// rule. `extended-matching` also reads the HTTP Host header; mihomo and
    /// Stash match the sniffed host anyway.
    static let ignorableOptions: Set<String> = ["extended-matching", "pre-matching", "notification-text", "notification-interval", "always-capture"]

    static func optionKey(_ option: String) -> String {
        String(option.split(separator: "=", maxSplits: 1).first ?? "").lowercased()
    }

    static func allowedOptions(for target: ClientTarget) -> Set<String> {
        if surgeTargets.contains(target) { return surgeOptions }
        switch target {
        case .clash: return ["no-resolve", "no-track"]
        case .shadowrocket: return ["no-resolve", "extended-matching", "pre-matching"]
        case .loon: return ["no-resolve"]
        default: return ["no-resolve", "src"]
        }
    }

    static func optionsSupported(_ options: [String], target: ClientTarget) -> Bool {
        let allowed = allowedOptions(for: target)
        return options.allSatisfy { allowed.contains(optionKey($0)) }
    }

    /// The options in `options` the target will not receive but that can be
    /// dropped without changing what the rule matches.
    static func droppedOptions(_ options: [String], target: ClientTarget) -> [String] {
        let allowed = allowedOptions(for: target)
        return options.filter {
            let key = optionKey($0)
            return ignorableOptions.contains(key) && !allowed.contains(key)
        }
    }

    /// Every ignorable option a rule line would lose on `target`, including
    /// those on the children of a logical rule.
    static func droppedOptions(inRule body: String, target: ClientTarget) -> [String] {
        guard let condition = RoutingRuleSyntax.condition(body) else { return [] }
        func collect(_ condition: RoutingRuleSyntax.Condition) -> [String] {
            droppedOptions(condition.options, target: target) + (condition.children ?? []).flatMap(collect)
        }
        return collect(condition)
    }

    static func render(_ body: String, policy: String, target: ClientTarget) -> String? {
        guard let parsed = RoutingRuleSyntax.condition(body),
              let condition = convert(parsed, target: target) else { return nil }
        var options = condition.options
        // Preserve Tower's existing no-resolve protection on ordinary IP rules.
        if !options.contains("no-resolve"), !options.contains("src"),
           condition.type == "GEOIP" || (surgeTargets.contains(target) && ["IP-CIDR", "IP-CIDR6", "IP-ASN"].contains(condition.type)) {
            options.append("no-resolve")
        }
        var matcher = condition
        matcher.options = []
        return ([matcher.body, policy] + options).joined(separator: ",")
    }

    static func convert(_ original: RoutingRuleSyntax.Condition, target: ClientTarget, depth: Int = 0) -> RoutingRuleSyntax.Condition? {
        let isMihomo = mihomoTargets.contains(target)
        let isSurge = surgeTargets.contains(target)
        let isStash = target == .clash
        let isLoon = target == .loon
        let isShadowrocket = target == .shadowrocket
        guard isMihomo || isSurge || isStash || isLoon || isShadowrocket else { return nil }
        var result = original
        let dropped = droppedOptions(result.options, target: target)
        result.options.removeAll { dropped.contains($0) }
        if let children = original.children {
            guard !isSurge || depth < 10 else { return nil }
            let converted = children.compactMap { convert($0, target: target, depth: depth + 1) }
            guard converted.count == children.count else { return nil }
            result.children = converted
            guard optionsSupported(result.options, target: target) else { return nil }
            return result
        }
        if result.type == "IP6-CIDR" { result.type = "IP-CIDR6" }
        let value = RoutingRuleSyntax.unquote(result.value)
        // Only Surge documents quoting a comma inside a value; mihomo's CSV
        // parser splits it, and Stash, Loon and Shadowrocket say nothing.
        guard isSurge || !value.contains(",") else { return nil }
        if isMihomo {
            switch result.type {
            case "DEST-PORT": result.type = "DST-PORT"
            case "PROTOCOL":
                guard ["TCP", "UDP"].contains(value.uppercased()) else { return nil }
                result.type = "NETWORK"; result.value = value.uppercased()
            case "SRC-IP":
                guard let cidr = sourceCIDR(value) else { return nil }
                result.type = "SRC-IP-CIDR"; result.value = cidr
            case "PROCESS-NAME" where value.hasPrefix("/"):
                result.type = value.contains("*") || value.contains("?") || value.hasSuffix("/") ? "PROCESS-PATH-WILDCARD" : "PROCESS-PATH"
                if value.hasSuffix("/") { result.value = value + "*" }
            case "PROCESS-NAME" where value.contains("*") || value.contains("?"):
                result.type = "PROCESS-NAME-WILDCARD"
            default: break
            }
            guard mihomo.contains(result.type) else { return nil }
        } else if isStash {
            if result.type == "DEST-PORT" { result.type = "DST-PORT" }
            guard stash.contains(result.type) else { return nil }
        } else if isLoon || isShadowrocket {
            // Neither client has a source-address form of an IP rule.
            guard !result.options.contains("src") else { return nil }
            switch result.type {
            // `*.example.com` matches every subdomain but not example.com
            // itself, so it stays a suffix rule minus the apex (logical
            // rules, Loon 3.1.7+), which older Loon builds also read; a bare
            // suffix rule would also block or route the apex (CLAUDE.md #25).
            // Other patterns use DOMAIN-WILDCARD (build 1008+, Loon 3.5.3),
            // whose `*` and `?` match the whole host like Surge's glob.
            // Loon's `[...]` classes have no counterpart in the source
            // dialects, so a literal bracket is not passed through.
            case "DOMAIN-WILDCARD" where isLoon:
                if !value.contains("*") && !value.contains("?") {
                    result.type = "DOMAIN"
                } else if value.hasPrefix("*."), !value.dropFirst(2).contains(where: { $0 == "*" || $0 == "?" }) {
                    let apex = String(value.dropFirst(2))
                    let notApex = RoutingRuleSyntax.Condition(type: "NOT", value: "", options: [],
                        children: [.init(type: "DOMAIN", value: apex, options: [])])
                    return .init(type: "AND", value: "", options: result.options,
                        children: [.init(type: "DOMAIN-SUFFIX", value: apex, options: []), notApex])
                } else if value.contains("[") || value.contains("]") {
                    return nil
                }
            case "DST-PORT", "DEST-PORT": result.type = isLoon ? "DEST-PORT" : "DST-PORT"
            case "NETWORK", "PROTOCOL":
                let name = value.uppercased()
                if isLoon {
                    guard loonProtocols.contains(name) else { return nil }
                } else {
                    guard depth > 0, ["TCP", "UDP"].contains(name) else { return nil }
                }
                result.type = "PROTOCOL"; result.value = name
            default: break
            }
            guard (isLoon ? loon : shadowrocket).contains(result.type) else { return nil }
        } else {
            if result.options.contains("src") {
                guard ["IP-CIDR", "IP-CIDR6"].contains(result.type) else { return nil }
                result.type = "SRC-IP"
                result.options.removeAll { ["src", "no-resolve"].contains($0) }
            }
            switch result.type {
            case "DST-PORT": result.type = "DEST-PORT"
            case "NETWORK":
                guard ["TCP", "UDP"].contains(value.uppercased()) else { return nil }
                result.type = "PROTOCOL"; result.value = value.uppercased()
            case "SRC-IP-CIDR": result.type = "SRC-IP"
            case "PROCESS-PATH", "PROCESS-PATH-WILDCARD":
                guard value.hasPrefix("/"), !value.hasSuffix("/") else { return nil }
                result.type = "PROCESS-NAME"
            case "PROCESS-NAME-WILDCARD": result.type = "PROCESS-NAME"
            default: break
            }
            guard surge.contains(result.type) else { return nil }
        }
        if ["RULE-SET", "DOMAIN-SET"].contains(result.type) {
            let builtin = result.type == "RULE-SET" && ["SYSTEM", "LAN"].contains(value)
            let remote = URL(string: value).map { ["https", "http"].contains($0.scheme ?? "") } ?? false
            guard isSurge && (builtin || remote) else { return nil }
        }
        guard optionsSupported(result.options, target: target) else { return nil }
        if ["DST-PORT", "DEST-PORT", "SRC-PORT", "IN-PORT"].contains(result.type) {
            guard let ranges = portRanges(value) else { return nil }
            if isSurge || isLoon || isShadowrocket, ranges.count > 1 {
                let children = ranges.map { RoutingRuleSyntax.Condition(type: result.type, value: $0, options: []) }
                return .init(type: "OR", value: "", options: result.options, children: children)
            }
            result.value = ranges.joined(separator: "/")
        }
        return result
    }

    private static func sourceCIDR(_ value: String) -> String? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        var v4 = in_addr(), v6 = in6_addr()
        let bits: Int
        if inet_pton(AF_INET, String(parts[0]), &v4) == 1 { bits = 32 }
        else if inet_pton(AF_INET6, String(parts[0]), &v6) == 1 { bits = 128 }
        else { return nil }
        if parts.count == 1 { return value + "/\(bits)" }
        guard let prefix = Int(parts[1]), (0...bits).contains(prefix) else { return nil }
        return value
    }

    static func portRanges(_ value: String) -> [String]? {
        var result: [String] = []
        for part in value.split(separator: "/", omittingEmptySubsequences: false) {
            let text = String(part)
            if let op = [">=", "<=", ">", "<"].first(where: text.hasPrefix),
               let port = Int(text.dropFirst(op.count)), (0...65535).contains(port) {
                let low = op.hasPrefix(">") ? port + (op == ">" ? 1 : 0) : 0
                let high = op.hasPrefix("<") ? port - (op == "<" ? 1 : 0) : 65535
                guard low <= high, low <= 65535, high >= 0 else { return nil }
                result.append("\(low)-\(high)")
            } else {
                let bounds = text.split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(bounds.count), bounds.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
                      let low = Int(bounds[0]), let high = Int(bounds.last!), (0...65535).contains(low), (low...65535).contains(high) else { return nil }
                result.append(text)
            }
        }
        return result.isEmpty ? nil : result
    }
}

enum RoutingBuiltinPolicies {
    static let common: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP"]
    static let mihomo: Set<String> = ["PASS", "PASS-RULE", "COMPATIBLE"]
    static let surge: Set<String> = ["REJECT-NO-DROP", "REJECT-TINYGIF", "CELLULAR", "CELLULAR-ONLY", "HYBRID", "NO-HYBRID"]
    /// Loon's 1x1 image reject (nsloon.app/docs/Policy), only ever written as
    /// the stand-in for Surge's REJECT-TINYGIF. Quantumult X has `reject-img`
    /// only as a rewrite action; its filters know `reject` alone and refuse
    /// the whole profile over an unknown policy.
    static let imageReject = "REJECT-IMG"
    static let canonical = common.union(mihomo).union(surge).union([imageReject])
    static let names = canonical.union(canonical.map { $0.lowercased() })

    static func supports(_ policy: String, target: ClientTarget) -> Bool {
        let name = policy.uppercased()
        if ["DIRECT", "REJECT"].contains(name) { return true }
        if name == "REJECT-DROP" { return target.usesClashFormat || [.surge, .surgeMac, .loon, .shadowrocket].contains(target) }
        if name == imageReject { return target == .loon }
        if mihomo.contains(name) { return RoutingRuleCapabilities.mihomoTargets.contains(target) }
        // Shadowrocket documents both of these rejects (LOWERTOP manual, 规则策略).
        if target == .shadowrocket, ["REJECT-NO-DROP", "REJECT-TINYGIF"].contains(name) { return true }
        if surge.contains(name) {
            return target == .surge || (target == .surgeMac && name.hasPrefix("REJECT-"))
        }
        return false
    }

    /// The closest built-in the target has for a Surge reject it lacks. The
    /// request is still refused; only the reply differs (an image, or an
    /// ICMP error instead of a drop). Nil when the target already supports
    /// the policy or no reject stands in for it.
    static func substitute(for policy: String, target: ClientTarget) -> String? {
        guard !supports(policy, target: target) else { return nil }
        switch policy.uppercased() {
        case "REJECT-TINYGIF":
            return target == .loon ? imageReject : "REJECT"
        case "REJECT-NO-DROP", "REJECT-DROP":
            return "REJECT"
        default:
            return nil
        }
    }
}

extension RoutingRuleCapabilities {
    /// sing-box logical rules keep the original expression tree, so an AND
    /// blocking UDP 443 never becomes a domain-wide reject.
    /// `localRuleSets` writes GEOIP and IP-ASN as references to inline rule
    /// sets (`localRuleSetDefinitions`) instead of repeating thousands of
    /// ranges at every use; DNS rules then share the same set.
    static func singBoxCondition(_ body: String, localRuleSets: Bool = false) -> [String: Any]? {
        guard let condition = RoutingRuleSyntax.condition(body) else { return nil }
        return singBoxCondition(condition, localRuleSets: localRuleSets)
    }

    static let localGeoIPPrefix = "tower-geoip-"
    static let localASNPrefix = "tower-asn-"

    /// Inline definitions for every local rule set tag referenced anywhere in
    /// `object` (route rules, DNS rules, nested logical rules).
    static func localRuleSetDefinitions(referencedIn object: Any) -> [[String: Any]] {
        var tags: [String] = []
        func scan(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let sets = dictionary["rule_set"] as? [String] {
                    tags += sets.filter { $0.hasPrefix(localGeoIPPrefix) || $0.hasPrefix(localASNPrefix) }
                }
                dictionary.values.forEach(scan)
            } else if let array = value as? [Any] {
                array.forEach(scan)
            }
        }
        scan(object)
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }.compactMap { tag in
            let cidrs: [String]
            if tag.hasPrefix(localGeoIPPrefix) {
                cidrs = IPCountryDatabase.cidrs(forCountry: String(tag.dropFirst(localGeoIPPrefix.count)))
            } else if let asn = UInt32(tag.dropFirst(localASNPrefix.count)) {
                cidrs = IPASNDatabase.cidrs(forASN: asn)
            } else {
                cidrs = []
            }
            return cidrs.isEmpty ? nil : ["type": "inline", "tag": tag, "rules": [["ip_cidr": cidrs]]]
        }
    }

    /// A rule set's addresses match the destination unless the rule asks for
    /// its source instead (`rule_set_ip_cidr_match_source`, sing-box 1.10+).
    private static func singBoxAddressCondition(_ cidrs: [String], ruleSet: String, source: Bool,
                                                localRuleSets: Bool) -> [String: Any] {
        guard localRuleSets else { return [source ? "source_ip_cidr" : "ip_cidr": cidrs] }
        var result: [String: Any] = ["rule_set": [ruleSet]]
        if source { result["rule_set_ip_cidr_match_source"] = true }
        return result
    }

    private static func singBoxCondition(_ condition: RoutingRuleSyntax.Condition, localRuleSets: Bool) -> [String: Any]? {
        guard condition.options.allSatisfy({ ["src", "no-resolve"].contains($0) || ignorableOptions.contains(optionKey($0)) }) else { return nil }
        if let children = condition.children {
            let mapped = children.compactMap { singBoxCondition($0, localRuleSets: localRuleSets) }
            guard mapped.count == children.count else { return nil }
            var rule: [String: Any] = ["type": "logical", "mode": condition.type == "OR" ? "or" : "and", "rules": mapped]
            if condition.type == "NOT" { rule["invert"] = true }
            return rule
        }
        let value = RoutingRuleSyntax.unquote(condition.value)
        switch condition.type {
        case "DOMAIN": return ["domain": [value]]
        case "DOMAIN-SUFFIX": return ["domain_suffix": [value]]
        case "DOMAIN-KEYWORD": return ["domain_keyword": [value]]
        case "DOMAIN-REGEX": return ["domain_regex": [value]]
        case "DOMAIN-WILDCARD":
            let regex = NSRegularExpression.escapedPattern(for: value).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
            return ["domain_regex": ["(?i)^" + regex + "$"]]
        case "IP-CIDR", "IP-CIDR6", "IP6-CIDR":
            return [condition.options.contains("src") ? "source_ip_cidr" : "ip_cidr": [value]]
        case "SRC-IP", "SRC-IP-CIDR": return ["source_ip_cidr": [value]]
        case "GEOIP":
            // sing-box 1.12 removed its GeoIP database. LAN is Surge's and
            // mihomo's name for the private ranges; a country is spelled out
            // from the offline database the app already ships. `src` matches
            // the connection's source, not its destination.
            let source = condition.options.contains("src")
            if ["LAN", "PRIVATE"].contains(value.uppercased()) {
                return [source ? "source_ip_is_private" : "ip_is_private": true]
            }
            let cidrs = IPCountryDatabase.cidrs(forCountry: value)
            guard !cidrs.isEmpty else { return nil }
            return singBoxAddressCondition(cidrs, ruleSet: localGeoIPPrefix + value.lowercased(),
                                           source: source, localRuleSets: localRuleSets)
        case "IP-ASN":
            // sing-box has no ASN matcher; the bundled ASN database lists the
            // ranges an AS originates, as it does for node network names.
            let digits = value.uppercased().hasPrefix("AS") ? String(value.dropFirst(2)) : value
            guard let asn = UInt32(digits) else { return nil }
            let cidrs = IPASNDatabase.cidrs(forASN: asn)
            guard !cidrs.isEmpty else { return nil }
            return singBoxAddressCondition(cidrs, ruleSet: localASNPrefix + String(asn),
                                           source: condition.options.contains("src"), localRuleSets: localRuleSets)
        case "NETWORK":
            guard ["tcp", "udp"].contains(value.lowercased()) else { return nil }
            return ["network": [value.lowercased()]]
        case "PROTOCOL":
            if ["tcp", "udp"].contains(value.lowercased()) { return ["network": [value.lowercased()]] }
            // Sniffed protocols have their own field; QUIC is narrower than UDP.
            guard ["http", "https", "tls", "quic", "stun"].contains(value.lowercased()) else { return nil }
            return ["protocol": [value.lowercased() == "https" ? "tls" : value.lowercased()]]
        case "DST-PORT", "DEST-PORT", "SRC-PORT":
            guard let ranges = portRanges(value) else { return nil }
            let source = condition.type == "SRC-PORT"
            var result: [String: Any] = [:]
            let ports = ranges.compactMap(Int.init)
            let intervals = ranges.filter { $0.contains("-") }.map { $0.replacingOccurrences(of: "-", with: ":") }
            if !ports.isEmpty { result[source ? "source_port" : "port"] = ports }
            if !intervals.isEmpty { result[source ? "source_port_range" : "port_range"] = intervals }
            return result
        default: return nil
        }
    }
}
