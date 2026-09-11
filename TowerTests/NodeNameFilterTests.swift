import XCTest
@testable import Tower

final class NodeNameFilterTests: XCTestCase {
    func testHKAlreadyMatchesHKGAndCustomLiteralKeywordsAreEscaped() throws {
        XCTAssertEqual(try NodeNameFilterMatcher.preview("(?i)港|HK|Hong Kong", candidates: [["HKG 01"], ["hk-02"], ["JP 01"]], caseInsensitive: false), [0, 1])
        var draft = NodeNameFilterDraft()
        draft.keywords = "HKG\n香港\nA+B [IEPL]"
        XCTAssertEqual(try NodeNameFilterMatcher.preview(draft.pattern, candidates: [["HKG 01"], ["香港02"], ["A+B [IEPL] 03"], ["AAAB I"]], caseInsensitive: false), [0, 1, 2])
        XCTAssertEqual(NodeNameFilterDraft(pattern: draft.pattern).keywords, draft.keywords)
    }

    func testDefaultKeywordExamplesAndExistingRegexRemainDistinct() throws {
        var simple = NodeNameFilterDraft()
        XCTAssertEqual(simple.style, .contains)
        XCTAssertEqual(NodeNameFilterDraft.MatchStyle.allCases, [.contains, .prefix, .suffix, .exact])
        XCTAssertEqual(simple.pattern, "")
        simple.keywords = "jp\nhk"
        XCTAssertEqual(try NodeNameFilterMatcher.preview(simple.pattern, candidates: [["JPN 01"], ["HKG 02"], ["US 01"]], caseInsensitive: false), [0, 1])
        simple.keywords = ".*"
        XCTAssertEqual(try NodeNameFilterMatcher.preview(simple.pattern, candidates: [["HK 01"], ["literal .* node"]], caseInsensitive: true), [1])
        let savedRegex = NodeNameFilterDraft(pattern: ".*")
        XCTAssertTrue(savedRegex.usesRegex)
        XCTAssertEqual(savedRegex.pattern, ".*")
        XCTAssertNil(NodeNameFilterDraft.decode(".*", caseInsensitiveDefault: true))
    }

    func testComplexExpressionAndAnchoredAlternativesStayInRegexMode() {
        for pattern in ["(?i)^(?!.*倍率).*(港|HKG)", "^HK|JP$", "[A-Z]+", " 港 ", "(?!)港|HK|Hong Kong"] {
            let draft = NodeNameFilterDraft(pattern: pattern)
            XCTAssertTrue(draft.usesRegex, pattern)
            XCTAssertEqual(draft.pattern, pattern)
        }
    }

    func testKeywordStylesAndExplicitCaseOverride() throws {
        var draft = NodeNameFilterDraft()
        draft.keywords = "HKG"
        draft.style = .prefix
        draft.ignoresCase = false
        XCTAssertEqual(try NodeNameFilterMatcher.preview(draft.pattern, candidates: [["HKG 01"], ["hkg 02"], ["香港 HKG 03"]], caseInsensitive: true), [0])
        let restored = NodeNameFilterDraft(pattern: draft.pattern)
        XCTAssertEqual(restored.style, .prefix)
        XCTAssertFalse(restored.ignoresCase)
        draft.style = .exact
        XCTAssertEqual(try NodeNameFilterMatcher.preview(draft.pattern, candidates: [["HKG"], ["HKG 01"]], caseInsensitive: true), [0])
    }

    func testInvalidOrExpensiveRegexDoesNotReportAnEmptyMatchList() {
        XCTAssertThrowsError(try NodeNameFilterMatcher.preview("[", candidates: [], caseInsensitive: true))
        XCTAssertThrowsError(try NodeNameFilterMatcher.preview("(a+)+$", candidates: [[String(repeating: "a", count: 10_000) + "!"]], caseInsensitive: true, timeLimit: 0.05))
    }

