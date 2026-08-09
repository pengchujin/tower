import Foundation

/// A rule scheme loaded from Clash YAML, subconverter `.ini`, or Surge config.
/// Unlike `RulePreset`, whose policy groups are fixed in Swift, an imported
/// scheme carries whatever groups the file declared, so generation reproduces
/// the source faithfully.
struct RuleScheme: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var summary: String
    var sourceURLString: String?
    var groups: [RuleSchemeGroup]
    var rulesets: [RuleSchemeRuleset]
    var updatedAt: Date?
    /// True for the schemes shipped inside the app bundle, which work offline
    /// and cannot be deleted.
    var isBundled: Bool

    init(
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        groups: [RuleSchemeGroup],
        rulesets: [RuleSchemeRuleset],
        updatedAt: Date? = nil,
        isBundled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.groups = groups
        self.rulesets = rulesets
        self.updatedAt = updatedAt
        self.isBundled = isBundled
    }

    /// Every remote list the scheme references, de-duplicated in first-use order.
    var remoteRulesetURLs: [URL] {
        var seen = Set<String>()
        return rulesets.compactMap { ruleset in
            guard case .remote(let url) = ruleset.resource,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    /// The group a client should fall back to, taken from the `[]FINAL` ruleset.
    var finalGroupName: String? {
        rulesets.first { ruleset in
            if case .inline(let rule) = ruleset.resource {
                return rule.uppercased() == "FINAL"
            }
            return false
        }?.groupName
    }

    /// Only groups that own non-final rules are user-facing choices. Routing
    /// primitives such as node selectors and regional URL tests are pulled in
    /// automatically through group references.
    var selectableRuleGroupNames: [String] {
        var seen = Set<String>()
        return rulesets.compactMap { ruleset in
            if case .inline(let rule) = ruleset.resource, rule.uppercased() == "FINAL" {
                return nil
            }
            return seen.insert(ruleset.groupName).inserted ? ruleset.groupName : nil
        }
    }

    /// Produces a valid, self-contained view of this scheme for generation.
    /// An explicit selection filters service rules, while the final policy and
    /// every transitively referenced helper group remain available.
    func customized(
        enabledRuleGroupNames: Set<String>?,
        customRuleFlows: [CustomRuleFlow]
    ) -> RuleScheme {
        let groupNames = Set(groups.map(\.name))
        let validPolicies = groupNames.union(["DIRECT", "REJECT", "direct", "reject"])
        let flows = customRuleFlows.filter {
            $0.schemeID == id && $0.isEnabled && validPolicies.contains($0.policyName)
        }

        var ordinaryRulesets: [RuleSchemeRuleset] = []
        var finalRulesets: [RuleSchemeRuleset] = []
        for ruleset in rulesets {
            if case .inline(let rule) = ruleset.resource, rule.uppercased() == "FINAL" {
                finalRulesets.append(ruleset)
            } else if enabledRuleGroupNames?.contains(ruleset.groupName) ?? true {
                ordinaryRulesets.append(ruleset)
            }
        }

        for flow in flows {
            ordinaryRulesets.append(contentsOf: flow.normalizedRules.map {
                RuleSchemeRuleset(groupName: flow.policyName, resource: .inline($0))
            })
        }

        var result = self
        result.rulesets = ordinaryRulesets + finalRulesets

        // Nil means the untouched default: reproduce every group exactly as
        // the source declared it. Explicit selections may safely prune groups.
        guard enabledRuleGroupNames != nil else { return result }

        var requiredNames = Set(result.rulesets.map(\.groupName)).intersection(groupNames)
        var didAddDependency = true
        while didAddDependency {
            didAddDependency = false
            for group in groups where requiredNames.contains(group.name) {
                for member in group.members {
                    guard case .reference(let name) = member,
                          groupNames.contains(name),
                          requiredNames.insert(name).inserted else { continue }
                    didAddDependency = true
                }
            }
        }
        result.groups = groups.filter { requiredNames.contains($0.name) }
        return result
    }

    /// Hides decorative leading emoji without breaking the graph between policy
    /// groups and rules. Every declaration and reference is renamed together.
    func withGroupEmojis(_ enabled: Bool) -> RuleScheme {
        guard !enabled else { return self }

        let candidates = groups.map { ($0.name, Self.removingLeadingEmoji(from: $0.name)) }
        let counts = Dictionary(grouping: candidates, by: \.1).mapValues(\.count)
        let names = Dictionary(uniqueKeysWithValues: candidates.map { original, candidate in
            // Keep the source names when removing decoration would create an
            // ambiguous group reference.
            (original, counts[candidate] == 1 ? candidate : original)
        })

        func renamed(_ name: String) -> String { names[name] ?? name }

        var result = self
        result.groups = groups.map { group in
            RuleSchemeGroup(
                name: renamed(group.name),
                kind: group.kind,
                members: group.members.map { member in
                    switch member {
                    case .reference(let name): return .reference(renamed(name))
                    case .nodePattern: return member
                    }
                },
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance
            )
        }
        result.rulesets = rulesets.map {
            RuleSchemeRuleset(groupName: renamed($0.groupName), resource: $0.resource)
        }
        return result
    }

    private static func removingLeadingEmoji(from name: String) -> String {
        var remainder = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var removedEmoji = false

        while let character = remainder.first {
            // Some familiar symbols, such as ♻️, are emoji only when they carry
            // a variation selector. `isEmojiPresentation` is therefore false
            // for their base scalar even though the whole Character is a
            // decorative emoji. `isEmoji` covers both native emoji and those
            // text-default symbols without splitting the grapheme cluster.
            let isEmoji = character.unicodeScalars.contains { $0.properties.isEmoji }
            guard isEmoji else { break }
            remainder.removeFirst()
            remainder = remainder.drop(while: \.isWhitespace).description
            removedEmoji = true
        }

        return removedEmoji && !remainder.isEmpty ? remainder : name
    }
}

struct RuleSchemeGroup: Codable, Hashable {
    enum Kind: String, Codable {
        case select
        case urlTest
    }

    let name: String
    let kind: Kind
    /// Members in their declared order; the order decides how the client lists
    /// them, so it must survive parsing.
    let members: [RuleSchemeGroupMember]
    let testURLString: String?
    let interval: Int?
    let tolerance: Int?

    init(
        name: String,
        kind: Kind,
        members: [RuleSchemeGroupMember],
        testURLString: String? = nil,
        interval: Int? = nil,
        tolerance: Int? = nil
    ) {
        self.name = name
        self.kind = kind
        self.members = members
        self.testURLString = testURLString
        self.interval = interval
        self.tolerance = tolerance
    }
}

enum RuleSchemeGroupMember: Codable, Hashable {
    /// A `[]`-prefixed member: another group, or a builtin such as DIRECT.
    case reference(String)
    /// A bare member: a regular expression matched against node names. `.*`
    /// selects every node.
    case nodePattern(String)
}

struct RuleSchemeRuleset: Codable, Hashable {
    enum Resource: Codable, Hashable {
        case remote(URL)
        /// A `[]`-prefixed rule written directly in the config, such as
        /// `[]GEOIP,CN` or `[]FINAL`.
        case inline(String)
    }

    let groupName: String
    let resource: Resource
}
