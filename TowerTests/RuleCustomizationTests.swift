import XCTest
@testable import Tower

final class RuleCustomizationTests: XCTestCase {
    private let nodes = [
        ProxyNode(
            kind: .shadowsocks,
            name: "香港 01",
            server: "hk.example.com",
            port: 443,
            cipher: "aes-128-gcm",
            password: "demo",
            rawURI: "ss://demo"
        )
    ]

    func testExplicitSelectionKeepsFinalGroupAndTransitiveDependencies() {
        let scheme = makeScheme()

        let customized = scheme.customized(
            enabledRuleGroupNames: ["AI 服务"],
            customRuleFlows: []
        )

        XCTAssertEqual(
            customized.groups.map(\.name),
            ["节点选择", "自动选择", "AI 服务", "漏网之鱼"]
        )
        XCTAssertEqual(customized.rulesets.map(\.groupName), ["AI 服务", "漏网之鱼"])
        XCTAssertFalse(customized.groups.map(\.name).contains("海外媒体"))
    }

    func testCustomRuleFlowNormalizesPastedPoliciesAndStaysBeforeFinal() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "Tailscale",
            policyName: "AI 服务",
            rulesText: """
            # 可以粘贴带旧策略的规则
            DOMAIN-SUFFIX,tailscale.com,旧策略
            IP-CIDR,100.64.0.0/10,旧策略,no-resolve
            """
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: [],
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.rulesets.map(\.resource),
            [
                .inline("DOMAIN-SUFFIX,tailscale.com"),
                .inline("IP-CIDR,100.64.0.0/10,no-resolve"),
                .inline("FINAL"),
            ]
        )
        XCTAssertEqual(customized.rulesets.map(\.groupName), ["AI 服务", "AI 服务", "漏网之鱼"])
        XCTAssertTrue(customized.groups.map(\.name).contains("AI 服务"))
    }

    func testUnrelatedCustomRulesStayNearFinalInsteadOfJumpingToTheTop() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "优先规则",
            policyName: "DIRECT",
            rulesText: "DOMAIN-SUFFIX,priority.example"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.rulesets.map(\.resource),
            [
                .inline("DOMAIN-SUFFIX,openai.com"),
                .inline("DOMAIN-SUFFIX,netflix.com"),
                .inline("DOMAIN-SUFFIX,priority.example"),
                .inline("FINAL"),
            ],
            "无冲突的用户规则只需放在 FINAL 前，不应抢占所有上游规则"
        )
    }

    func testCustomRuleMovesBeforeAnUpstreamRuleWithTheSameMatch() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "奈飞覆盖",
            policyName: "DIRECT",
            rulesText: "DOMAIN-SUFFIX,netflix.com"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.rulesets.map(\.resource),
            [
                .inline("DOMAIN-SUFFIX,openai.com"),
                .inline("DOMAIN-SUFFIX,netflix.com"),
                .inline("DOMAIN-SUFFIX,netflix.com"),
                .inline("FINAL"),
            ]
        )
        XCTAssertEqual(
            customized.rulesets.map(\.groupName),
            ["AI 服务", "DIRECT", "海外媒体", "漏网之鱼"],
            "自定义规则必须排在具有相同匹配内容的上游规则之前"
        )
    }

    func testCustomRuleMovesBeforeAnUpstreamRulesetForTheSameGroup() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "媒体覆盖",
            policyName: "海外媒体",
            rulesText: "DOMAIN-SUFFIX,priority.example"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.rulesets.map(\.resource),
            [
                .inline("DOMAIN-SUFFIX,openai.com"),
                .inline("DOMAIN-SUFFIX,priority.example"),
                .inline("DOMAIN-SUFFIX,netflix.com"),
                .inline("FINAL"),
            ]
        )
    }

    func testGeneratedPolicyGroupStaysBeforeGroupBoundToFinalRule() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "OpenAI",
            rulesText: "DOMAIN-SUFFIX,priority.example",
            defaultPolicyName: "节点选择"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.groups.map(\.name),
            ["节点选择", "自动选择", "AI 服务", "海外媒体", "OpenAI", "漏网之鱼"]
        )
    }

    func testGeneratedPolicyGroupMovesBeforeGroupOwningSameMatch() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "OpenAI 自定义",
            rulesText: "DOMAIN-SUFFIX,openai.com",
            defaultPolicyName: "节点选择"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.groups.map(\.name),
            ["节点选择", "自动选择", "OpenAI 自定义", "AI 服务", "海外媒体", "漏网之鱼"]
        )
    }

    func testExistingPolicyGroupIsNotRepositionedWhenCustomFlowUsesSameName() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "AI 服务",
            rulesText: "DOMAIN-SUFFIX,priority.example",
            defaultPolicyName: "节点选择"
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(customized.groups.map(\.name), scheme.groups.map(\.name))
    }

    @MainActor
    func testCachedRemoteDomainMatchMovesCustomRuleBeforeOwningRuleset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-domain-rule-order-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let upstreamURL = try XCTUnwrap(URL(string: "https://rules.example.com/upstream-domain.list"))
        try store.store("DOMAIN-SUFFIX,openai.com\n", for: upstreamURL)
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            downloadStore: store,
            arguments: []
        )
        let scheme = makeRemoteOrderingScheme(url: upstreamURL)
        model.upsertCustomRuleFlow(
            CustomRuleFlow(
                schemeID: scheme.id,
                name: "OpenAI 优先",
                policyName: "DIRECT",
                rulesText: "DOMAIN-SUFFIX,openai.com"
            )
        )

        let effective = model.effectiveScheme(scheme)

        XCTAssertEqual(
            effective.rulesets.map(\.resource),
            [.inline("DOMAIN-SUFFIX,openai.com"), .remote(upstreamURL), .inline("FINAL")]
        )
    }

    @MainActor
    func testCachedRemoteIPMatchIgnoresNoResolveWhenOrdering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-ip-rule-order-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let upstreamURL = try XCTUnwrap(URL(string: "https://rules.example.com/upstream-ip.list"))
        try store.store("IP-CIDR,100.64.0.0/10,no-resolve\n", for: upstreamURL)
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            downloadStore: store,
            arguments: []
        )
        let scheme = makeRemoteOrderingScheme(url: upstreamURL)
        model.upsertCustomRuleFlow(
            CustomRuleFlow(
                schemeID: scheme.id,
                name: "Tailscale 优先",
                policyName: "DIRECT",
                rulesText: "IP-CIDR,100.64.0.0/10"
            )
        )

        let effective = model.effectiveScheme(scheme)

        XCTAssertEqual(
            effective.rulesets.map(\.resource),
            [.inline("IP-CIDR,100.64.0.0/10"), .remote(upstreamURL), .inline("FINAL")]
        )
    }

    func testUserCreatedRuleSetOwnsAReusablePolicyGroup() {
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "🪄 我的收藏",
            rulesText: "DOMAIN-SUFFIX,example.org",
            kind: .select,
            policyNames: ["节点选择", "DIRECT"]
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(flow.policyName, "🪄 我的收藏")
        XCTAssertEqual(
            flow.generatedPolicyGroup,
            RuleSchemeGroup(
                name: "🪄 我的收藏",
                kind: .select,
                members: [.reference("节点选择"), .reference("DIRECT")]
            )
        )
        XCTAssertTrue(customized.groups.contains { $0.name == "🪄 我的收藏" })
        XCTAssertTrue(customized.rulesets.contains {
            $0.groupName == "🪄 我的收藏"
                && $0.resource == .inline("DOMAIN-SUFFIX,example.org")
        })
    }

    func testSimpleRuleSetCreationDefaultsToEnabledAndKeepsOneRoutingTarget() {
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: "custom",
            name: "Google",
            rulesText: "DOMAIN-SUFFIX,google.com",
            defaultPolicyName: "节点选择"
        )

        XCTAssertTrue(flow.isEnabled)
        XCTAssertEqual(flow.policyName, "Google")
        XCTAssertEqual(flow.generatedPolicyGroup?.kind, .select)
        XCTAssertEqual(flow.generatedPolicyGroup?.members, [.reference("节点选择")])
    }

    func testBlackmatrixListBodyNormalizesWithoutTreatingCommentsAsRules() {
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: "custom",
            name: "Google",
            rulesText: """
            # NAME: Google
            # AUTHOR: blackmatrix7
            DOMAIN,voice.telephony.goog
            DOMAIN-SUFFIX,1e100.net
            IP-CIDR,8.8.8.8/32,no-resolve
            PROCESS-NAME,com.google.android.gms
            """,
            defaultPolicyName: "节点选择"
        )

        XCTAssertEqual(
            flow.normalizedRules,
            [
                "DOMAIN,voice.telephony.goog",
                "DOMAIN-SUFFIX,1e100.net",
                "IP-CIDR,8.8.8.8/32,no-resolve",
                "PROCESS-NAME,com.google.android.gms",
            ]
        )
    }

    func testUserCreatedRuleSetRecognizesHTTPSRuleSetURL() throws {
        let source = "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list"
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: "custom",
            name: "🎬 奈飞",
            rulesText: source,
            defaultPolicyName: "节点选择"
        )

        XCTAssertEqual(flow.remoteRuleURL?.absoluteString, source)
        XCTAssertEqual(flow.ruleInputText, source)
        XCTAssertTrue(flow.normalizedRules.isEmpty)
        XCTAssertTrue(flow.hasRuleContent)
    }

    func testUserCreatedInlineRulesRemainInlineContent() {
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: "custom",
            name: "Apple",
            rulesText: """
            DOMAIN,apple.comscoreresearch.com
            IP-CIDR,17.0.0.0/8,no-resolve
            """,
            defaultPolicyName: "DIRECT"
        )

        XCTAssertNil(flow.remoteRuleURL)
        XCTAssertEqual(
            flow.normalizedRules,
            [
                "DOMAIN,apple.comscoreresearch.com",
                "IP-CIDR,17.0.0.0/8,no-resolve",
            ]
        )
        XCTAssertTrue(flow.hasRuleContent)
    }

    func testCustomTailscaleRulesReachEveryExportFormat() {
        let scheme = makeScheme().customized(
            enabledRuleGroupNames: [],
            customRuleFlows: [
                CustomRuleFlow(
                    schemeID: "custom",
                    name: "Tailscale",
                    policyName: "AI 服务",
                    rulesText: "DOMAIN-SUFFIX,tailscale.com"
                )
            ]
        )

        for target in ClientTarget.allCases {
            let result = ConfigurationGenerator().generate(
                nodes: nodes,
                scheme: scheme,
                target: target
            )
            XCTAssertTrue(result.content.contains("tailscale.com"), "\(target.name) 丢失自定义规则")
        }
    }

    func testDisablingGroupEmojiRenamesGroupsReferencesAndRulesetsTogether() {
        let scheme = RuleScheme(
            id: "emoji",
            name: "Emoji 规则",
            summary: "测试",
            groups: [
                RuleSchemeGroup(
                    name: "🚀 节点选择",
                    kind: .select,
                    members: [.reference("♻️ 自动选择"), .reference("DIRECT")]
                ),
                RuleSchemeGroup(
                    name: "♻️ 自动选择",
                    kind: .urlTest,
                    members: [.nodePattern(".*")]
                ),
                RuleSchemeGroup(
                    name: "🤖 AI 服务",
                    kind: .select,
                    members: [.reference("🚀 节点选择")]
                ),
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "🤖 AI 服务", resource: .inline("DOMAIN-SUFFIX,openai.com")),
                RuleSchemeRuleset(groupName: "🚀 节点选择", resource: .inline("FINAL")),
            ]
        )

        let plain = scheme.withGroupEmojis(false)

        XCTAssertEqual(plain.groups.map(\.name), ["节点选择", "自动选择", "AI 服务"])
        XCTAssertEqual(plain.groups[0].members, [.reference("自动选择"), .reference("DIRECT")])
        XCTAssertEqual(plain.groups[2].members, [.reference("节点选择")])
        XCTAssertEqual(plain.rulesets.map(\.groupName), ["AI 服务", "节点选择"])
    }

    func testOldSnapshotWithoutCustomizationFieldsStillDecodes() throws {
        let json = """
        {
          "subscriptions": [],
          "nodes": [],
          "selectedPresetID": "acl4ssr-default",
          "selectedTarget": "surge"
        }
        """

        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.selectedRuleGroups)
        XCTAssertNil(snapshot.ruleSchemeCustomizations)
        XCTAssertNil(snapshot.customRuleFlows)
        XCTAssertNil(snapshot.localRuleSets)
        XCTAssertNil(snapshot.ruleGroupEmojisEnabled)
        XCTAssertNil(snapshot.excludedNodeIDs)
        XCTAssertNil(snapshot.preferRuleSets)
        XCTAssertNil(snapshot.preferRuleSetsWasExplicitlySet)
    }

    @MainActor
    func testSavingLocalRuleSetDoesNotAddItToCurrentScheme() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-rule-library-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeScheme()
        let ruleSet = LocalRuleSet(
            name: "测试",
            rulesText: "DOMAIN-SUFFIX,example.com"
        )

        try await model.saveLocalRuleSet(ruleSet)

        XCTAssertEqual(model.localRuleSets, [ruleSet])
        XCTAssertTrue(model.customRuleFlows(for: scheme).isEmpty)

        let reloaded = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        XCTAssertEqual(reloaded.localRuleSets, [ruleSet])
        XCTAssertTrue(reloaded.customRuleFlows(for: scheme).isEmpty)
    }

    @MainActor
    func testAddingAndRemovingLocalRuleSetOnlyChangesCurrentSchemeMembership() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-rule-membership-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeScheme()
        let ruleSet = LocalRuleSet(
            name: "测试",
            rulesText: "DOMAIN-SUFFIX,example.com"
        )
        try await model.saveLocalRuleSet(ruleSet)

        model.addLocalRuleSet(ruleSet, to: scheme)

        XCTAssertTrue(model.isLocalRuleSetAdded(ruleSet, to: scheme))
        XCTAssertEqual(model.localRuleSets, [ruleSet])
        let flow = try XCTUnwrap(model.customRuleFlows(for: scheme).first)
        XCTAssertEqual(flow.localRuleSetID, ruleSet.id)
        XCTAssertEqual(flow.name, "测试")
        XCTAssertTrue(model.customizableRuleGroups(for: scheme).contains { $0.name == "测试" })

        model.removeLocalRuleSet(ruleSet, from: scheme)

        XCTAssertFalse(model.isLocalRuleSetAdded(ruleSet, to: scheme))
        XCTAssertEqual(model.localRuleSets, [ruleSet])
        XCTAssertFalse(model.customizableRuleGroups(for: scheme).contains { $0.name == "测试" })
    }

    @MainActor
    func testNewLocalPlacementKeepsUpstreamGroupOrderAndReportsSuccess() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-rule-priority-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeScheme()
        let first = LocalRuleSet(name: "第一条", rulesText: "DOMAIN-SUFFIX,first.example")
        let second = LocalRuleSet(name: "第二条", rulesText: "DOMAIN-SUFFIX,second.example")

        try await model.saveLocalRuleSet(first)
        try await model.saveLocalRuleSet(second)
        model.addLocalRuleSet(first, to: scheme)
        model.addLocalRuleSet(second, to: scheme)

        let groupNames = model.customizableRuleGroups(for: scheme).map(\.name)
        let upstreamNames = Set(scheme.groups.map(\.name))
        XCTAssertEqual(
            groupNames.filter(upstreamNames.contains),
            scheme.groups.map(\.name),
            "新增规则不能改变原有策略组的相对顺序"
        )
        let finalIndex = try XCTUnwrap(groupNames.firstIndex(of: "漏网之鱼"))
        XCTAssertLessThan(try XCTUnwrap(groupNames.firstIndex(of: "第一条")), finalIndex)
        XCTAssertLessThan(try XCTUnwrap(groupNames.firstIndex(of: "第二条")), finalIndex)
        XCTAssertEqual(model.toast?.text, "已添加“第二条”到当前规则")
        XCTAssertEqual(model.toast?.symbol, "checkmark.circle.fill")
        XCTAssertEqual(model.toast?.tone, .success)
    }

    @MainActor
    func testEditingLocalRuleSetSynchronizesItsAddedPlacements() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-rule-edit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeScheme()
        var ruleSet = LocalRuleSet(
            name: "测试",
            rulesText: "DOMAIN-SUFFIX,old.example"
        )
        try await model.saveLocalRuleSet(ruleSet)
        model.addLocalRuleSet(ruleSet, to: scheme)

        ruleSet.name = "测试新版"
        ruleSet.setRuleInput("DOMAIN-SUFFIX,new.example")
        try await model.saveLocalRuleSet(ruleSet)

        let flow = try XCTUnwrap(model.customRuleFlows(for: scheme).first)
        XCTAssertEqual(flow.name, "测试新版")
        XCTAssertEqual(flow.policyName, "测试新版")
        XCTAssertEqual(flow.normalizedRules, ["DOMAIN-SUFFIX,new.example"])
        XCTAssertEqual(flow.generatedPolicyGroup?.name, "测试新版")
    }

    @MainActor
    func testLegacyHandWrittenFlowMigratesIntoLocalLibraryAndKeepsMembership() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-rule-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let scheme = makeScheme()
        let legacyFlow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "旧规则",
            rulesText: "DOMAIN-SUFFIX,legacy.example",
            defaultPolicyName: "节点选择"
        )
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: scheme.id,
            selectedTarget: .surge,
            customRuleFlows: [legacyFlow]
        ))

        let model = AppModel(persistence: store, arguments: [])

        let migrated = try XCTUnwrap(model.localRuleSets.first)
        XCTAssertEqual(migrated.id, legacyFlow.id)
        XCTAssertEqual(migrated.name, "旧规则")
        XCTAssertEqual(model.customRuleFlows.first?.localRuleSetID, migrated.id)
        XCTAssertEqual(model.customRuleFlows.first?.id, legacyFlow.id)
    }

    func testFixedRoutingGroupsAreIdentifiedAcrossEmojiNames() {
        let scheme = makeFixedGroupScheme()

        XCTAssertEqual(
            scheme.protectedRuleGroupNames,
            ["🎯 全球直连", "🐟 漏网之鱼"]
        )
        XCTAssertEqual(scheme.editableRuleGroupNames, ["🤖 AI 服务"])
    }

    @MainActor
    func testAppModelDoesNotDisableFixedRoutingGroups() {
        let model = AppModel(arguments: [])
        let scheme = makeFixedGroupScheme()

        model.setRuleGroup("🎯 全球直连", enabled: false, for: scheme)

        XCTAssertTrue(model.selectedRuleGroupNames(for: scheme).contains("🎯 全球直连"))
        XCTAssertFalse(model.isRuleGroupSelectionCustomized(for: scheme))
    }

    @MainActor
    func testAppModelPersistsGroupSelectionAndCustomFlowsSeparatelyFromScheme() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-customization-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        let scheme = try XCTUnwrap(model.ruleSchemes.first)
        let disabledGroup = try XCTUnwrap(scheme.editableRuleGroupNames.first)
        let policyName = try XCTUnwrap(scheme.groups.first?.name)

        model.setRuleGroup(disabledGroup, enabled: false, for: scheme)
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "Tailscale",
            policyName: policyName,
            rulesText: "DOMAIN-SUFFIX,tailscale.com"
        )
        model.upsertCustomRuleFlow(flow)
        model.setRuleGroupEmojisEnabled(false, for: scheme)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertFalse(reloaded.selectedRuleGroupNames(for: scheme).contains(disabledGroup))
        let reloadedFlow = try XCTUnwrap(reloaded.customRuleFlows(for: scheme).first)
        XCTAssertEqual(reloadedFlow.id, flow.id)
        XCTAssertEqual(reloadedFlow.name, flow.name)
        XCTAssertEqual(reloadedFlow.policyName, flow.policyName)
        XCTAssertEqual(reloadedFlow.normalizedRules, flow.normalizedRules)
        XCTAssertEqual(reloadedFlow.localRuleSetID, flow.id)
        XCTAssertEqual(reloaded.localRuleSets.map(\.id), [flow.id])
        XCTAssertFalse(reloaded.ruleGroupEmojisAreEnabled(for: scheme))
    }

    @MainActor
    func testAppModelDefaultsRuleSetsOffAndPersistsOptIn() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-ruleset-preference-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)

        let model = AppModel(persistence: store, arguments: [])
        XCTAssertFalse(model.preferRuleSets)

        model.setPreferRuleSets(true)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertTrue(reloaded.preferRuleSets)
    }

    @MainActor
    func testLegacyImplicitRuleSetDefaultMigratesToOff() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-ruleset-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [],
            selectedPresetID: "acl4ssr-default",
            selectedTarget: .surge,
            preferRuleSets: true
        ))

        let model = AppModel(persistence: store, arguments: [])

        XCTAssertFalse(model.preferRuleSets)
    }

    func testGroupCustomizationMergesOrderingAndCandidateOverrides() {
        let scheme = makeScheme()
        let customization = RuleSchemeCustomization(
            schemeID: scheme.id,
            groupOrder: ["漏网之鱼", "AI 服务", "节点选择", "自动选择", "海外媒体"],
            groupOverrides: [
                "AI 服务": RuleSchemeGroupOverride(
                    kind: .select,
                    members: [
                        .reference("香港节点"),
                        .reference("日本节点"),
                        .reference("DIRECT"),
                        .reference("REJECT"),
                    ]
                )
            ]
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [],
            groupCustomization: customization
        )

        XCTAssertEqual(
            customized.groups.map(\.name),
            ["漏网之鱼", "AI 服务", "节点选择", "自动选择", "海外媒体", "香港节点", "日本节点"]
        )
        XCTAssertEqual(
            customized.groups.first { $0.name == "AI 服务" }?.members,
            [
                .reference("香港节点"),
                .reference("日本节点"),
                .reference("DIRECT"),
                .reference("REJECT"),
            ]
        )
    }

    func testServiceRuleOnlyOffersRoutingTargetsInsteadOfOtherServiceRules() throws {
        let scheme = makeEditorRoleScheme()
        let apple = try XCTUnwrap(scheme.groups.first { $0.name == "🍎 苹果服务" })

        XCTAssertEqual(scheme.groupEditorMode(for: apple), .routingTargets)
        XCTAssertEqual(
            scheme.routingTargetGroupNames(excluding: apple.name),
            [
                "🚀 节点选择",
                "🎛️ 手动切换",
                "♻️ 自动选择",
                "🇭🇰 香港节点",
                "🇯🇵 日本节点",
                "🇺🇸 美国节点",
                "🇸🇬 狮城节点",
                "🇨🇳 台湾节点",
                "🇰🇷 韩国节点",
                "DIRECT",
                "REJECT",
            ]
        )
        XCTAssertFalse(scheme.routingTargetGroupNames().contains("🤖 AI 平台"))
        XCTAssertFalse(scheme.routingTargetGroupNames().contains("🎥 Netflix"))
        XCTAssertFalse(scheme.routingTargetGroupNames().contains("🌍 国外媒体"))
    }

    func testSelectedMissingRegionalCandidatesAreInjectedAsOrderedSelectGroups() throws {
        let scheme = makeEditorRoleScheme()
        let customization = RuleSchemeCustomization(
            schemeID: scheme.id,
            groupOverrides: [
                "🍎 苹果服务": RuleSchemeGroupOverride(
                    kind: .select,
                    members: [
                        .reference("🇺🇸 美国节点"),
                        .reference("🇨🇳 台湾节点"),
                        .reference("🇰🇷 韩国节点"),
                        .reference("DIRECT"),
                    ]
                )
            ]
        )

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [],
            groupCustomization: customization
        )

        XCTAssertEqual(
            customized.groups.first { $0.name == "🍎 苹果服务" }?.members,
            [
                .reference("🇺🇸 美国节点"),
                .reference("🇨🇳 台湾节点"),
                .reference("🇰🇷 韩国节点"),
                .reference("DIRECT"),
            ],
            "候选策略的顺序必须保留，第一项就是客户端默认项"
        )
        XCTAssertEqual(
            try XCTUnwrap(customized.groups.first { $0.name == "🇺🇸 美国节点" }),
            RuleSchemeGroup(
                name: "🇺🇸 美国节点",
                kind: .select,
                members: [.nodePattern("(美国|美國|波特兰|达拉斯|俄勒冈|凤凰城|费利蒙|硅谷|拉斯维加斯|洛杉矶|洛杉磯|圣何塞|圣克拉拉|西雅图|芝加哥|United States|USA|(^|[^A-Za-z])US([^A-Za-z]|$))")]
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(customized.groups.first { $0.name == "🇨🇳 台湾节点" }),
            RuleSchemeGroup(
                name: "🇨🇳 台湾节点",
                kind: .select,
                members: [.nodePattern("(台湾|臺灣|台北|臺北|新北|彰化|TW|Taiwan)")]
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(customized.groups.first { $0.name == "🇰🇷 韩国节点" }),
            RuleSchemeGroup(
                name: "🇰🇷 韩国节点",
                kind: .select,
                members: [.nodePattern("(韩国|韓國|首尔|首爾|KR|KOR|Korea)")]
            )
        )
    }

    func testRegionalPolicyGroupOnlyEditsNodeNamePatterns() throws {
        let scheme = makeEditorRoleScheme()
        let japan = try XCTUnwrap(scheme.groups.first { $0.name == "🇯🇵 日本节点" })
        let nodeSelector = try XCTUnwrap(scheme.groups.first { $0.name == "🚀 节点选择" })

        XCTAssertEqual(scheme.groupEditorMode(for: japan), .nodePatternsOnly)
        XCTAssertEqual(japan.members, [.nodePattern("(?i)日本|JP|Japan")])
        XCTAssertEqual(scheme.groupEditorMode(for: nodeSelector), .routingTargets)
    }

    @MainActor
    func testAppModelPersistsGroupOrderingAndCandidateOverrides() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-policy-group-customization-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        let scheme = makeScheme()
        let updated = RuleSchemeGroup(
            name: "AI 服务",
            kind: .select,
            members: [.reference("节点选择"), .reference("DIRECT"), .reference("REJECT")]
        )

        model.updateRuleGroup(updated, for: scheme)
        model.moveRuleGroups(
            fromOffsets: IndexSet(integer: 4),
            toOffset: 0,
            for: scheme
        )

        let reloaded = AppModel(persistence: store, arguments: [])
        let groups = reloaded.customizableRuleGroups(for: scheme)
        XCTAssertEqual(groups.first?.name, "漏网之鱼")
        XCTAssertEqual(
            groups.first { $0.name == "AI 服务" }?.members,
            [.reference("节点选择"), .reference("DIRECT"), .reference("REJECT")]
        )
    }

    @MainActor
    func testMovingGeneratedRuleGroupOverridesItsAutomaticInitialPlacement() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-generated-group-order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "Netflix",
            rulesText: "DOMAIN-SUFFIX,netflix.com",
            defaultPolicyName: "节点选择"
        )

        model.upsertCustomRuleFlow(flow)
        let initialGroups = model.customizableRuleGroups(for: scheme)
        let source = try XCTUnwrap(initialGroups.firstIndex { $0.name == "Netflix" })
        model.moveRuleGroups(
            fromOffsets: IndexSet(integer: source),
            toOffset: 0,
            for: scheme
        )

        XCTAssertEqual(model.customizableRuleGroups(for: scheme).first?.name, "Netflix")
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.customizableRuleGroups(for: scheme).first?.name, "Netflix")
    }

    @MainActor
    func testRenamingRuleGroupIdentityRewritesBindingsReferencesAndPersists() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-policy-group-identity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        var scheme = makeScheme()
        let nodeSelector = scheme.groups[0]
        scheme.groups[0] = RuleSchemeGroup(
            name: nodeSelector.name,
            kind: nodeSelector.kind,
            members: [.reference("AI 服务")] + nodeSelector.members
        )

        try model.renameRuleGroup(
            named: "AI 服务",
            to: "🤖 智能服务",
            for: scheme
        )

        let reloaded = AppModel(persistence: store, arguments: [])
        let effective = reloaded.effectiveScheme(scheme)
        XCTAssertTrue(effective.groups.contains { $0.name == "🤖 智能服务" })
        XCTAssertFalse(effective.groups.contains { $0.name == "AI 服务" })
        XCTAssertEqual(
            effective.groups.first { $0.name == "节点选择" }?.members.first,
            .reference("🤖 智能服务")
        )
        XCTAssertEqual(effective.rulesets.first?.groupName, "🤖 智能服务")
    }

    @MainActor
    func testRenamingRuleGroupRejectsEmptyAndDuplicateNames() throws {
        let model = AppModel(arguments: [])
        let scheme = makeScheme()

        XCTAssertThrowsError(try model.renameRuleGroup(named: "AI 服务", to: "   ", for: scheme))
        XCTAssertThrowsError(try model.renameRuleGroup(named: "AI 服务", to: "海外媒体", for: scheme))
    }

    @MainActor
    func testDeletingReferencedGroupReportsDependentsAndRepairsTheirCandidates() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-group-deletion-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        let scheme = makeScheme()

        XCTAssertEqual(
            model.ruleGroupReferences(to: "节点选择", for: scheme),
            ["AI 服务", "海外媒体", "漏网之鱼"]
        )

        model.deleteRuleGroup(named: "节点选择", for: scheme)

        let groups = model.customizableRuleGroups(for: scheme)
        XCTAssertFalse(groups.contains { $0.name == "节点选择" })
        XCTAssertEqual(
            groups.first { $0.name == "AI 服务" }?.members,
            [.reference("DIRECT")]
        )

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertFalse(reloaded.customizableRuleGroups(for: scheme).contains { $0.name == "节点选择" })
    }

    @MainActor
    func testDeletingUserCreatedGroupAlsoRemovesItsCatalogMembership() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-catalog-group-deletion-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: fileURL),
            arguments: []
        )
        let scheme = makeScheme()
        let entry = RuleCatalogEntry(
            id: "custom-google",
            name: "Google",
            category: .infrastructure,
            provider: .blackmatrix7,
            sourceURLString: "https://rules.example.com/google.list",
            defaultRoute: .proxy,
            suggestedPolicyName: "Google"
        )
        let flow = CustomRuleFlow(
            schemeID: scheme.id,
            name: "Google",
            policyName: "Google",
            rulesText: "DOMAIN-SUFFIX,google.com",
            catalogID: entry.id,
            generatedPolicyGroup: RuleSchemeGroup(
                name: "Google",
                kind: .select,
                members: [.reference("节点选择")]
            )
        )
        model.upsertCustomRuleFlow(flow)

        XCTAssertTrue(model.isCatalogEntryAdded(entry, to: scheme))

        model.deleteRuleGroup(named: "Google", for: scheme)

        XCTAssertFalse(model.isCatalogEntryAdded(entry, to: scheme))
        XCTAssertTrue(model.customRuleFlows(for: scheme).isEmpty)
    }

    @MainActor
    func testDeletingRenamedUserCreatedGroupRemovesItsStoredRuleFlow() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-renamed-rule-group-deletion-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: fileURL),
            arguments: []
        )
        let scheme = makeScheme()
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "测试规则",
            rulesText: "DOMAIN-SUFFIX,example.com",
            defaultPolicyName: "节点选择"
        )
        model.upsertCustomRuleFlow(flow)
        try model.renameRuleGroup(named: "测试规则", to: "🧩 测试规则集", for: scheme)

        model.deleteRuleGroup(named: "🧩 测试规则集", for: scheme)

        XCTAssertTrue(model.customRuleFlows(for: scheme).isEmpty)
    }

    @MainActor
    func testSavingCustomizationCreatesReusableSchemeSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-saved-rule-scheme-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeScheme()
        model.updateRuleGroup(
            RuleSchemeGroup(
                name: "AI 服务",
                kind: .select,
                members: [.reference("节点选择"), .reference("DIRECT")]
            ),
            for: scheme
        )

        let saved = model.saveCustomizedScheme(named: "我的规则", from: scheme)

        XCTAssertEqual(saved.name, "我的规则")
        XCTAssertFalse(saved.isBundled)
        XCTAssertNil(saved.sourceURLString)
        XCTAssertEqual(model.selectedPresetID, saved.id)
        XCTAssertTrue(model.importedSchemes.contains(saved))
        XCTAssertEqual(
            saved.groups.first { $0.name == "AI 服务" }?.members,
            [.reference("节点选择"), .reference("DIRECT")]
        )
    }

    @MainActor
    func testEditingImportedSchemeMetadataPersistsWithoutReplacingItsRulesOrCustomization() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-imported-scheme-metadata-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let persistence = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: persistence, arguments: [])
        var scheme = makeScheme()
        scheme.sourceURLString = "https://example.com/config.ini"
        model.importedSchemes = [scheme]
        model.selectedPresetID = scheme.id
        model.setRuleGroup("海外媒体", enabled: false, for: scheme)
        let selectedGroups = model.selectedRuleGroups[scheme.id]

        XCTAssertTrue(model.updateImportedSchemeMetadata(
            id: scheme.id,
            name: "  我的分流方案  ",
            summary: "  家庭设备使用  "
        ))

        let updated = try XCTUnwrap(model.importedSchemes.first)
        XCTAssertEqual(updated.name, "我的分流方案")
        XCTAssertEqual(updated.summary, "家庭设备使用")
        XCTAssertEqual(updated.localizedSummary(), "家庭设备使用")
        XCTAssertEqual(updated.id, scheme.id)
        XCTAssertEqual(updated.sourceURLString, scheme.sourceURLString)
        XCTAssertEqual(updated.groups, scheme.groups)
        XCTAssertEqual(updated.rulesets, scheme.rulesets)
        XCTAssertEqual(model.selectedPresetID, scheme.id)
        XCTAssertEqual(model.selectedRuleGroups[scheme.id], selectedGroups)

        let reloaded = AppModel(persistence: persistence, arguments: [])
        XCTAssertEqual(reloaded.importedSchemes.first?.name, "我的分流方案")
        XCTAssertEqual(reloaded.importedSchemes.first?.localizedSummary(), "家庭设备使用")
        XCTAssertEqual(reloaded.selectedRuleGroups[scheme.id], selectedGroups)
    }

    @MainActor
    func testRenamingImportedSchemeDoesNotFreezeItsAutomaticSummaryLanguage() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-imported-scheme-name-only-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        var scheme = makeScheme()
        scheme.sourceURLString = "https://example.com/config.ini"
        scheme.summary = "从 example.com 导入"
        model.importedSchemes = [scheme]
        let displayedSummary = scheme.localizedSummary()

        XCTAssertTrue(model.updateImportedSchemeMetadata(
            id: scheme.id,
            name: "新名称",
            summary: displayedSummary
        ))

        let updated = try XCTUnwrap(model.importedSchemes.first)
        XCTAssertNil(updated.summaryIsUserEdited)
        let englishResources = try XCTUnwrap(Bundle.main.url(forResource: "en", withExtension: "lproj"))
        let englishBundle = try XCTUnwrap(Bundle(url: englishResources))
        XCTAssertEqual(updated.localizedSummary(bundle: englishBundle), "Import from example.com")
    }

    @MainActor
    func testDeletingImportedSchemeKeepsRuleFilesStillUsedByAnotherScheme() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-shared-imported-rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloadStore = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let persistence = PersistenceStore(fileURL: directory.appendingPathComponent("state.json"))
        let sharedURL = URL(string: "https://example.com/shared.list")!
        try downloadStore.store("DOMAIN-SUFFIX,example.com", for: sharedURL)
        let model = AppModel(
            persistence: persistence,
            schemeRepository: RuleSchemeRepository(downloadStore: downloadStore),
            downloadStore: downloadStore,
            arguments: []
        )
        var first = makeRemoteOrderingScheme(url: sharedURL)
        first.name = "方案一"
        var second = makeRemoteOrderingScheme(url: sharedURL)
        second = RuleScheme(
            id: "remote-ordering-second",
            name: "方案二",
            summary: second.summary,
            sourceURLString: second.sourceURLString,
            groups: second.groups,
            rulesets: second.rulesets
        )
        model.importedSchemes = [first, second]

        model.deleteScheme(first)

        XCTAssertEqual(model.importedSchemes.map(\.id), [second.id])
        XCTAssertTrue(downloadStore.hasCachedRules(for: sharedURL))

        model.deleteScheme(second)

        XCTAssertFalse(downloadStore.hasCachedRules(for: sharedURL))
    }

    @MainActor
    func testSelectingSchemeReusesRuleCountUntilRuleContentChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-count-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let rulesDirectory = directory.appendingPathComponent("rules", isDirectory: true)
        let downloadStore = RuleDownloadStore(folderURL: rulesDirectory)
        let ruleURL = URL(string: "https://example.com/cache-test.list")!
        try downloadStore.store("DOMAIN-SUFFIX,one.example", for: ruleURL)
        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            schemeRepository: RuleSchemeRepository(downloadStore: downloadStore),
            downloadStore: downloadStore,
            arguments: []
        )
        let scheme = makeRemoteOrderingScheme(url: ruleURL)

        XCTAssertEqual(model.ruleCount(for: scheme), 2)

        // Simulate fresh data arriving behind the repository. A visual-only
        // scheme selection must use the count the card already displayed,
        // rather than parsing the same files again on the main actor.
        try downloadStore.store(
            """
            DOMAIN-SUFFIX,one.example
            DOMAIN-SUFFIX,two.example
            """,
            for: ruleURL
        )
        model.selectScheme(scheme)
        XCTAssertEqual(model.ruleCount(for: scheme), 2)

        // A real rule mutation invalidates the cached count.
        model.upsertCustomRuleFlow(CustomRuleFlow(
            schemeID: scheme.id,
            name: "新增规则",
            policyName: "上游规则",
            rulesText: "DOMAIN-SUFFIX,three.example"
        ))
        XCTAssertEqual(model.ruleCount(for: scheme), 4)
    }

    @MainActor
    func testSavingCustomizationPreservesSourceEmojisWhenExportEmojisAreDisabled() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-saved-rule-emoji-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeFixedGroupScheme()
        model.setRuleGroupEmojisEnabled(false, for: scheme)

        let saved = model.saveCustomizedScheme(named: "保留 Emoji", from: scheme)

        XCTAssertEqual(saved.groups.map(\.name), scheme.groups.map(\.name))
        XCTAssertEqual(saved.rulesets.map(\.groupName), scheme.rulesets.map(\.groupName))
    }

    @MainActor
    func testSavedCustomizationInheritsDisabledExportEmojiPreference() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-saved-rule-emoji-setting-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: fileURL), arguments: [])
        let scheme = makeFixedGroupScheme()
        model.setRuleGroupEmojisEnabled(false, for: scheme)

        let saved = model.saveCustomizedScheme(named: "继承 Emoji 设置", from: scheme)

        XCTAssertFalse(model.ruleGroupEmojisAreEnabled(for: saved))
    }

    @MainActor
    func testResetRestoresTheOriginalSchemeWithoutDeletingTheLocalLibrary() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-full-rule-reset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: fileURL),
            arguments: []
        )
        let scheme = makeScheme()
        let localRuleSet = LocalRuleSet(
            name: "本地测试",
            rulesText: "DOMAIN-SUFFIX,local.example"
        )

        try await model.saveLocalRuleSet(localRuleSet)
        model.addLocalRuleSet(localRuleSet, to: scheme)
        model.setRuleGroup("AI 服务", enabled: false, for: scheme)
        model.setRuleGroupEmojisEnabled(false, for: scheme)
        try model.renameRuleGroup(named: "海外媒体", to: "🌍 国外媒体", for: scheme)

        model.resetRuleCustomization(for: scheme)

        XCTAssertEqual(model.customizableRuleGroups(for: scheme), scheme.groups)
        XCTAssertEqual(model.effectiveScheme(scheme).rulesets, scheme.rulesets)
        XCTAssertEqual(model.selectedRuleGroupNames(for: scheme), Set(scheme.selectableRuleGroupNames))
        XCTAssertTrue(model.customRuleFlows(for: scheme).isEmpty)
        XCTAssertTrue(model.ruleGroupEmojisAreEnabled(for: scheme))
        XCTAssertEqual(model.localRuleSets.map(\.id), [localRuleSet.id])
        XCTAssertEqual(model.toast?.tone, .success)
    }

    private func makeScheme() -> RuleScheme {
        RuleScheme(
            id: "custom",
            name: "可定制规则",
            summary: "测试",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.reference("自动选择"), .reference("DIRECT")]
                ),
                RuleSchemeGroup(
                    name: "自动选择",
                    kind: .urlTest,
                    members: [.nodePattern(".*")]
                ),
                RuleSchemeGroup(
                    name: "AI 服务",
                    kind: .select,
                    members: [.reference("节点选择"), .reference("DIRECT")]
                ),
                RuleSchemeGroup(
                    name: "海外媒体",
                    kind: .select,
                    members: [.reference("节点选择"), .reference("DIRECT")]
                ),
                RuleSchemeGroup(
                    name: "漏网之鱼",
                    kind: .select,
                    members: [.reference("节点选择"), .reference("DIRECT")]
                ),
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "AI 服务", resource: .inline("DOMAIN-SUFFIX,openai.com")),
                RuleSchemeRuleset(groupName: "海外媒体", resource: .inline("DOMAIN-SUFFIX,netflix.com")),
                RuleSchemeRuleset(groupName: "漏网之鱼", resource: .inline("FINAL")),
            ]
        )
    }

    private func makeFixedGroupScheme() -> RuleScheme {
        RuleScheme(
            id: "fixed",
            name: "固定分组",
            summary: "测试",
            groups: [
                RuleSchemeGroup(name: "🎯 全球直连", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "🤖 AI 服务", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "🐟 漏网之鱼", kind: .select, members: [.reference("DIRECT")]),
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "🎯 全球直连", resource: .inline("GEOIP,CN")),
                RuleSchemeRuleset(groupName: "🤖 AI 服务", resource: .inline("DOMAIN-SUFFIX,openai.com")),
                RuleSchemeRuleset(groupName: "🐟 漏网之鱼", resource: .inline("FINAL")),
            ]
        )
    }

    private func makeRemoteOrderingScheme(url: URL) -> RuleScheme {
        RuleScheme(
            id: "remote-ordering",
            name: "远程规则排序",
            summary: "测试",
            groups: [
                RuleSchemeGroup(name: "节点选择", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "上游规则", kind: .select, members: [.reference("节点选择")]),
                RuleSchemeGroup(name: "漏网之鱼", kind: .select, members: [.reference("节点选择")]),
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "上游规则", resource: .remote(url)),
                RuleSchemeRuleset(groupName: "漏网之鱼", resource: .inline("FINAL")),
            ]
        )
    }

    private func makeEditorRoleScheme() -> RuleScheme {
        RuleScheme(
            id: "editor-roles",
            name: "编辑器角色",
            summary: "测试",
            groups: [
                RuleSchemeGroup(
                    name: "🚀 节点选择",
                    kind: .select,
                    members: [
                        .reference("♻️ 自动选择"),
                        .reference("🇭🇰 香港节点"),
                        .reference("DIRECT"),
                        .nodePattern(".*"),
                    ]
                ),
                RuleSchemeGroup(name: "🎛️ 手动切换", kind: .select, members: [.nodePattern(".*")]),
                RuleSchemeGroup(name: "♻️ 自动选择", kind: .urlTest, members: [.nodePattern(".*")]),
                RuleSchemeGroup(name: "🇭🇰 香港节点", kind: .urlTest, members: [.nodePattern("(?i)香港|HK|Hong Kong")]),
                RuleSchemeGroup(name: "🇸🇬 狮城节点", kind: .urlTest, members: [.nodePattern("(?i)新加坡|狮城|SG|Singapore")]),
                RuleSchemeGroup(name: "🇯🇵 日本节点", kind: .urlTest, members: [.nodePattern("(?i)日本|JP|Japan")]),
                RuleSchemeGroup(name: "🤖 AI 平台", kind: .select, members: [.reference("🚀 节点选择")]),
                RuleSchemeGroup(name: "🎥 Netflix", kind: .select, members: [.reference("🇸🇬 狮城节点")]),
                RuleSchemeGroup(name: "🌍 国外媒体", kind: .select, members: [.reference("🚀 节点选择")]),
                RuleSchemeGroup(name: "🍎 苹果服务", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "🎯 全球直连", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "🛑 广告拦截", kind: .select, members: [.reference("REJECT")]),
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "🤖 AI 平台", resource: .inline("DOMAIN-SUFFIX,openai.com")),
                RuleSchemeRuleset(groupName: "🎥 Netflix", resource: .inline("DOMAIN-SUFFIX,netflix.com")),
                RuleSchemeRuleset(groupName: "🌍 国外媒体", resource: .inline("DOMAIN-SUFFIX,youtube.com")),
                RuleSchemeRuleset(groupName: "🍎 苹果服务", resource: .inline("DOMAIN-SUFFIX,apple.com")),
                RuleSchemeRuleset(groupName: "🎯 全球直连", resource: .inline("GEOIP,CN")),
                RuleSchemeRuleset(groupName: "🛑 广告拦截", resource: .inline("DOMAIN-SUFFIX,ads.example")),
                RuleSchemeRuleset(groupName: "🚀 节点选择", resource: .inline("FINAL")),
            ]
        )
    }
}
