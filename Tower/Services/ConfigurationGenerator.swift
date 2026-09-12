import Foundation

struct ConfigurationGenerator {
    private static let manualGroupName = "手动切换"
    private static let nestedSelectGroupName = "🚀 节点选择"
    private static let nestedAutoGroupName = "♻️ 自动选择"
    private static let nestedManualGroupName = "🎛️ 手动切换"
    private static let directGroupName = "🎯 直接连接"
    private static let regionDefinitions = [
        RegionDefinition(code: "HK", name: "🇭🇰 香港"),
        RegionDefinition(code: "JP", name: "🇯🇵 日本"),
        RegionDefinition(code: "US", name: "🇺🇸 美国"),
        RegionDefinition(code: "SG", name: "🇸🇬 新加坡"),
        RegionDefinition(code: "TW", name: "🇹🇼 台湾"),
        RegionDefinition(code: "KR", name: "🇰🇷 韩国"),
        RegionDefinition(code: "GB", name: "🇬🇧 英国"),
        RegionDefinition(code: "DE", name: "🇩🇪 德国"),
        RegionDefinition(code: "FR", name: "🇫🇷 法国")
    ]
    private static let otherRegionsName = "🌍 其他地区"
    // Rule types Surge, Shadowrocket and Loon all accept in a [Rule] section.
    // The bundled snapshot currently uses DOMAIN-SUFFIX, IP-CIDR, DOMAIN,
    // IP-CIDR6, PROCESS-NAME, DOMAIN-KEYWORD and GEOIP; the rest are listed so a
    // future snapshot does not lose valid rules.
    private static let surgeFamilyRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-SET", "DOMAIN-WILDCARD",
        "IP-CIDR", "IP-CIDR6", "IP6-CIDR", "IP-ASN", "GEOIP",
        "PROCESS-NAME", "USER-AGENT", "URL-REGEX", "RULE-SET",
        "DEST-PORT", "SRC-IP", "SRC-PORT", "IN-PORT", "PROTOCOL", "SUBNET",
        "AND", "OR", "NOT"
    ]

    private let rules: RuleRepository

    init(rules: RuleRepository = RuleRepository()) {
        self.rules = rules
    }

    func generate(
        nodes: [ProxyNode],
        preset: RulePreset,
        target: ClientTarget,
        countryCodes: [UUID: String] = [:],
        excludedKinds: Set<ProxyKind> = [],
        remoteSubscriptions: [RemoteSubscriptionLink] = [],
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter {
                writes(
                    $0,
                    to: target,
                    excluding: excludedKinds,
                    supportedKindsOverride: supportedKindsOverride
                )
            },
            reservedNames: reservedProxyNames(for: preset)
        )
        let remoteEntries = remoteSubscriptionEntries(
            target.supportsEmbeddedRemoteSubscriptions ? remoteSubscriptions : []
        )
        let remoteSourceIDs = Set(remoteEntries.map(\.sourceID))
        let inlineNodes = supported.filter { node in
            node.sourceID.map(remoteSourceIDs.contains) != true
        }
        let regionGroups = makeRegionGroups(nodes: supported, countryCodes: countryCodes)
        let content: String
        switch target {
        case .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing:
            content = clash(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                preset: preset,
                regionGroups: regionGroups,
                target: target
            )
        case .surge, .surgeMac:
            content = surgeLike(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                preset: preset,
                regionGroups: regionGroups,
                shadowrocket: false
            )
        case .shadowrocket:
            // Shadowrocket accepts Clash YAML directly. Keeping nodes in that
            // structured form preserves connection fields which have no
            // reliable equivalent in its legacy one-line configuration
            // dialect (client fingerprints, port hopping and nested transport
            // options in particular).
            content = clash(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: [],
                preset: preset,
                regionGroups: regionGroups,
                target: .shadowrocket
            )
        case .loon:
            content = loon(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                preset: preset,
                regionGroups: regionGroups
            )
        case .quanx:
            content = quanX(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                preset: preset,
                regionGroups: regionGroups
            )
        case .hiddify, .singBox:
            content = singBox(nodes: supported, preset: preset, regionGroups: regionGroups, target: target)
        case .egern:
            content = egern(
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                preset: preset,
                regionGroups: regionGroups
            )
        case .v2box:
            content = ""
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: inlineNodes.count,
            skippedNodeCount: nodes.filter { $0.sourceID.map(remoteSourceIDs.contains) != true }.count - inlineNodes.count,
            ruleCount: rules.count(for: preset),
            fileExtensionOverride: target == .shadowrocket ? "yaml" : nil,
            remoteSourceCount: remoteEntries.count
        )
    }

    // MARK: - Imported schemes

    /// Generates from an imported scheme, reproducing the groups the source
    /// file declared instead of Tower's built-in policy layout.
    func generate(
        nodes: [ProxyNode],
        scheme: RuleScheme,
        target: ClientTarget,
        schemes: RuleSchemeRepository = RuleSchemeRepository(),
        excludedKinds: Set<ProxyKind> = [],
        preferRuleSets: Bool = true,
        remoteSubscriptions: [RemoteSubscriptionLink] = [],
        sourceURLHashes: [UUID: String] = [:],
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> GeneratedConfiguration {
        // Adapt a copy for this export; the saved source remains Smart so switching
        // back to a native client restores its original algorithm and options.
        var scheme = scheme
        var downgradedSmart = false
        var ignoredNotifications = false
        scheme.groups = scheme.groups.map { group in
            let downgrade = group.kind == .smart && ![ClientTarget.surge, .surgeMac, .egern].contains(target)
            var parameters = group.parameters
            // Source exclusions still constrain local materialization when the
            // destination cannot emit these native options. Keep their internal
            // meaning separate from the options passed to the client.
            if parameters?["tower-source-patterns"] != nil {
                for key in ["exclude-filter", "exclude-type"] {
                    if let value = parameters?[key] { parameters?["tower-source-" + key] = value }
                }
            }
            if downgrade {
                downgradedSmart = true
                parameters?["priorities"] = nil
                parameters?["tower-priority-order"] = nil
            }
            if parameters?["no-alert"] != nil,
               !nativeOptionKeys(sourceFormat: group.sourceFormat, target: target).contains("no-alert") {
                parameters?["no-alert"] = nil
                ignoredNotifications = true
            }
            return RuleSchemeGroup(name: group.name, kind: downgrade ? .urlTest : group.kind,
                                   members: group.members, testURLString: group.testURLString,
                                   interval: group.interval, tolerance: group.tolerance,
                                   algorithm: group.algorithm, sourceType: group.sourceType,
                                   sourceFormat: group.sourceFormat, parameters: parameters)
        }
        var adaptationDiagnostics: [String] = []
        scheme.groups = scheme.groups.map { group in
            let adapted = compatiblePolicy(group, target: target)
            if adapted.kind != group.kind || adapted.members != group.members || (adapted.parameters ?? [:]) != (group.parameters ?? [:]) {
                adaptationDiagnostics.append(String(localized: "策略组“\(group.name)”已兼容转换为\(adapted.kind.displayTitle)，不支持的参数已忽略。"))
            }
            return adapted
        }
        let supported = uniquedNames(
            nodes.filter {
                writes(
                    $0,
                    to: target,
                    excluding: excludedKinds,
                    supportedKindsOverride: supportedKindsOverride
                )
            },
            reservedNames: Set(scheme.groups.map(\.name) + ["DIRECT", "REJECT", "direct", "reject"])
        )
        let remoteEntries = remoteSubscriptionEntries(
            target.supportsEmbeddedRemoteSubscriptions ? remoteSubscriptions : []
        )
        let remoteSourceIDs = Set(remoteEntries.map(\.sourceID))
        let graphIssues = RuleSchemePolicyValidator.validate(
            groups: scheme.groups,
            ruleTargets: scheme.rulesets.map(\.groupName),
            nodeNames: Set(supported.flatMap { [$0.name, NodeRegionResolver.displayName(for: $0)] }),
            allowUnresolvedPatterns: !remoteEntries.isEmpty
        )
        let resolved = resolveGroups(
            scheme: scheme,
            nodes: supported,
            target: target,
            preserveUnresolvedPatterns: !remoteEntries.isEmpty,
            sourceURLHashes: sourceURLHashes,
            remoteSourceIDs: remoteSourceIDs
        )
        let explicitlyInlineNames = Set(resolved.flatMap(\.inlineNodeNames))
        let inlineNodes = supported.filter { node in
            node.sourceID.map(remoteSourceIDs.contains) != true
                || explicitlyInlineNames.contains(NodeRegionResolver.displayName(for: node))
        }
        var diagnostics: [String] = []
        diagnostics += policyCapabilityIssues(scheme.groups, target: target)
        diagnostics += graphIssues.filter { $0.code != .emptyGroup }.map { issue in
            let detail = issue.names.joined(separator: ", ")
            return String(localized: "策略组校验失败（\(issue.code.displayTitle)）：\(detail)。请修正后导出。")
        }
        let normalizedNames = scheme.groups.map { group in
            [.surge, .surgeMac, .loon, .quanx].contains(target) ? confName(group.name) : collapsingLineBreaks(group.name)
        }
        let collidedNames = Dictionary(grouping: normalizedNames, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        if !collidedNames.isEmpty {
            let detail = collidedNames.joined(separator: ", ")
            let label = RuleSchemePolicyValidator.Code.duplicateGroupName.displayTitle
            diagnostics.append(String(localized: "策略组校验失败（\(label)）：\(detail)。请修正后导出。"))
        }
        let missingDomainSets = !([.surge, .surgeMac].contains(target) && preferRuleSets)
            && scheme.rulesets.contains { !schemes.hasDomainSetContent($0.resource) }
        if missingDomainSets {
            diagnostics.append(String(localized: "部分规则还没下载完成") + " · " + String(localized: "刷新规则"))
        }
        var capabilityBlocked = !diagnostics.isEmpty
        diagnostics += adaptationDiagnostics
        if downgradedSmart {
            diagnostics.append(String(localized: "当前客户端不支持 Smart，已转换为延迟优选。"))
        }
        if ignoredNotifications {
            diagnostics.append(String(localized: "已忽略当前客户端不支持的通知设置。"))
        }
        for (source, group) in zip(scheme.groups, resolved) where group.kind == .select
            && group.members == [builtinPolicyName("DIRECT", target: target)]
            && !(source.kind == .select && source.members == [.reference("DIRECT")]) {
            diagnostics.append(String(localized: "策略组“\(group.name)”没有匹配节点，已回退为直连。"))
        }
        let knownPolicies = Set(scheme.groups.map(\.name)
            + supported.map { NodeRegionResolver.displayName(for: $0) }
            + Array(RoutingBuiltinPolicies.names))
        let references = scheme.groups.flatMap(\.members).compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }
        let unknownPolicies = Set(scheme.rulesets.map(\.groupName) + references).subtracting(knownPolicies)
        if !unknownPolicies.isEmpty {
            let names = unknownPolicies.sorted().joined(separator: ", ")
            diagnostics.append(String(localized: "规则引用了不存在的策略组：\(names)。请修正规则后导出。"))
        }
        let rulePlan = RuleSetEmissionPlanner(repository: schemes).plan(
            for: scheme,
            target: target,
            preferRuleSets: preferRuleSets
        )
        if !rulePlan.finalOptions.isEmpty,
           !RoutingRuleCapabilities.surgeTargets.contains(target) {
            capabilityBlocked = true
            let body = (["FINAL", rulePlan.finalGroupName ?? ""] + rulePlan.finalOptions).joined(separator: ",")
            diagnostics.append(String(localized: "无法转换规则：\(body) → \(target.name)。"))
        }
        var unsupportedRuleCount = 0
        for rule in rulePlan.inlineRules {
            let supportedRule: Bool
            if target.usesSingBoxFormat { supportedRule = RoutingRuleCapabilities.singBoxCondition(rule.line) != nil }
            else if target == .egern { supportedRule = egernRule(rule.line, policy: rule.policyName) != nil }
            else { supportedRule = mappedRule(rule.line, policyName: rule.policyName, target: target) != nil }
            if !supportedRule {
                unsupportedRuleCount += 1
                if rule.policyName.uppercased().hasPrefix("REJECT") { capabilityBlocked = true }
                diagnostics.append(String(localized: "无法转换规则：\(rule.line) → \(target.name)。"))
            }
        }
        for policy in Set(scheme.rulesets.map(\.groupName) + references) where RoutingBuiltinPolicies.names.contains(policy) && !RoutingBuiltinPolicies.supports(policy, target: target) {
            capabilityBlocked = true
            diagnostics.append(String(localized: "当前客户端不支持内置策略：\(policy)。"))
        }
        let content: String
        switch target {
        case .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing:
            content = clashScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                target: target,
                rulePlan: rulePlan
            )
        case .shadowrocket:
            content = clashScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: [],
                target: .shadowrocket,
                rulePlan: rulePlan
            )
        case .surge, .surgeMac:
            content = surgeLikeScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                target: target,
                rulePlan: rulePlan
            )
        case .loon:
            content = loonScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                rulePlan: rulePlan
            )
        case .quanx:
            content = quanXScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                rulePlan: rulePlan
            )
        case .hiddify, .singBox:
            content = singBoxScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                rulePlan: rulePlan,
                target: target,
                dnsDomainRules: target == .singBox ? SingBoxDNSPolicy.domainRules(from:
                    RuleSetEmissionPlanner(repository: schemes).plan(
                        for: scheme, target: target, preferRuleSets: false
                    ).inlineRules
                ) : []
            )
        case .egern:
            content = egernScheme(
                scheme,
                groups: resolved,
                nodes: supported,
                inlineNodes: inlineNodes,
                remoteSubscriptions: remoteEntries,
                rulePlan: rulePlan
            )
        case .v2box:
            content = ""
        }

        return GeneratedConfiguration(
            target: target,
            content: unknownPolicies.isEmpty && !capabilityBlocked ? content : "",
            supportedNodeCount: inlineNodes.count,
            skippedNodeCount: nodes.filter { $0.sourceID.map(remoteSourceIDs.contains) != true }.count - inlineNodes.count,
            ruleCount: capabilityBlocked || !unknownPolicies.isEmpty ? 0 : max(0, ruleCount(for: scheme, schemes: schemes) - unsupportedRuleCount),
            fileExtensionOverride: target == .shadowrocket ? "yaml" : nil,
            remoteSourceCount: remoteEntries.count,
            diagnostics: diagnostics,
            hasInvalidPolicyReferences: !unknownPolicies.isEmpty || capabilityBlocked
        )
    }

    /// Return nil when an algorithm has no faithful native representation.
    private func loadBalanceAlgorithm(_ value: String?, target: ClientTarget) -> String? {
        let raw = (value ?? "destination-hash").lowercased().replacingOccurrences(of: "_", with: "-")
        let kind: String
        switch raw {
        case "round-robin", "roundrobin": kind = "round-robin"
        case "hash", "dest-hash", "destination-hash", "consistent-hashing", "pcc", "persistent": kind = "hash"
        case "random": kind = "random"
        case "sticky-sessions": kind = "sticky-sessions"
        default: return nil
        }
        switch target {
        case .surge, .surgeMac: return kind == "random" ? "random" : kind == "hash" ? "persistent" : nil
        case .quanx: return kind == "round-robin" ? "round-robin" : kind == "hash" ? "dest-hash" : nil
        case .loon: return kind == "random" ? "Random" : kind == "hash" ? "PCC" : kind == "round-robin" ? "Round-Robin" : nil
        case .egern: return kind == "hash" ? "hash" : kind == "round-robin" ? "round_robin" : nil
        case .clash, .clashMi:
            return kind == "hash" ? "consistent-hashing" : ["round-robin", "sticky-sessions"].contains(kind) ? kind : nil
        case .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty: return kind == "hash" ? "consistent-hashing" : kind == "round-robin" ? kind : nil
        default: return nil
        }
    }

    private func stringArray(_ text: String?) -> [String]? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String]
    }

    private func safeConditionalRules(_ text: String?) -> String? {
        guard let text, let data = text.data(using: .utf8),
              let rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: [String: String]]],
              rules.allSatisfy({ rule in
                  rule.count == 1 && rule.allSatisfy { key, value in
                      ["ssid", "bssid", "cellular"].contains(key)
                        && Set(value.keys) == Set(["match", "policy"])
                  }
              }),
              let encoded = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    private func validConditional(_ group: RuleSchemeGroup, target: ClientTarget) -> Bool {
        let parameters = group.parameters ?? [:]
        switch target {
        case .surge, .surgeMac:
            guard group.sourceFormat == "surge", let fields = stringArray(parameters["subnet-fields"]),
                  fields.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("default=") || $0.hasPrefix("default =") }) else { return false }
            return fields.allSatisfy { $0.contains("=") && !$0.contains("\n") && !$0.contains("\r") }
        case .quanx:
            guard group.sourceFormat == "quanx", let fields = stringArray(parameters["ssid-members"]), fields.count >= 2 else { return false }
            return fields.enumerated().allSatisfy { offset, field in
                guard !field.contains("\n"), !field.contains("\r") else { return false }
                if offset < 2 { return true }
                guard let colon = field.firstIndex(of: ":") else { return false }
                // A literal comma in the SSID has no documented escape in QX;
                // reject instead of percent-encoding it into a different network.
                return !field[..<colon].contains(",")
            }
        case .egern:
            return group.sourceFormat == "egern" && parameters["default_policy"] != nil
                && safeConditionalRules(parameters["rules"]) != nil
                && Set(parameters.keys).isSubset(of: ["name", "rules", "default_policy", "type", "tower-source-bindings", "tower-source-tags", "tower-source-patterns"])
        default: return false
        }
    }

    /// Only pass through documented scalar options in the same dialect. Units
    /// and meanings are deliberately not guessed across clients.
    private func nativeOptionKeys(sourceFormat: String?, target: ClientTarget) -> Set<String> {
        switch (sourceFormat, target) {
        case ("surge", .surge), ("surge", .surgeMac): return ["timeout", "evaluate-before-use", "no-alert"]
        case ("surge", .loon): return ["max-timeout"]
        case ("quanx", .quanx): return ["alive-checking"]
        case ("clash", .clash), ("clash", .clashMi):
            return ["lazy", "timeout", "max-failed-times", "exclude-filter", "exclude-type", "disable-udp"]
        case ("clash", .clashApple), ("clash", .clashVerge), ("clash", .clashMac), ("clash", .flClash), ("clash", .mihomoParty): return ["lazy", "timeout"]
        case ("egern", .egern): return ["timeout", "flatten", "block_quic"]
        case ("sing-box", .singBox), ("sing-box", .hiddify):
            return ["idle_timeout", "interrupt_exist_connections"]
        default: return []
        }
    }

    private func isSafeNativeOption(_ key: String, value: String) -> Bool {
        if ["no-alert", "evaluate-before-use"].contains(key) {
            return ["true", "false", "0", "1"].contains(value)
        }
        if ["evaluate-before-use", "no-alert", "alive-checking", "lazy", "disable-udp", "flatten", "block_quic", "interrupt_exist_connections"].contains(key) {
            return ["true", "false"].contains(value)
        }
        if ["timeout", "max-timeout", "max-failed-times"].contains(key) {
            return Int(value).map { $0 >= 0 } ?? false
        }
        if key == "idle_timeout" { return value.range(of: "^[0-9]+(ms|s|m|h)$", options: .regularExpression) != nil }
        if key == "exclude-filter" { return (try? NSRegularExpression(pattern: value)) != nil }
        if key == "exclude-type" { return value.range(of: "^[a-zA-Z0-9|_-]+$", options: .regularExpression) != nil }
        return false
    }

    private func nativeOptions(_ group: ResolvedSchemeGroup, target: ClientTarget) -> [(String, String)] {
        let allowed = nativeOptionKeys(sourceFormat: group.sourceFormat, target: target)
        return (group.parameters ?? [:]).filter { allowed.contains($0.key) && isSafeNativeOption($0.key, value: $0.value) }.sorted { $0.key < $1.key }
    }

    private func appendNativeOptions(_ group: ResolvedSchemeGroup, target: ClientTarget, to output: inout String) {
        let options = nativeOptions(group, target: target)
        if target == .egern, group.parameters?["flatten"] == "true", let filter = group.parameters?["filter"] {
            output += "      filter: \(yaml(filter))\n"
        }
        guard !options.isEmpty else { return }
        if [.surge, .surgeMac, .loon, .quanx].contains(target) {
            if output.hasSuffix("\n") { output.removeLast() }
            output += options.map { ", \($0.0)=\(confValue($0.1))" }.joined() + "\n"
        } else {
            let indent = target == .egern ? "      " : "    "
            for (key, value) in options {
                let scalar = ["exclude-filter", "exclude-type"].contains(key) ? yaml(value) : value
                output += "\(indent)\(key): \(scalar)\n"
            }
        }
    }

    private func orderedEgernPriorities(_ parameters: [String: String]?) -> [(String, String)]? {
        guard let raw = parameters?["priorities"], let data = raw.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: NSNumber],
              !values.isEmpty,
              values.allSatisfy({ (try? NSRegularExpression(pattern: $0.key)) != nil && $0.value.doubleValue.isFinite && $0.value.doubleValue >= 0 }) else { return nil }
        let order: [String]
        if let declared = stringArray(parameters?["tower-priority-order"]) {
            guard declared.count == values.count, Set(declared) == Set(values.keys) else { return nil }
            order = declared
        } else {
            // With no source-order metadata, reordering is safe only when every coefficient is equal.
            guard Set(values.values.map(\.doubleValue)).count <= 1 else { return nil }
            order = values.keys.sorted()
        }
        return order.compactMap { key in values[key].map { (key, $0.stringValue) } }
    }

    private func supportsPolicyKind(_ group: RuleSchemeGroup, target: ClientTarget) -> Bool {
            switch group.kind {
            case .select, .urlTest: return true
            case .smart: return [.surge, .surgeMac, .egern].contains(target)
            case .fallback: return [.surge, .surgeMac, .quanx, .clash, .clashMi, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .loon, .egern, .shadowrocket].contains(target)
            case .loadBalance: return loadBalanceAlgorithm(group.algorithm, target: target) != nil
            case .relay: return [.clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty].contains(target) || (target == .loon && group.sourceType == "chain")
            case .conditional: return validConditional(group, target: target)
            case .unsupported: return false
            }
    }

    /// Export-only adaptation; never overwrite the user's original policy model.
    private func compatiblePolicy(_ group: RuleSchemeGroup, target: ClientTarget) -> RuleSchemeGroup {
        var kind = group.kind
        var members = group.members
        var parameters = group.parameters ?? [:]
        if !supportsPolicyKind(group, target: target) {
            switch kind {
            case .smart, .fallback, .loadBalance: kind = .urlTest
            case .conditional:
                kind = .select
                var defaultPolicy = parameters["default_policy"]
                if group.sourceFormat == "surge", let fields = stringArray(parameters["subnet-fields"]) {
                    defaultPolicy = fields.compactMap { field -> String? in
                        let pair = field.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        return pair.count == 2 && pair[0] == "default" ? pair[1] : nil
                    }.first
                } else if group.sourceFormat == "quanx" {
                    defaultPolicy = stringArray(parameters["ssid-members"])?.first
                }
                if let defaultPolicy, !defaultPolicy.isEmpty { members = [.reference(defaultPolicy)] }
            case .relay, .unsupported: kind = .select
            case .select, .urlTest: break
            }
            for key in ["subnet-fields", "ssid-members", "default_policy", "rules", "priorities", "tower-priority-order"] {
                parameters[key] = nil
            }
        }
        func copy(_ options: [String: String]) -> RuleSchemeGroup {
            RuleSchemeGroup(name: group.name, kind: kind, members: members,
                testURLString: group.testURLString, interval: group.interval, tolerance: group.tolerance,
                algorithm: group.algorithm, sourceType: group.sourceType,
                sourceFormat: group.sourceFormat, parameters: options.isEmpty ? nil : options)
        }
        // Conditional data and priority maps must be validated together, not one key at a time.
        let compoundKeys: Set<String> = kind == .conditional
            ? ["subnet-fields", "ssid-members", "default_policy", "rules"]
            : kind == .smart ? ["priorities", "tower-priority-order"] : []
        let compound = parameters.filter { compoundKeys.contains($0.key) }
        if !compound.isEmpty && !policyCapabilityIssues([copy(compound)], target: target).isEmpty {
            for key in compoundKeys { parameters[key] = nil }
        }
        for (key, value) in parameters where !compoundKeys.contains(key) {
            var probe = compound
            probe[key] = value
            if !policyCapabilityIssues([copy(probe)], target: target).isEmpty {
                parameters[key] = nil
            }
        }
        return copy(parameters)
    }

    private func policyCapabilityIssues(_ groups: [RuleSchemeGroup], target: ClientTarget) -> [String] {
        groups.compactMap { group in
            let supported = supportsPolicyKind(group, target: target)
            // Source structure and fields already represented by the model are
            // not raw output. Never copy arbitrary source options into another dialect.
            let represented: Set<String> = ["name", "tag", "type", "proxies", "policies", "outbounds", "url", "latency_test_url", "interval", "check-interval", "tolerance", "algorithm", "strategy", "persistent", "raw-fields", "include-other-group", "include-all-proxies", "include-all", "policy-path", "policy-regex-filter", "server-tag-regex", "filter", "use", "urls", "update-interval", "update_interval", "icon", "hidden", "resource-tag-regex", "tower-source-bindings", "tower-source-tags", "tower-source-patterns"]
            let unhandled = (group.parameters ?? [:]).filter { key, value in
                if ["resource-tag-regex", "server-tag-regex", "filter", "policy-regex-filter"].contains(key) { return (try? NSRegularExpression(pattern: value)) == nil }
                if key == "tower-source-bindings" {
                    guard let data = value.data(using: .utf8),
                          (try? JSONSerialization.jsonObject(with: data)) is [String: String] else { return true }
                    return false
                }
                if ["tower-source-patterns", "tower-source-tags"].contains(key) { return stringArray(value) == nil }
                if key == "tower-source-exclude-filter" { return !isSafeNativeOption("exclude-filter", value: value) }
                if key == "tower-source-exclude-type" { return !isSafeNativeOption("exclude-type", value: value) }
                if represented.contains(key) { return false }
                if nativeOptionKeys(sourceFormat: group.sourceFormat, target: target).contains(key),
                   isSafeNativeOption(key, value: value) { return false }
                if group.kind == .conditional, validConditional(group, target: target) { return false }
                if key == "alive-checking", value == "false" { return false }
                if key == "tower-priority-order", target == .egern, group.kind == .smart { return stringArray(value) == nil }
                if key == "priorities", target == .egern, group.kind == .smart {
                    return orderedEgernPriorities(group.parameters) == nil
                }
                return true
            }.keys.sorted()
            guard !supported || !unhandled.isEmpty else { return nil }
            let type = ([group.sourceType ?? group.kind.rawValue] + unhandled).joined(separator: ", ")
            return String(localized: "策略组“\(group.name)”的类型或参数（\(type)）无法在 \(target.rawValue) 中保持原意，请先修改策略组。")
        }
    }

    /// Generates the remote node resource expected by clients that can add a
    /// subscription without replacing their rules and policy groups.
    func generateNodeSubscription(
        nodes: [ProxyNode],
        target: ClientTarget,
        excludedKinds: Set<ProxyKind> = [],
        profileName: String = TowerBrand.localizedName
    ) -> GeneratedConfiguration {
        guard target.supportsNodesOnlyExport else {
            return GeneratedConfiguration(
                target: target,
                content: "",
                supportedNodeCount: 0,
                skippedNodeCount: nodes.count,
                ruleCount: 0,
                profileName: profileName,
                contentMode: .nodesOnly,
                fileExtensionOverride: target.usesClashFormat ? "yaml" : "txt"
            )
        }

        var supported = uniquedNames(
            nodes.filter { writes($0, to: target, excluding: excludedKinds) },
            reservedNames: target.copiesAggregatedSubscription(mode: .nodesOnly)
                ? ["DIRECT", "REJECT", "direct", "reject"] : []
        )
        // A Surge policy-path list cannot carry the separate WireGuard section
        // required by section-name. Keep these nodes in full-profile export.
        if target == .surge || target == .surgeMac {
            supported.removeAll { $0.kind == .wireguard }
        }
        // Snell has no subscription URI. WireGuard URI conventions also vary
        // between producers, so Shadowrocket receives both only in the full
        // profile form that carries their complete settings.
        if target == .shadowrocket {
            supported.removeAll { $0.kind == .snell || $0.kind == .wireguard }
        }

        let content: String
        switch target {
        case .shadowrocket:
            let generator = ProxyNodeShareLinkGenerator()
            let links = supported.map { generator.canonicalLink(for: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            content = Data(links.joined(separator: "\n").utf8).base64EncodedString()
        case .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing:
            content = "proxies:\n" + (supported.isEmpty
                ? "  []\n"
                : supported.map { clashNode($0, target: target) }.joined(separator: "\n") + "\n")
        case .surge, .surgeMac:
            content = supported.map { surgeNode($0, shadowrocket: false) }.joined(separator: "\n")
                + (supported.isEmpty ? "" : "\n")
        case .loon:
            content = supported.map(loonNode).joined(separator: "\n") + (supported.isEmpty ? "" : "\n")
        case .quanx:
            content = supported.map(quanXNode).joined(separator: "\n") + (supported.isEmpty ? "" : "\n")
        case .hiddify:
            let generator = ProxyNodeShareLinkGenerator()
            content = supported.map { generator.canonicalLink(for: $0) }.joined(separator: "\n")
                + (supported.isEmpty ? "" : "\n")
        case .v2box:
            let generator = ProxyNodeShareLinkGenerator()
            let links = supported.map { generator.canonicalLink(for: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            content = Data(links.joined(separator: "\n").utf8).base64EncodedString()
        default:
            content = ""
            supported = []
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: 0,
            profileName: profileName,
            contentMode: .nodesOnly,
            fileExtensionOverride: target.usesClashFormat ? "yaml" : "txt"
        )
    }

    /// A node reaches the configuration when the client can express it and the
    /// user has not excluded that protocol. Excluded nodes stay in the input so
    /// they are reported as skipped rather than vanishing from the counts.
    private func writes(
        _ node: ProxyNode,
        to target: ClientTarget,
        excluding excludedKinds: Set<ProxyKind>,
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> Bool {
        let supportsKind = supportedKindsOverride?.contains(node.kind) ?? target.supports(node.kind)
        guard supportsKind, !excludedKinds.contains(node.kind) else { return false }
        // sing-box supports SPKI/public-key hashes, not leaf-certificate hashes.
        // Never silently discard a pin or relabel it as a public-key digest.
        if [.singBox, .hiddify].contains(target), certificatePin(node) != nil { return false }
        // An id that is neither a UUID nor short enough for Xray's name mapping
        // has no faithful form; writing it blank would look fine and never
        // connect.
        if [.vmess, .vless].contains(node.kind), node.exportableUUID == nil { return false }
        // Tower implements TUIC v5. Both parts of its credential are required;
        // a v4 token or half-filled v5 entry may import, but can never
        // authenticate. Skip and count it instead of poisoning the profile.
        if node.kind == .tuic {
            guard node.uuid.flatMap({ UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) != nil,
                  !(node.password ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        if node.kind == .wireguard {
            guard !(node.wireGuardPrivateKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(node.wireGuardPublicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(node.wireGuardAllowedIPs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !((node.wireGuardIPv4 ?? "").isEmpty && (node.wireGuardIPv6 ?? "").isEmpty) else {
                return false
            }
        }
        // REALITY needs the server's public key. A client with no field for it
        // would get plain TLS aimed at a borrowed SNI — the exact "looks right,
        // never connects" outcome, so those nodes are skipped and counted.
        if node.usesReality, !target.expressesReality { return false }
        // Stash's compatibility baseline supports Reality only on VLESS TCP.
        // Do not emit ordinary TLS when the source requires Reality.
        if target == .clash, node.usesReality,
           node.kind != .vless || !["", "tcp"].contains(node.transport?.lowercased() ?? "tcp") { return false }
        // Hako's verified outbound implementations do not consume Reality for
        // these kinds or native SS TLS. Preserve the source and report skips.
        if [.clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty].contains(target) {
            if node.usesReality, [.anytls, .socks5, .http].contains(node.kind) { return false }
            if node.kind == .shadowsocks, node.tls,
               (node.plugin ?? "").isEmpty, simpleObfsMode(node) == nil { return false }
        }
        // Native SS-over-TLS is distinct from Stash's supported SS plugins.
        if target == .clash, node.kind == .shadowsocks, node.tls,
           (node.plugin ?? "").isEmpty, simpleObfsMode(node) == nil { return false }
        // Stash before iOS 3.6 rejects Snell v4/v5 at configuration load time.
        // Until a client-version preference exists, use the compatible v1-v3
        // baseline. Never rewrite the version: it must match the server.
        // Omitted YAML version defaults to v1 in Stash.
        if node.kind == .snell, target == .clash, !(1...3).contains(node.version ?? 1) { return false }
        // Mihomo has its own version support, independent of Stash.
        if node.kind == .snell, [.clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi].contains(target), !(1...5).contains(node.version ?? 4) { return false }
        // Egern has no native ordinary SS-over-TLS transport. Never strip it.
        if target == .egern, node.kind == .shadowsocks, node.tls { return false }
        // sing-box 1.14 represents non-QUIC Snell v5 with version 4.
        // Other versions require capabilities Tower does not model yet.
        if node.kind == .snell, target == .singBox {
            guard [4, 5].contains(node.version ?? 4) else { return false }
            if let obfs = node.obfs, !obfs.isEmpty, !["none", "http"].contains(obfs.lowercased()) { return false }
        }
        // Official Shadowsocks has no native TLS field. Its SIP003 plugins
        // carry their own TLS; never silently export native SS TLS as plain SS.
        if [.singBox, .hiddify].contains(target), node.kind == .shadowsocks,
           node.tls, (node.plugin ?? "").isEmpty, simpleObfsMode(node) == nil { return false }
        // The official SOCKS outbound cannot express TLS. Dropping TLS would
        // change the protocol; exclude the node and keep it in skipped counts.
        if [.singBox, .hiddify].contains(target), node.kind == .socks5, node.tls || node.usesReality { return false }
        // Surge and Shadowrocket carry Hysteria 2's obfuscator in the key name
        // — `salamander-password` and a bare `obfsParam` — so neither has any
        // way to say "some other obfuscator". (Surge also documents its own
        // `gecko-password`, but nothing Tower parses produces that name.)
        // Writing one anyway would hand the password to Salamander and produce
        // the "looks right, never connects" outcome, so the node is skipped and
        // counted instead.
        if node.kind == .hysteria2, [.surge, .surgeMac, .shadowrocket].contains(target),
           let obfs = hysteria2Obfs(node), obfs.type.lowercased() != "salamander" { return false }
        if node.plugin == "v2ray-plugin" {
            // Quantumult X requires a confirmed non-multiplexed server.
            if target == .quanx, node.pluginMux != false { return false }
            // Only the WebSocket mode is modelled. These clients either expose
            // SIP003 directly or have a documented equivalent; the others must
            // skip instead of silently exporting plain Shadowsocks.
            guard node.transport == "ws",
                  [.clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing, .shadowrocket, .quanx, .hiddify, .singBox].contains(target) else { return false }
        }
        if !canExpressTransport(of: node, on: target) { return false }
        return true
    }

    private func canExpressTransport(of node: ProxyNode, on target: ClientTarget) -> Bool {
        guard [.vmess, .vless, .trojan].contains(node.kind) else { return true }
        let transport = node.transport?.lowercased() ?? "tcp"
        if transport == "tcp" || transport.isEmpty { return true }
        switch target {
        case .clash:
            if node.kind == .trojan { return ["ws", "grpc"].contains(transport) }
            return ["ws", "http", "h2", "grpc"].contains(transport)
        case .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing:
            if transport == "xhttp" { return node.kind == .vless }
            return ["ws", "http", "h2", "grpc", "httpupgrade"].contains(transport)
        case .surge, .surgeMac:
            return transport == "ws" && [.vmess, .trojan].contains(node.kind)
        case .shadowrocket:
            return ["ws", "http", "h2", "grpc", "httpupgrade", "xhttp"].contains(transport)
                && (transport != "xhttp" || node.kind == .vless)
        case .loon:
            if node.kind == .trojan { return ["ws", "http"].contains(transport) }
            return ["ws", "http"].contains(transport)
        case .quanx:
            return transport == "ws" || (node.kind == .vmess && transport == "http" && !node.tls)
        case .hiddify, .singBox:
            return ["ws", "http", "h2", "grpc", "httpupgrade"].contains(transport)
        case .egern:
            if node.kind == .trojan { return ["ws", "http"].contains(transport) }
            return ["ws", "http", "h2", "grpc"].contains(transport)
        case .v2box:
            return ["ws", "http", "h2", "grpc", "httpupgrade", "xhttp"].contains(transport)
                && (transport != "xhttp" || node.kind == .vless)
        }
    }

    struct RemoteSubscriptionEntry: Hashable {
        let sourceID: UUID
        let identifier: String
        let displayName: String
        let urlString: String
        let userAgent: String?
    }

    private func remoteSubscriptionEntries(
        _ subscriptions: [RemoteSubscriptionLink]
    ) -> [RemoteSubscriptionEntry] {
        subscriptions.enumerated().map { index, subscription in
            RemoteSubscriptionEntry(
                sourceID: subscription.sourceID,
                identifier: "tower-subscription-\(index + 1)",
                displayName: "塔台订阅 \(index + 1) · \(confName(subscription.name))",
                urlString: collapsingLineBreaks(subscription.urlString),
                userAgent: subscription.userAgent.map(collapsingLineBreaks)
            )
        }
    }

    private func remoteNodeNameSet(
        nodes: [ProxyNode],
        subscriptions: [RemoteSubscriptionEntry]
    ) -> Set<String> {
        let sourceIDs = Set(subscriptions.map(\.sourceID))
        return Set(nodes.compactMap { node in
            guard node.sourceID.map(sourceIDs.contains) == true else { return nil }
            return NodeRegionResolver.displayName(for: node)
        })
    }

    private func remoteFilter(for patterns: [String]) -> String? {
        let valid = patterns.compactMap { pattern -> String? in
            let trimmed = collapsingLineBreaks(pattern)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  (try? NSRegularExpression(pattern: trimmed)) != nil else { return nil }
            return trimmed
        }
        guard !valid.isEmpty else { return nil }
        if valid.contains(".*") { return nil }
        return valid.map { "(?:\($0))" }.joined(separator: "|")
    }

    private func exactNameFilter(_ names: [String]) -> String? {
        let names = names.removingDuplicates()
        guard !names.isEmpty else { return nil }
        let alternatives = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return "^(?:\(alternatives))$"
    }

    private func remoteGroupSelection(
        for group: ResolvedSchemeGroup,
        remoteNodeNames: Set<String>
    ) -> (includesRemoteNodes: Bool, filter: String?) {
        if group.allowedRemoteSourceIDs?.isEmpty == true { return (false, nil) }
        if !group.nodePatterns.isEmpty {
            return (true, remoteFilter(for: group.nodePatterns))
        }
        let explicitRemoteNames = group.members.filter { remoteNodeNames.contains($0) && !group.inlineNodeNames.contains($0) }
        return (!explicitRemoteNames.isEmpty, exactNameFilter(explicitRemoteNames))
    }

    struct ResolvedSchemeGroup {
        let name: String
        let kind: RuleSchemeGroup.Kind
        /// Group references and node names, in the order the source declared.
        let members: [String]
        /// Only the node names, needed for the Quantumult X tag regex.
        let nodeNames: [String]
        /// Preserve an all-node source regex instead of expanding it into one
        /// very long Quantumult X tag regex.
        let matchesAllNodes: Bool
        /// Original subscription-node regexes. Remote providers can apply
        /// these after a background refresh, including to nodes Tower has not
        /// downloaded yet.
        let nodePatterns: [String]
        let testURL: String
        let interval: Int
        let tolerance: Int
        var algorithm: String? = nil
        var parameters: [String: String]? = nil
        var sourceFormat: String? = nil
        var allowedRemoteSourceIDs: Set<UUID>? = nil
        var inlineNodeNames: Set<String> = []
    }

    private func boundSourceIDs(_ group: RuleSchemeGroup, sourceURLHashes: [UUID: String]) -> Set<UUID>? {
        let parameters = group.parameters ?? [:]
        let restrictsSources = parameters["use"] != nil || parameters["tower-source-tags"] != nil
            || parameters["resource-tag-regex"] != nil
        guard restrictsSources else { return nil }
        guard let raw = parameters["tower-source-bindings"], let data = raw.data(using: .utf8),
              let bindings = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return [] }
        var tags = Set(bindings.keys)
        if let use = stringArray(group.parameters?["use"]) { tags.formIntersection(use) }
        if let selected = stringArray(group.parameters?["tower-source-tags"]) { tags.formIntersection(selected) }
        if let regex = group.parameters?["resource-tag-regex"] {
            guard let expression = try? NSRegularExpression(pattern: regex) else { return [] }
            tags = Set(tags.filter { expression.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil })
        }
        let hashes = Set(tags.compactMap { bindings[$0] })
        return Set(sourceURLHashes.compactMap { hashes.contains($0.value) ? $0.key : nil })
    }

    private func sourceNodeAllowed(_ node: ProxyNode, parameters: [String: String], caseInsensitive: Bool) -> Bool {
        if let exclude = parameters["tower-source-exclude-filter"] ?? parameters["exclude-filter"],
           let expression = try? NSRegularExpression(pattern: exclude, options: caseInsensitive ? [.caseInsensitive] : []),
           expression.firstMatch(in: node.name, range: NSRange(node.name.startIndex..., in: node.name)) != nil { return false }
        if let excluded = parameters["tower-source-exclude-type"] ?? parameters["exclude-type"] {
            let kind = node.kind == .shadowsocks ? "ss" : node.kind.rawValue.lowercased()
            if excluded.lowercased().split(separator: "|").map(String.init).contains(kind) { return false }
        }
        return true
    }

    private func groupSubscriptions(_ group: ResolvedSchemeGroup, from subscriptions: [RemoteSubscriptionEntry]) -> [RemoteSubscriptionEntry] {
        guard let allowed = group.allowedRemoteSourceIDs else { return subscriptions }
        return subscriptions.filter { allowed.contains($0.sourceID) }
    }

    private func resolveGroups(
        scheme: RuleScheme,
        nodes: [ProxyNode],
        target: ClientTarget,
        preserveUnresolvedPatterns: Bool = false,
        sourceURLHashes: [UUID: String] = [:],
        remoteSourceIDs: Set<UUID> = []
    ) -> [ResolvedSchemeGroup] {
        let groupNames = Set(scheme.groups.map(\.name))
        let displayNames = nodes.map { NodeRegionResolver.displayName(for: $0) }

        return scheme.groups.map { group in
            var members: [String] = []
            var nodeNames: [String] = []
            var matchesAllNodes = false
            var nodePatterns: [String] = []
            var inlineNodeNames: Set<String> = []
            let sourceIDs = boundSourceIDs(group, sourceURLHashes: sourceURLHashes)
            let sourcePatterns = Set(stringArray(group.parameters?["tower-source-patterns"]) ?? [])
            let dynamicSourceNodes = nodes.filter { node in
                (sourceIDs == nil || node.sourceID.map { sourceIDs!.contains($0) } == true)
                    && sourceNodeAllowed(node, parameters: group.parameters ?? [:],
                        caseInsensitive: group.sourceFormat == nil || group.sourceFormat == "subconverter")
            }

            for member in group.members {
                switch member {
                case .reference(let name):
                    guard group.kind != .smart || target == .egern else { continue }
                    // DIRECT and REJECT are spelled differently per client; any
                    // other reference points at a sibling group.
                    if groupNames.contains(name) {
                        members.append(name)
                    } else {
                        members.append(builtinPolicyName(name, target: target))
                        if displayNames.contains(name) {
                            nodeNames.append(name)
                            if sourceIDs != nil { inlineNodeNames.insert(name) }
                        }
                    }
                case .nodePattern(let pattern):
                    guard (try? NSRegularExpression(pattern: pattern)) != nil else { continue }
                    let isSourcePattern = sourcePatterns.contains(pattern)
                    if sourceIDs == nil || isSourcePattern { nodePatterns.append(pattern) }
                    if pattern.trimmingCharacters(in: .whitespacesAndNewlines) == ".*" { matchesAllNodes = true }
                    let pool = isSourcePattern ? dynamicSourceNodes : nodes
                    let matches = matchingNodeNames(pattern, nodes: pool,
                        displayNames: pool.map { NodeRegionResolver.displayName(for: $0) },
                        caseInsensitive: group.sourceFormat == nil || group.sourceFormat == "subconverter")
                    members.append(contentsOf: matches)
                    nodeNames.append(contentsOf: matches)
                    if sourceIDs != nil && !isSourcePattern { inlineNodeNames.formUnion(matches) }
                }
            }

            let hasRemotePool = !nodePatterns.isEmpty && preserveUnresolvedPatterns
                && (sourceIDs == nil || !sourceIDs!.intersection(remoteSourceIDs).isEmpty)
            let empty = members.isEmpty && !hasRemotePool
            if empty { members = [builtinPolicyName("DIRECT", target: target)] }
            return ResolvedSchemeGroup(
                name: group.name,
                kind: empty ? .select : group.kind,
                members: members.removingDuplicates(),
                nodeNames: nodeNames.removingDuplicates(),
                matchesAllNodes: matchesAllNodes,
                nodePatterns: nodePatterns.removingDuplicates(),
                testURL: group.testURLString ?? "http://www.gstatic.com/generate_204",
                interval: group.interval ?? 300,
                tolerance: group.tolerance ?? 50,
                algorithm: group.algorithm,
                parameters: group.parameters,
                sourceFormat: group.sourceFormat,
                allowedRemoteSourceIDs: sourceIDs,
                inlineNodeNames: inlineNodeNames
            )
        }
    }

    /// Matches the source regex against both the original remark and the name
    /// Tower will actually write, since Tower may prepend a flag or add a
    /// de-duplication suffix.
    private func matchingNodeNames(
        _ pattern: String,
        nodes: [ProxyNode],
        displayNames: [String],
        caseInsensitive: Bool = true
    ) -> [String] {
        if pattern == ".*" { return displayNames }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return []
        }

        return zip(nodes, displayNames).compactMap { node, displayName in
            let candidates = [displayName, node.name]
            let matched = candidates.contains { candidate in
                let range = NSRange(candidate.startIndex..., in: candidate)
                return expression.firstMatch(in: candidate, options: [], range: range) != nil
            }
            return matched ? displayName : nil
        }
    }

    private func builtinPolicyName(_ name: String, target: ClientTarget) -> String {
        switch name.uppercased() {
        case "DIRECT": target == .quanx ? "direct" : "DIRECT"
        case "REJECT": target == .quanx ? "reject" : "REJECT"
        default: name
        }
    }

    private func ruleCount(for scheme: RuleScheme, schemes: RuleSchemeRepository) -> Int {
        scheme.rulesets.reduce(0) { $0 + schemes.lines(for: $1.resource).count }
    }

    /// Emits every local rule in declaration order. `FINAL` is held separately
    /// by the planner because each format spells it differently and it must
    /// remain last even when the ordinary rules are remote resources.
    private func localSchemeRules(
        _ plan: RuleSetEmissionPlanner.Plan,
        target: ClientTarget,
        indent: String = ""
    ) -> String {
        var output = ""
        for entry in plan.entries {
            guard case .inline(let rule) = entry else { continue }
            if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: target) {
                output += "\(indent)\(mapped)\n"
            }
        }

        guard let finalGroup = plan.finalGroupName else { return output }
        switch target {
        case .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing: output += "\(indent)MATCH,\(finalGroup)\n"
        case .quanx: output += "\(indent)final, \(finalGroup)\n"
        default: output += "\(indent)FINAL,\(finalGroup)\n"
        }
        return output
    }

    /// Quantumult X has no `no-resolve` rule option. Its documented way to
    /// avoid resolving a hostname only to test later IP rules is one catch-all
    /// host rule immediately before `final`. Hostname requests take the same
    /// policy as `final`; pure-IP requests do not match `host-keyword` and
    /// continue to the final rule.
    private func quanXLocalSchemeRules(
        _ plan: RuleSetEmissionPlanner.Plan,
        dnsProtectionMode: RuleSchemeDNSProtectionMode
    ) -> String {
        var output = ""
        for entry in plan.entries {
            guard case .inline(let rule) = entry else { continue }
            if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: .quanx) {
                output += mapped + "\n"
            }
        }

        guard let finalGroup = plan.finalGroupName else { return output }
        let policy = confName(finalGroup)
        let sourceRequestsNoResolve = plan.inlineRules.contains {
            quanXSourceRuleRequestsNoResolve($0.line)
        }
        if dnsProtectionMode != .followScheme || sourceRequestsNoResolve {
            output += "host-keyword, ., \(policy)\n"
        }
        output += "final, \(policy)\n"
        return output
    }

    private func quanXSourceRuleRequestsNoResolve(_ rule: String) -> Bool {
        let fields = rule.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let type = fields.first?.uppercased(),
              ["IP-CIDR", "IP-CIDR6", "IP6-CIDR", "IP-ASN", "GEOIP"].contains(type) else {
            return false
        }
        return fields.dropFirst(2).contains { $0.lowercased() == "no-resolve" }
    }

    private func schemeHeader(
        _ scheme: RuleScheme,
        target: ClientTarget,
        embedsRemoteSubscriptions: Bool = false
    ) -> String {
        let origin = scheme.sourceURLString ?? (scheme.isBundled ? "随 App 打包的快照" : "导出")
        let credentialNotice = embedsRemoteSubscriptions
            ? "Subscription URLs are embedded for client-side updates."
            : "Subscription credentials never leave this device."
        return """
        # Generated locally by 塔台 for \(target.name)
        # Rules: \(scheme.name) (\(origin))
        # \(credentialNotice)

        """
    }

    private func schemeIPv6(_ scheme: RuleScheme) -> Bool {
        scheme.networkSettings?.ipv6Enabled ?? true
    }

    private func schemePlainDNS(_ scheme: RuleScheme) -> [String] {
        let values = (scheme.networkSettings?.dnsServers ?? []).compactMap(
            RuleSchemeNetworkSettings.normalizedPlainDNSServer
        )
        return values.isEmpty ? ["223.5.5.5", "119.29.29.29"] : values
    }

    private func schemeEncryptedDNS(_ scheme: RuleScheme) -> [String] {
        let values = scheme.networkSettings?.encryptedDNSServers ?? []
        return values.isEmpty
            ? ["https://223.5.5.5/dns-query", "https://doh.pub/dns-query"]
            : values
    }

    private func schemeTestURL(_ scheme: RuleScheme) -> String {
        scheme.networkSettings?.proxyTestURLString
            ?? "http://www.gstatic.com/generate_204"
    }

    private func schemeDNSProtectionMode(_ scheme: RuleScheme) -> RuleSchemeDNSProtectionMode {
        scheme.networkSettings?.dnsProtectionMode ?? .standard
    }

    private func clashNetworkBlock(_ scheme: RuleScheme, target: ClientTarget) -> String {
        let plain = schemePlainDNS(scheme)
        let nameservers = schemeEncryptedDNS(scheme)
        let protectionMode = schemeDNSProtectionMode(scheme)
        let proxyResolvers = scheme.networkSettings == nil
            ? ["https://223.5.5.5/dns-query"]
            : nameservers
        let fallbackResolvers = scheme.networkSettings == nil
            ? ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"]
            : nameservers
        var output = "ipv6: \(schemeIPv6(scheme))\n\n"
        output += "dns:\n"
        output += "  enable: true\n"
        if protectionMode != .followScheme {
            output += "  enhanced-mode: fake-ip\n"
            output += "  fake-ip-range: 198.18.0.1/16\n"
            output += "  fake-ip-filter:\n"
            for value in ["*.lan", "+.local", "+.msftconnecttest.com", "+.msftncsi.com"] {
                output += "    - \(yaml(value))\n"
            }
        }
        output += "  default-nameserver:\n"
        for value in plain { output += "    - \(value)\n" }
        if protectionMode != .followScheme {
            output += "  proxy-server-nameserver:\n"
            for value in proxyResolvers { output += "    - \(value)\n" }
        }
        output += "  nameserver:\n"
        for value in nameservers { output += "    - \(value)\n" }
        if protectionMode != .followScheme {
            output += "  fallback:\n"
            for value in fallbackResolvers { output += "    - \(value)\n" }
            output += "  fallback-filter:\n"
            output += "    geoip: true\n"
            output += "    geoip-code: CN\n"
        }
        if protectionMode == .strict, [.clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi].contains(target) {
            output += "\ntun:\n"
            output += "  enable: true\n"
            output += "  stack: mixed\n"
            output += "  auto-route: true\n"
            output += "  auto-detect-interface: true\n"
            output += "  dns-hijack:\n"
            output += "    - any:53\n"
            output += "    - tcp://any:53\n"
            output += "  strict-route: true\n"
        }
        return output
    }

    private func clashScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        target: ClientTarget,
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let providerNames = remoteSubscriptions.map(\.identifier)
        var output = schemeHeader(
            scheme,
            target: target,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        """
        output += "\n" + clashNetworkBlock(scheme, target: target) + "\nproxies:\n"
        output += "\n"
        output += inlineNodes.isEmpty ? "  []\n" : inlineNodes.map { clashNode($0, target: target) }.joined(separator: "\n") + "\n"
        output += clashProxyProviders(remoteSubscriptions, target: target)
        output += "\nproxy-groups:\n"
        for group in groups {
            let providerNames = groupSubscriptions(group, from: remoteSubscriptions).map(\.identifier)
            let inlineMembers = group.members.filter { !remoteNodeNames.contains($0) || group.inlineNodeNames.contains($0) }
            let remoteSelection = remoteGroupSelection(
                for: group,
                remoteNodeNames: remoteNodeNames
            )
            switch group.kind {
            case .select:
                output += clashSelectGroup(
                    name: group.name,
                    nodeNames: inlineMembers,
                    providerNames: remoteSelection.includesRemoteNodes ? providerNames : [],
                    providerFilter: remoteSelection.filter
                )
            case .urlTest, .fallback, .loadBalance, .relay:
                var block = "  - name: \(yaml(group.name))\n"
                let type = group.kind == .urlTest ? "url-test" : group.kind == .fallback ? "fallback" : group.kind == .relay ? "relay" : "load-balance"
                block += "    type: \(type)\n"
                if group.kind == .loadBalance {
                    block += "    strategy: \(loadBalanceAlgorithm(group.algorithm, target: target) ?? "consistent-hashing")\n"
                }
                if group.kind != .relay {
                    block += "    url: \(yaml(group.testURL))\n"
                    block += "    interval: \(group.interval)\n"
                    if group.kind == .urlTest { block += "    tolerance: \(group.tolerance)\n" }
                }
                block += clashGroupMembers(
                    nodeNames: inlineMembers,
                    providerNames: remoteSelection.includesRemoteNodes ? providerNames : [],
                    providerFilter: remoteSelection.filter
                )
                output += block
            case .smart, .conditional, .unsupported: break // Capability preflight blocks these.
            }
            appendNativeOptions(group, target: target, to: &output)
        }
        let remoteResources = rulePlan.remoteResources
        if !remoteResources.isEmpty {
            output += "\nrule-providers:\n"
            for resource in remoteResources {
                let provider: (behavior: String, format: String, fileExtension: String)
                switch resource.format {
                case .clashDomainMRS:
                    provider = ("domain", "mrs", "mrs")
                case .clashIPCIDRMRS:
                    provider = ("ipcidr", "mrs", "mrs")
                case .clashProviderYAML:
                    provider = ("classical", "yaml", "yaml")
                default:
                    provider = ("classical", "text", "list")
                }
                output += "  \(resource.identifier):\n"
                output += "    type: http\n"
                output += "    behavior: \(resource.provider?.behavior?.replacingOccurrences(of: "-text", with: "") ?? provider.behavior)\n"
                output += "    format: \(resource.provider?.format ?? provider.format)\n"
                output += "    url: \(yaml(resource.url.absoluteString))\n"
                output += "    path: ./ruleset/\(resource.identifier).\(provider.fileExtension)\n"
                let referenceInterval = resource.options.first { $0.hasPrefix("update-interval=") }.flatMap { Int($0.dropFirst("update-interval=".count)) }
                output += "    interval: \(resource.provider?.interval ?? referenceInterval ?? 86400)\n"
            }
        }
        output += "\nrules:\n"
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                let options = resource.options.filter { !$0.hasPrefix("update-interval=") }
                let noResolve = options.isEmpty ? (resource.format == .clashIPCIDRMRS ? ",no-resolve" : "") : "," + options.joined(separator: ",")
                output += "  - RULE-SET,\(resource.identifier),\(resource.policyName)\(noResolve)\n"
            case .inline(let rule):
                // The document dialect is Clash YAML for all three callers,
                // but rule support still belongs to the selected client.
                if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: target) {
                    output += "  - \(mapped)\n"
                }
            }
        }
        if let final = rulePlan.finalGroupName { output += "  - MATCH,\(final)\n" }
        return output
    }

    private func surgeLikeScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        target: ClientTarget,
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let sourceGroupNames = remoteSubscriptions.map(\.displayName)
        var output = schemeHeader(
            scheme,
            target: target,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += "[General]\n"
        output += "loglevel = notify\n"
        output += "ipv6 = \(schemeIPv6(scheme))\n"
        output += "dns-server = \(schemePlainDNS(scheme).joined(separator: ", "))\n"
        output += "encrypted-dns-server = \(schemeEncryptedDNS(scheme).joined(separator: ", "))\n"
        if schemeDNSProtectionMode(scheme) == .strict, [.surge, .surgeMac].contains(target) {
            output += "hijack-dns = *:53\n"
            output += "encrypted-dns-follow-outbound-mode = true\n"
        }
        output += "skip-proxy = 127.0.0.1, localhost, *.local\n"
        output += "test-timeout = 5\n\n[Proxy]\n"
        output += "\n"
        for node in inlineNodes {
            output += surgeNode(node, shadowrocket: target == .shadowrocket) + "\n"
        }
        output += surgeWireGuardSections(inlineNodes)
        output += "\n[Proxy Group]\n"
        output += surgeRemoteSourceGroups(remoteSubscriptions)
        for group in groups {
            let sourceGroupNames = groupSubscriptions(group, from: remoteSubscriptions).map(\.displayName)
            let inlineMembers = group.members.filter { !remoteNodeNames.contains($0) || group.inlineNodeNames.contains($0) }
            let remoteSelection = remoteGroupSelection(
                for: group,
                remoteNodeNames: remoteNodeNames
            )
            let includedSources = remoteSelection.includesRemoteNodes ? sourceGroupNames : []
            switch group.kind {
            case .select:
                output += surgeSelect(
                    name: group.name,
                    values: inlineMembers,
                    sourceGroupNames: includedSources,
                    remoteFilter: remoteSelection.filter
                )
            case .urlTest, .smart:
                output += surgeURLTest(
                    name: group.name,
                    names: inlineMembers,
                    sourceGroupNames: includedSources,
                    remoteFilter: remoteSelection.filter,
                    testURL: group.testURL,
                    interval: group.interval,
                    tolerance: group.tolerance,
                    smart: group.kind == .smart && [.surge, .surgeMac].contains(target)
                )
            case .fallback, .loadBalance:
                var values = inlineMembers.map(confName)
                values += surgeRemoteGroupParameters(sourceGroupNames: includedSources, remoteFilter: remoteSelection.filter)
                values += ["url=\(confValue(group.testURL))", "interval=\(group.interval)"]
                if group.kind == .loadBalance, loadBalanceAlgorithm(group.algorithm, target: .surge) == "persistent" {
                    values.append("persistent=true")
                }
                output += "\(confName(group.name)) = \(group.kind == .fallback ? "fallback" : "load-balance"), \(values.joined(separator: ", "))\n"
            case .conditional:
                if let fields = stringArray(group.parameters?["subnet-fields"]) {
                    output += "\(confName(group.name)) = subnet, " + fields.map { field in
                        guard let equal = field.firstIndex(of: "=") else { return "" }
                        return "\(surgeQuoted(String(field[..<equal]).trimmingCharacters(in: .whitespaces)))=\(confName(String(field[field.index(after: equal)...]).trimmingCharacters(in: .whitespaces)))"
                    }.joined(separator: ", ") + "\n"
                }
            case .relay, .unsupported: break
            }
            appendNativeOptions(group, target: target, to: &output)
        }
        output += "\n[Rule]\n"
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                var options = resource.options
                if !options.contains(where: { $0.hasPrefix("update-interval=") }) { options.append("update-interval=\(resource.provider?.interval ?? 86400)") }
                output += (["RULE-SET", resource.url.absoluteString, confName(resource.policyName)] + options).joined(separator: ",") + "\n"
            case .inline(let rule):
                if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: target) {
                    output += mapped + "\n"
                }
            }
        }
        if let final = rulePlan.finalGroupName { output += (["FINAL", confName(final)] + rulePlan.finalOptions).joined(separator: ",") + "\n" }
        return output
    }

    private func loonScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteAliases = remoteSubscriptions.map(\.displayName)
        var filtersByGroupName: [String: String] = [:]
        var remoteFilters: [(name: String, pattern: String)] = []
        var filterSources: [String: Set<UUID>] = [:]
        for (index, group) in groups.enumerated() {
            let selection = remoteGroupSelection(for: group, remoteNodeNames: remoteNodeNames)
            guard selection.includesRemoteNodes, let filter = selection.filter else { continue }
            let name = "塔台筛选 \(index + 1) · \(group.name)"
            filtersByGroupName[group.name] = name
            remoteFilters.append((name, filter))
            filterSources[name] = Set(groupSubscriptions(group, from: remoteSubscriptions).map(\.sourceID))
        }
        var output = schemeHeader(
            scheme,
            target: .loon,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += "[General]\n"
        output += "ipv6 = \(schemeIPv6(scheme))\n"
        output += "dns-server = \(schemePlainDNS(scheme).joined(separator: ", "))\n\n"
        output += "[Proxy]\n"
        output += "\n"
        for node in inlineNodes { output += loonNode(node) + "\n" }
        output += loonRemoteProxySections(
            subscriptions: remoteSubscriptions,
            filters: remoteFilters,
            filterSourceIDs: filterSources
        )
        output += "\n[Proxy Group]\n"
        for group in groups {
            let remoteAliases = groupSubscriptions(group, from: remoteSubscriptions).map(\.displayName)
            var members = group.members.filter { !remoteNodeNames.contains($0) || group.inlineNodeNames.contains($0) }
            let remoteSelection = remoteGroupSelection(
                for: group,
                remoteNodeNames: remoteNodeNames
            )
            if remoteSelection.includesRemoteNodes {
                if let filterName = filtersByGroupName[group.name] {
                    members.append(filterName)
                } else {
                    members.append(contentsOf: remoteAliases)
                }
            }
            let memberList = members.map(confName).joined(separator: ",")
            switch group.kind {
            case .select:
                output += "\(confName(group.name)) = select,\(memberList)\n"
            case .urlTest, .fallback:
                output += "\(confName(group.name)) = \(group.kind == .fallback ? "fallback" : "url-test"),\(memberList)"
                output += ",url=\(confValue(group.testURL)),interval=\(group.interval)"
                if group.kind == .urlTest { output += ",tolerance=\(group.tolerance)" }
                output += "\n"
            case .loadBalance:
                output += "\(confName(group.name)) = load-balance,\(memberList),algorithm=\(loadBalanceAlgorithm(group.algorithm, target: .loon) ?? "Random")\n"
            case .smart, .conditional, .relay, .unsupported: break
            }
            appendNativeOptions(group, target: .loon, to: &output)
        }
        let chains = groups.filter { $0.kind == .relay }
        if !chains.isEmpty {
            output += "\n[Proxy Chain]\n"
            for chain in chains {
                output += "\(confName(chain.name)) = \(chain.members.map(confName).joined(separator: ","))\n"
            }
        }
        output += "\n[Rule]\n"
        output += localSchemeRules(rulePlan, target: .loon)
        let remoteResources = rulePlan.remoteResources
        if !remoteResources.isEmpty {
            output += "\n[Remote Rule]\n"
            for resource in remoteResources {
                output += "\(resource.url.absoluteString),policy=\(confName(resource.policyName))"
                output += ",tag=\(resource.identifier),enabled=true\n"
            }
        }
        return output
    }

    private func quanXScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteAliases = remoteSubscriptions.map(\.displayName)
        var output = schemeHeader(
            scheme,
            target: .quanx,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += "[general]\n"
        output += "server_check_url = \(schemeTestURL(scheme))\n"
        output += "server_check_timeout = 5000\n\n"
        output += "[dns]\nno-system\n"
        for value in schemePlainDNS(scheme) { output += "server = \(value)\n" }
        // Section order follows subconverter's QuanX template, which is what
        // every working converter emits: `[policy]` comes before the server and
        // filter sections, not after them. Tower used to put the whole node
        // list between `[dns]` and `[policy]`, and Quantumult X imported the
        // rules while dropping every policy group.
        output += "\n\n[policy]\n"
        for group in groups {
            let remoteAliases = groupSubscriptions(group, from: remoteSubscriptions).map(\.displayName)
            if group.kind == .conditional {
                if let fields = stringArray(group.parameters?["ssid-members"]) {
                    let mapped = fields.enumerated().map { offset, field -> String in
                        if offset < 2 { return confName(builtinPolicyName(field, target: .quanx)) }
                        guard let separator = field.firstIndex(of: ":") else { return field }
                        let ssid = String(field[..<separator])
                        let policy = String(field[field.index(after: separator)...])
                        return "\(ssid):\(confName(builtinPolicyName(policy, target: .quanx)))"
                    }
                    output += "ssid=\(confName(group.name)), \(mapped.joined(separator: ", "))\n"
                }
                continue
            }
            let type: String
            switch group.kind {
            case .select: type = "static"
            case .urlTest: type = "url-latency-benchmark"
            case .fallback: type = "available"
            case .loadBalance: type = loadBalanceAlgorithm(group.algorithm, target: .quanx) ?? "dest-hash"
            case .smart, .conditional, .relay, .unsupported: continue
            }
            var members = group.members.filter { !remoteNodeNames.contains($0) || group.inlineNodeNames.contains($0) }.map(confName)
            let selection = remoteGroupSelection(for: group, remoteNodeNames: remoteNodeNames)
            if !remoteSubscriptions.isEmpty, selection.includesRemoteNodes {
                members += quanXRemotePolicyParameters(aliases: remoteAliases, filter: selection.filter)
            }
            // Local candidates have already been filtered by Tower. List their
            // tags explicitly: regex-only latency groups may be omitted by QX.
            // Explicit ordering matters for available and is safe for every QX type.
            output += "\(type)=\(confName(group.name)), \(members.joined(separator: ", "))"
            if group.kind == .urlTest {
                output += ", check-interval=\(group.interval), alive-checking=\(group.parameters?["alive-checking"] ?? "false"), tolerance=\(group.tolerance)"
            }
            output += "\n"
        }
        // Every module is emitted exactly once and in this order. Quantumult X
        // rejects the whole file for either mistake: a missing module is
        // `配置文件缺少模块 [server_remote]`, and a repeated one is
        // `配置文件语法错误, duplicated section, [server_remote]`.
        let remoteRules = rulePlan.remoteResources.map {
            "\($0.url.absoluteString), tag=\($0.identifier), force-policy=\(confName($0.policyName)), enabled=true"
        }
        output += "\n[server_remote]\n"
        output += quanXRemoteSubscriptionLines(remoteSubscriptions)
        output += "\n[filter_remote]\n"
        if !remoteRules.isEmpty { output += remoteRules.joined(separator: "\n") + "\n" }
        output += "\n[rewrite_remote]\n"
        output += "\n[server_local]\n"
        for node in inlineNodes { output += quanXNode(node) + "\n" }
        output += "\n[filter_local]\n"
        output += quanXLocalSchemeRules(
            rulePlan,
            dnsProtectionMode: schemeDNSProtectionMode(scheme)
        )
        for section in ["rewrite_local", "task_local", "http_backend", "mitm"] {
            output += "\n[\(section)]\n"
        }
        return output
    }

    // MARK: - Built-in presets

    private func clash(
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup],
        target: ClientTarget
    ) -> String {
        let inlineNodeNames = inlineNodes.map { NodeRegionResolver.displayName(for: $0) }
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let providerNames = remoteSubscriptions.map(\.identifier)
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(
            target: target,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: true

        dns:
          enable: true
          enhanced-mode: fake-ip
          fake-ip-range: 198.18.0.1/16
          fake-ip-filter:
            - "*.lan"
            - "+.local"
            - "+.msftconnecttest.com"
            - "+.msftncsi.com"
          default-nameserver:
            - 223.5.5.5
            - 119.29.29.29
          proxy-server-nameserver:
            - https://223.5.5.5/dns-query
          nameserver:
            - https://223.5.5.5/dns-query
            - https://doh.pub/dns-query
          fallback:
            - https://1.1.1.1/dns-query
            - https://dns.google/dns-query
          fallback-filter:
            geoip: true
            geoip-code: CN

        proxies:
        """
        output += "\n"
        output += inlineNodes.isEmpty ? "  []\n" : inlineNodes.map { clashNode($0, target: target) }.joined(separator: "\n") + "\n"
        output += clashProxyProviders(remoteSubscriptions, target: target)
        output += "\nproxy-groups:\n"
        output += clashSelectGroup(
            name: RulePolicy.select.configurationName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += clashSelectGroup(
            name: Self.manualGroupName,
            nodeNames: inlineNodeNames.isEmpty && providerNames.isEmpty ? ["DIRECT"] : inlineNodeNames,
            providerNames: providerNames
        )
        output += clashURLTestGroup(
            name: RulePolicy.auto.configurationName,
            nodeNames: inlineNodeNames,
            providerNames: providerNames
        )
        output += clashSelectGroup(
            name: Self.nestedSelectGroupName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.nestedManualGroupName,
            nodeNames: inlineNodeNames.isEmpty && providerNames.isEmpty ? [Self.directGroupName] : inlineNodeNames,
            providerNames: providerNames,
            hidden: true
        )
        output += clashURLTestGroup(
            name: Self.nestedAutoGroupName,
            nodeNames: inlineNodeNames,
            providerNames: providerNames,
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.directGroupName,
            nodeNames: ["DIRECT"],
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += clashSelectGroup(
                name: policy.configurationName,
                nodeNames: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                )
            )
        }
        for group in regionGroups {
            let inlineNames = group.nodeNames.filter { !remoteNodeNames.contains($0) }
            let remoteNames = group.nodeNames.filter(remoteNodeNames.contains)
            output += clashSelectGroup(
                name: group.name,
                nodeNames: [group.automaticName] + inlineNames,
                providerNames: remoteNames.isEmpty ? [] : providerNames,
                providerFilter: exactNameFilter(remoteNames)
            )
            output += clashURLTestGroup(
                name: group.automaticName,
                nodeNames: inlineNames,
                providerNames: remoteNames.isEmpty ? [] : providerNames,
                providerFilter: exactNameFilter(remoteNames),
                hidden: true
            )
        }
        output += "\nrules:\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: target) {
                    output += "  - \(mapped)\n"
                }
            }
        }
        if preset.includeGeoIPCN {
            output += "  - GEOIP,CN,DIRECT,no-resolve\n"
        }
        output += "  - MATCH,\(clashPolicyName(preset.finalPolicy))\n"
        return output
    }

    private func clashNode(_ node: ProxyNode, target: ClientTarget) -> String {
        var values: [String] = [
            "  - name: \(yaml(NodeRegionResolver.displayName(for: node)))",
            "    type: \(node.kind.rawValue)",
            "    server: \(yaml(node.server))",
            "    port: \(node.port)"
        ]
        switch node.kind {
        case .shadowsocks:
            values += ["    cipher: \(yaml(node.cipher ?? "aes-256-gcm"))", "    password: \(yaml(node.password ?? ""))", "    udp: true"]
            if node.plugin == "v2ray-plugin" {
                values.append("    plugin: v2ray-plugin")
                values.append("    plugin-opts:")
                values.append("      mode: websocket")
                if let mux = node.pluginMux { values.append("      mux: \(mux ? "true" : "false")") }
                if node.tls { values.append("      tls: true") }
                if let host = node.hostHeader, !host.isEmpty { values.append("      host: \(yaml(host))") }
                if let path = node.exportablePath { values.append("      path: \(yaml(path))") }
            } else if let mode = simpleObfsMode(node) {
                values.append("    plugin: obfs")
                values.append("    plugin-opts:")
                values.append("      mode: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    values.append("      host: \(yaml(host))")
                }
            }
            // Preserve native SS-over-TLS fields for Shadowrocket and Karing.
            // This is distinct from simple-obfs TLS and SIP003 plugins.
            if [.shadowrocket, .karing].contains(target), node.tls, (node.plugin ?? "").isEmpty,
               simpleObfsMode(node) == nil {
                appendClashTransport(node, target: target, to: &values)
                appendClashALPN(node, to: &values)
            }
        case .shadowsocksR:
            values += [
                "    cipher: \(yaml(node.cipher ?? "aes-256-cfb"))",
                "    password: \(yaml(node.password ?? ""))",
                "    protocol: \(yaml(node.protocolName ?? "origin"))",
                "    obfs: \(yaml(node.obfs ?? "plain"))"
            ]
            if let value = node.protocolParam, !value.isEmpty { values.append("    protocol-param: \(yaml(value))") }
            if let value = node.obfsParam, !value.isEmpty { values.append("    obfs-param: \(yaml(value))") }
        case .vmess:
            values += [
                "    uuid: \(yaml(node.exportableUUID ?? ""))",
                "    alterId: \(node.alterID ?? 0)",
                "    cipher: \(yaml(node.cipher ?? "auto"))",
                "    udp: true"
            ]
            appendClashTransport(node, target: target, to: &values)
        case .vless:
            values += ["    uuid: \(yaml(node.exportableUUID ?? ""))", "    udp: true"]
            appendClashTransport(node, target: target, to: &values)
        case .trojan:
            values += ["    password: \(yaml(node.password ?? ""))", "    udp: true"]
            appendClashTransport(node, target: target, to: &values)
        case .hysteria2:
            values += [
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let ports = node.portHopping, !ports.isEmpty { values.append("    ports: \(yaml(ports))") }
            appendClashALPN(node, to: &values)
            // Hysteria 2 calls this value `fingerprint`: it is the SHA-256
            // certificate pin, not a browser-style uTLS ClientHello name.
            if let fingerprint = node.certificateFingerprint, !fingerprint.isEmpty {
                values.append("    fingerprint: \(yaml(fingerprint))")
            }
            if let obfs = hysteria2Obfs(node) {
                values.append("    obfs: \(yaml(obfs.type))")
                values.append("    obfs-password: \(yaml(obfs.password))")
            }
        case .hysteria:
            // Hysteria 1's congestion control is rate-based, so `up`/`down`
            // are load-bearing rather than hints. Mihomo's own defaults are
            // what an airport that omitted them expects.
            values += [
                "    auth-str: \(yaml(node.password ?? ""))",
                "    up: \(node.upMbps ?? 50)",
                "    down: \(node.downMbps ?? 100)",
                "    skip-cert-verify: \(node.skipCertificateVerification)"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            appendClashCertificateFingerprint(node, to: &values)
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                values.append("    obfs: \(yaml(obfs))")
            }
            if let name = node.protocolName, !name.isEmpty { values.append("    protocol: \(yaml(name))") }
            appendClashALPN(node, to: &values)
        case .tuic:
            values += [
                "    uuid: \(yaml(node.exportableUUID ?? ""))",
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let value = node.congestionControl, !value.isEmpty {
                values.append("    congestion-controller: \(yaml(value))")
            }
            if let value = node.udpRelayMode, !value.isEmpty {
                values.append("    udp-relay-mode: \(yaml(value))")
            }
            if let ports = node.portHopping, !ports.isEmpty { values.append("    ports: \(yaml(ports))") }
            appendClashALPN(node, to: &values)
            appendClashCertificateFingerprint(node, to: &values)
            appendClashClientFingerprint(node, to: &values)
        case .wireguard:
            values += [
                "    private-key: \(yaml(node.wireGuardPrivateKey ?? ""))",
                "    public-key: \(yaml(node.wireGuardPublicKey ?? ""))"
            ]
            if let value = node.wireGuardIPv4 { values.append("    ip: \(yaml(value))") }
            if let value = node.wireGuardIPv6 { values.append("    ipv6: \(yaml(value))") }
            values.append("    allowed-ips: \(yamlList(csv(node.wireGuardAllowedIPs)))")
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                values.append("    pre-shared-key: \(yaml(value))")
            }
            if let bytes = wireGuardReservedBytes(node), !bytes.isEmpty {
                values.append("    reserved: [\(bytes.map(String.init).joined(separator: ", "))]")
            }
            if let value = node.wireGuardPersistentKeepalive {
                values.append("    persistent-keepalive: \(value)")
            }
            if let value = node.wireGuardMTU { values.append("    mtu: \(value)") }
            if !csv(node.wireGuardDNS).isEmpty {
                values.append("    dns: \(yamlList(csv(node.wireGuardDNS)))")
            }
            values.append("    udp: true")
        case .anytls:
            values += [
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let value = node.idleSessionCheckInterval { values.append("    idle-session-check-interval: \(value)") }
            if let value = node.idleSessionTimeout { values.append("    idle-session-timeout: \(value)") }
            if let value = node.minIdleSession { values.append("    min-idle-session: \(value)") }
            appendClashALPN(node, to: &values)
            appendClashCertificateFingerprint(node, to: &values)
            if [.shadowrocket, .karing].contains(target) {
                values.append("    tls: true")
                appendClashReality(node, to: &values)
            }
            appendClashClientFingerprint(node, to: &values)
        case .snell:
            values.append("    psk: \(yaml(node.password ?? ""))")
            if let version = node.version { values.append("    version: \(version)") }
            // Snell only carries UDP from version 3 onwards.
            if (node.version ?? 4) >= 3 { values.append("    udp: true") }
            if let mode = node.obfs, !mode.isEmpty, mode.lowercased() != "none" {
                values.append("    obfs-opts:")
                values.append("      mode: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    values.append("      host: \(yaml(host))")
                }
            }
        case .socks5, .http:
            if let username = node.username, !username.isEmpty { values.append("    username: \(yaml(username))") }
            if let password = node.password, !password.isEmpty { values.append("    password: \(yaml(password))") }
            values.append("    tls: \(node.tls)")
            if node.tls {
                if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
                values.append("    skip-cert-verify: \(node.skipCertificateVerification)")
                appendClashALPN(node, to: &values)
                appendClashCertificateFingerprint(node, to: &values)
                if [.shadowrocket, .karing].contains(target) { appendClashReality(node, to: &values) }
                appendClashClientFingerprint(node, to: &values)
            }
        case .unknown:
            break
        }
        return values.joined(separator: "\n")
    }

    /// REALITY needs the server's public key and short id; without them the
    /// node is plain TLS to a borrowed SNI and cannot connect.
    private func appendClashReality(_ node: ProxyNode, to values: inout [String]) {
        guard node.usesReality else { return }
        values.append("    reality-opts:")
        values.append("      public-key: \(yaml(node.realityPublicKey ?? ""))")
        if let shortID = node.realityShortID, !shortID.isEmpty {
            values.append("      short-id: \(yaml(shortID))")
        }
        // Clash Meta defaults the fingerprint when REALITY is on but it is
        // absent, so send whatever the airport specified.
        values.append("    client-fingerprint: \(yaml(node.fingerprint ?? "chrome"))")
    }

    /// Writes `alpn` as the YAML list Mihomo expects.
    ///
    /// A URI carries it as one comma-joined string; written back as a scalar
    /// the client reads `h3,h2` as a single protocol name and the handshake
    /// never matches.
    private func appendClashALPN(_ node: ProxyNode, to values: inout [String]) {
        let entries = ALPNList.values(node.alpn)
        guard !entries.isEmpty else { return }
        values.append("    alpn: [\(entries.map(yaml).joined(separator: ", "))]")
    }

    /// Shadowrocket's Clash reader consumes the same uTLS field as Mihomo.
    /// REALITY writes it together with `reality-opts`; ordinary TLS protocols
    /// still need it at the proxy root or their ClientHello differs from the
    /// provider's server expectation.
    private func appendClashClientFingerprint(_ node: ProxyNode, to values: inout [String]) {
        guard !node.usesReality,
              let fingerprint = node.fingerprint,
              !fingerprint.isEmpty else { return }
        values.append("    client-fingerprint: \(yaml(fingerprint))")
    }

    private func appendClashCertificateFingerprint(_ node: ProxyNode, to values: inout [String]) {
        guard let fingerprint = node.certificateFingerprint,
              !fingerprint.isEmpty else { return }
        values.append("    fingerprint: \(yaml(fingerprint))")
    }

    private func appendClashTransport(_ node: ProxyNode, target: ClientTarget, to values: inout [String]) {
        values.append("    tls: \(node.tls)")
        values.append("    skip-cert-verify: \(node.skipCertificateVerification)")
        if let sni = node.sni, !sni.isEmpty {
            let key = target == .clash && node.kind == .trojan ? "sni" : "servername"
            values.append("    \(key): \(yaml(sni))")
        }
        appendClashCertificateFingerprint(node, to: &values)
        appendClashReality(node, to: &values)
        if node.kind == .vless, let flow = node.flow, !flow.isEmpty {
            values.append("    flow: \(yaml(flow))")
        }
        appendClashClientFingerprint(node, to: &values)
        if let transport = node.transport, !transport.isEmpty, transport != "tcp" {
            values.append("    network: \(yaml(transport == "httpupgrade" ? "ws" : transport))")
            switch transport {
            case "ws", "httpupgrade":
                values.append("    ws-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.exportableTransportHost {
                    values.append("      headers:")
                    values.append("        Host: \(yaml(host))")
                }
                if transport == "httpupgrade" { values.append("      v2ray-http-upgrade: true") }
            case "grpc":
                values.append("    grpc-opts:")
                if let service = node.path, !service.isEmpty {
                    let normalized = service.hasPrefix("/") ? String(service.dropFirst()) : service
                    values.append("      grpc-service-name: \(yaml(normalized))")
                }
            case "http":
                values.append("    http-opts:")
                values.append("      path: [\(yaml(node.exportablePath ?? "/"))]")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      headers:")
                    values.append("        Host: [\(yaml(host))]")
                }
            case "h2":
                values.append("    h2-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      host: [\(yaml(host))]")
                }
            case "xhttp":
                values.append("    xhttp-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty { values.append("      host: \(yaml(host))") }
                if let mode = node.transportMode, !mode.isEmpty { values.append("      mode: \(yaml(mode))") }
            default:
                break
            }
        }
    }

    private func clashSelectGroup(
        name: String,
        nodeNames: [String],
        providerNames: [String] = [],
        providerFilter: String? = nil,
        hidden: Bool = false
    ) -> String {
        var output = "  - name: \(yaml(name))\n    type: select\n"
        output += clashGroupMembers(
            nodeNames: nodeNames,
            providerNames: providerNames,
            providerFilter: providerFilter
        )
        if hidden { output += "    hidden: true\n" }
        return output
    }

    private func clashURLTestGroup(
        name: String,
        nodeNames: [String],
        providerNames: [String] = [],
        providerFilter: String? = nil,
        hidden: Bool = false
    ) -> String {
        guard !nodeNames.isEmpty || !providerNames.isEmpty else {
            return clashSelectGroup(name: name, nodeNames: ["DIRECT"])
        }
        var output = "  - name: \(yaml(name))\n"
        output += "    type: url-test\n"
        output += "    url: http://www.gstatic.com/generate_204\n"
        output += "    interval: 300\n"
        output += "    tolerance: 50\n"
        output += clashGroupMembers(
            nodeNames: nodeNames,
            providerNames: providerNames,
            providerFilter: providerFilter
        )
        if hidden { output += "    hidden: true\n" }
        return output
    }

    private func clashGroupMembers(
        nodeNames: [String],
        providerNames: [String],
        providerFilter: String?
    ) -> String {
        var output = ""
        let names = nodeNames.removingDuplicates()
        if !names.isEmpty {
            output += "    proxies:\n"
            for name in names { output += "      - \(yaml(name))\n" }
        }
        if !providerNames.isEmpty {
            output += "    use:\n"
            for name in providerNames.removingDuplicates() {
                output += "      - \(yaml(name))\n"
            }
            if let providerFilter, !providerFilter.isEmpty {
                output += "    filter: \(yaml(providerFilter))\n"
            }
        }
        if names.isEmpty && providerNames.isEmpty {
            output += "    proxies:\n      - DIRECT\n"
        }
        return output
    }

    private func clashProxyProviders(
        _ subscriptions: [RemoteSubscriptionEntry],
        target: ClientTarget
    ) -> String {
        guard !subscriptions.isEmpty else { return "" }
        var output = "\nproxy-providers:\n"
        for subscription in subscriptions {
            output += "  \(subscription.identifier):\n"
            output += "    type: http\n"
            output += "    url: \(yaml(subscription.urlString))\n"
            output += "    path: ./providers/\(subscription.identifier).yaml\n"
            output += "    interval: 86400\n"
            if let userAgent = subscription.userAgent, !userAgent.isEmpty {
                if target == .clash {
                    output += "    headers:\n"
                    output += "      User-Agent: \(yaml(userAgent))\n"
                } else {
                    output += "    header:\n"
                    output += "      User-Agent:\n"
                    output += "        - \(yaml(userAgent))\n"
                }
            }
            output += "    health-check:\n"
            output += "      enable: true\n"
            output += "      url: http://www.gstatic.com/generate_204\n"
            output += "      interval: 600\n"
        }
        return output
    }

    private func surgeLike(
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup],
        shadowrocket: Bool
    ) -> String {
        let target: ClientTarget = shadowrocket ? .shadowrocket : .surge
        let names = inlineNodes.map { NodeRegionResolver.displayName(for: $0) }
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let sourceGroupNames = remoteSubscriptions.map(\.displayName)
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(
            target: target,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += """
        [General]
        loglevel = notify
        ipv6 = true
        # `system` first meant the carrier's resolver got every query. Removed.
        # No encrypted-DNS key is written here: Shadowrocket's manual documents
        # none, and this project does not guess a client's field names.
        dns-server = 223.5.5.5, 119.29.29.29
        skip-proxy = 127.0.0.1, localhost, *.local
        test-timeout = 5

        [Proxy]
        """
        output += "\n"
        for node in inlineNodes {
            output += surgeNode(node, shadowrocket: shadowrocket) + "\n"
        }
        output += surgeWireGuardSections(inlineNodes)
        output += "\n[Proxy Group]\n"
        output += surgeRemoteSourceGroups(remoteSubscriptions)
        output += surgeSelect(
            name: RulePolicy.select.configurationName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += surgeSelect(
            name: Self.manualGroupName,
            values: names.isEmpty && sourceGroupNames.isEmpty ? ["DIRECT"] : names,
            sourceGroupNames: sourceGroupNames
        )
        output += surgeURLTest(
            name: RulePolicy.auto.configurationName,
            names: names,
            sourceGroupNames: sourceGroupNames
        )
        output += surgeSelect(
            name: Self.nestedSelectGroupName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            hidden: true
        )
        output += surgeSelect(
            name: Self.nestedManualGroupName,
            values: names.isEmpty && sourceGroupNames.isEmpty ? [Self.directGroupName] : names,
            sourceGroupNames: sourceGroupNames,
            hidden: true
        )
        output += surgeURLTest(
            name: Self.nestedAutoGroupName,
            names: names,
            sourceGroupNames: sourceGroupNames,
            hidden: true
        )
        output += surgeSelect(
            name: Self.directGroupName,
            values: ["DIRECT"],
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += surgeSelect(
                name: policy.configurationName,
                values: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                )
            )
        }
        for group in regionGroups {
            let inlineNames = group.nodeNames.filter { !remoteNodeNames.contains($0) }
            let remoteNames = group.nodeNames.filter(remoteNodeNames.contains)
            output += surgeSelect(
                name: group.name,
                values: [group.automaticName] + inlineNames,
                sourceGroupNames: remoteNames.isEmpty ? [] : sourceGroupNames,
                remoteFilter: exactNameFilter(remoteNames)
            )
            output += surgeURLTest(
                name: group.automaticName,
                names: inlineNames,
                sourceGroupNames: remoteNames.isEmpty ? [] : sourceGroupNames,
                remoteFilter: exactNameFilter(remoteNames),
                hidden: true
            )
        }
        output += "\n[Rule]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: target) {
                    output += mapped + "\n"
                }
            }
        }
        if preset.includeGeoIPCN { output += "GEOIP,CN,DIRECT,no-resolve\n" }
        output += "FINAL,\(surgePolicyName(preset.finalPolicy))\n"
        return output
    }

    private func surgeNode(_ node: ProxyNode, shadowrocket: Bool) -> String {
        let name = confName(NodeRegionResolver.displayName(for: node))
        var components: [String] = []
        switch node.kind {
        case .shadowsocks:
            components = ["ss", node.server, "\(node.port)", "encrypt-method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
            if shadowrocket, node.plugin == "v2ray-plugin" {
                components.append("obfs=\(node.tls ? "wss" : "ws")")
                appendValue(node.hostHeader, key: "obfs-host", to: &components)
                appendValue(node.exportablePath, key: "obfs-uri", to: &components)
            } else if let mode = simpleObfsMode(node) {
                components.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &components)
            }
        case .shadowsocksR:
            components = ["ssr", node.server, "\(node.port)", "encrypt-method=\(node.cipher ?? "aes-256-cfb")", "password=\(confValue(node.password ?? ""))", "protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "protocol-param", to: &components)
            appendValue(node.obfsParam, key: "obfs-param", to: &components)
        case .vmess:
            components = [
                "vmess",
                node.server,
                "\(node.port)",
                "username=\(node.exportableUUID ?? "")",
                "vmess-aead=\((node.alterID ?? 0) == 0)"
            ]
            if let cipher = node.cipher,
               ["aes-128-gcm", "chacha20-ietf-poly1305"].contains(cipher.lowercased()) {
                components.append("encrypt-method=\(cipher)")
            }
            appendSurgeTransport(node, includeTLSFlag: true, shadowrocket: shadowrocket, to: &components)
        case .vless:
            components = ["vless", node.server, "\(node.port)", "username=\(node.exportableUUID ?? "")"]
            appendSurgeTransport(node, includeTLSFlag: true, shadowrocket: shadowrocket, to: &components)
            // Shadowrocket only — Surge takes no VLESS and rejects REALITY.
            // Its vocabulary is its own: `pbk`/`sid`/`fingerprint` rather than
            // Loon's public-key/short-id/fp, and the flow is an enum (`xtls=2`
            // for vision) rather than the flow string.
            if shadowrocket, node.usesReality {
                appendValue(node.realityPublicKey, key: "pbk", to: &components)
                appendValue(node.realityShortID, key: "sid", to: &components)
                appendValue(node.fingerprint, key: "fingerprint", to: &components)
                if let xtls = shadowrocketXTLSMode(node) { components.append("xtls=\(xtls)") }
            }
        case .trojan:
            components = ["trojan", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTransport(node, includeTLSFlag: false, shadowrocket: shadowrocket, to: &components)
        case .hysteria2:
            // `password=` is deliberate for both clients, even though
            // Shadowrocket's manual writes Hysteria 2 as `auth=`. The manual
            // listing one spelling does not mean the app rejects the other:
            // Shadowrocket was checked on device with a Tower-generated
            // profile, and it fills the password field and connects from
            // `password=`. See docs/HANDOFF.md — do not "fix" this to `auth=`
            // from the manual alone.
            components = ["hysteria2", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            // The Salamander layer is not optional decoration: a server that
            // runs it drops every packet that arrives unobfuscated, so a node
            // written without this key imports cleanly and never connects.
            // The obfuscator is named by the key rather than carried as a
            // value — `salamander-password` in Surge's manual, a bare
            // `obfsParam` in Shadowrocket's.
            if let obfs = hysteria2Obfs(node) {
                let key = shadowrocket ? "obfsParam" : "salamander-password"
                components.append("\(key)=\(confValue(obfs.password))")
            }
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
        case .hysteria:
            // Shadowrocket only; Surge has no Hysteria 1 server type and
            // writes(_:to:excluding:) drops these before generation.
            components = ["hysteria", node.server, "\(node.port)", "auth=\(confValue(node.password ?? ""))"]
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                components.append("obfsParam=\(confValue(obfs))")
            }
            appendValue(node.protocolName, key: "protocol", to: &components)
            components.append("upmbps=\(node.upMbps ?? 50)")
            components.append("downmbps=\(node.downMbps ?? 100)")
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
            components.append("udp=1")
        case .tuic:
            if shadowrocket {
                // Shadowrocket's own vocabulary: the UUID is `user`, the SNI is
                // `peer`, and UDP is the numeric `udp=1` rather than Surge's
                // `udp-relay=true`.
                components = ["tuic", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
                appendValue(node.exportableUUID, key: "user", to: &components)
                appendSurgeTLS(node, includeTLSFlag: false, to: &components)
                components.append("udp=1")
            } else {
                // Surge distinguishes the two TUIC versions by server type and
                // only ever gets v5 from a `tuic://uuid:password@` URI.
                components = ["tuic-v5", node.server, "\(node.port)"]
                appendValue(node.exportableUUID, key: "uuid", to: &components)
                components.append("password=\(confValue(node.password ?? ""))")
                appendSurgeTLS(node, includeTLSFlag: false, to: &components)
                components.append("udp-relay=true")
            }
        case .wireguard:
            components = ["wireguard", "section-name=\(wireGuardSectionName(node))"]
        case .anytls:
            components = ["anytls", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
            components.append("udp-relay=true")
        case .snell:
            components = ["snell", node.server, "\(node.port)", "psk=\(confValue(node.password ?? ""))"]
            if let version = node.version { components.append("version=\(version)") }
            if let mode = node.obfs, !mode.isEmpty, mode.lowercased() != "none" {
                components.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &components)
            }
            if (node.version ?? 4) >= 3 { components.append("udp-relay=true") }
        case .socks5:
            components = [node.tls ? "socks5-tls" : "socks5", node.server, "\(node.port)"]
            components += surgeCredentialPair(node)
            components.append("udp-relay=true")
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .http:
            components = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            components += surgeCredentialPair(node)
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .unknown:
            components = ["direct"]
        }
        if !shadowrocket {
            appendValue(certificatePin(node), key: "server-cert-fingerprint-sha256", to: &components)
        }
        if shadowrocket, node.kind == .vless { components.append("udp-relay=true") }
        return "\(name) = \(components.joined(separator: ", "))"
    }

    // Surge and Shadowrocket read username and password as positional fields.
    // Emitting only one of them would move the password into the username slot,
    // so a half-filled credential pair is written as an explicit empty username.
    private func surgeCredentialPair(_ node: ProxyNode) -> [String] {
        let username = node.username ?? ""
        let password = node.password ?? ""
        guard !username.isEmpty || !password.isEmpty else { return [] }
        return [confValue(username), confValue(password)]
    }

    private func wireGuardSectionName(_ node: ProxyNode) -> String {
        "tower-\(node.id.uuidString.lowercased())"
    }

    private func surgeWireGuardSections(_ nodes: [ProxyNode]) -> String {
        var output = ""
        for node in nodes where node.kind == .wireguard {
            output += "\n[WireGuard \(wireGuardSectionName(node))]\n"
            output += "private-key = \(node.wireGuardPrivateKey ?? "")\n"
            if let value = node.wireGuardIPv4, !value.isEmpty { output += "self-ip = \(value)\n" }
            if let value = node.wireGuardIPv6, !value.isEmpty { output += "self-ip-v6 = \(value)\n" }
            if let value = node.wireGuardDNS, !value.isEmpty { output += "dns-server = \(value)\n" }
            if let value = node.wireGuardMTU { output += "mtu = \(value)\n" }
            var peer = [
                "public-key = \(node.wireGuardPublicKey ?? "")",
                "allowed-ips = \"\(node.wireGuardAllowedIPs ?? "0.0.0.0/0, ::/0")\"",
                "endpoint = \(node.endpoint)"
            ]
            if let value = node.wireGuardPreSharedKey, !value.isEmpty { peer.append("preshared-key = \(value)") }
            if let value = node.wireGuardPersistentKeepalive { peer.append("keepalive = \(value)") }
            if let bytes = wireGuardReservedBytes(node), bytes.count == 3 {
                peer.append("client-id = \(bytes.map(String.init).joined(separator: "/"))")
            }
            output += "peer = (\(peer.joined(separator: ", ")))\n"
        }
        return output
    }

    private func csv(_ value: String?) -> [String] {
        (value ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n\"'"))
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'")) }
            .filter { !$0.isEmpty }
    }

    private func wireGuardReservedBytes(_ node: ProxyNode) -> [Int]? {
        let bytes = csv(node.wireGuardReserved).compactMap(Int.init)
        guard bytes.allSatisfy({ (0 ... 255).contains($0) }) else { return nil }
        return bytes
    }

    private func yamlList(_ values: [String]) -> String {
        "[\(values.map(yaml).joined(separator: ", "))]"
    }

    /// Shadowrocket numbers the XTLS flow instead of naming it: 2 is vision,
    /// 1 the older direct mode.
    private func shadowrocketXTLSMode(_ node: ProxyNode) -> Int? {
        guard let flow = node.flow?.lowercased(), !flow.isEmpty else { return nil }
        if flow.contains("vision") { return 2 }
        if flow.contains("direct") { return 1 }
        return nil
    }

    private func appendSurgeTransport(
        _ node: ProxyNode,
        includeTLSFlag: Bool,
        shadowrocket: Bool,
        to values: inout [String]
    ) {
        appendSurgeTLS(node, includeTLSFlag: includeTLSFlag, to: &values)
        if node.transport == "ws" {
            values.append("ws=true")
            appendValue(node.exportablePath ?? "/", key: "ws-path", to: &values)
            if let host = node.exportableTransportHost {
                values.append("ws-headers=Host:\(confValue(host))")
            }
        } else if shadowrocket, let transport = node.transport, transport != "tcp" {
            values.append("obfs=\(transport)")
            if transport == "grpc" {
                appendValue(node.path?.hasPrefix("/") == true ? String(node.path!.dropFirst()) : node.path,
                            key: "serviceName", to: &values)
            } else {
                appendValue(node.exportablePath, key: "path", to: &values)
            }
            appendValue(node.hostHeader, key: "host", to: &values)
            if transport == "xhttp" { appendValue(node.transportMode, key: "mode", to: &values) }
        }
    }

    /// Leaf-certificate SHA-256, distinct from both uTLS and public-key pins.
    /// Intrinsically TLS protocols also cover snapshots with an old false flag.
    private func certificatePin(_ node: ProxyNode) -> String? {
        guard !node.usesReality,
              [.trojan, .hysteria, .hysteria2, .tuic, .anytls].contains(node.kind)
                || (node.tls && [.vmess, .vless, .http, .socks5, .shadowsocks].contains(node.kind)),
              let raw = node.certificateFingerprint else { return nil }
        let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return pin.isEmpty ? nil : pin
    }

    private func appendSurgeTLS(
        _ node: ProxyNode,
        includeTLSFlag: Bool,
        to values: inout [String]
    ) {
        if includeTLSFlag, node.tls { values.append("tls=true") }
        appendValue(node.sni, key: "sni", to: &values)
        if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
        appendValue(node.alpn, key: "alpn", to: &values)
    }

    private func surgeSelect(
        name: String,
        values: [String],
        sourceGroupNames: [String] = [],
        remoteFilter: String? = nil,
        hidden: Bool = false
    ) -> String {
        var parameters = values.removingDuplicates().map(confName)
        parameters += surgeRemoteGroupParameters(
            sourceGroupNames: sourceGroupNames,
            remoteFilter: remoteFilter
        )
        if hidden { parameters.append("hidden=true") }
        if parameters.isEmpty { parameters.append("DIRECT") }
        return "\(confName(name)) = select, \(parameters.joined(separator: ", "))\n"
    }

    private func surgeURLTest(
        name: String,
        names: [String],
        sourceGroupNames: [String] = [],
        remoteFilter: String? = nil,
        testURL: String = "http://www.gstatic.com/generate_204",
        interval: Int = 300,
        tolerance: Int = 50,
        hidden: Bool = false,
        smart: Bool = false
    ) -> String {
        guard !names.isEmpty || !sourceGroupNames.isEmpty else {
            return surgeSelect(name: name, values: ["DIRECT"], hidden: hidden)
        }
        var parameters = names.map(confName)
        parameters += surgeRemoteGroupParameters(
            sourceGroupNames: sourceGroupNames,
            remoteFilter: remoteFilter
        )
        if !smart {
            parameters += [
                "url=\(confValue(testURL))",
                "interval=\(interval)",
                "tolerance=\(tolerance)"
            ]
        }
        if hidden { parameters.append("hidden=true") }
        return "\(confName(name)) = \(smart ? "smart" : "url-test"), \(parameters.joined(separator: ", "))\n"
    }

    private func surgeRemoteSourceGroups(
        _ subscriptions: [RemoteSubscriptionEntry]
    ) -> String {
        subscriptions.map { subscription in
            "\(confName(subscription.displayName)) = select, policy-path=\(confValue(subscription.urlString)), update-interval=86400, hidden=true\n"
        }.joined()
    }

    private func surgeRemoteGroupParameters(
        sourceGroupNames: [String],
        remoteFilter: String?
    ) -> [String] {
        guard !sourceGroupNames.isEmpty else { return [] }
        let groups = sourceGroupNames.map(confName).joined(separator: ",")
        var parameters = ["include-other-group=\(surgeQuoted(groups))"]
        if let remoteFilter, !remoteFilter.isEmpty {
            parameters.append("policy-regex-filter=\(surgeQuoted(remoteFilter))")
        }
        return parameters
    }

    private func loon(
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let names = inlineNodes.map { NodeRegionResolver.displayName(for: $0) }
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteAliases = remoteSubscriptions.map(\.displayName)
        let regionGroupNames = regionGroups.map(\.name)
        var filterNamesByRegion: [String: String] = [:]
        let regionFilters: [(name: String, pattern: String)] = regionGroups.enumerated().compactMap {
            index, group in
            let remoteNames = group.nodeNames.filter(remoteNodeNames.contains)
            guard let filter = exactNameFilter(remoteNames) else { return nil }
            let filterName = "塔台地区筛选 \(index + 1) · \(group.name)"
            filterNamesByRegion[group.name] = filterName
            return (filterName, filter)
        }
        var output = header(
            target: .loon,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += """
        [General]
        ipv6 = true
        dns-server = 223.5.5.5, 119.29.29.29

        [Proxy]
        """
        output += "\n"
        for node in inlineNodes { output += loonNode(node) + "\n" }
        output += loonRemoteProxySections(
            subscriptions: remoteSubscriptions,
            filters: regionFilters
        )
        output += "\n[Proxy Group]\n"
        let selectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(RulePolicy.select.configurationName)) = select,\(selectNames)\n"
        let manualNames = (names.isEmpty && remoteAliases.isEmpty ? ["DIRECT"] : names + remoteAliases)
            .map(confName).joined(separator: ",")
        output += "\(confName(Self.manualGroupName)) = select,\(manualNames)\n"
        if names.isEmpty && remoteAliases.isEmpty {
            output += "\(confName(RulePolicy.auto.configurationName)) = select,DIRECT\n"
        } else {
            output += "\(confName(RulePolicy.auto.configurationName)) = url-test,\((names + remoteAliases).map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50\n"
        }
        let nestedSelectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedSelectGroupName)) = select,\(nestedSelectNames),hidden=true\n"
        let nestedManualNames = (names.isEmpty && remoteAliases.isEmpty ? [Self.directGroupName] : names + remoteAliases)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedManualGroupName)) = select,\(nestedManualNames),hidden=true\n"
        if names.isEmpty && remoteAliases.isEmpty {
            output += "\(confName(Self.nestedAutoGroupName)) = select,\(confName(Self.directGroupName)),hidden=true\n"
        } else {
            output += "\(confName(Self.nestedAutoGroupName)) = url-test,\((names + remoteAliases).map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,hidden=true\n"
        }
        output += "\(confName(Self.directGroupName)) = select,DIRECT,hidden=true\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "REJECT"
            )
                .map(confName)
                .joined(separator: ",")
            output += "\(confName(policy.configurationName)) = select,\(choices)\n"
        }
        for group in regionGroups {
            let inlineNames = group.nodeNames.filter { !remoteNodeNames.contains($0) }
            let remoteMembers = filterNamesByRegion[group.name].map { [$0] } ?? []
            output += "\(confName(group.name)) = select,\(([group.automaticName] + inlineNames + remoteMembers).map(confName).joined(separator: ","))\n"
            output += "\(confName(group.automaticName)) = url-test,\((inlineNames + remoteMembers).map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,hidden=true\n"
        }
        output += "\n[Rule]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .loon) { output += mapped + "\n" }
            }
        }
        // Without `no-resolve` this rule forces a local lookup of every domain
        // no earlier rule matched, purely to test its country — and those are
        // exactly the domains no rule list bothered to cover. With it the rule
        // simply does not match a domain, the request falls through to the
        // final policy, and the node resolves it instead.
        if preset.includeGeoIPCN { output += "GEOIP,CN,DIRECT,no-resolve\n" }
        output += "FINAL,\(surgePolicyName(preset.finalPolicy))\n"
        return output
    }

    private func loonRemoteProxySections(
        subscriptions: [RemoteSubscriptionEntry],
        filters: [(name: String, pattern: String)],
        filterSourceIDs: [String: Set<UUID>] = [:]
    ) -> String {
        guard !subscriptions.isEmpty else { return "" }
        var output = "\n[Remote Proxy]\n"
        for subscription in subscriptions {
            output += "\(confName(subscription.displayName)) = \(subscription.urlString)\n"
        }
        output += "\n[Remote Filter]\n"
        for filter in filters {
            let allowed = filterSourceIDs[filter.name]
            let aliases = subscriptions.filter { allowed == nil || allowed!.contains($0.sourceID) }
                .map { confName($0.displayName) }.joined(separator: ",")
            if !aliases.isEmpty {
                output += "\(confName(filter.name)) = NameRegex,\(aliases),FilterKey = \(loonQuoted(filter.pattern))\n"
            }
        }
        return output
    }

    private func loonNode(_ node: ProxyNode) -> String {
        let name = confName(NodeRegionResolver.displayName(for: node))
        var values: [String]
        switch node.kind {
        case .shadowsocks:
            values = ["Shadowsocks", node.server, "\(node.port)", node.cipher ?? "aes-256-gcm", loonQuoted(node.password ?? "")]
            if let mode = simpleObfsMode(node) {
                // Loon names the simple-obfs mode obfs-name; plain "obfs" is
                // the ShadowsocksR field and means something else there.
                values.append("obfs-name=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &values)
            }
            values.append("udp=true")
        case .shadowsocksR:
            values = ["ShadowsocksR", node.server, "\(node.port)", node.cipher ?? "aes-256-cfb", loonQuoted(node.password ?? ""), "protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "protocol-param", to: &values)
            appendValue(node.obfsParam, key: "obfs-param", to: &values)
            values.append("udp=true")
        case .vmess:
            values = [
                "vmess",
                node.server,
                "\(node.port)",
                node.cipher ?? "auto",
                loonQuoted(node.exportableUUID ?? ""),
                "transport=\(node.transport ?? "tcp")",
                "alterId=\(node.alterID ?? 0)"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .vless:
            values = [
                "VLESS",
                node.server,
                "\(node.port)",
                loonQuoted(node.exportableUUID ?? ""),
                "transport=\(node.transport ?? "tcp")"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .trojan:
            values = ["trojan", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            appendValue(node.transport, key: "transport", to: &values)
            appendValue(node.exportablePath, key: "path", to: &values)
            appendValue(node.hostHeader, key: "host", to: &values)
            appendValue(node.alpn, key: "alpn", to: &values)
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values.append("udp=true")
        case .hysteria2:
            values = ["Hysteria2", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values += ["udp=true", "fast-open=true"]
        case .wireguard:
            values = [
                "wireguard",
                "interface-ip=\(node.wireGuardIPv4 ?? "")",
                "private-key=\(loonQuoted(node.wireGuardPrivateKey ?? ""))"
            ]
            if let value = node.wireGuardIPv6, !value.isEmpty { values.append("interface-ipv6=\(value)") }
            if let value = node.wireGuardMTU { values.append("mtu=\(value)") }
            if let value = node.wireGuardDNS, !value.isEmpty { values.append("dns=\(value)") }
            if let value = node.wireGuardPersistentKeepalive { values.append("keepalive=\(value)") }
            var peer = [
                "public-key=\(loonQuoted(node.wireGuardPublicKey ?? ""))",
                "allowed-ips=\(loonQuoted(node.wireGuardAllowedIPs ?? "0.0.0.0/0,::/0"))",
                "endpoint=\(node.endpoint)"
            ]
            if let value = node.wireGuardReserved, !value.isEmpty { peer.append("reserved=[\(value)]") }
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                peer.append("preshared-key=\(loonQuoted(value))")
            }
            values.append("peers=[{\(peer.joined(separator: ","))}]")
            values.append("udp=true")
        case .anytls:
            values = ["anytls", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values.append("udp=true")
        case .socks5:
            values = ["Socks5", node.server, "\(node.port)"]
            values += loonCredentialPair(node)
            if node.tls {
                values.append("over-tls=true")
                appendValue(node.sni, key: "sni", to: &values)
                appendValue(node.alpn, key: "alpn", to: &values)
                if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            }
            values.append("udp=true")
        case .http:
            values = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            values += loonCredentialPair(node)
            if node.tls {
                if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
                appendValue(node.sni, key: "sni", to: &values)
                appendValue(node.alpn, key: "alpn", to: &values)
            }
        // Loon implements neither, and writes(_:to:excluding:) filters them
        // out before generation, so this branch is defensive only.
        case .hysteria, .tuic, .snell, .unknown:
            values = ["Direct"]
        }
        // Confirmed in Loon on device: these TLS protocols also accept
        // Reality's public key and short id, not only VLESS.
        if [.anytls, .trojan].contains(node.kind), node.usesReality {
            values.removeAll { $0.hasPrefix("tls-name=") }
            appendValue(node.sni, key: "sni", to: &values)
            values.append("public-key=\(loonQuoted(node.realityPublicKey ?? ""))")
            appendValue(node.realityShortID, key: "short-id", to: &values)
        }
        appendValue(certificatePin(node), key: "tls-cert-sha256", to: &values)
        return "\(name) = \(values.joined(separator: ","))"
    }

    // Loon also reads username and password positionally, so both fields are
    // emitted together or not at all. Empty trailing fields produce a line that
    // Loon rejects when a proxy needs no authentication.
    private func loonCredentialPair(_ node: ProxyNode) -> [String] {
        let username = node.username ?? ""
        let password = node.password ?? ""
        guard !username.isEmpty || !password.isEmpty else { return [] }
        // Loon 3.5.0 treats quotes around a simple username as part of the
        // credential. Keep quoting for names that require field escaping.
        let simple = !username.isEmpty && username.range(of: "^[A-Za-z0-9_.@-]+$", options: .regularExpression) != nil
        return [simple ? username : loonQuoted(username), loonQuoted(password)]
    }

    private func appendLoonTransportAndTLS(_ node: ProxyNode, to values: inout [String]) {
        if node.usesReality {
            values.append("public-key=\"\(confValue(node.realityPublicKey ?? ""))\"")
            appendValue(node.realityShortID, key: "short-id", to: &values)
        }
        if let flow = node.flow, !flow.isEmpty { values.append("flow=\(confValue(flow))") }
        appendValue(node.exportablePath, key: "path", to: &values)
        appendValue(node.exportableTransportHost, key: "host", to: &values)
        values.append("over-tls=\(node.tls)")
        appendValue(node.sni, key: "tls-name", to: &values)
        if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
    }

    private func quanX(
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let names = inlineNodes.map { NodeRegionResolver.displayName(for: $0) }
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteAliases = remoteSubscriptions.map(\.displayName)
        let allRemoteParameters = quanXRemotePolicyParameters(aliases: remoteAliases, filter: nil)
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(
            target: .quanx,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += """
        [general]
        server_check_url = http://www.gstatic.com/generate_204
        server_check_timeout = 5000

        [dns]
        no-system
        server = 223.5.5.5
        server = 1.1.1.1
        """
        // Section order follows subconverter's QuanX template, which is what
        // every working converter emits: `[policy]` comes before the server and
        // filter sections, not after them. Tower used to put the whole node
        // list between `[dns]` and `[policy]`, and Quantumult X imported the
        // rules while dropping every policy group.
        output += "\n\n[policy]\n"
        let selectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(RulePolicy.select.configurationName), \(selectValues)\n"
        let manualValues = (names.isEmpty && allRemoteParameters.isEmpty ? ["direct"] : names.map(confName) + allRemoteParameters)
            .joined(separator: ", ")
        output += "static=\(Self.manualGroupName), \(manualValues)\n"
        if names.isEmpty && allRemoteParameters.isEmpty {
            output += "static=\(RulePolicy.auto.configurationName), direct\n"
        } else {
            output += "url-latency-benchmark=\(RulePolicy.auto.configurationName), \((names.map(confName) + allRemoteParameters).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        let nestedSelectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(Self.nestedSelectGroupName), \(nestedSelectValues)\n"
        let nestedManualValues = (names.isEmpty && allRemoteParameters.isEmpty
            ? [confName(Self.directGroupName)]
            : names.map(confName) + allRemoteParameters)
            .joined(separator: ", ")
        output += "static=\(Self.nestedManualGroupName), \(nestedManualValues)\n"
        if names.isEmpty && allRemoteParameters.isEmpty {
            output += "static=\(Self.nestedAutoGroupName), \(Self.directGroupName)\n"
        } else {
            output += "url-latency-benchmark=\(Self.nestedAutoGroupName), \((names.map(confName) + allRemoteParameters).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "static=\(Self.directGroupName), direct\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "reject"
            )
                .map(confName)
                .joined(separator: ", ")
            output += "static=\(policy.configurationName), \(choices)\n"
        }
        for group in regionGroups {
            if remoteSubscriptions.isEmpty {
                output += "static=\(group.name), \(([group.automaticName] + group.nodeNames).map(confName).joined(separator: ", "))\n"
                output += "url-latency-benchmark=\(group.automaticName), \(group.nodeNames.map(confName).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
                continue
            }
            let inlineNames = group.nodeNames.filter { !remoteNodeNames.contains($0) }.map(confName)
            let remoteNames = group.nodeNames.filter(remoteNodeNames.contains)
            let remoteParameters = remoteNames.isEmpty
                ? []
                : quanXRemotePolicyParameters(
                    aliases: remoteAliases,
                    filter: exactNameFilter(remoteNames)
                )
            output += "static=\(group.name), \(([confName(group.automaticName)] + inlineNames + remoteParameters).joined(separator: ", "))\n"
            output += "url-latency-benchmark=\(group.automaticName), \((inlineNames + remoteParameters).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "\n[server_remote]\n"
        output += quanXRemoteSubscriptionLines(remoteSubscriptions)
        output += "\n[filter_remote]\n\n[rewrite_remote]\n"
        output += "\n[server_local]\n"
        for node in inlineNodes { output += quanXNode(node) + "\n" }
        output += "\n[filter_local]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .quanx) { output += mapped + "\n" }
            }
        }
        if preset.includeGeoIPCN { output += "geoip, cn, direct\n" }
        let finalPolicy = quanXPolicyName(preset.finalPolicy)
        output += "host-keyword, ., \(finalPolicy)\n"
        output += "final, \(finalPolicy)\n"
        for section in ["rewrite_local", "task_local", "http_backend", "mitm"] {
            output += "\n[\(section)]\n"
        }
        return output
    }

    private func quanXRemoteSubscriptionLines(
        _ subscriptions: [RemoteSubscriptionEntry]
    ) -> String {
        subscriptions.map { subscription in
            "\(confValue(subscription.urlString)), tag=\(confName(subscription.displayName)), update-interval=86400, enabled=true\n"
        }.joined()
    }

    private func quanXRemotePolicyParameters(
        aliases: [String],
        filter: String?
    ) -> [String] {
        guard !aliases.isEmpty else { return [] }
        let aliasRegex = exactNameFilter(aliases) ?? ".*"
        var values = ["resource-tag-regex=\(aliasRegex)"]
        if let filter, !filter.isEmpty { values.append("server-tag-regex=\(filter)") }
        return values
    }

    private func quanXNode(_ node: ProxyNode) -> String {
        var values = [node.endpoint]
        let prefix: String
        switch node.kind {
        case .shadowsocks:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
            if node.plugin == "v2ray-plugin" {
                values.append("obfs=\(node.tls ? "wss" : "ws")")
                appendValue(node.hostHeader, key: "obfs-host", to: &values)
                appendValue(node.exportablePath, key: "obfs-uri", to: &values)
            } else if node.tls {
                values.append("obfs=over-tls")
                appendValue(node.sni, key: "obfs-host", to: &values)
            } else if let mode = simpleObfsMode(node) {
                values.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &values)
            }
        case .shadowsocksR:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-cfb")", "password=\(confValue(node.password ?? ""))", "ssr-protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "ssr-protocol-param", to: &values)
            appendValue(node.obfsParam, key: "obfs-host", to: &values)
        case .vmess:
            prefix = "vmess"
            values += ["method=\(quanXVMessMethod(node))", "password=\(confValue(node.exportableUUID ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .vless:
            prefix = "vless"
            values += ["method=none", "password=\(confValue(node.exportableUUID ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .trojan:
            prefix = "trojan"
            values.append("password=\(confValue(node.password ?? ""))")
            if node.transport?.lowercased() == "ws" {
                // Trojan's TLS layer is mandatory even for snapshots parsed by
                // older Tower versions, where an omitted Clash `tls` key left
                // this stored flag false.
                var secureNode = node
                secureNode.tls = true
                appendQuanXTransport(secureNode, to: &values)
            } else {
                // Quantumult X gives Trojan its own native TLS vocabulary.
                // `obfs=over-tls` / `obfs-host` belong to VMess and VLESS.
                values.append("over-tls=true")
                appendValue(node.sni, key: "tls-host", to: &values)
            }
        case .anytls:
            prefix = "anytls"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
            values.append("udp-relay=true")
        case .socks5:
            prefix = "socks5"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)
        case .http:
            prefix = "http"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)

        // Quantumult X implements none of these, and writes(_:to:excluding:)
        // filters them out before generation, so this is defensive only.
        case .hysteria, .hysteria2, .tuic, .wireguard, .snell, .unknown:
            prefix = "http"
        }
        if [.socks5, .http].contains(node.kind), node.tls {
            values.append("over-tls=true")
            appendValue(node.sni, key: "tls-host", to: &values)
        }
        if node.tls || [.trojan, .anytls].contains(node.kind) {
            appendQuanXTLS(node, to: &values)
        }
        values.append("tag=\(confName(NodeRegionResolver.displayName(for: node)))")
        return "\(prefix)=\(values.joined(separator: ", "))"
    }

    private func appendQuanXTransport(_ node: ProxyNode, to values: inout [String]) {
        if node.transport == "ws" {
            values.append("obfs=\(node.tls ? "wss" : "ws")")
            let transportHost = node.kind == .vless
                ? node.exportableTransportHost
                : (node.hostHeader ?? node.sni)
            appendValue(transportHost, key: "obfs-host", to: &values)
            appendValue(node.exportablePath ?? "/", key: "obfs-uri", to: &values)
        } else if node.kind == .vmess, node.transport?.lowercased() == "http" {
            values.append("obfs=http")
            appendValue(node.hostHeader, key: "obfs-host", to: &values)
            appendValue(node.exportablePath ?? "/", key: "obfs-uri", to: &values)
        } else if node.tls {
            values.append("obfs=over-tls")
            appendValue(node.sni, key: "obfs-host", to: &values)
        }
    }

    private func appendQuanXTLS(_ node: ProxyNode, to values: inout [String]) {
        if node.usesReality {
            appendValue(node.realityPublicKey, key: "reality-base64-pubkey", to: &values)
            appendValue(node.realityShortID, key: "reality-hex-shortid", to: &values)
        } else {
            let protocols = ALPNList.values(node.alpn)
            if !protocols.isEmpty, protocols.allSatisfy({ !$0.utf8.isEmpty && $0.utf8.count <= 255 }) {
                let bytes = protocols.flatMap { [UInt8($0.utf8.count)] + Array($0.utf8) }
                values.append("tls-alpn=\(bytes.map { String(format: "%02x", $0) }.joined())")
            }
            appendValue(certificatePin(node), key: "tls-cert-sha256", to: &values)
            if node.skipCertificateVerification { values.append("tls-verification=false") }
        }
        if node.kind == .vless, let flow = node.flow, !flow.isEmpty {
            let mapped = flow == "xtls-rprx-vision-udp443" ? "xtls-rprx-vision" : flow
            values.append("vless-flow=\(confValue(mapped))")
        }
    }

    // Quantumult X names the VMess cipher with the same method key it uses for
    // Shadowsocks. "auto" is not one of its accepted values, so it is mapped to
    // the AEAD cipher that its VMess implementation negotiates by default.
    /// Hysteria 2's obfs layer, only when both halves of it survived.
    ///
    /// The type and the password are one thing, not two optional ones:
    /// `obfs: salamander` on its own makes Mihomo refuse the entire profile —
    /// "proxy 301: hysteria2 obfs: salamander requires obfs-password" — and
    /// takes every other node in the file down with it. sing-box is the same.
    /// Without the password the node could not have connected either way, so
    /// the obfs layer is dropped rather than half-written.
    func hysteria2Obfs(_ node: ProxyNode) -> (type: String, password: String)? {
        guard node.kind == .hysteria2,
              let type = node.obfs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !type.isEmpty,
              type.lowercased() != "none",
              let password = node.obfsParam?.trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty else { return nil }
        return (type, password)
    }

    /// The simple-obfs mode of a Shadowsocks node, or nil when it carries no
    /// plugin. `obfs`/`obfsParam` hold the ShadowsocksR obfuscation for SSR
    /// nodes, so this is scoped to plain Shadowsocks, where the same fields
    /// carry the SIP003 plugin's mode and host.
    func simpleObfsMode(_ node: ProxyNode) -> String? {
        guard node.kind == .shadowsocks,
              let mode = node.obfs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ["http", "tls"].contains(mode) else { return nil }
        return mode
    }

    private func quanXVMessMethod(_ node: ProxyNode) -> String {
        let accepted = ["aes-128-gcm", "chacha20-poly1305", "chacha20-ietf-poly1305", "none"]
        guard let cipher = node.cipher?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              accepted.contains(cipher) else {
            return "chacha20-ietf-poly1305"
        }
        return cipher
    }

    private func mappedRule(_ rule: String, policy: RulePolicy, target: ClientTarget) -> String? {
        let policyName: String
        switch target {
        case .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi, .karing: policyName = clashPolicyName(policy)
        case .quanx: policyName = quanXPolicyName(policy)
        default: policyName = surgePolicyName(policy)
        }
        return mappedRule(rule, policyName: policyName, target: target)
    }

    /// Shared by the built-in presets and by imported schemes, whose policy
    /// names come from the imported file rather than from `RulePolicy`.
    private func mappedRule(_ rule: String, policyName: String, target: ClientTarget) -> String? {
        let policyName = [.surge, .surgeMac, .loon, .quanx].contains(target) ? confName(policyName) : policyName
        if RoutingRuleCapabilities.compiledTargets.contains(target) {
            return RoutingRuleCapabilities.render(rule, policy: policyName, target: target)
        }
        // The legacy emitters have no recursive dialect conversion. Passing an
        // outer AND through their CSV path would leave Mihomo-only children in
        // a Loon/Shadowrocket profile and incorrectly report it as compatible.
        if let condition = RoutingRuleSyntax.condition(rule), condition.children != nil {
            return nil
        }
        var parts = rule.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2 else { return nil }

        let ruleType = parts[0].uppercased()
        let hasTrailingNoResolve = parts.last?.lowercased() == "no-resolve"
        // Clash/Mihomo does not implement Surge's URL-REGEX dialect. These
        // expressions may inspect the URL path, so converting them to a domain
        // rule would silently change their meaning; omit them for Clash only.
        if target.usesClashFormat, target != .clash, ruleType == "URL-REGEX" {
            return nil
        }

        if target == .quanx {
            let mappedType: String
            switch ruleType {
            case "DOMAIN", "HOST": mappedType = "host"
            case "DOMAIN-SUFFIX", "HOST-SUFFIX": mappedType = "host-suffix"
            case "DOMAIN-KEYWORD", "HOST-KEYWORD": mappedType = "host-keyword"
            case "DOMAIN-WILDCARD", "HOST-WILDCARD": mappedType = "host-wildcard"
            case "IP-CIDR": mappedType = "ip-cidr"
            case "IP-CIDR6", "IP6-CIDR": mappedType = "ip6-cidr"
            case "GEOIP": mappedType = "geoip"
            case "IP-ASN": mappedType = "ip-asn"
            case "USER-AGENT": mappedType = "user-agent"
            default: return nil
            }
            // A QuanX filter resource may already carry its own policy as the
            // third field. The RuleScheme assignment (or filter_remote's
            // force-policy) owns the policy in Tower, so normalize to the
            // matcher and value before adding that policy. This also removes
            // the unsupported Surge-style `no-resolve` field.
            parts = [mappedType, parts[1], confName(policyName)]
        } else if ruleType == "GEOSITE" {
            // Mihomo and Stash both implement GEOSITE directly. The imported
            // subconverter dialect can therefore be preserved for the two
            // Clash targets, while clients without a documented equivalent
            // must continue dropping it instead of rejecting the profile.
            guard target.usesClashFormat else { return nil }
        } else if !Self.surgeFamilyRuleTypes.contains(ruleType) {
            // A future rule snapshot may introduce a type these clients cannot
            // parse. Dropping it keeps the rest of the configuration loadable
            // instead of shipping a line that fails at import time.
            return nil
        }

        if target == .quanx {
            // QuanX's DNS short-circuit is emitted once before `final`, not as
            // a per-rule option. `parts` is already complete here.
            return parts.joined(separator: ", ")
        }

        if hasTrailingNoResolve {
            parts.insert(policyName, at: parts.count - 1)
        } else {
            parts.append(policyName)
            let surgeIPRule = [.surge, .surgeMac].contains(target)
                && ["IP-CIDR", "IP-CIDR6", "IP6-CIDR", "IP-ASN"].contains(ruleType)
            if ruleType == "GEOIP" || surgeIPRule {
                // A GEOIP rule above later domain rules otherwise makes the
                // client resolve the domain locally just to decide whether it
                // matches — and the domains that reach it are the ones no rule
                // list covered. Every built-in preset already writes the flag
                // for all seven clients; an imported scheme must not route
                // differently on Stash than it does on Surge. Surge also
                // needs this for inline IP/ASN rules: imported service lists
                // can place their IP ranges before another list's domains.
                // Keep policy order while avoiding that premature DNS lookup.
                parts.append("no-resolve")
            }
        }
        return parts.joined(separator: ",")
    }

    private func configurablePolicies(_ preset: RulePreset) -> [RulePolicy] {
        preset.policies.filter { ![.direct, .reject, .select, .auto].contains($0) }
    }

    private func makeRegionGroups(
        nodes: [ProxyNode],
        countryCodes: [UUID: String]
    ) -> [RegionStrategyGroup] {
        let preferredCodes = Set(Self.regionDefinitions.map(\.code))
        var nodesByCode: [String: [String]] = [:]
        var otherNodeNames: [String] = []

        for node in nodes {
            // Same order the UI shows: the airport's own name first, the IP
            // database only for names that say nothing about where they are.
            let rawCode = NodeRegionResolver.countryCode(for: node) ?? countryCodes[node.id]
            let normalizedCode = rawCode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let countryCode = normalizedCode == "UK" ? "GB" : normalizedCode
            let nodeName = NodeRegionResolver.displayName(for: node)

            if let countryCode, preferredCodes.contains(countryCode) {
                nodesByCode[countryCode, default: []].append(nodeName)
            } else {
                otherNodeNames.append(nodeName)
            }
        }

        var groups = Self.regionDefinitions.compactMap { definition -> RegionStrategyGroup? in
            guard let names = nodesByCode[definition.code], !names.isEmpty else { return nil }
            return RegionStrategyGroup(
                name: definition.name,
                nodeNames: names.removingDuplicates()
            )
        }
        if !otherNodeNames.isEmpty {
            groups.append(
                RegionStrategyGroup(
                    name: Self.otherRegionsName,
                    nodeNames: otherNodeNames.removingDuplicates()
                )
            )
        }
        return groups
    }

    private func nestedPrimaryChoices(regionGroupNames: [String]) -> [String] {
        [Self.nestedAutoGroupName, Self.nestedManualGroupName]
            + regionGroupNames
            + [Self.directGroupName]
    }

    private func policyChoices(
        _ policy: RulePolicy,
        regionGroupNames: [String],
        reject: String
    ) -> [String] {
        let select = Self.nestedSelectGroupName
        let auto = Self.nestedAutoGroupName
        let manual = Self.nestedManualGroupName
        let translatedDirect = Self.directGroupName
        return switch policy {
        case .foreignAds:
            [reject, translatedDirect, select]
        case .domestic, .apple, .microsoft:
            [translatedDirect, select, manual] + regionGroupNames + [auto]
        default:
            [select, auto, manual] + regionGroupNames + [translatedDirect]
        }
    }

    private func clashPolicyName(_ policy: RulePolicy) -> String {
        policy.configurationName
    }

    private func surgePolicyName(_ policy: RulePolicy) -> String {
        policy.configurationName
    }

    private func quanXPolicyName(_ policy: RulePolicy) -> String {
        switch policy {
        case .direct: "direct"
        case .reject: "reject"
        default: policy.configurationName
        }
    }

    private func header(
        target: ClientTarget,
        embedsRemoteSubscriptions: Bool = false
    ) -> String {
        let credentialNotice = embedsRemoteSubscriptions
            ? "Subscription URLs are embedded for client-side updates."
            : "Subscription credentials never leave this device."
        return """
        # Generated locally by 塔台 for \(target.name)
        # Rules are selected and stored locally on this device.
        # \(credentialNotice)

        """
    }

    private func reservedProxyNames(for preset: RulePreset) -> Set<String> {
        Set(
            preset.policies.map(\.configurationName)
                + Self.regionDefinitions.map(\.name)
                + Self.regionDefinitions.map { "\($0.name) · 延迟优选" }
                + [
                    Self.manualGroupName,
                    Self.nestedSelectGroupName,
                    Self.nestedAutoGroupName,
                    Self.nestedManualGroupName,
                    Self.directGroupName,
                    Self.otherRegionsName,
                    "\(Self.otherRegionsName) · 延迟优选",
                    "DIRECT",
                    "REJECT",
                    "direct",
                    "reject"
                ]
        )
    }

    private func uniquedNames(
        _ nodes: [ProxyNode],
        reservedNames: Set<String>
    ) -> [ProxyNode] {
        var counts: [String: Int] = [:]
        return nodes.map { node in
            var copy = node
            let displayName = NodeRegionResolver.displayName(for: node)
            var base = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? node.endpoint : displayName
            if reservedNames.contains(base) {
                base += " · 节点"
            }
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            copy.name = count == 1 ? base : "\(base) · \(count)"
            return copy
        }
    }

    private func appendValue(
        _ value: String?,
        key: String,
        separator: String = "=",
        to values: inout [String]
    ) {
        guard let value, !value.isEmpty else { return }
        values.append("\(key)\(separator)\(confValue(value))")
    }

    /// A raw newline inside a double-quoted YAML scalar ends the value, so it is
    /// folded away before the quote and backslash escapes are applied.
    private func yaml(_ value: String) -> String {
        let escaped = collapsingLineBreaks(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // Node names come from subscription remarks, which are untrusted text. A
    // newline would end the proxy line early and "#" or ";" would turn the rest
    // of it into a comment in the Surge, Loon and Quantumult X formats.
    private func confName(_ value: String) -> String {
        collapsingLineBreaks(value)
            .replacingOccurrences(of: "=", with: "-")
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: "#", with: "＃")
            .replacingOccurrences(of: ";", with: "；")
            // Square brackets open a section in every INI-style config. A node
            // called "[BETA-1] 🇭🇰 HongKong" started one mid-file and orphaned
            // every proxy after it — Shadowrocket showed the five nodes above
            // the line and silently dropped the other twenty-three.
            .replacingOccurrences(of: "[", with: "［")
            .replacingOccurrences(of: "]", with: "］")
            .trimmingCharacters(in: .whitespaces)
    }

    private func confValue(_ value: String) -> String {
        collapsingLineBreaks(value)
            .replacingOccurrences(of: ",", with: "%2C")
    }

    private func surgeQuoted(_ value: String) -> String {
        let escaped = collapsingLineBreaks(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Loon's positional credential fields are quoted in its documented node
    /// syntax. Escaping here also prevents commas inside credentials from
    /// becoming extra fields.
    private func loonQuoted(_ value: String) -> String {
        let escaped = collapsingLineBreaks(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func collapsingLineBreaks(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct RegionDefinition {
    let code: String
    let name: String
}

struct RegionStrategyGroup {
    let name: String
    let nodeNames: [String]

    var automaticName: String { "\(name) · 延迟优选" }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - sing-box

/// sing-box speaks JSON, and Hiddify is a Flutter shell over hiddify-core,
/// which is sing-box — so one document serves both.
///
/// The tree is built as Foundation objects and handed to `JSONSerialization`
/// rather than assembled as text. Node names are airport-controlled and the
/// serialiser escapes them for us, which is the same reason `confName` and
/// `yaml()` exist for the other formats.
extension ConfigurationGenerator {
    struct SingBoxGroup {
        let tag: String
        let isAutomatic: Bool
        let members: [String]
    }

    func singBox(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup],
        target: ClientTarget
    ) -> String {
        let nodeTags = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)

        var groups: [SingBoxGroup] = [
            .init(
                tag: RulePolicy.select.configurationName,
                isAutomatic: false,
                members: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            ),
            .init(tag: RulePolicy.auto.configurationName, isAutomatic: true, members: nodeTags),
            .init(
                tag: Self.manualGroupName,
                isAutomatic: false,
                members: nodeTags.isEmpty ? [Self.singBoxDirectTag] : nodeTags
            ),
            // The four aliases every policy group points at. Clash declares
            // them as hidden groups; sing-box has no hidden flag but still
            // needs them to exist, or it refuses to start on the dangling
            // reference that policyChoices hands out.
            .init(
                tag: Self.nestedSelectGroupName,
                isAutomatic: false,
                members: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            ),
            .init(tag: Self.nestedAutoGroupName, isAutomatic: true, members: nodeTags),
            .init(
                tag: Self.nestedManualGroupName,
                isAutomatic: false,
                members: nodeTags.isEmpty ? [Self.singBoxDirectTag] : nodeTags
            ),
            .init(tag: Self.directGroupName, isAutomatic: false, members: [Self.singBoxDirectTag])
        ]
        for policy in configurablePolicies(preset) where !Self.singBoxRejectingPolicies.contains(policy) {
            groups.append(.init(
                tag: policy.configurationName,
                isAutomatic: false,
                members: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: Self.singBoxRejectTag
                )
            ))
        }
        for group in regionGroups {
            groups.append(.init(
                tag: group.name,
                isAutomatic: false,
                members: [group.automaticName] + group.nodeNames
            ))
            groups.append(.init(tag: group.automaticName, isAutomatic: true, members: group.nodeNames))
        }

        var outbounds: [[String: Any]] = groups.map { group in
            var outbound: [String: Any] = [
                "tag": group.tag,
                "type": group.isAutomatic ? "urltest" : "selector",
                // A group with nothing in it still has to resolve somewhere, or
                // sing-box refuses to start on a dangling reference.
                "outbounds": group.members.isEmpty ? [Self.singBoxDirectTag] : group.members
            ]
            if group.isAutomatic {
                outbound["url"] = "https://www.gstatic.com/generate_204"
                outbound["interval"] = "300s"
                outbound["tolerance"] = 50
            }
            return outbound
        }
        outbounds += nodes.filter { target != .singBox || $0.kind != .wireguard }
            .compactMap(singBoxOutbound)
        outbounds.append(["tag": Self.singBoxDirectTag, "type": "direct"])

        var configuration: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": singBoxDNS(
                remoteDetour: nodes.isEmpty ? nil : RulePolicy.select.configurationName
            ),
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
                "stack": "mixed"
            ]],
            "outbounds": outbounds,
            "route": [
                "rules": singBoxRoutePrelude() + singBoxRules(preset: preset),
                "final": preset.finalPolicy.configurationName,
                "default_domain_resolver": "local",
                "auto_detect_interface": true
            ],
            "experimental": [
                "cache_file": ["enabled": true, "store_fakeip": false]
            ]
        ]

        if target == .singBox {
            let endpoints = nodes.compactMap(singBoxWireGuardEndpoint)
            if !endpoints.isEmpty { configuration["endpoints"] = endpoints }
        }

        if target == .singBox {
            SingBoxDNSPolicy.apply(to: &configuration, nodeTags: nodeTags,
                preferredProxy: RulePolicy.select.configurationName,
                domainRules: singBoxRules(preset: preset), protection: .standard, ipv6Enabled: false)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    static let singBoxDirectTag = "DIRECT"
    static let singBoxRejectTag = "REJECT"

    /// Current sing-box DNS schema (1.12+). Keeping it in one place prevents
    /// imported rule schemes from falling back to the removed legacy
    /// `address: https://...` server representation.
    ///
    /// The local resolver only bootstraps proxy server hostnames through
    /// `route.default_domain_resolver`. User DNS goes to the remote resolver
    /// through a real proxy outbound, otherwise a successful but polluted
    /// carrier answer can still send every connection to the wrong address.
    private func singBoxDNS(remoteDetour: String?) -> [String: Any] {
        var remote: [String: Any] = [
            "type": "https",
            "tag": "remote",
            "server": "1.1.1.1",
            "server_port": 443,
            "path": "/dns-query",
            "tls": ["enabled": true, "server_name": "cloudflare-dns.com"]
        ]
        if let remoteDetour, !remoteDetour.isEmpty {
            remote["detour"] = remoteDetour
        }

        return [
            "servers": [
                remote,
                [
                    "type": "https",
                    "tag": "local",
                    "server": "223.5.5.5",
                    "server_port": 443,
                    "path": "/dns-query",
                    "tls": ["enabled": true, "server_name": "dns.alidns.com"]
                ]
            ],
            // A direct-only document has no proxy path for remote DoH. Keep
            // that edge case usable instead of creating a dangling detour.
            "final": remoteDetour == nil ? "local" : "remote",
            "strategy": "prefer_ipv4",
            // Preserve DNS answer metadata so later TUN connections addressed
            // only by IP can still match the original domain rules.
            "reverse_mapping": true
        ]
    }

    /// Preserve imported DNS without making proxy hostname resolution depend
    /// on the proxy itself. Literal bootstrap addresses resolve the encrypted
    /// resolver host; the direct encrypted resolver then bootstraps the proxy.
    private func singBoxDNS(for scheme: RuleScheme, remoteDetour: String?) -> [String: Any] {
        guard scheme.networkSettings != nil else { return singBoxDNS(remoteDetour: remoteDetour) }
        var servers: [[String: Any]] = schemePlainDNS(scheme).enumerated().map { index, address in
            ["type": "udp", "tag": index == 0 ? "bootstrap" : "bootstrap-\(index + 1)", "server": address]
        }
        var localServers: [[String: Any]] = []
        for value in schemeEncryptedDNS(scheme) {
            guard let url = URLComponents(string: value),
                  let type = url.scheme?.lowercased(), ["https", "tls", "quic"].contains(type),
                  let rawHost = url.host, !rawHost.isEmpty else { continue }
            let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let index = localServers.count
            var server: [String: Any] = [
                "type": type,
                "tag": index == 0 ? "local" : "local-\(index + 1)",
                "server": host,
                "server_port": url.port ?? (type == "https" ? 443 : 853),
                "tls": ["enabled": true, "server_name": host]
            ]
            if RuleSchemeNetworkSettings.normalizedPlainDNSServer(host) == nil {
                server["domain_resolver"] = "bootstrap"
            }
            if type == "https" {
                let path = url.percentEncodedPath.isEmpty ? "/dns-query" : url.percentEncodedPath
                server["path"] = path + (url.percentEncodedQuery.map { "?" + $0 } ?? "")
            }
            localServers.append(server)
        }
        // Defend legacy snapshots containing invalid resolver URLs as well as
        // freshly validated settings. The bootstrap is still a literal address.
        if localServers.isEmpty {
            localServers = [["type": "https", "tag": "local", "server": "223.5.5.5", "path": "/dns-query"]]
        }
        servers += localServers
        if let remoteDetour {
            servers += localServers.enumerated().map { index, local in
                var remote = local
                remote["tag"] = index == 0 ? "remote" : "remote-\(index + 1)"
                remote["detour"] = remoteDetour
                return remote
            }
        }
        return [
            "servers": servers,
            "final": remoteDetour == nil ? "local" : "remote",
            "strategy": schemeIPv6(scheme) ? "prefer_ipv4" : "ipv4_only",
            "reverse_mapping": true
        ]
    }

    /// Non-final route actions must run before destination rules. Sniffing
    /// recovers HTTP Host/TLS SNI from TUN connections so domain rules can
    /// match; DNS traffic is then handed to the configured DNS module.
    private func singBoxRoutePrelude() -> [[String: Any]] {
        [
            ["action": "sniff"],
            [
                "type": "logical",
                "mode": "or",
                "rules": [
                    ["protocol": "dns"],
                    ["port": 53]
                ],
                "action": "hijack-dns"
            ]
        ]
    }

    /// Policies whose whole point is to drop traffic.
    ///
    /// The other clients express these as a group the user can flip between
    /// REJECT and DIRECT. sing-box cannot: from 1.11 rejection is a route
    /// action and there is no outbound for a selector to point at. So the
    /// rules carry `action: reject` directly and no group is emitted — which
    /// is what the group defaulted to anyway.
    static let singBoxRejectingPolicies: Set<RulePolicy> = [.reject, .foreignAds]

    /// Route rules, grouped by destination.
    ///
    /// sing-box takes arrays per rule, so every domain heading for the same
    /// policy collapses into one entry instead of one line each — an ACL4SSR
    /// snapshot is twenty thousand rules and the per-line form is unreadable
    /// and slow to parse.
    private func singBoxRules(preset: RulePreset) -> [[String: Any]] {
        var ordered: [String] = []
        var byPolicy: [String: [String: [String]]] = [:]

        for assignment in preset.assignments {
            let policyName = Self.singBoxRejectingPolicies.contains(assignment.policy)
                ? Self.singBoxRejectTag
                : assignment.policy.configurationName
            for rule in rules.lines(for: assignment) {
                let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count >= 2, let field = Self.singBoxRuleFields[parts[0].uppercased()] else {
                    continue
                }
                let value = parts[1]
                guard !value.isEmpty else { continue }
                if byPolicy[policyName] == nil {
                    byPolicy[policyName] = [:]
                    ordered.append(policyName)
                }
                byPolicy[policyName]?[field, default: []].append(value)
            }
        }

        var result: [[String: Any]] = []
        for policyName in ordered {
            guard let fields = byPolicy[policyName], !fields.isEmpty else { continue }
            var rule: [String: Any] = [:]
            for (field, values) in fields.sorted(by: { $0.key < $1.key }) {
                rule[field] = values.removingDuplicates()
            }
            // 1.11 deprecated the block outbound; rejection is a rule action now.
            if policyName == Self.singBoxRejectTag {
                rule["action"] = "reject"
            } else {
                rule["outbound"] = policyName
            }
            result.append(rule)
        }
        if preset.includeGeoIPCN {
            result.append(["ip_is_private": true, "outbound": Self.singBoxDirectTag])
        }
        return result
    }

    /// `process_name` is deliberately absent. The App Store Apple client can
    /// only search processes in the standalone macOS and jailbroken iOS
    /// variants; emitting it makes every iPhone connection log Not implemented
    /// and, when grouped with destinations, prevents the whole rule matching.
    private static let singBoxRuleFields: [String: String] = [
        "DOMAIN": "domain",
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-KEYWORD": "domain_keyword",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr",
        "IP6-CIDR": "ip_cidr"
    ]
}

extension ConfigurationGenerator {
    /// WireGuard is an endpoint in current sing-box, but its tag remains a
    /// valid selector/route member. Hiddify retains its separate dialect.
    private func singBoxWireGuardEndpoint(_ node: ProxyNode) -> [String: Any]? {
        guard node.kind == .wireguard else { return nil }
        func prefix(_ value: String?, bits: Int) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value.contains("/") ? value : "\(value)/\(bits)"
        }
        var peer: [String: Any] = [
            "address": node.server,
            "port": node.port,
            "public_key": node.wireGuardPublicKey ?? "",
            "allowed_ips": csv(node.wireGuardAllowedIPs)
        ]
        if let value = node.wireGuardPreSharedKey, !value.isEmpty { peer["pre_shared_key"] = value }
        if let value = wireGuardReservedBytes(node), !value.isEmpty { peer["reserved"] = value }
        if let value = node.wireGuardPersistentKeepalive { peer["persistent_keepalive_interval"] = value }
        var endpoint: [String: Any] = [
            "type": "wireguard",
            "tag": NodeRegionResolver.displayName(for: node),
            "address": [prefix(node.wireGuardIPv4, bits: 32), prefix(node.wireGuardIPv6, bits: 128)].compactMap { $0 },
            "private_key": node.wireGuardPrivateKey ?? "",
            "peers": [peer]
        ]
        if let value = node.wireGuardMTU { endpoint["mtu"] = value }
        return endpoint
    }

    /// A protocol outbound; current WireGuard endpoints are emitted separately.
    func singBoxOutbound(_ node: ProxyNode) -> [String: Any]? {
        var outbound: [String: Any] = [
            "tag": NodeRegionResolver.displayName(for: node),
            "server": node.server,
            "server_port": node.port
        ]

        switch node.kind {
        case .shadowsocks:
            outbound["type"] = "shadowsocks"
            outbound["method"] = node.cipher ?? "aes-256-gcm"
            outbound["password"] = node.password ?? ""
            if node.plugin == "v2ray-plugin" {
                outbound["plugin"] = "v2ray-plugin"
                var options = ["mode=websocket"]
                if let mux = node.pluginMux { options.append("mux=\(mux ? "1" : "0")") }
                if node.tls { options.append("tls") }
                if let host = node.hostHeader, !host.isEmpty { options.append("host=\(host)") }
                if let path = node.exportablePath { options.append("path=\(path)") }
                outbound["plugin_opts"] = options.joined(separator: ";")
            } else if let mode = simpleObfsMode(node) {
                outbound["plugin"] = "obfs-local"
                var options = ["obfs=\(mode)"]
                if let host = node.obfsParam, !host.isEmpty { options.append("obfs-host=\(host)") }
                outbound["plugin_opts"] = options.joined(separator: ";")
            }
        case .shadowsocksR:
            outbound["type"] = "shadowsocksr"
            outbound["method"] = node.cipher ?? "aes-256-cfb"
            outbound["password"] = node.password ?? ""
            outbound["protocol"] = node.protocolName ?? "origin"
            if let param = node.protocolParam { outbound["protocol_param"] = param }
            outbound["obfs"] = node.obfs ?? "plain"
            if let param = node.obfsParam { outbound["obfs_param"] = param }
        case .vmess:
            outbound["type"] = "vmess"
            outbound["uuid"] = node.exportableUUID ?? ""
            outbound["security"] = singBoxVMessSecurity(node)
            outbound["alter_id"] = 0
        case .vless:
            outbound["type"] = "vless"
            outbound["uuid"] = node.exportableUUID ?? ""
            if let flow = node.flow, !flow.isEmpty { outbound["flow"] = flow }
        case .trojan:
            outbound["type"] = "trojan"
            outbound["password"] = node.password ?? ""
        case .hysteria2:
            outbound["type"] = "hysteria2"
            outbound["password"] = node.password ?? ""
            if let obfs = hysteria2Obfs(node) {
                outbound["obfs"] = ["type": obfs.type, "password": obfs.password]
            }
        case .hysteria:
            outbound["type"] = "hysteria"
            outbound["auth_str"] = node.password ?? ""
            outbound["up_mbps"] = node.upMbps ?? 50
            outbound["down_mbps"] = node.downMbps ?? 100
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                outbound["obfs"] = obfs
            }
        case .tuic:
            outbound["type"] = "tuic"
            outbound["uuid"] = node.exportableUUID ?? ""
            outbound["password"] = node.password ?? ""
            if let value = node.congestionControl, !value.isEmpty {
                outbound["congestion_control"] = value
            }
            if let value = node.udpRelayMode, !value.isEmpty { outbound["udp_relay_mode"] = value }
        case .wireguard:
            outbound["type"] = "wireguard"
            var addresses: [String] = []
            if let value = node.wireGuardIPv4, !value.isEmpty { addresses.append(value.contains("/") ? value : "\(value)/32") }
            if let value = node.wireGuardIPv6, !value.isEmpty { addresses.append(value.contains("/") ? value : "\(value)/128") }
            // Legacy WireGuard outbounds (Hiddify) use local_address;
            // address belongs to the newer sing-box endpoint schema.
            outbound["local_address"] = addresses
            outbound["private_key"] = node.wireGuardPrivateKey ?? ""
            outbound["peer_public_key"] = node.wireGuardPublicKey ?? ""
            if let value = node.wireGuardPreSharedKey, !value.isEmpty { outbound["pre_shared_key"] = value }
            if let value = wireGuardReservedBytes(node), !value.isEmpty { outbound["reserved"] = value }
            if let value = node.wireGuardMTU { outbound["mtu"] = value }
        case .anytls:
            outbound["type"] = "anytls"
            outbound["password"] = node.password ?? ""
            if let value = node.idleSessionCheckInterval {
                outbound["idle_session_check_interval"] = "\(value)s"
            }
            if let value = node.idleSessionTimeout { outbound["idle_session_timeout"] = "\(value)s" }
            if let value = node.minIdleSession { outbound["min_idle_session"] = value }
        case .snell:
            outbound["type"] = "snell"
            outbound["psk"] = node.password ?? ""
            // The v5 wire protocol is v4-compatible except for QUIC, which
            // sing-box does not implement. Its schema therefore requires 4.
            outbound["version"] = 4
            if node.obfs?.lowercased() == "http" {
                outbound["obfs_mode"] = "http"
                if let host = node.obfsParam, !host.isEmpty { outbound["obfs_host"] = host }
            }
        case .socks5:
            outbound["type"] = "socks"
            outbound["version"] = "5"
            if let user = node.username, !user.isEmpty { outbound["username"] = user }
            if let password = node.password, !password.isEmpty { outbound["password"] = password }
        case .http:
            outbound["type"] = "http"
            if let user = node.username, !user.isEmpty { outbound["username"] = user }
            if let password = node.password, !password.isEmpty { outbound["password"] = password }
        case .unknown:
            return nil
        }

        if let tls = singBoxTLS(node) { outbound["tls"] = tls }
        if let transport = singBoxTransport(node) { outbound["transport"] = transport }
        return outbound
    }

    /// Trojan, Hysteria 2 and AnyTLS are TLS by definition, so they carry the
    /// block whether or not the node bothered to say `tls=1`.
    private func singBoxTLS(_ node: ProxyNode) -> [String: Any]? {
        // SIP003 plugin TLS belongs to the plugin itself. Emitting a second
        // outbound TLS block would turn a valid Shadowsocks + v2ray-plugin
        // node into a different (and invalid) protocol stack.
        guard ![ProxyKind.shadowsocks, .snell, .wireguard].contains(node.kind) else { return nil }
        let alwaysSecure: Set<ProxyKind> = [.trojan, .hysteria, .hysteria2, .tuic, .anytls]
        guard node.tls || alwaysSecure.contains(node.kind) else { return nil }

        var tls: [String: Any] = [
            "enabled": true,
            "server_name": node.sni ?? node.hostHeader ?? node.server,
            "insecure": node.skipCertificateVerification
        ]
        let alpn = ALPNList.values(node.alpn)
        if !alpn.isEmpty {
            tls["alpn"] = alpn
        }
        if node.usesReality {
            var reality: [String: Any] = ["enabled": true, "public_key": node.realityPublicKey ?? ""]
            if let shortID = node.realityShortID, !shortID.isEmpty { reality["short_id"] = shortID }
            tls["reality"] = reality
            // REALITY needs uTLS; sing-box rejects the pair otherwise.
            tls["utls"] = ["enabled": true, "fingerprint": node.fingerprint ?? "chrome"]
        }
        return tls
    }

    private func singBoxTransport(_ node: ProxyNode) -> [String: Any]? {
        // Only these outbound schemas accept V2Ray transport. Shadowsocks
        // carries WebSocket/TLS through plugin_opts, never a second transport.
        guard [.vmess, .vless, .trojan].contains(node.kind) else { return nil }
        guard let transport = node.transport, !transport.isEmpty, transport != "tcp" else { return nil }
        switch transport {
        case "ws":
            var websocket: [String: Any] = ["type": "ws"]
            if let path = node.exportablePath { websocket["path"] = path }
            if let host = node.exportableTransportHost { websocket["headers"] = ["Host": host] }
            return websocket
        case "grpc":
            var grpc: [String: Any] = ["type": "grpc"]
            if let service = node.path, !service.isEmpty {
                grpc["service_name"] = service.hasPrefix("/") ? String(service.dropFirst()) : service
            }
            return grpc
        case "h2", "http":
            var http: [String: Any] = ["type": "http"]
            if let path = node.exportablePath { http["path"] = path }
            if let host = node.hostHeader, !host.isEmpty { http["host"] = [host] }
            return http
        case "httpupgrade":
            var upgrade: [String: Any] = ["type": "httpupgrade"]
            if let path = node.exportablePath { upgrade["path"] = path }
            if let host = node.hostHeader, !host.isEmpty { upgrade["host"] = host }
            return upgrade
        default:
            return nil
        }
    }

    /// sing-box rejects `auto`; it wants a concrete cipher.
    private func singBoxVMessSecurity(_ node: ProxyNode) -> String {
        let accepted: Set<String> = [
            "auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305", "aes-128-ctr"
        ]
        let cipher = node.cipher?.lowercased() ?? ""
        guard accepted.contains(cipher), cipher != "auto" else { return "auto" }
        return cipher
    }
}

extension ConfigurationGenerator {
    /// The imported-scheme path, reproducing the groups the source file
    /// declared instead of Tower's own policy layout — same contract as the
    /// other clients, expressed as sing-box selectors and urltests.
    func singBoxScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        rulePlan: RuleSetEmissionPlanner.Plan,
        target: ClientTarget,
        dnsDomainRules: [[String: Any]] = []
    ) -> String {
        let finalGroup = rulePlan.finalGroupName ?? groups.first?.name ?? Self.singBoxDirectTag
        var outbounds: [[String: Any]] = groups.map { group in
            var outbound: [String: Any] = [
                "tag": group.name,
                "type": group.kind != .select ? "urltest" : "selector",
                "outbounds": group.members.isEmpty ? [Self.singBoxDirectTag] : group.members
            ]
            if group.kind != .select {
                outbound["url"] = group.testURL
                outbound["interval"] = "\(group.interval)s"
                outbound["tolerance"] = group.tolerance
            }
            for (key, value) in nativeOptions(group, target: target) {
                if ["true", "false"].contains(value) { outbound[key] = value == "true" }
                else { outbound[key] = value }
            }
            return outbound
        }
        outbounds += nodes.filter { target != .singBox || $0.kind != .wireguard }
            .compactMap(singBoxOutbound)

        // A route-level `action: reject` is sufficient for direct blocking
        // rules, but selectors cannot reference an action. Imported schemes
        // commonly expose choices such as [REJECT, DIRECT], so provide the
        // concrete dependency only when the imported graph actually needs it.
        let needsRejectOutbound = groups.contains { group in
            group.members.contains { $0.uppercased() == Self.singBoxRejectTag }
        } || finalGroup.uppercased() == Self.singBoxRejectTag
        let alreadyDefinesReject = outbounds.contains {
            ($0["tag"] as? String)?.uppercased() == Self.singBoxRejectTag
        }
        if needsRejectOutbound && !alreadyDefinesReject {
            outbounds.append(["tag": Self.singBoxRejectTag, "type": "block"])
        }
        outbounds.append(["tag": Self.singBoxDirectTag, "type": "direct"])

        var rules: [[String: Any]] = []
        var pendingGroup: String?
        var pendingFields: [String: [String]] = [:]

        func rule(policyName: String, fields: [String: [String]]) -> [String: Any] {
            var rule: [String: Any] = [:]
            for (field, values) in fields.sorted(by: { $0.key < $1.key }) {
                rule[field] = values.removingDuplicates()
            }
            if policyName.uppercased() == "REJECT" {
                rule["action"] = "reject"
            } else {
                rule["outbound"] = policyName
            }
            return rule
        }

        func flushPending() {
            guard let group = pendingGroup, !pendingFields.isEmpty else { return }
            rules.append(rule(policyName: group, fields: pendingFields))
            pendingGroup = nil
            pendingFields = [:]
        }

        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                flushPending()
                var remoteRule: [String: Any] = ["rule_set": [resource.identifier]]
                if resource.policyName.uppercased() == "REJECT" {
                    remoteRule["action"] = "reject"
                } else {
                    remoteRule["outbound"] = resource.policyName
                }
                rules.append(remoteRule)
            case .inline(let inline):
                let parts = inline.line.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count >= 2 else { continue }
                guard let field = Self.singBoxRuleFields[parts[0].uppercased()], !parts[1].isEmpty,
                      !parts.contains("src") else {
                    flushPending()
                    if var rule = RoutingRuleCapabilities.singBoxCondition(inline.line) {
                        if inline.policyName.uppercased() == "REJECT" { rule["action"] = "reject" }
                        else { rule["outbound"] = inline.policyName }
                        rules.append(rule)
                    }
                    continue
                }
                if pendingGroup != inline.policyName {
                    flushPending()
                    pendingGroup = inline.policyName
                }
                pendingFields[field, default: []].append(parts[1])
            }
        }
        flushPending()

        rules = singBoxRoutePrelude() + rules

        let remoteRuleSets: [[String: Any]] = rulePlan.remoteResources.map { resource in
            let format = resource.format == .singBoxBinarySRS ? "binary" : "source"
            return [
                "type": "remote",
                "tag": resource.identifier,
                "format": format,
                "url": resource.url.absoluteString,
                "update_interval": "1d"
            ]
        }

        let remoteDetour = singBoxRemoteDNSDetour(
            finalGroup: finalGroup,
            groups: groups,
            nodes: nodes
        )
        var route: [String: Any] = [
            "rules": rules,
            "final": finalGroup,
            "default_domain_resolver": "local",
            "auto_detect_interface": true
        ]
        if !remoteRuleSets.isEmpty { route["rule_set"] = remoteRuleSets }

        var configuration: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": singBoxDNS(for: scheme, remoteDetour: remoteDetour),
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": schemeIPv6(scheme)
                    ? ["172.19.0.1/30", "fdfe:dcba:9876::1/126"] : ["172.19.0.1/30"],
                "auto_route": true,
                "strict_route": true,
                "stack": "mixed"
            ]],
            "outbounds": outbounds,
            "route": route,
            "experimental": ["cache_file": ["enabled": true, "store_fakeip": false]]
        ]

        // sing-box 1.14 deprecated the implicit downloader used by remote
        // rule sets. The standalone sing-box MT target is versioned with that
        // core, so give it an explicit Go HTTP client. Hiddify intentionally
        // keeps its older dialect until its embedded core is tested separately.
        if target == .singBox, !remoteRuleSets.isEmpty {
            let httpClientTag = "tower-rule-set"
            var httpClient: [String: Any] = [
                "tag": httpClientTag,
                "engine": "go",
                // Resolve before the detour: a SOCKS/HTTP peer may have no
                // working DNS during cold startup. Do not delegate rule host
                // resolution to that peer or the tunnel's system resolver.
                "domain_resolver": "local"
            ]
            if let remoteDetour { httpClient["detour"] = remoteDetour }
            configuration["http_clients"] = [httpClient]
            route["default_http_client"] = httpClientTag
            configuration["route"] = route
        }

        if target == .singBox {
            let endpoints = nodes.compactMap(singBoxWireGuardEndpoint)
            if !endpoints.isEmpty { configuration["endpoints"] = endpoints }
        }

        if target == .singBox {
            SingBoxDNSPolicy.apply(to: &configuration,
                nodeTags: nodes.map { NodeRegionResolver.displayName(for: $0) },
                preferredProxy: remoteDetour, domainRules: dnsDomainRules,
                protection: schemeDNSProtectionMode(scheme),
                ipv6Enabled: scheme.networkSettings?.ipv6Enabled ?? false)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    /// Imported schemes name their selectors themselves. Prefer the final
    /// selector because it represents the source scheme's default route, then
    /// fall back to a node-containing group or the first concrete node.
    private func singBoxRemoteDNSDetour(
        finalGroup: String,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode]
    ) -> String? {
        let reserved = [Self.singBoxDirectTag, Self.singBoxRejectTag]
        if !reserved.contains(where: { $0.caseInsensitiveCompare(finalGroup) == .orderedSame }),
           groups.contains(where: { $0.name == finalGroup }) {
            return finalGroup
        }
        if let group = groups.first(where: { !$0.nodeNames.isEmpty }) {
            return group.name
        }
        return nodes.first.map { NodeRegionResolver.displayName(for: $0) }
    }
}

