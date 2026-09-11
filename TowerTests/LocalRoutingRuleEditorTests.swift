import XCTest
@testable import Tower

final class LocalRoutingRuleEditorTests: XCTestCase {
    let reject = "AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT"

    func testCompatibilitySummaryChecksEveryRuleAndDistinguishesUnvalidatedInput() {
        let ordinary = LocalRuleCompatibilitySummary(text: "DOMAIN-SUFFIX,example.com")
        XCTAssertTrue(ordinary.supported.contains(.clashMi))
        let mixed = LocalRuleCompatibilitySummary(text: "DOMAIN-SUFFIX,example.com\nURL-REGEX,^https://example.com,REJECT")
        XCTAssertTrue(mixed.unsupported.contains(.clashMi))
        XCTAssertTrue(mixed.supported.contains(.surge))
        let invalid = LocalRuleCompatibilitySummary(text: "DOMAIN,example.com\nAND,((NETWORK,UDP)")
        XCTAssertNotNil(invalid.error)
        XCTAssertTrue(invalid.supported.isEmpty)
        let remote = LocalRuleCompatibilitySummary(text: "https://example.com/rules.list")
        XCTAssertTrue(remote.isRemote)
        XCTAssertTrue(remote.supported.isEmpty)
        XCTAssertNil(remote.error)
        let blank = LocalRuleCompatibilitySummary(text: "# comment\n")
        XCTAssertTrue(blank.isEmpty)
        XCTAssertTrue(blank.supported.isEmpty)
    }

    func testLocalDocumentPreservesCompoundRulesAndParameters() {
        let text = reject + "\nURL-REGEX,'^https://a.example/a{1,3}',旧策略,extended-matching\nIP-CIDR,192.168.0.0/16,旧策略,src"
        let set = LocalRuleSet(name: "QUIC", rulesText: text)
        XCTAssertEqual(set.normalizedRules, [
            "AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com))",
            "URL-REGEX,'^https://a.example/a{1,3}',extended-matching",
            "IP-CIDR,192.168.0.0/16,src"
        ])
        XCTAssertEqual(set.rulesText, text)
    }

    func testInvalidLineReportsOriginalLineNumber() {
        let document = LocalRoutingRuleDocument("# comment\n\n" + reject + "\nAND,((NETWORK,UDP)")
        XCTAssertEqual(document.firstError?.number, 4)
        XCTAssertNil(LocalRoutingRuleDocument("NOT,((NETWORK,UDP),(DST-PORT,443))").entries.first?.condition)
    }

    func testWindowsLineEndingsAndUntouchedTextArePreserved() {
        let text = "# keep\r\n\r\n" + reject + "\r\nDOMAIN,example.com\r\n"
        XCTAssertEqual(LocalRoutingRuleDocument(text).entries.map(\.lineIndex), [2, 3])
        XCTAssertEqual(LocalRoutingRuleDocument.replacingLine(in: text, at: 3, with: "DOMAIN,changed.com"),
                       text.replacingOccurrences(of: "DOMAIN,example.com", with: "DOMAIN,changed.com"))
        XCTAssertEqual(LocalRoutingRuleDocument.replacingLine(in: text, at: 3, with: nil),
                       "# keep\r\n\r\n" + reject + "\r\n")
    }

    func testFormReplacementLeavesOtherRulesAndCommentsUntouched() throws {
        let text = "# keep\n" + reject + "\nDOMAIN-SUFFIX,openai.com\n"
        let document = LocalRoutingRuleDocument(text)
        var condition = try XCTUnwrap(document.entries.first?.condition)
        condition.children?[1].value = "8443"
        let edited = LocalRoutingRuleDocument.replacingLine(in: text, at: 1,
            with: LocalRoutingRuleDocument.line(condition, policy: "REJECT"))
        XCTAssertEqual(edited, text.replacingOccurrences(of: "443", with: "8443"))
        XCTAssertEqual(LocalRoutingRuleDocument(edited).entries.first?.policy, "REJECT")
    }