    func testCombinedPreviewDeduplicatesAndRejectsInvalidExpressions() async {
        let names = [["HKG 01"], ["JP 01"], ["US 01"]]
        let input = NodeNameFilterPreviewInput(patterns: ["HK", "HKG|JP"], candidates: names, insensitive: true)
        let result = await input.evaluate()
        XCTAssertNil(result.error)
        XCTAssertEqual(result.matches, [0, 1])
        XCTAssertEqual(result.input, input)
        let invalid = await NodeNameFilterPreviewInput(patterns: ["HK", "["], candidates: names, insensitive: true).evaluate()
        XCTAssertNotNil(invalid.error)
        XCTAssertTrue(invalid.matches.isEmpty)
    }

    @MainActor
    func testCustomizationSurvivesPersistenceAndAllClientExports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistenceStore(fileURL: directory.appendingPathComponent("state.json"))
        let model = AppModel(persistence: store, arguments: [])
        let scheme = try RuleSchemeParser().parse(text: "[custom]\ncustom_proxy_group=香港节点`url-test`^HK$`https://example.com/check`300\nruleset=香港节点,[]FINAL", id: "node-filter", name: "Filter", summary: "")
        let original = try XCTUnwrap(scheme.groups.first)
        var draft = NodeNameFilterDraft()
        draft.keywords = "HKG"
        let group = RuleSchemeGroup(name: original.name, kind: original.kind, members: [.nodePattern(draft.pattern)])
        model.updateRuleGroup(group, for: scheme)
        let restored = AppModel(persistence: store, arguments: [])
        let customized = scheme.customized(enabledRuleGroupNames: nil, customRuleFlows: [], groupCustomization: restored.ruleSchemeCustomizations[scheme.id])
        XCTAssertEqual(customized.groups.first?.members, [.nodePattern(draft.pattern)])
        XCTAssertEqual(scheme.groups.first?.members, [.nodePattern("^HK$")])
        let nodes = ["HKG 01", "JP 01"].map { ProxyNode(kind: .trojan, name: $0, server: "example.com", port: 443, password: "test", rawURI: "") }
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: customized, target: target, preferRuleSets: false)
            XCTAssertFalse(output.hasInvalidPolicyReferences, target.rawValue)
            XCTAssertTrue(output.content.contains("HKG 01"), target.rawValue)
            if [ClientTarget.clashMi, .surge, .singBox].contains(target) {
                let members = try exportedMembers(output.content, target: target, groupName: group.name)
                XCTAssertTrue(members.contains("HKG 01"), members)
                XCTAssertFalse(members.contains("JP 01"), members)
            }
        }
    }
    @MainActor
    func testEditedProviderPatternKeepsSourceScopeAfterPersistence() throws {
        let a = SubscriptionSource(name: "A", urlString: "https://example.com/a")
        let b = SubscriptionSource(name: "B", urlString: "https://example.com/b")
        let nodes = [
            ProxyNode(sourceID: a.id, kind: .http, name: "HKG keep", server: "a.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: a.id, kind: .http, name: "HKG drop", server: "b.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: b.id, kind: .http, name: "HKG other", server: "c.example.com", port: 80, rawURI: "")
        ]
        let scheme = try RuleSchemeParser().parse(text: """
        proxy-providers:
          AirportA: {type: http, url: https://example.com/a}
        proxy-groups:
          - {name: HK, type: fallback, use: [AirportA], filter: '^HK$', exclude-filter: drop}
        rules: ['MATCH,HK']
        """, id: "provider-filter", name: "Providers", summary: "")
        let original = try XCTUnwrap(scheme.groups.first)
        XCTAssertTrue(try XCTUnwrap(EditableNodeNameFilter.rows(for: original).first).isSourceBound)
        let edited = RuleSchemeGroup(name: original.name, kind: original.kind, members: [.nodePattern("HKG")])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistenceStore(fileURL: directory.appendingPathComponent("state.json"))
        let model = AppModel(persistence: store, arguments: [])
        model.updateRuleGroup(edited, for: scheme, sourceNodePatterns: ["HKG"])
        let restored = AppModel(persistence: store, arguments: [])
        try restored.renameRuleGroup(named: "HK", to: "Region", for: scheme)
        let renamed = AppModel(persistence: store, arguments: [])
        let customized = scheme.customized(enabledRuleGroupNames: nil, customRuleFlows: [], groupCustomization: renamed.ruleSchemeCustomizations[scheme.id])
        XCTAssertEqual(customized.groups.first?.parameters?["tower-source-patterns"], "[\"HKG\"]")
        let hashes = [a.id: RuleSchemeParser.sourceURLHash(a.urlString), b.id: RuleSchemeParser.sourceURLHash(b.urlString)]
        for target in [ClientTarget.clashMi, .surge, .singBox] {
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: customized, target: target, sourceURLHashes: hashes)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            let members = try exportedMembers(output.content, target: target, groupName: "Region")
            XCTAssertTrue(members.contains("HKG keep"), members)
            XCTAssertFalse(members.contains("HKG drop"), members)
            XCTAssertFalse(members.contains("HKG other"), members)
        }
    }

    @MainActor
    func testSupplementalGroupEditsSurviveReopeningPersistenceAndExports() throws {
        let scheme = try RuleSchemeParser().parse(text: "[custom]\ncustom_proxy_group=入口`select`[]DIRECT\nruleset=入口,[]FINAL", id: "supplemental-filter", name: "Filter", summary: "")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersistenceStore(fileURL: folder.appendingPathComponent("state.json"))
        let model = AppModel(persistence: store, arguments: [])
        let japan = "🇯🇵 日本节点"
        model.updateRuleGroup(.init(name: "入口", kind: .select, members: [.reference(japan)]), for: scheme)
        let generated = try XCTUnwrap(model.customizableRuleGroups(for: scheme).first { $0.name == japan })
        let original = try XCTUnwrap(EditableNodeNameFilter.rows(for: generated).first)
        var draft = NodeNameFilterDraft(pattern: original.pattern)
        draft.keywords = draft.keywords.split(separator: "\n").filter { $0 != "Japan" }.joined(separator: "\n")
        model.updateRuleGroup(.init(name: japan, kind: .fallback, members: [.nodePattern(draft.pattern)]), for: scheme)
        let reopened = try XCTUnwrap(model.customizableRuleGroups(for: scheme).first { $0.name == japan })
        XCTAssertEqual(reopened.members, [.nodePattern(draft.pattern)])
        XCTAssertEqual(reopened.kind, .fallback)
        let restored = AppModel(persistence: store, arguments: [])
        let customized = restored.customizableScheme(for: scheme)
        XCTAssertEqual(customized.groups.first { $0.name == japan }?.members, reopened.members)
        let nodes = ["Japan only", "JP only"].map {
            ProxyNode(kind: .trojan, name: $0, server: "example.com", port: 443, password: "test", rawURI: "")
        }
        for target in [ClientTarget.clashMi, .surge, .singBox] {
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: customized, target: target, preferRuleSets: false)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            let members = try exportedMembers(output.content, target: target, groupName: japan)
            XCTAssertFalse(members.contains("Japan only"), members)
            XCTAssertTrue(members.contains("JP only"), members)
        }
        try restored.renameRuleGroup(named: japan, to: "我的日本", for: scheme)
        let renamed = restored.customizableScheme(for: scheme)
        XCTAssertEqual(renamed.groups.first { $0.name == "我的日本" }?.members, [.nodePattern(draft.pattern)])
        XCTAssertFalse(renamed.groups.contains { $0.name == japan })
    }

    func testUserCreatedNodeGroupsMaterializeAndRemainCandidates() throws {
        let scheme = try RuleSchemeParser().parse(text: "[custom]\ncustom_proxy_group=入口`select`[]DIRECT\nruleset=入口,[]FINAL", id: "custom-filter", name: "Filter", summary: "")
        let custom = RuleSchemeGroup(name: "英国专线", kind: .urlTest, members: [.nodePattern("(?i)(?:英国|UK|London)")], interval: 300, isCustomNodeFilter: true)
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(RuleSchemeCustomization(schemeID: scheme.id))) as? [String: Any])
        object["addedNodeGroups"] = try JSONSerialization.jsonObject(with: encoder.encode([custom]))
        let customization = try JSONDecoder().decode(RuleSchemeCustomization.self, from: JSONSerialization.data(withJSONObject: object))
        let result = scheme.customized(enabledRuleGroupNames: nil, customRuleFlows: [], groupCustomization: customization)
        XCTAssertEqual(result.groups.first { $0.name == custom.name }, custom)
        XCTAssertTrue(result.routingTargetGroupNames().contains(custom.name))
        XCTAssertFalse(result.routingTargetGroupNames(excluding: custom.name).contains(custom.name))
    }

    @MainActor
    func testCreatedFilterLifecyclePersistenceCandidatesAndExports() throws {
        let scheme = try RuleSchemeParser().parse(text: "[custom]\ncustom_proxy_group=入口`select`[]DIRECT\nruleset=入口,[]FINAL", id: "custom-life", name: "Filter", summary: "")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersistenceStore(fileURL: folder.appendingPathComponent("state.json"))
        let model = AppModel(persistence: store, arguments: [])
        for name in ["", "DIRECT", "reject", "Bad,Name", "Bad\nName", "入口"] {
            XCTAssertThrowsError(try model.createNodeFilterGroup(name: name, pattern: "UK", kind: .urlTest, for: scheme))
        }
        for pattern in ["", "["] {
            XCTAssertThrowsError(try model.createNodeFilterGroup(name: "英国节点", pattern: pattern, kind: .urlTest, for: scheme))
        }
        XCTAssertTrue(model.customizableRuleGroups(for: scheme).allSatisfy { $0.isCustomNodeFilter != true })
        let created = try model.createNodeFilterGroup(name: "英国节点", pattern: "(?i)(?:UK|London)", kind: .urlTest, for: scheme)
        XCTAssertThrowsError(try model.createNodeFilterGroup(name: created.name, pattern: "UK", kind: .urlTest, for: scheme))
        XCTAssertEqual(scheme.groupEditorMode(for: created), .nodePatternsOnly)
        model.updateRuleGroup(.init(name: "入口", kind: .select, members: [.reference("DIRECT"), .reference(created.name)]), for: scheme)
        model.updateRuleGroup(.init(name: created.name, kind: .fallback, members: [.nodePattern("(?i)UK")]), for: scheme)
        try model.renameRuleGroup(named: created.name, to: "我的英国", for: scheme)
        let restored = AppModel(persistence: store, arguments: [])
        let result = restored.customizableScheme(for: scheme)
        let group = try XCTUnwrap(result.groups.first { $0.name == "我的英国" })
        XCTAssertEqual(group.kind, .fallback)
        XCTAssertEqual(group.members, [.nodePattern("(?i)UK")])
        XCTAssertTrue(result.routingTargetGroupNames().contains(group.name))
        XCTAssertFalse(result.routingTargetGroupNames(excluding: group.name).contains(group.name))
        XCTAssertEqual(result.groups.first?.members, [.reference("DIRECT"), .reference(group.name)])
        let nodes = ["UK 01", "London 02", "US 03"].map { ProxyNode(kind: .trojan, name: $0, server: "example.com", port: 443, password: "test", rawURI: "") }
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: result, target: target, preferRuleSets: false)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            if [ClientTarget.clashMi, .surge, .singBox].contains(target) {
                let members = try exportedMembers(output.content, target: target, groupName: group.name)
                XCTAssertTrue(members.contains("UK 01"), members)
                XCTAssertFalse(members.contains("London 02"), members)
                XCTAssertFalse(members.contains("US 03"), members)
            }
            XCTAssertFalse(output.content.contains("isCustomNodeFilter"))
        }
        let saved = restored.saveCustomizedScheme(named: "Copy", from: scheme)
        XCTAssertTrue(saved.routingTargetGroupNames().contains(group.name))
        restored.deleteRuleGroup(named: group.name, for: scheme)
        let deleted = AppModel(persistence: store, arguments: []).customizableScheme(for: scheme)
        XCTAssertFalse(deleted.groups.contains { $0.isCustomNodeFilter == true })
        XCTAssertFalse(deleted.routingTargetGroupNames().contains(group.name))
        XCTAssertEqual(deleted.groups.first?.members, [.reference("DIRECT")])
    }

    @MainActor
    func testAllNodesGroupTracksEnabledSelectionAndFutureNodes() throws {
        let scheme = try RuleSchemeParser().parse(text: "[custom]\ncustom_proxy_group=入口`select`[]DIRECT\nruleset=入口,[]FINAL", id: "all-nodes-filter", name: "Filter", summary: "")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersistenceStore(fileURL: folder.appendingPathComponent("state.json"))
        let model = AppModel(persistence: store, arguments: [])
        let disabledSource = SubscriptionSource(name: "Disabled", urlString: "https://example.com/disabled", isEnabled: false)
        model.subscriptions = [disabledSource]
        let keep = ProxyNode(kind: .trojan, name: "Keep", server: "keep.example.com", port: 443, password: "test", rawURI: "")
        let excluded = ProxyNode(kind: .trojan, name: "Excluded", server: "excluded.example.com", port: 443, password: "test", rawURI: "")
        let disabled = ProxyNode(sourceID: disabledSource.id, kind: .trojan, name: "Disabled", server: "disabled.example.com", port: 443, password: "test", rawURI: "")
        model.nodes = [keep, excluded, disabled]
        model.setNode(excluded, included: false)
        let group = try model.createNodeFilterGroup(name: "全部自定义", pattern: ".*", kind: .urlTest, for: scheme)
        model.updateRuleGroup(.init(name: "入口", kind: .select, members: [.reference(group.name)]), for: scheme)
        let restored = AppModel(persistence: store, arguments: [])
        let saved = restored.customizableScheme(for: scheme)
        XCTAssertEqual(saved.groups.first { $0.name == group.name }?.members, [.nodePattern(".*")])
        XCTAssertEqual(restored.enabledNodes.map(\.name), ["Keep"])
        let future = ProxyNode(kind: .trojan, name: "Future", server: "future.example.com", port: 443, password: "test", rawURI: "")
        restored.nodes.append(future)
        let input = restored.enabledNodes
        XCTAssertEqual(try NodeNameFilterMatcher.preview(".*", candidates: input.map { [$0.name] }, caseInsensitive: true), [0, 1])
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let output = ConfigurationGenerator().generate(nodes: input, scheme: saved, target: target, preferRuleSets: false)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            XCTAssertFalse(output.content.contains("excluded.example.com"))
            XCTAssertFalse(output.content.contains("disabled.example.com"))
            if [ClientTarget.clashMi, .surge, .singBox].contains(target) {
                let members = try exportedMembers(output.content, target: target, groupName: group.name)
                XCTAssertTrue(members.contains("Keep"), members)
                XCTAssertTrue(members.contains("Future"), members)
                XCTAssertFalse(members.contains("Excluded"), members)
                XCTAssertFalse(members.contains("Disabled"), members)
            }
        }
    }

    private func exportedMembers(_ content: String, target: ClientTarget, groupName: String) throws -> String {
        switch target {
        case .clashMi:
            return try XCTUnwrap(content.components(separatedBy: "proxy-groups:").dropFirst().first)
                .components(separatedBy: "rules:").first ?? ""
        case .surge:
            return try XCTUnwrap(content.components(separatedBy: "\n").first { $0.hasPrefix(groupName + " = ") })
        case .singBox:
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            let groups = try XCTUnwrap(document["outbounds"] as? [[String: Any]])
            let group = try XCTUnwrap(groups.first { $0["tag"] as? String == groupName })
            return try XCTUnwrap(group["outbounds"] as? [String]).joined(separator: "\n")
        default: XCTFail("Unsupported fixture target"); return ""
        }
    }

}
