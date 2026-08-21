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
    /// Missing keeps the legacy imported-source description, while `true`
    /// means the user deliberately replaced that automatic copy.
    var summaryIsUserEdited: Bool?
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
        summaryIsUserEdited: Bool? = nil,
        isBundled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.groups = groups
        self.rulesets = rulesets
        self.updatedAt = updatedAt
        self.summaryIsUserEdited = summaryIsUserEdited
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

    /// Imported summaries used to be localized before being persisted. Derive
    /// the generic source description at display time so changing the app
    /// language also fixes schemes saved by older builds.
    func localizedSummary(bundle: Bundle = .main) -> String {
        guard summaryIsUserEdited != true,
              !isBundled,
              let sourceURLString,
              let host = URL(string: sourceURLString)?.host else {
            return summary
        }
        return String(localized: "从 \(host) 导入", bundle: bundle)
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

    /// Routing primitives that define the shape of a valid configuration are
    /// shown for context but are never user-removable. The final policy is
    /// detected structurally; common direct/reject groups are recognised by
    /// their source names after decorative emoji are removed.
    var protectedRuleGroupNames: [String] {
        let finalName = finalGroupName
        let fixedNames: Set<String> = [
            "全球直连", "全球拦截", "漏网之鱼",
            "global direct", "global reject", "final", "final match",
        ]
        return groups.compactMap { group in
            let key = Self.removingLeadingEmoji(from: group.name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return group.name == finalName || fixedNames.contains(key) ? group.name : nil
        }
    }

    var editableRuleGroupNames: [String] {
        let protectedNames = Set(protectedRuleGroupNames)
        return selectableRuleGroupNames.filter { !protectedNames.contains($0) }
    }

    /// The policy-group editor has two deliberately separate jobs. Service
    /// rules choose an outbound policy, while regional/helper groups define
    /// which node names they contain. Mixing the two makes service rules appear
    /// as candidates for one another and can create cyclic configurations.
    func groupEditorMode(for group: RuleSchemeGroup) -> RuleSchemeGroupEditorMode {
        if isPrimaryNodeSelector(group.name) {
            return .routingTargets
        }

        let declaredRuleGroups = Set(rulesets.map(\.groupName))
        let hasNodePattern = group.members.contains { member in
            if case .nodePattern = member { return true }
            return false
        }
        return hasNodePattern && !declaredRuleGroups.contains(group.name)
            ? .nodePatternsOnly
            : .routingTargets
    }

    /// Only general-purpose outbound policies belong in a service rule's
    /// candidate list. Other service rules (AI, Netflix, Apple, media, etc.)
    /// are routing rules, not destinations, and must never be offered here.
    func routingTargetGroupNames(
        from candidateGroups: [RuleSchemeGroup]? = nil,
        excluding excludedName: String? = nil
    ) -> [String] {
        let candidateGroups = candidateGroups ?? groups
        var seen = Set<String>()
        let declaredCore = candidateGroups.compactMap { group -> String? in
            guard group.name != excludedName,
                  isCoreRoutingTarget(group.name) else { return nil }
            return group.name
        }
        let declaredRegions = Dictionary(
            candidateGroups.compactMap { group -> (SupplementalRoutingRegion, String)? in
                guard group.name != excludedName,
                      let region = Self.routingRegion(for: group.name) else { return nil }
                return (region, group.name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let regionalTargets = SupplementalRoutingRegion.allCases.map { region in
            declaredRegions[region] ?? region.canonicalName
        }
        return (declaredCore + regionalTargets + ["DIRECT", "REJECT"])
            .filter { seen.insert($0).inserted }
    }

    /// Produces a valid, self-contained view of this scheme for generation.
    /// An explicit selection filters service rules, while the final policy and
    /// every transitively referenced helper group remain available.
    func customized(
        enabledRuleGroupNames: Set<String>?,
        customRuleFlows: [CustomRuleFlow],
        groupCustomization: RuleSchemeCustomization? = nil,
        resolvedRuleLines: [URL: [String]] = [:]
    ) -> RuleScheme {
        let candidateFlows = customRuleFlows.filter { $0.schemeID == id && $0.isEnabled }
        var availableGroups = groups
        var availableGroupNames = Set(groups.map(\.name))
        var insertedGeneratedRuleSetIDs = Set<UUID>()
        for flow in candidateFlows {
            guard let group = flow.expansion.policyGroup,
                  availableGroupNames.insert(group.name).inserted else { continue }
            availableGroups.append(group)
            insertedGeneratedRuleSetIDs.insert(flow.id)
        }
        availableGroups = groupCustomization?.applying(to: availableGroups) ?? availableGroups
        availableGroups = Self.injectMissingRegionalGroups(into: availableGroups)

        let groupNames = Set(availableGroups.map(\.name))
        let validPolicies = groupNames.union(["DIRECT", "REJECT", "direct", "reject"])
        let expansions = candidateFlows.map { flow in
            groupCustomization?.applying(to: flow.expansion) ?? flow.expansion
        }.filter {
            validPolicies.contains($0.binding.policyGroupName)
        }

        var ordinaryRulesets: [RuleSchemeRuleset] = []
        var finalRulesets: [RuleSchemeRuleset] = []
        let removedGroupNames = groupCustomization?.removedGroupNames ?? []
        for sourceRuleset in rulesets {
            let ruleset = RuleSchemeRuleset(
                groupName: groupCustomization?.renamedGroupName(sourceRuleset.groupName)
                    ?? sourceRuleset.groupName,
                resource: sourceRuleset.resource
            )
            guard !removedGroupNames.contains(ruleset.groupName) else { continue }
            if case .inline(let rule) = ruleset.resource, rule.uppercased() == "FINAL" {
                finalRulesets.append(ruleset)
            } else if enabledRuleGroupNames?.contains(ruleset.groupName) ?? true {
                ordinaryRulesets.append(ruleset)
            }
        }

        var customRulesetsByInsertion = Array(
            repeating: [RuleSchemeRuleset](),
            count: ordinaryRulesets.count + 1
        )
        let explicitlyOrderedGroupNames = Set(groupCustomization?.groupOrder ?? [])
        var generatedGroupPlacements: [(groupName: String, anchorName: String?)] = []
        for expansion in expansions {
            let policyGroupName = expansion.binding.policyGroupName
            var expansionRulesets: [RuleSchemeRuleset] = []
            if let url = expansion.ruleSet.remoteURL {
                expansionRulesets.append(
                    RuleSchemeRuleset(groupName: policyGroupName, resource: .remote(url))
                )
            }
            expansionRulesets.append(contentsOf: expansion.ruleSet.inlineRules.map {
                RuleSchemeRuleset(groupName: policyGroupName, resource: .inline($0))
            })
            let insertion = Self.customRulesetInsertionIndex(
                for: expansion,
                in: ordinaryRulesets,
                resolvedRuleLines: resolvedRuleLines
            )
            customRulesetsByInsertion[insertion].append(contentsOf: expansionRulesets)
            if let groupName = expansion.policyGroup?.name,
               insertedGeneratedRuleSetIDs.contains(expansion.ruleSet.id),
               !explicitlyOrderedGroupNames.contains(groupName) {
                generatedGroupPlacements.append(
                    (
                        groupName: groupName,
                        anchorName: insertion < ordinaryRulesets.count
                            ? ordinaryRulesets[insertion].groupName
                            : finalRulesets.first?.groupName
                    )
                )
            }
        }

        var mergedRulesets: [RuleSchemeRuleset] = []
        for index in ordinaryRulesets.indices {
            mergedRulesets.append(contentsOf: customRulesetsByInsertion[index])
            mergedRulesets.append(ordinaryRulesets[index])
        }
        mergedRulesets.append(contentsOf: customRulesetsByInsertion[ordinaryRulesets.count])

        for placement in generatedGroupPlacements {
            guard let currentIndex = availableGroups.firstIndex(where: {
                $0.name == placement.groupName
            }) else { continue }
            let group = availableGroups.remove(at: currentIndex)
            guard let anchorName = placement.anchorName,
                  let anchorIndex = availableGroups.firstIndex(where: {
                      $0.name == anchorName
                  }) else {
                availableGroups.append(group)
                continue
            }
            availableGroups.insert(group, at: anchorIndex)
        }

        var result = self
        result.groups = availableGroups
        result.rulesets = mergedRulesets + finalRulesets

        // Nil means the untouched default: reproduce every group exactly as
        // the source declared it. Explicit selections may safely prune groups.
        guard enabledRuleGroupNames != nil else { return result }

        var requiredNames = Set(result.rulesets.map(\.groupName)).intersection(groupNames)
        var didAddDependency = true
        while didAddDependency {
            didAddDependency = false
            for group in availableGroups where requiredNames.contains(group.name) {
                for member in group.members {
                    guard case .reference(let name) = member,
                          groupNames.contains(name),
                          requiredNames.insert(name).inserted else { continue }
                    didAddDependency = true
                }
            }
        }
        result.groups = availableGroups.filter { requiredNames.contains($0.name) }
        return result
    }

    private static func customRulesetInsertionIndex(
        for expansion: CustomRuleFlowExpansion,
        in upstreamRulesets: [RuleSchemeRuleset],
        resolvedRuleLines: [URL: [String]]
    ) -> Int {
        let customGroup = normalizedPolicyName(expansion.binding.policyGroupName)
        let customURL = expansion.ruleSet.remoteURL
        var customLines = expansion.ruleSet.inlineRules
        if let customURL {
            customLines.append(contentsOf: resolvedRuleLines[customURL] ?? [])
        }
        let customMatches = Set(customLines.compactMap(ruleMatchKey))

        return upstreamRulesets.firstIndex { upstream in
            if normalizedPolicyName(upstream.groupName) == customGroup {
                return true
            }
            switch upstream.resource {
            case .remote(let url):
                if url == customURL { return true }
                let upstreamMatches = Set(
                    (resolvedRuleLines[url] ?? []).compactMap(ruleMatchKey)
                )
                return !customMatches.isDisjoint(with: upstreamMatches)
            case .inline(let rule):
                guard let match = ruleMatchKey(rule) else { return false }
                return customMatches.contains(match)
            }
        } ?? upstreamRulesets.count
    }

    private static func ruleMatchKey(_ rawRule: String) -> String? {
        let parts = rawRule.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return [parts[0].uppercased(), parts[1].lowercased()].joined(separator: ",")
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

    private func isPrimaryNodeSelector(_ name: String) -> Bool {
        let key = Self.normalizedPolicyName(name)
        return [
            "节点选择", "proxy", "proxy select", "select proxy", "node selection",
        ].contains(key)
    }

    private func isGeneralRoutingTarget(_ name: String) -> Bool {
        isCoreRoutingTarget(name) || Self.routingRegion(for: name) != nil
    }

    private func isCoreRoutingTarget(_ name: String) -> Bool {
        let key = Self.normalizedPolicyName(name)
        let coreNames: Set<String> = [
            "节点选择", "手动切换", "自动选择",
            "proxy", "proxy select", "select proxy", "node selection",
            "manual", "manual switch", "manual select",
            "auto", "auto select", "automatic", "automatic selection",
        ]
        return coreNames.contains(key)
    }

    private static func normalizedPolicyName(_ name: String) -> String {
        removingLeadingEmoji(from: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private enum SupplementalRoutingRegion: CaseIterable, Hashable {
        case hongKong
        case japan
        case unitedStates
        case singapore
        case taiwan
        case korea

        var canonicalName: String {
            switch self {
            case .hongKong: "🇭🇰 香港节点"
            case .japan: "🇯🇵 日本节点"
            case .unitedStates: "🇺🇸 美国节点"
            case .singapore: "🇸🇬 狮城节点"
            case .taiwan: "🇨🇳 台湾节点"
            case .korea: "🇰🇷 韩国节点"
            }
        }

        var nodePattern: String {
            switch self {
            case .hongKong:
                "(香港|HK|HKG|Hong Kong|HongKong)"
            case .japan:
                "(日本|东京|東京|大阪|埼玉|川日|泉日|沪日|深日|JP|Japan)"
            case .unitedStates:
                "(美国|美國|波特兰|达拉斯|俄勒冈|凤凰城|费利蒙|硅谷|拉斯维加斯|洛杉矶|洛杉磯|圣何塞|圣克拉拉|西雅图|芝加哥|United States|USA|(^|[^A-Za-z])US([^A-Za-z]|$))"
            case .singapore:
                "(新加坡|狮城|獅城|SG|SGP|Singapore)"
            case .taiwan:
                "(台湾|臺灣|台北|臺北|新北|彰化|TW|Taiwan)"
            case .korea:
                "(韩国|韓國|首尔|首爾|KR|KOR|Korea)"
            }
        }
    }

    private static func routingRegion(for name: String) -> SupplementalRoutingRegion? {
        let normalized = normalizedPolicyName(name)
            .replacingOccurrences(of: " nodes", with: "")
            .replacingOccurrences(of: " node", with: "")
        let key = normalized.hasSuffix("节点")
            ? String(normalized.dropLast(2))
            : normalized
        switch key {
        case "香港", "hong kong", "hongkong", "hk", "hkg":
            return .hongKong
        case "日本", "japan", "jp":
            return .japan
        case "美国", "美國", "united states", "usa", "us":
            return .unitedStates
        case "新加坡", "狮城", "獅城", "singapore", "sg", "sgp":
            return .singapore
        case "台湾", "臺灣", "taiwan", "tw":
            return .taiwan
        case "韩国", "韓國", "korea", "kr", "kor":
            return .korea
        default:
            return nil
        }
    }

    private static func injectMissingRegionalGroups(
        into groups: [RuleSchemeGroup]
    ) -> [RuleSchemeGroup] {
        var result = groups
        var names = Set(groups.map(\.name))
        let references = groups.flatMap(\.members).compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }
        for reference in references {
            guard !names.contains(reference),
                  let region = routingRegion(for: reference),
                  names.insert(reference).inserted else { continue }
            result.append(
                RuleSchemeGroup(
                    name: reference,
                    kind: .select,
                    members: [.nodePattern(region.nodePattern)]
                )
            )
        }
        return result
    }
}

enum RuleSchemeGroupEditorMode: Equatable {
    case routingTargets
    case nodePatternsOnly
}

/// A compact overlay for user-owned policy-group changes. Keeping it separate
/// from the imported scheme means refreshing an upstream rule file cannot
/// overwrite the user's order, mode, or candidate policies.
struct RuleSchemeCustomization: Codable, Hashable {
    let schemeID: String
    var groupOrder: [String]
    var groupOverrides: [String: RuleSchemeGroupOverride]
    /// Source policy names mapped to user-facing names. Optional keeps every
    /// snapshot written before identity editing decodable without migration.
    var groupRenames: [String: String]?
    /// Optional keeps snapshots written before group deletion support fully
    /// decodable without a custom migration.
    var removedGroupNames: Set<String>?

    init(
        schemeID: String,
        groupOrder: [String] = [],
        groupOverrides: [String: RuleSchemeGroupOverride] = [:],
        groupRenames: [String: String]? = nil,
        removedGroupNames: Set<String>? = nil
    ) {
        self.schemeID = schemeID
        self.groupOrder = groupOrder
        self.groupOverrides = groupOverrides
        self.groupRenames = groupRenames
        self.removedGroupNames = removedGroupNames
    }

    func renamedGroupName(_ name: String) -> String {
        groupRenames?[name] ?? name
    }

    func sourceGroupName(for visibleName: String) -> String {
        groupRenames?.first(where: { $0.value == visibleName })?.key ?? visibleName
    }

    func applying(to groups: [RuleSchemeGroup]) -> [RuleSchemeGroup] {
        let removedNames = removedGroupNames ?? []
        let customizedGroups = groups.compactMap { group -> RuleSchemeGroup? in
            let visibleName = renamedGroupName(group.name)
            guard !removedNames.contains(visibleName) else { return nil }
            let override = groupOverrides[visibleName] ?? groupOverrides[group.name]
            var members = override?.members ?? group.members
            members = members.map { member in
                guard case .reference(let name) = member else { return member }
                return .reference(renamedGroupName(name))
            }
            members.removeAll { member in
                guard case .reference(let name) = member else { return false }
                return removedNames.contains(name)
            }
            let kind = override?.kind ?? group.kind
            if kind == .select, members.isEmpty {
                members = [.reference("DIRECT")]
            }
            return RuleSchemeGroup(
                name: visibleName,
                kind: kind,
                members: members,
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance
            )
        }

        guard !groupOrder.isEmpty else { return customizedGroups }
        let byName = Dictionary(uniqueKeysWithValues: customizedGroups.map { ($0.name, $0) })
        var seen = Set<String>()
        let ordered = groupOrder.compactMap { name -> RuleSchemeGroup? in
            guard seen.insert(name).inserted else { return nil }
            return byName[name]
        }
        return ordered + customizedGroups.filter { seen.insert($0.name).inserted }
    }

    func applying(to expansion: CustomRuleFlowExpansion) -> CustomRuleFlowExpansion {
        let policyGroup = expansion.policyGroup.flatMap { applying(to: [$0]).first }
        return CustomRuleFlowExpansion(
            ruleSet: expansion.ruleSet,
            policyGroup: policyGroup,
            binding: RuleSetPolicyBinding(
                ruleSetID: expansion.binding.ruleSetID,
                policyGroupName: renamedGroupName(expansion.binding.policyGroupName)
            )
        )
    }
}

struct RuleSchemeGroupOverride: Codable, Hashable {
    var kind: RuleSchemeGroup.Kind?
    var members: [RuleSchemeGroupMember]?

    init(
        kind: RuleSchemeGroup.Kind? = nil,
        members: [RuleSchemeGroupMember]? = nil
    ) {
        self.kind = kind
        self.members = members
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