    @MainActor
    func testInvalidSaveDoesNotOverwriteLibraryOrPlacements() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")), arguments: [])
        var set = LocalRuleSet(name: "QUIC", rulesText: reject)
        try await model.saveLocalRuleSet(set)
        set.rulesText = "# comment\nAND,((NETWORK,UDP)"
        do {
            try await model.saveLocalRuleSet(set)
            XCTFail("Invalid draft must be rejected")
        } catch let error as LocalRoutingRuleDocument.InvalidLine {
            XCTAssertEqual(error.number, 2)
        }
        XCTAssertEqual(model.localRuleSets.first(where: { $0.id == set.id })?.rulesText, reject)
    }

    func testIncompatibleLocalRejectBlocksExportInsteadOfBroadening() throws {
        let scheme = try RuleSchemeParser().parse(text: "[Proxy Group]\nOpenAI = select,Test\n[Rule]\nFINAL,OpenAI", id: "ui", name: "UI", summary: "")
        let flow = CustomRuleFlow(schemeID: scheme.id, name: "QUIC", policyName: "OpenAI", rulesText: "AND,((PROTOCOL,QUIC),(DOMAIN-SUFFIX,openai.com)),REJECT")
        let selected = scheme.customized(enabledRuleGroupNames: ["OpenAI"], customRuleFlows: [flow])
        let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")
        let result = ConfigurationGenerator().generate(nodes: [node], scheme: selected, target: .clashMi, preferRuleSets: false)
        XCTAssertTrue(result.hasInvalidPolicyReferences)
        XCTAssertFalse(result.content.contains("DOMAIN-SUFFIX,openai.com,REJECT"))
    }

    func testStoredLocalRuleRejectSurvivesPlacementAndExport() throws {
        let set = LocalRuleSet(name: "QUIC", rulesText: reject + "\nDOMAIN-SUFFIX,openai.com")
        let restored = try JSONDecoder().decode(LocalRuleSet.self, from: JSONEncoder().encode(set))
        let scheme = try RuleSchemeParser().parse(text: "[Proxy Group]\nOpenAI = select,Test\n[Rule]\nFINAL,OpenAI", id: "ui", name: "UI", summary: "")
        let flow = CustomRuleFlow(schemeID: scheme.id, name: "QUIC", policyName: "OpenAI", rulesText: restored.rulesText)
        let selected = scheme.customized(enabledRuleGroupNames: ["OpenAI"], customRuleFlows: [flow])
        let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let result = ConfigurationGenerator().generate(nodes: [node], scheme: selected, target: target, preferRuleSets: false)
            // Creating this ignored directory opts a local QA run into emitting
            // the same three small profiles for installed core validators.
            let evidence = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent(".artifacts/rule-ui/core")
            if FileManager.default.fileExists(atPath: evidence.path), [.clashMi, .surge, .singBox].contains(target) {
                let ext = target == .surge ? "conf" : (target == .singBox ? "json" : "yaml")
                try Data(result.content.utf8).write(to: evidence.appendingPathComponent(target.rawValue + "." + ext), options: [.atomic, .completeFileProtection])
            }
            if target.usesSingBoxFormat {
                XCTAssertFalse(result.hasInvalidPolicyReferences)
                XCTAssertTrue(result.content.contains("reject"))
                XCTAssertTrue(result.content.contains("udp"))
            } else if RoutingRuleCapabilities.compiledTargets.contains(target) {
                XCTAssertFalse(result.hasInvalidPolicyReferences)
                let expected = RoutingRuleCapabilities.surgeTargets.contains(target) ? reject.replacingOccurrences(of: "NETWORK", with: "PROTOCOL").replacingOccurrences(of: "DST-PORT", with: "DEST-PORT") : reject
                XCTAssertTrue(result.content.contains(expected))
                XCTAssertTrue(result.content.contains("DOMAIN-SUFFIX,openai.com,OpenAI"))
            } else {
                XCTAssertTrue(result.hasInvalidPolicyReferences, "\(target) must block unsupported REJECT conditions")
            }
        }
    }
}
