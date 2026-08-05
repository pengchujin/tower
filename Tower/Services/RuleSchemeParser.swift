import Foundation

enum RuleSchemeParseError: LocalizedError, Equatable {
    case notReadableText
    case noGroups
    case noRulesets

    var errorDescription: String? {
        switch self {
        case .notReadableText: "规则配置不是可识别的文本"
        case .noGroups: "配置里没有找到策略组（custom_proxy_group）"
        case .noRulesets: "配置里没有找到规则（ruleset）"
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

    private func value(of key: String, in line: String) -> String? {
        let prefix = "\(key)="
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
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