// MARK: - Egern

/// Egern's YAML nests by type: every proxy, policy group and rule is a
/// single-key mapping whose key names the kind, unlike Clash's flat `type:`.
///
///     proxies:
///       - shadowsocks:
///           name: HK 01
///     policy_groups:
///       - select:
///           name: 节点选择
///           policies: [...]
///     rules:
///       - domain_suffix:
///           match: google.com
///           policy: 节点选择
extension ConfigurationGenerator {
    static let egernDirect = "DIRECT"
    static let egernReject = "REJECT"

    func egern(
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let nodeNames = inlineNodes.map { NodeRegionResolver.displayName(for: $0) }
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteURLs = remoteSubscriptions.map(\.urlString)
        let regionGroupNames = regionGroups.map(\.name)

        var output = header(
            target: .egern,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += "\nproxies:\n"
        output += inlineNodes.isEmpty ? "  []\n" : inlineNodes.compactMap(egernProxy).joined()

        output += "\npolicy_groups:\n"
        output += egernSelect(
            name: RulePolicy.select.configurationName,
            policies: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += egernAutoTest(
            name: RulePolicy.auto.configurationName,
            policies: nodeNames,
            urls: remoteURLs
        )
        output += egernSelect(
            name: Self.manualGroupName,
            policies: nodeNames.isEmpty && remoteURLs.isEmpty ? [Self.egernDirect] : nodeNames,
            urls: remoteURLs
        )
        // The four aliases every policy group points at, declared here the way
        // the other formats declare them.
        output += egernSelect(
            name: Self.nestedSelectGroupName,
            policies: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += egernAutoTest(name: Self.nestedAutoGroupName, policies: nodeNames, urls: remoteURLs)
        output += egernSelect(
            name: Self.nestedManualGroupName,
            policies: nodeNames.isEmpty && remoteURLs.isEmpty ? [Self.egernDirect] : nodeNames,
            urls: remoteURLs
        )
        output += egernSelect(name: Self.directGroupName, policies: [Self.egernDirect])

        for policy in configurablePolicies(preset) {
            output += egernSelect(
                name: policy.configurationName,
                policies: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: Self.egernReject
                )
            )
        }
        for group in regionGroups {
            let inlineNames = group.nodeNames.filter { !remoteNodeNames.contains($0) }
            let remoteNames = group.nodeNames.filter(remoteNodeNames.contains)
            let urls = remoteNames.isEmpty ? [] : remoteURLs
            let filter = exactNameFilter(remoteNames)
            output += egernSelect(
                name: group.name,
                policies: [group.automaticName] + inlineNames,
                urls: urls,
                filter: filter
            )
            output += egernAutoTest(
                name: group.automaticName,
                policies: inlineNames,
                urls: urls,
                filter: filter
            )
        }

        output += "\nrules:\n"
        for assignment in preset.assignments {
            let policyName = assignment.policy == .reject
                ? Self.egernReject
                : assignment.policy.configurationName
            for rule in rules.lines(for: assignment) {
                if let line = egernRule(rule, policy: policyName) { output += line }
            }
        }
        if preset.includeGeoIPCN {
            output += "  - geoip:\n      match: CN\n      no_resolve: true\n      policy: \(Self.egernDirect)\n"
        }
        output += "  - default:\n      policy: \(yaml(preset.finalPolicy.configurationName))\n"
        return output
    }

    func egernScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        inlineNodes: [ProxyNode],
        remoteSubscriptions: [RemoteSubscriptionEntry],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let remoteNodeNames = remoteNodeNameSet(nodes: nodes, subscriptions: remoteSubscriptions)
        let remoteURLs = remoteSubscriptions.map(\.urlString)
        var output = schemeHeader(
            scheme,
            target: .egern,
            embedsRemoteSubscriptions: !remoteSubscriptions.isEmpty
        )
        output += "\nproxies:\n"
        output += inlineNodes.isEmpty ? "  []\n" : inlineNodes.compactMap(egernProxy).joined()

        output += "\npolicy_groups:\n"
        for group in groups {
            let remoteURLs = groupSubscriptions(group, from: remoteSubscriptions).map(\.urlString)
            let inlineMembers = group.members.filter { !remoteNodeNames.contains($0) || group.inlineNodeNames.contains($0) }
            let remoteSelection = remoteGroupSelection(
                for: group,
                remoteNodeNames: remoteNodeNames
            )
            let urls = remoteSelection.includesRemoteNodes ? remoteURLs : []
            switch group.kind {
            case .select:
                output += egernSelect(
                    name: group.name,
                    policies: inlineMembers,
                    urls: urls,
                    filter: remoteSelection.filter
                )
            case .urlTest, .smart, .fallback, .loadBalance:
                let type = group.kind == .urlTest ? "auto_test" : group.kind == .smart ? "smart" : group.kind == .fallback ? "fallback" : "load_balance"
                output += "  - \(type):\n      name: \(yaml(group.name))\n"
                output += egernGroupMembers(policies: inlineMembers, urls: urls, filter: remoteSelection.filter)
                if group.kind == .loadBalance {
                    output += "      algorithm: \(loadBalanceAlgorithm(group.algorithm, target: .egern) ?? "hash")\n"
                }
                if group.kind == .urlTest || group.kind == .fallback {
                    output += "      interval: \(group.interval)\n      latency_test_url: \(yaml(group.testURL))\n"
                }
                if group.kind == .urlTest { output += "      tolerance: \(group.tolerance)\n" }
                if group.kind == .smart, let priorities = orderedEgernPriorities(group.parameters) {
                    output += "      priorities:\n"
                    for (pattern, coefficient) in priorities {
                        output += "        \(yaml(pattern)): \(coefficient)\n"
                    }
                }
            case .conditional:
                if let rules = safeConditionalRules(group.parameters?["rules"]),
                   let fallback = group.parameters?["default_policy"] {
                    output += "  - conditional:\n      name: \(yaml(group.name))\n"
                    output += "      rules: \(rules)\n      default_policy: \(yaml(fallback))\n"
                }
            case .relay, .unsupported: break
            }
            appendNativeOptions(group, target: .egern, to: &output)
        }

        output += "\nrules:\n"
        let finalGroup = rulePlan.finalGroupName ?? groups.first?.name ?? Self.egernDirect
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                output += "  - rule_set:\n"
                output += "      match: \(yaml(resource.url.absoluteString))\n"
                output += "      policy: \(yaml(resource.policyName))\n"
                output += "      update_interval: 86400\n"
            case .inline(let rule):
                if let mapped = egernRule(rule.line, policy: rule.policyName) { output += mapped }
            }
        }
        output += "  - default:\n      policy: \(yaml(finalGroup))\n"
        return output
    }

    private func egernSelect(
        name: String,
        policies: [String],
        urls: [String] = [],
        filter: String? = nil
    ) -> String {
        var block = "  - select:\n      name: \(yaml(name))\n"
        block += egernGroupMembers(policies: policies, urls: urls, filter: filter)
        return block
    }

    private func egernAutoTest(
        name: String,
        policies: [String],
        urls: [String] = [],
        filter: String? = nil,
        interval: Int = 600,
        tolerance: Int = 100
    ) -> String {
        var block = "  - auto_test:\n      name: \(yaml(name))\n"
        block += egernGroupMembers(policies: policies, urls: urls, filter: filter)
        return block + "      interval: \(interval)\n      tolerance: \(tolerance)\n      timeout: 5\n"
    }

    private func egernGroupMembers(
        policies: [String],
        urls: [String],
        filter: String?
    ) -> String {
        var output = ""
        let policies = policies.isEmpty && urls.isEmpty ? [Self.egernDirect] : policies
        if !policies.isEmpty {
            output += "      policies:\n"
            for policy in policies { output += "        - \(yaml(policy))\n" }
        }
        if !urls.isEmpty {
            output += "      urls:\n"
            for url in urls.removingDuplicates() { output += "        - \(yaml(url))\n" }
            output += "      update_interval: 86400\n"
            if let filter, !filter.isEmpty { output += "      filter: \(yaml(filter))\n" }
        }
        return output
    }

    /// One rule per entry: Egern's `match` takes a single value, so a rule list
    /// is one mapping each rather than an array per policy.
    private func egernRule(_ rule: String, policy: String) -> String? {
        let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2,
              let matcher = Self.egernRuleMatchers[parts[0].uppercased()],
              !parts[1].isEmpty else { return nil }

        // Egern spells the flag as a neighbouring key rather than a trailing
        // field, which is why it used to be dropped here. GEOIP always skips
        // resolution, matching the built-in presets and the other six clients;
        // an IP rule keeps whatever the source file asked for.
        let isIPMatcher = matcher == "geoip" || matcher == "ip_cidr"
        let skipsResolution = isIPMatcher
            && (parts[0].uppercased() == "GEOIP"
                || parts.dropFirst().contains { $0.lowercased() == "no-resolve" })

        var line = "  - \(matcher):\n      match: \(yaml(parts[1]))\n"
        if skipsResolution { line += "      no_resolve: true\n" }
        return line + "      policy: \(yaml(policy))\n"
    }

    private static let egernRuleMatchers: [String: String] = [
        "DOMAIN": "domain",
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-KEYWORD": "domain_keyword",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr",
        "IP6-CIDR": "ip_cidr",
        "GEOIP": "geoip",
        "URL-REGEX": "url_regex",
        "DEST-PORT": "dest_port",
        "PROTOCOL": "protocol"
    ]

    /// One `- <type>:` entry with the snake_case keys Egern uses.
    func egernProxy(_ node: ProxyNode) -> String? {
        var body: [String] = ["      name: \(yaml(NodeRegionResolver.displayName(for: node)))"]
        func endpoint() {
            body.append("      server: \(yaml(node.server))")
            body.append("      port: \(node.port)")
        }

        let type: String
        switch node.kind {
        case .shadowsocks:
            type = "shadowsocks"
            // Egern spells this one without the `-ietf` infix.
            let cipher = node.cipher ?? "aes-256-gcm"
            body.append("      method: \(yaml(cipher == "chacha20-ietf-poly1305" ? "chacha20-poly1305" : cipher))")
            body.append("      password: \(yaml(node.password ?? ""))")
            endpoint()
            if let mode = simpleObfsMode(node) {
                body.append("      obfs: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    body.append("      obfs_host: \(yaml(host))")
                }
            }
        case .trojan, .anytls:
            type = node.kind == .trojan ? "trojan" : "anytls"
            endpoint()
            body.append("      password: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
        case .hysteria2:
            // Egern names this one `auth`, not `password`, and treats it as
            // required: "missing field `auth`" rejects the whole profile.
            type = "hysteria2"
            endpoint()
            body.append("      auth: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
        case .tuic:
            type = "tuic"
            endpoint()
            body.append("      uuid: \(yaml(node.exportableUUID ?? ""))")
            body.append("      password: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
            // Egern wants a list here even for the single value a URI carries.
            let alpn = ALPNList.values(node.alpn)
            body.append("      alpn: [\((alpn.isEmpty ? ["h3"] : alpn).map(yaml).joined(separator: ", "))]")
        case .wireguard:
            type = "wireguard"
            endpoint()
            body.append("      private_key: \(yaml(node.wireGuardPrivateKey ?? ""))")
            body.append("      peer_public_key: \(yaml(node.wireGuardPublicKey ?? ""))")
            if let value = node.wireGuardIPv4 { body.append("      local_ipv4: \(yaml(value))") }
            if let value = node.wireGuardIPv6 { body.append("      local_ipv6: \(yaml(value))") }
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                body.append("      preshared_key: \(yaml(value))")
            }
            if let bytes = wireGuardReservedBytes(node), !bytes.isEmpty {
                body.append("      reserved: [\(bytes.map(String.init).joined(separator: ", "))]")
            }
            if !csv(node.wireGuardDNS).isEmpty { body.append("      dns_servers: \(yamlList(csv(node.wireGuardDNS)))") }
            if let value = node.wireGuardMTU { body.append("      mtu: \(value)") }
            if let value = node.wireGuardPersistentKeepalive { body.append("      keepalive: \(value)") }
        case .vmess:
            type = "vmess"
            endpoint()
            body.append("      user_id: \(yaml(node.exportableUUID ?? ""))")
            body.append("      security: \(yaml(egernVMessSecurity(node)))")
            body.append("      legacy: false")
        case .vless:
            type = "vless"
            endpoint()
            body.append("      user_id: \(yaml(node.exportableUUID ?? ""))")
            if let flow = node.flow, !flow.isEmpty { body.append("      flow: \(yaml(flow))") }
        case .snell:
            type = "snell"
            endpoint()
            body.append("      psk: \(yaml(node.password ?? ""))")
            body.append("      version: \(node.version ?? 4)")
        case .socks5, .http:
            let secure = node.tls
            type = node.kind == .socks5 ? (secure ? "socks5_tls" : "socks5") : (secure ? "https" : "http")
            endpoint()
            if let user = node.username, !user.isEmpty { body.append("      username: \(yaml(user))") }
            if let password = node.password, !password.isEmpty {
                body.append("      password: \(yaml(password))")
            }
        case .hysteria, .shadowsocksR, .unknown:
            // supports(_:) filters these out; this keeps the switch total.
            return nil
        }

        body.append("      udp_relay: true")
        if node.usesReality, ![.vmess, .vless].contains(node.kind) {
            body.append("      reality:")
            body.append("        public_key: \(yaml(node.realityPublicKey ?? ""))")
            if let shortID = node.realityShortID, !shortID.isEmpty {
                body.append("        short_id: \(yaml(shortID))")
            }
        }
        if ![.shadowsocks, .vmess, .vless].contains(node.kind) {
            body.append("      skip_tls_verify: \(node.skipCertificateVerification ? "true" : "false")")
            if let fingerprint = node.certificateFingerprint, !fingerprint.isEmpty {
                body.append("      fingerprint_sha256: \(yaml(fingerprint))")
            }
        }
        if [.http, .socks5].contains(node.kind), node.tls, let sni = node.sni {
            body.append("      sni: \(yaml(sni))")
        }
        if node.kind == .hysteria2 {
            if let obfs = hysteria2Obfs(node) {
                body.append("      obfs: \(yaml(obfs.type))")
                body.append("      obfs_password: \(yaml(obfs.password))")
            }
            if let bandwidth = node.upMbps { body.append("      bandwidth: \(bandwidth)") }
        }
        if node.kind == .tuic, let mode = node.udpRelayMode {
            body.append("      udp_relay_mode: \(yaml(mode))")
        }
        if let transport = egernTransport(node) { body.append(contentsOf: transport) }
        return "  - \(type):\n" + body.joined(separator: "\n") + "\n"
    }

    /// Websocket nests under `transport`, keyed `ws` or `wss` by whether the
    /// node negotiates TLS.
    private func egernTransport(_ node: ProxyNode) -> [String]? {
        if node.kind == .trojan, node.transport == "ws" {
            var lines = ["      websocket:", "        path: \(yaml(node.exportablePath ?? "/"))"]
            if let host = node.exportableTransportHost { lines.append("        host: \(yaml(host))") }
            return lines
        }
        guard [.vmess, .vless].contains(node.kind) else { return nil }
        let transport = node.transport ?? "tcp"
        if transport == "tcp" && !node.tls && !node.usesReality { return nil }
        var lines = ["      transport:"]
        switch transport {
        case "tcp":
            lines.append("        tls:")
            if let sni = node.sni { lines.append("          sni: \(yaml(sni))") }
            if node.usesReality {
                lines.append("          reality:")
                lines.append("            public_key: \(yaml(node.realityPublicKey ?? ""))")
                if let shortID = node.realityShortID { lines.append("            short_id: \(yaml(shortID))") }
            }
        case "ws":
            lines.append("        \(node.tls ? "wss" : "ws"):")
            if let path = node.exportablePath { lines.append("          path: \(yaml(path))") }
            if let host = node.exportableTransportHost {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
            if node.tls, let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        case "http":
            lines.append("        http1:")
            lines.append("          path: \(yaml(node.exportablePath ?? "/"))")
            if let host = node.hostHeader, !host.isEmpty {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
        case "h2":
            lines.append("        http2:")
            lines.append("          path: \(yaml(node.exportablePath ?? "/"))")
            if let host = node.hostHeader, !host.isEmpty {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
            if let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        case "grpc":
            lines.append("        grpc:")
            if let service = node.path, !service.isEmpty {
                lines.append("          service_name: \(yaml(service.hasPrefix("/") ? String(service.dropFirst()) : service))")
            }
            if let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        default:
            return nil
        }
        if node.tls || node.usesReality {
            lines.append("          skip_tls_verify: \(node.skipCertificateVerification ? "true" : "false")")
            if let fingerprint = node.certificateFingerprint { lines.append("          fingerprint_sha256: \(yaml(fingerprint))") }
        }
        return lines
    }

    private func egernVMessSecurity(_ node: ProxyNode) -> String {
        let cipher = node.cipher?.lowercased() ?? "auto"
        if cipher == "chacha20-ietf-poly1305" { return "chacha20-poly1305" }
        let accepted: Set<String> = ["auto", "none", "aes-128-gcm", "chacha20-poly1305"]
        return accepted.contains(cipher) ? cipher : "auto"
    }
}
