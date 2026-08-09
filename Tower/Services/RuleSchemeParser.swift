import Foundation

enum RuleSchemeParseError: LocalizedError, Equatable {
    case notReadableText
    case noGroups
    case noRulesets

    var errorDescription: String? {
        switch self {
        case .notReadableText: String(localized: "规则配置不是可识别的文本")
        case .noGroups: String(localized: "配置里没有找到可识别的策略组")
        case .noRulesets: String(localized: "配置里没有找到可识别的规则")
        }
    }
}

/// Reads the subconverter remote-config `.ini` dialect used by ACL4SSR.
///
/// Two directives matter:
///
///     ruleset=<组名>,<https 规则列表地址>
///     ruleset=<组名>,[]<直接写出的规则>
///     custom_proxy_group=<组名>`<类型>`<成员>`…[`<测试地址>`<间隔,超时,容差>]
///
/// A member written as `[]名称` references another group or a builtin policy;
/// anything else is a regular expression matched against node names.
struct RuleSchemeParser {
    func parse(
        data: Data,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        isBundled: Bool = false
    ) throws -> RuleScheme {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw RuleSchemeParseError.notReadableText
        }
        return try parse(
            text: text,
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            isBundled: isBundled
        )
    }

    func parse(
        text: String,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        isBundled: Bool = false
    ) throws -> RuleScheme {
        // Self-Configuration publishes a complete Clash YAML document rather
        // than a subconverter INI. Only the three sections Tower needs are
        // read: policy groups, rules and their remote providers. Nodes and DNS
        // remain Tower's responsibility.
        if text.contains("proxy-groups:"), text.contains("rules:") {
            return try parseClashConfiguration(
                text: text,
                id: id,
                name: name,
                summary: summary,
                sourceURLString: sourceURLString,
                isBundled: isBundled
            )
        }

        // A complete Surge configuration carries the same information in
        // [Proxy Group] and [Rule] that a subconverter config puts in
        // custom_proxy_group= and ruleset=, so both are accepted.
        if !text.contains("custom_proxy_group="), text.contains("[Proxy Group]") {
            return try parseSurgeConfiguration(
                text: text,
                id: id,
                name: name,
                summary: summary,
                sourceURLString: sourceURLString,
                isBundled: isBundled
            )
        }

        var groups: [RuleSchemeGroup] = []
        var rulesets: [RuleSchemeRuleset] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // `;` and `#` start comments, and `[custom]` is a section header.
            guard !line.isEmpty,
                  !line.hasPrefix(";"),
                  !line.hasPrefix("#"),
                  !line.hasPrefix("[") else { continue }

            if let value = value(of: "ruleset", in: line) {
                if let ruleset = parseRuleset(value) { rulesets.append(ruleset) }
            } else if let value = value(of: "custom_proxy_group", in: line) {
                if let group = parseGroup(value) { groups.append(group) }
            }
        }

        guard !groups.isEmpty else { throw RuleSchemeParseError.noGroups }
        guard !rulesets.isEmpty else { throw RuleSchemeParseError.noRulesets }

        return RuleScheme(
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            groups: groups,
            rulesets: rulesets,
            updatedAt: .now,
            isBundled: isBundled
        )
    }

    // MARK: - Clash YAML

    private struct ClashGroupDraft {
        var name = ""
        var kind: RuleSchemeGroup.Kind = .select
        var proxies: [String] = []
        var usesProvider = false
        var filter: String?
        var testURLString: String?
        var interval: Int?
        var tolerance: Int?
    }

    private func parseClashConfiguration(
        text: String,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String?,
        isBundled: Bool
    ) throws -> RuleScheme {
        let lines = text.components(separatedBy: .newlines)
        let providers = clashProviderURLs(in: lines)
        let drafts = clashGroupDrafts(in: lines)
        let groupNames = Set(drafts.map(\.name))

        let groups = drafts.compactMap { draft -> RuleSchemeGroup? in
            guard !draft.name.isEmpty else { return nil }
            var members = draft.proxies.map { value -> RuleSchemeGroupMember in
                if groupNames.contains(value)
                    || value.uppercased() == "DIRECT"
                    || value.uppercased() == "REJECT" {
                    return .reference(value)
                }
                return .nodePattern("^\(NSRegularExpression.escapedPattern(for: value))$")
            }
            if draft.usesProvider {
                members.append(.nodePattern(draft.filter ?? ".*"))
            }
            return RuleSchemeGroup(
                name: draft.name,
                kind: draft.kind,
                members: members,
                testURLString: draft.testURLString,
                interval: draft.interval,
                tolerance: draft.tolerance
            )
        }
        let rulesets = clashRulesets(in: lines, providers: providers)

        guard !groups.isEmpty else { throw RuleSchemeParseError.noGroups }
        guard !rulesets.isEmpty else { throw RuleSchemeParseError.noRulesets }

        return RuleScheme(
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            groups: groups,
            rulesets: rulesets,
            updatedAt: .now,
            isBundled: isBundled
        )
    }

    private func clashGroupDrafts(in lines: [String]) -> [ClashGroupDraft] {
        var result: [ClashGroupDraft] = []
        var inSection = false
        var current: ClashGroupDraft?
        var listKey: String?

        func finish(_ draft: ClashGroupDraft?) {
            if let draft, !draft.name.isEmpty { result.append(draft) }
        }

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " }.count
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if indent == 0 {
                if inSection { finish(current) }
                inSection = line == "proxy-groups:"
                current = nil
                listKey = nil
                continue
            }
            guard inSection else { continue }

            if indent == 2, line.hasPrefix("- name:") {
                finish(current)
                current = ClashGroupDraft()
                current?.name = yamlScalar(after: "- name:", in: line)
                listKey = nil
                continue
            }
            guard current != nil else { continue }

            if indent == 4 {
                listKey = nil
                if line == "proxies:" || line == "use:" {
                    listKey = String(line.dropLast())
                } else if line.hasPrefix("type:") {
                    let value = yamlScalar(after: "type:", in: line).lowercased()
                    current?.kind = value == "url-test" ? .urlTest : .select
                } else if line.hasPrefix("filter:") {
                    current?.filter = yamlScalar(after: "filter:", in: line)
                } else if line.hasPrefix("url:") {
                    current?.testURLString = yamlScalar(after: "url:", in: line)
                } else if line.hasPrefix("interval:") {
                    current?.interval = Int(yamlScalar(after: "interval:", in: line))
                } else if line.hasPrefix("tolerance:") {
                    current?.tolerance = Int(yamlScalar(after: "tolerance:", in: line))
                }
                continue
            }

            if indent >= 6, line.hasPrefix("- ") {
                let value = unquotedYAMLScalar(String(line.dropFirst(2)))
                if listKey == "proxies" { current?.proxies.append(value) }
                if listKey == "use" { current?.usesProvider = true }
            }
        }
        if inSection { finish(current) }
        return result
    }

    private func clashProviderURLs(in lines: [String]) -> [String: URL] {
        var result: [String: URL] = [:]
        var inSection = false
        var providerName: String?

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " }.count
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if indent == 0 {
                inSection = line == "rule-providers:"
                providerName = nil
                continue
            }
            guard inSection else { continue }

            if indent == 2, line.hasSuffix(":"), !line.hasPrefix("-") {
                providerName = unquotedYAMLScalar(String(line.dropLast()))
            } else if indent == 4,
                      line.hasPrefix("url:"),
                      let providerName {
                let value = yamlScalar(after: "url:", in: line)
                if let url = URL(string: value), url.scheme?.lowercased() == "https" {
                    result[providerName] = url
                }
            }
        }
        return result
    }

    private func clashRulesets(
        in lines: [String],
        providers: [String: URL]
    ) -> [RuleSchemeRuleset] {
        var result: [RuleSchemeRuleset] = []
        var inSection = false

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " }.count
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if indent == 0 {
                inSection = line == "rules:"
                continue
            }
            guard inSection, line.hasPrefix("- ") else { continue }

            let value = unquotedYAMLScalar(String(line.dropFirst(2)))
            let parts = value.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2 else { continue }

            if parts[0].uppercased() == "RULE-SET", parts.count >= 3,
               let url = providers[parts[1]] {
                result.append(RuleSchemeRuleset(groupName: parts[2], resource: .remote(url)))
                continue
            }

            if parts[0].uppercased() == "MATCH" {
                result.append(RuleSchemeRuleset(groupName: parts[1], resource: .inline("FINAL")))
                continue
            }

            let hasNoResolve = parts.last?.lowercased() == "no-resolve"
            let policyIndex = parts.count - (hasNoResolve ? 2 : 1)
            guard policyIndex > 0 else { continue }
            let policy = parts[policyIndex]
            var ruleParts = Array(parts[..<policyIndex])
            if hasNoResolve { ruleParts.append("no-resolve") }
            result.append(
                RuleSchemeRuleset(
                    groupName: policy,
                    resource: .inline(ruleParts.joined(separator: ","))
                )
            )
        }
        return result
    }

    private func yamlScalar(after key: String, in line: String) -> String {
        unquotedYAMLScalar(
            String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        )
    }

    private func unquotedYAMLScalar(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" || first == "'"),
              first == last else { return value }
        return String(value.dropFirst().dropLast())
    }

    private func value(of key: String, in line: String) -> String? {
        let prefix = "\(key)="
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Surge configuration

    /// Reads `[Proxy Group]` and `[Rule]` out of a complete Surge config.
    ///
    /// The other sections are deliberately ignored: `[Proxy]` holds nodes,
    /// which arrive through subscriptions instead, and `[URL Rewrite]`,
    /// `[Script]`, `[MITM]` and `[Host]` have no equivalent in Tower's model.
    private func parseSurgeConfiguration(
        text: String,
        id: String,
        name: String,
        summary: String,
        sourceURLString: String?,
        isBundled: Bool
    ) throws -> RuleScheme {
        var section = ""
        var groupLines: [(name: String, kind: RuleSchemeGroup.Kind, fields: [String])] = []
        var ruleLines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"), !line.hasPrefix("//") else {
                continue
            }
            if line.hasPrefix("[") {
                section = line.lowercased()
                continue
            }

            switch section {
            case "[proxy group]":
                if let group = parseSurgeGroupLine(line) { groupLines.append(group) }
            case "[rule]":
                ruleLines.append(line)
            default:
                continue
            }
        }

        guard !groupLines.isEmpty else { throw RuleSchemeParseError.noGroups }

        // Members are resolved only once every group name is known: a bare name
        // is a sibling group if one exists by that name, otherwise it names a
        // node literally rather than describing a pattern.
        let groupNames = Set(groupLines.map(\.name))
        let groups = groupLines.map { entry -> RuleSchemeGroup in
            var members: [RuleSchemeGroupMember] = []
            var testURLString: String?
            var interval: Int?
            var tolerance: Int?

            for field in entry.fields {
                if let separator = field.firstIndex(of: "=") {
                    let key = String(field[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
                    let value = String(field[field.index(after: separator)...])
                        .trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "url": testURLString = value
                    case "interval": interval = Int(value)
                    case "tolerance": tolerance = Int(value)
                    default: break
                    }
                    continue
                }

                if groupNames.contains(field) || field.uppercased() == "DIRECT" || field.uppercased() == "REJECT" {
                    members.append(.reference(field))
                } else {
                    // Tower may rename a node when it writes the configuration,
                    // so the literal name becomes an anchored pattern that the
                    // generator matches against both the original remark and
                    // the name it will emit.
                    members.append(.nodePattern("^\(NSRegularExpression.escapedPattern(for: field))$"))
                }
            }

            return RuleSchemeGroup(
                name: entry.name,
                kind: entry.kind,
                members: members,
                testURLString: testURLString,
                interval: interval,
                tolerance: tolerance
            )
        }.filter { !$0.members.isEmpty }

        let rulesets = ruleLines.compactMap(parseSurgeRuleLine)
        guard !rulesets.isEmpty else { throw RuleSchemeParseError.noRulesets }

        return RuleScheme(
            id: id,
            name: name,
            summary: summary,
            sourceURLString: sourceURLString,
            groups: groups,
            rulesets: rulesets,
            updatedAt: .now,
            isBundled: isBundled
        )
    }

    /// `名称 = select,成员,…` or `名称 = url-test,成员,…,url=…,interval=…`.
    private func parseSurgeGroupLine(
        _ line: String
    ) -> (name: String, kind: RuleSchemeGroup.Kind, fields: [String])? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let body = String(line[line.index(after: separator)...])
        let parts = body.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty, let rawKind = parts.first?.lowercased() else { return nil }

        let kind: RuleSchemeGroup.Kind
        switch rawKind {
        case "select": kind = .select
        case "url-test", "fallback", "load-balance": kind = .urlTest
        default: return nil
        }
        return (name, kind, Array(parts.dropFirst()).filter { !$0.isEmpty })
    }

    /// `RULE-SET,<url>,<策略>[,参数]`, `FINAL,<策略>` or an inline rule such as
    /// `DOMAIN,example.com,<策略>`.
    private func parseSurgeRuleLine(_ line: String) -> RuleSchemeRuleset? {
        let parts = line.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2 else { return nil }
        let type = parts[0].uppercased()

        // Logical rules nest comma-separated conditions inside parentheses, so
        // they cannot be split this way and have no equivalent outside Surge.
        guard !["AND", "OR", "NOT"].contains(type) else { return nil }

        if type == "FINAL" {
            return RuleSchemeRuleset(groupName: parts[1], resource: .inline("FINAL"))
        }

        if type == "RULE-SET" {
            guard parts.count >= 3,
                  let url = URL(string: parts[1]),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return RuleSchemeRuleset(groupName: parts[2], resource: .remote(url))
        }

        // Everything else ends with the policy, optionally followed by flags
        // such as no-resolve which belong to the rule rather than the policy.
        var fields = parts
        var trailing: [String] = []
        while let last = fields.last,
              last.lowercased() == "no-resolve" || last.contains("=") {
            trailing.insert(last, at: 0)
            fields.removeLast()
        }
        guard fields.count >= 3 else { return nil }

        let policy = fields.removeLast()
        let rule = (fields + trailing.filter { $0.lowercased() == "no-resolve" })
            .joined(separator: ",")
        return RuleSchemeRuleset(groupName: policy, resource: .inline(rule))
    }

    /// Splits on the first comma only: an inline rule such as `[]GEOIP,CN`
    /// contains commas of its own.
    private func parseRuleset(_ value: String) -> RuleSchemeRuleset? {
        guard let separator = value.firstIndex(of: ",") else { return nil }
        let groupName = String(value[..<separator]).trimmingCharacters(in: .whitespaces)
        let target = String(value[value.index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        guard !groupName.isEmpty, !target.isEmpty else { return nil }

        if target.hasPrefix("[]") {
            let rule = String(target.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty else { return nil }
            return RuleSchemeRuleset(groupName: groupName, resource: .inline(rule))
        }

        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return RuleSchemeRuleset(groupName: groupName, resource: .remote(url))
    }

    private func parseGroup(_ value: String) -> RuleSchemeGroup? {
        let fields = value.components(separatedBy: "`")
        guard fields.count >= 3 else { return nil }

        let name = fields[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let kind: RuleSchemeGroup.Kind
        switch fields[1].trimmingCharacters(in: .whitespaces).lowercased() {
        case "select":
            kind = .select
        case "url-test", "fallback", "load-balance":
            // Tower emits latency selection for every automatic group type; the
            // distinction between them is not represented in its policy model.
            kind = .urlTest
        default:
            return nil
        }

        var members: [RuleSchemeGroupMember] = []
        var testURLString: String?
        var interval: Int?
        var tolerance: Int?

        for field in fields.dropFirst(2) {
            let entry = field.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }

            if entry.hasPrefix("[]") {
                let reference = String(entry.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !reference.isEmpty { members.append(.reference(reference)) }
            } else if entry.lowercased().hasPrefix("http://") || entry.lowercased().hasPrefix("https://") {
                testURLString = entry
            } else if isTimingField(entry) {
                let numbers = entry.components(separatedBy: ",")
                interval = numbers.first.flatMap { Int($0) }
                if numbers.count >= 3 { tolerance = Int(numbers[2]) }
            } else {
                members.append(.nodePattern(entry))
            }
        }

        guard !members.isEmpty else { return nil }
        return RuleSchemeGroup(
            name: name,
            kind: kind,
            members: members,
            testURLString: testURLString,
            interval: interval,
            tolerance: tolerance
        )
    }

    /// The trailing `300,,50` field: only digits and commas, and it must carry
    /// at least one comma so a node pattern of bare digits is not mistaken for
    /// timing information.
    private func isTimingField(_ entry: String) -> Bool {
        entry.contains(",")
            && entry.allSatisfy { $0.isNumber || $0 == "," }
    }
}
