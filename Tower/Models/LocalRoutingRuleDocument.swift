import Foundation

/// Parses authored rules without rewriting their original text.
struct LocalRoutingRuleDocument {
    struct Entry: Identifiable {
        let lineIndex: Int
        let raw: String
        let condition: RoutingRuleSyntax.Condition?
        let policy: String?
        let replacedPolicy: String?
        var id: Int { lineIndex }
        var body: String { condition?.body ?? raw }
    }

    struct InvalidLine: LocalizedError {
        let number: Int
        var errorDescription: String? {
            String(localized: "第 \(number) 行无效，请检查类型、括号、引号和参数。")
        }
    }

    let entries: [Entry]
    var firstError: InvalidLine? {
        entries.first(where: { $0.condition == nil }).map { InvalidLine(number: $0.lineIndex + 1) }
    }

    init(_ text: String) {
        entries = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated().compactMap { index, rawLine in
            let raw = String(rawLine)
            let line = RoutingRuleSyntax.removingComment(raw.trimmingCharacters(in: .whitespaces))
            guard !line.isEmpty else { return nil }
            guard var fields = RoutingRuleSyntax.fields(line), fields.count >= 2 else {
                return Entry(lineIndex: index, raw: raw, condition: nil, policy: nil, replacedPolicy: nil)
            }
            var policy: String?, replacedPolicy: String?
            if fields.count > 2, !Self.isOption(fields[2]) {
                let pasted = RoutingRuleSyntax.unquote(fields.remove(at: 2))
                if RoutingBuiltinPolicies.canonical.contains(pasted.uppercased()) { policy = pasted.uppercased() }
                else { replacedPolicy = pasted }
            }
            let body = fields.joined(separator: ",")
            let parsed = RoutingRuleSyntax.condition(body)
            let valid = parsed.map(Self.isValid) ?? false
            return Entry(lineIndex: index, raw: raw, condition: valid ? parsed : nil,
                         policy: policy, replacedPolicy: replacedPolicy)
        }
    }

    static func isOption(_ value: String) -> Bool {
        let key = RoutingRuleCapabilities.optionKey(value)
        return RoutingRuleCapabilities.surgeOptions.union(["src", "no-track"]).contains(key) || value.contains("=")
    }

    private static func isValid(_ condition: RoutingRuleSyntax.Condition) -> Bool {
        guard condition.options.allSatisfy({ !$0.isEmpty && isOption($0) }) else { return false }
        if let children = condition.children { return !children.isEmpty && children.allSatisfy(isValid) }
        return RoutingRuleCapabilities.mihomo.union(RoutingRuleCapabilities.surge).contains(condition.type)
    }

    static func replacingLine(in text: String, at index: Int?, with line: String?) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var result = text
        if let index, lines.indices.contains(index) {
            if let line {
                result.replaceSubrange(lines[index].startIndex..<lines[index].endIndex, with: line)
            } else {
                let start = index + 1 < lines.count ? lines[index].startIndex
                    : (index > 0 ? lines[index - 1].endIndex : text.startIndex)
                let end = index + 1 < lines.count ? lines[index + 1].startIndex : text.endIndex
                result.removeSubrange(start..<end)
            }
        } else if let line {
            let separator = text.isEmpty || text.last?.isNewline == true ? "" : (text.contains("\r\n") ? "\r\n" : "\n")
            result += separator + line
        }
        return result
    }

    static func line(_ condition: RoutingRuleSyntax.Condition, policy: String?) -> String {
        var matcher = condition
        matcher.options = []
        return ([matcher.body] + (policy.map { [$0] } ?? []) + condition.options).joined(separator: ",")
    }
}


struct LocalRuleCompatibilitySummary: Sendable {
    let isRemote: Bool
    let isEmpty: Bool
    let error: String?
    let supported: [ClientTarget]
    let unsupported: [ClientTarget]

    init(text: String) {
        isRemote = LocalRuleSet(name: "", rulesText: text).remoteRuleURL != nil
        let document = LocalRoutingRuleDocument(isRemote ? "" : text)
        isEmpty = document.entries.isEmpty
        error = document.firstError?.localizedDescription
        let targets: [ClientTarget] = [.clashMi, .surge, .surgeMac, .singBox, .clash]
        guard !isRemote, !isEmpty, error == nil else {
            supported = []; unsupported = []
            return
        }
        func supports(_ target: ClientTarget) -> Bool {
            document.entries.allSatisfy { entry in
                guard let condition = entry.condition else { return false }
                let policy = entry.policy ?? "DIRECT"
                return RoutingBuiltinPolicies.supports(policy, target: target)
                    && (target.usesSingBoxFormat
                        ? RoutingRuleCapabilities.singBoxCondition(condition.body) != nil
                        : RoutingRuleCapabilities.render(condition.body, policy: policy, target: target) != nil)
            }
        }
        let compatible = targets.filter(supports)
        supported = compatible
        unsupported = targets.filter { !compatible.contains($0) }
    }
}
