import Foundation

struct NodeNameFilterDraft: Equatable {
    enum MatchStyle: String, CaseIterable, Identifiable {
        case contains, prefix, suffix, exact
        var id: Self { self }
        var title: String {
            switch self {
            case .contains: String(localized: "包含关键词")
            case .prefix: String(localized: "以关键词开头")
            case .suffix: String(localized: "以关键词结尾")
            case .exact: String(localized: "名称完全相同")
            }
        }
    }

    var keywords = ""
    var style: MatchStyle = .contains
    var ignoresCase = true
    var usesRegex = false
    var regex = ""

    init(pattern: String = "", caseInsensitiveDefault: Bool = true) {
        ignoresCase = caseInsensitiveDefault
        regex = pattern
        guard !pattern.isEmpty else { return }
        if let simple = Self.decode(pattern, caseInsensitiveDefault: caseInsensitiveDefault) { self = simple }
        else { usesRegex = true }
    }

    var pattern: String {
        if usesRegex { return regex }
        let values = keywords.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !values.isEmpty else { return "" }
        let flags = ignoresCase ? "(?i)" : "(?-i)"
        let alternatives = values.map { word in
            word.map { "\\.*+?()[]{}^$|".contains($0) ? "\\" + String($0) : String($0) }.joined()
        }.joined(separator: "|")
        let prefix = style == .prefix || style == .exact ? "^" : ""
        let suffix = style == .suffix || style == .exact ? "$" : ""
        return flags + prefix + "(?:" + alternatives + ")" + suffix
    }

    /// Literal alternatives are reversible.
    /// Other expert expressions stay in regex mode without normalization.
    static func decode(_ pattern: String, caseInsensitiveDefault: Bool) -> Self? {
        var text = pattern
        var draft = Self()
        draft.ignoresCase = caseInsensitiveDefault
        if text.hasPrefix("(?i)") { draft.ignoresCase = true; text.removeFirst(4) }
        else if text.hasPrefix("(?-i)") { draft.ignoresCase = false; text.removeFirst(5) }
        let anchoredStart = text.hasPrefix("^")
        if anchoredStart { text.removeFirst() }
        let anchoredEnd = text.hasSuffix("$") && !text.hasSuffix("\\$")
        if anchoredEnd { text.removeLast() }
        if text.hasPrefix("(?:"), text.hasSuffix(")") { text = String(text.dropFirst(3).dropLast()) }
        else if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        // Anchors without a grouping bind only to the first/last alternative.
        if (anchoredStart || anchoredEnd), text.contains("|"), !pattern.contains("(?:") { return nil }
        var words: [String] = [], word = "", escaped = false
        let meta = Set("\\.*+?()[]{}^$|")
        for char in text {
            if escaped {
                guard meta.contains(char) || char == "#" || char == "-" else { return nil }
                word.append(char); escaped = false
            } else if char == "\\" { escaped = true }
            else if char == "|" {
                guard !word.isEmpty else { return nil }
                words.append(word); word = ""
            } else {
                guard !meta.contains(char), !char.isNewline else { return nil }
                word.append(char)
            }
        }
        guard !escaped, !word.isEmpty else { return nil }
        words.append(word)
        // Basic inputs trim whitespace; never silently trim a literal match.
        guard words.allSatisfy({ $0 == $0.trimmingCharacters(in: .whitespaces) }) else { return nil }
        draft.keywords = words.joined(separator: "\n")
        draft.style = anchoredStart ? (anchoredEnd ? .exact : .prefix) : (anchoredEnd ? .suffix : .contains)
        draft.regex = pattern
        return draft
    }
}

enum NodeNameFilterMatcher {
    enum Failure: LocalizedError {
        case invalid, timedOut
        var errorDescription: String? {
            switch self {
            case .invalid: String(localized: "节点筛选表达式无效")
            case .timedOut: String(localized: "匹配耗时过长，请简化正则表达式后重试。")
            }
        }
    }

    static func expression(_ pattern: String, caseInsensitive: Bool) throws -> NSRegularExpression {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pattern.contains(where: \.isNewline),
              let expression = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            throw Failure.invalid
        }
        return expression
    }

    /// Same raw/display-name candidates as configuration generation. Progress
    /// callbacks bound expert regex work; a timeout never becomes a zero count.
    static func preview(_ pattern: String, candidates: [[String]], caseInsensitive: Bool, timeLimit: TimeInterval = 1) throws -> [Int] {
        let expression = try expression(pattern, caseInsensitive: caseInsensitive)
        let deadline = ProcessInfo.processInfo.systemUptime + timeLimit
        var matches: [Int] = []
        for (index, names) in candidates.enumerated() {
            var matched = false, timedOut = false
            for name in names {
                if ProcessInfo.processInfo.systemUptime > deadline { throw Failure.timedOut }
                expression.enumerateMatches(in: name, options: [.reportProgress], range: NSRange(name.startIndex..., in: name)) { result, _, stop in
                    if ProcessInfo.processInfo.systemUptime > deadline { timedOut = true; stop.pointee = true }
                    else if result != nil { matched = true; stop.pointee = true }
                }
                if timedOut { throw Failure.timedOut }
                if matched { break }
            }
            if matched { matches.append(index) }
        }
        return matches
    }
}

struct EditableNodeNameFilter: Identifiable, Equatable {
    var id = UUID()
    var pattern: String
    var isEnabled = true
    var isSourceBound = false

    static func rows(for group: RuleSchemeGroup) -> [Self] {
        let sourcePatterns = group.parameters?["tower-source-patterns"]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return group.members.compactMap { member in
            guard case .nodePattern(let pattern) = member else { return nil }
            return Self(pattern: pattern, isSourceBound: sourcePatterns.contains(pattern))
        }
    }
}
