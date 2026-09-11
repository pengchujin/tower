import Foundation

/// Validates the declared graph before generation builds name-indexed dictionaries.
/// Node names must be the original, unescaped names used by member regexes.
enum RuleSchemePolicyValidator {
    enum Code: String, Hashable {
        case duplicateGroupName
        case unknownGroupMember
        case unknownRuleTarget
        case cycle
        case emptyGroup
        case invalidNodePattern

        var displayTitle: String {
            switch self {
            case .duplicateGroupName: String(localized: "策略组名称重复")
            case .unknownGroupMember: String(localized: "候选策略不存在")
            case .unknownRuleTarget: String(localized: "规则目标不存在")
            case .cycle: String(localized: "策略组循环引用")
            case .emptyGroup: String(localized: "策略组没有可用候选项")
            case .invalidNodePattern: String(localized: "节点筛选表达式无效")
            }
        }
    }

    struct Issue: Hashable {
        let code: Code
        /// Group first, followed by the offending member/pattern where applicable.
        let names: [String]
    }

    private static func conditionalTargets(_ group: RuleSchemeGroup) -> [String] {
        guard group.kind == .conditional, let parameters = group.parameters else { return [] }
        func array(_ key: String) -> [String] {
            guard let text = parameters[key], let data = text.data(using: .utf8) else { return [] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String] ?? []
        }
        var targets: [String] = []
        for (index, field) in array("ssid-members").enumerated() {
            if index < 2 { targets.append(field); continue }
            if let colon = field.firstIndex(of: ":") { targets.append(String(field[field.index(after: colon)...])) }
        }
        for field in array("subnet-fields") {
            if let equal = field.firstIndex(of: "=") { targets.append(String(field[field.index(after: equal)...])) }
        }
        if let fallback = parameters["default_policy"] { targets.append(fallback) }
        if let text = parameters["rules"], let data = text.data(using: .utf8),
           let rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for wrapper in rules {
                for value in wrapper.values {
                    if let rule = value as? [String: Any], let policy = rule["policy"] as? String { targets.append(policy) }
                }
            }
        }
        return targets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func validate(
        groups: [RuleSchemeGroup],
        ruleTargets: [String],
        nodeNames: Set<String>,
        allowUnresolvedPatterns: Bool = false
    ) -> [Issue] {
        let builtins = RoutingBuiltinPolicies.names
        var issues: [Issue] = []
        var seenIssues: Set<Issue> = []
        func append(_ code: Code, _ names: [String]) {
            let issue = Issue(code: code, names: names)
            if seenIssues.insert(issue).inserted { issues.append(issue) }
        }

        var indexByName: [String: Int] = [:]
        for (index, group) in groups.enumerated() {
            if indexByName[group.name] != nil {
                append(.duplicateGroupName, [group.name])
            } else {
                indexByName[group.name] = index
            }
        }
        var edges = Array(repeating: [Int](), count: groups.count)
        var reverseEdges = Array(repeating: [Int](), count: groups.count)
        var reachesCandidate = Array(repeating: false, count: groups.count)

        for (index, group) in groups.enumerated() {
            // Conditional fields are the actual emitted routing targets. They
            // remain authoritative even if an editor removed a member from the
            // separate candidate list; validate them for missing targets/cycles.
            let declared = Set(group.members)
            let conditionMembers = conditionalTargets(group).map(RuleSchemeGroupMember.reference)
                .filter { !declared.contains($0) }
            for member in group.members + conditionMembers {
                switch member {
                case .reference(let name):
                    if let target = indexByName[name] {
                        edges[index].append(target)
                        reverseEdges[target].append(index)
                    } else if builtins.contains(name) || nodeNames.contains(name) {
                        reachesCandidate[index] = true
                    } else {
                        append(.unknownGroupMember, [group.name, name])
                    }
                case .nodePattern(let pattern):
                    guard let regex = try? NSRegularExpression(pattern: pattern, options:
                        group.sourceFormat == nil || group.sourceFormat == "subconverter" ? [.caseInsensitive] : []) else {
                        append(.invalidNodePattern, [group.name, pattern])
                        continue
                    }
                    if allowUnresolvedPatterns || nodeNames.contains(where: { name in
                        regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
                    }) {
                        reachesCandidate[index] = true
                    }
                }
            }
        }
        for name in ruleTargets where indexByName[name] == nil && !builtins.contains(name) && !nodeNames.contains(name) {
            append(.unknownRuleTarget, [name])
        }

        // Iterative traversal avoids overflowing the stack on deeply nested imports.
        var colors = Array(repeating: 0, count: groups.count)
        for root in groups.indices where colors[root] == 0 {
            var stack: [(node: Int, next: Int)] = [(root, 0)]
            var pathIndices: [Int: Int] = [root: 0]
            colors[root] = 1
            while let frame = stack.last {
                if frame.next == edges[frame.node].count {
                    colors[frame.node] = 2
                    pathIndices[frame.node] = nil
                    stack.removeLast()
                    continue
                }
                let next = edges[frame.node][frame.next]
                stack[stack.count - 1].next += 1
                if colors[next] == 0 {
                    colors[next] = 1
                    pathIndices[next] = stack.count
                    stack.append((next, 0))
                } else if colors[next] == 1, let start = pathIndices[next] {
                    append(.cycle, stack[start...].map { groups[$0.node].name })
                }
            }
        }

        // Propagate concrete candidates backwards. A group containing only another
        // empty group is also empty; a circular reference is not a candidate.
        var queue = groups.indices.filter { reachesCandidate[$0] }
        var cursor = 0
        while cursor < queue.count {
            let target = queue[cursor]
            cursor += 1
            for owner in reverseEdges[target] where !reachesCandidate[owner] {
                reachesCandidate[owner] = true
                queue.append(owner)
            }
        }
        for index in groups.indices where !reachesCandidate[index] {
            append(.emptyGroup, [groups[index].name])
        }
        return issues
    }
}
