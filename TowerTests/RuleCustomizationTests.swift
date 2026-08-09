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
        XCTAssertNil(snapshot.customRuleFlows)
        XCTAssertNil(snapshot.ruleGroupEmojisEnabled)
        XCTAssertNil(snapshot.excludedNodeIDs)
        XCTAssertNil(snapshot.preferRuleSets)
        XCTAssertNil(snapshot.preferRuleSetsWasExplicitlySet)
    }

    @MainActor
    func testAppModelPersistsGroupSelectionAndCustomFlowsSeparatelyFromScheme() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-customization-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let model = AppModel(persistence: store, arguments: [])
        let scheme = try XCTUnwrap(model.ruleSchemes.first)
        let disabledGroup = try XCTUnwrap(scheme.selectableRuleGroupNames.first)
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
        XCTAssertEqual(reloaded.customRuleFlows(for: scheme), [flow])
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
}
