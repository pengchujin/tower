import XCTest
@testable import Tower

final class MihomoYAMLSyntaxTests: XCTestCase {
    private func read(_ text: String) throws -> [String: Any] {
        var reader = SchemeYAMLReader(text)
        let value = try reader.read()
        return try XCTUnwrap(value as? [String: Any])
    }

    func testMultilineFlowAndAliasesPreserveTemplatesAndOverrides() throws {
        let root = try read("""
        defaults:
          &base {
            type: url-test,
            proxies: [DIRECT,
              REJECT,], # comment
            interval: 180,
          }
        groups:
          - { name: Auto, <<: *base }
          - { type: select, <<: *base, name: Manual }
          - <<: *base
            name: Other
            interval: 360
        """)
        let groups = try XCTUnwrap(root["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0]["type"] as? String, "url-test")
        XCTAssertEqual(groups[0]["proxies"] as? [String], ["DIRECT", "REJECT"])
        XCTAssertEqual(groups[1]["type"] as? String, "select")
        XCTAssertEqual(groups[2]["interval"] as? Int, 360)
        XCTAssertEqual((root["defaults"] as? [String: Any])?["interval"] as? Int, 180)
    }

    func testMergeSequenceUsesFirstSourceAndExplicitValuesRegardlessOfPosition() throws {
        let root = try read("""
        first: &a {type: url-test, interval: 180}
        second: &b {type: fallback, tolerance: 50}
        merged:
          interval: 300
          <<: [*a, *b]
        arrays: &nodes [DIRECT, REJECT]
        copied: *nodes
        """)
        let merged = try XCTUnwrap(root["merged"] as? [String: Any])
        XCTAssertEqual(merged["type"] as? String, "url-test")
        XCTAssertEqual(merged["interval"] as? Int, 300)
        XCTAssertEqual(merged["tolerance"] as? Int, 50)
        XCTAssertEqual(root["copied"] as? [String], ["DIRECT", "REJECT"])
    }

    func testNestedAliasesKeepPriorityOrderAndQuotedRegex() throws {
        let root = try read(#"""
        weights: &weights {"(?i)jp": 2, "hk:#[]{}": 1}
        base: &base
          priorities: *weights
          filter: '(?i)^(?!.*(?:港|hk)).*'
        group: {<<: *base}
        """#)
        let group = try XCTUnwrap(root["group"] as? [String: Any])
        XCTAssertEqual(group["tower-priority-order"] as? [String], ["(?i)jp", "hk:#[]{}"])
        XCTAssertEqual(group["filter"] as? String, "(?i)^(?!.*(?:港|hk)).*")
    }

    func testPlainApostrophesAndQuotedCommentMarkersArePreserved() throws {
        let root = try read("""
        name: Alice's nodes
        note: "keep # inside"
        groups: [{name: "Hong Kong", filter: '(?i)hk|hong kong'}]
        """)
        XCTAssertEqual(root["name"] as? String, "Alice's nodes")
        XCTAssertEqual(root["note"] as? String, "keep # inside")
    }

    func testMalformedAndRecursiveDocumentsStillFail() {
        for text in [
            "x: *missing", "x: &x [*x]", "x: {<<: 42}",
            "x: {name: A, name: B}", "x: {<<: {}, <<: {}}",
            "x: [DIRECT, REJECT}", "x: [DIRECT,,REJECT]",
            "x: !include config.yaml", "x: 1\n---\ny: 2",
        ] {
            XCTAssertThrowsError(try read(text), text)
        }
    }

    func testDepthAndAliasExpansionAreBounded() {
        let deep = "x: " + String(repeating: "[", count: 100) + "0" + String(repeating: "]", count: 100)
        XCTAssertThrowsError(try read(deep))
        var bomb = "a0: &a0 [x,x,x,x,x,x,x,x,x,x]\n"
        for i in 1...8 {
            bomb += "a\(i): &a\(i) [" + Array(repeating: "*a\(i-1)", count: 10).joined(separator: ",") + "]\n"
        }
        XCTAssertThrowsError(try read(bomb))
    }

    func testMihomoTemplateRoundTripKeepsGroupsRulesAndSelectedNodes() async throws {
        let source = """
        base: &base {type: select, proxies: [Japan, DIRECT]}
        provider: &provider {type: http, interval: 180}
        selection: &selection {type: url-test, use: [Airport], filter: '(?i)jp|japan'}
        proxy-providers:
          Airport: {<<: *provider, url: 'https://example.com/subscription'}
        proxy-groups:
          - {name: OpenAI, <<: *base}
          - {name: Japan, <<: *selection}
        rules:
          - AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT
          - DOMAIN-SUFFIX,openai.com,OpenAI
          - GEOSITE,category-ai-!cn,OpenAI
          - MATCH,OpenAI
        """
        let parser = RuleSchemeParser()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = RuleSchemeImportService(store: RuleDownloadStore(folderURL: folder))
        let scheme = try await service.importScheme(text: source, name: "Test").scheme
        XCTAssertEqual(scheme.groups.map(\.name), ["OpenAI", "Japan"])
        XCTAssertEqual(scheme.rulesets.count, 4)
        let persisted = try JSONDecoder().decode(RuleScheme.self, from: JSONEncoder().encode(scheme))
        let reopened = try parser.parse(text: XCTUnwrap(persisted.rawConfigurationText), id: "reopened", name: "Test", summary: "", useSelectedNodes: true)
        XCTAssertEqual(reopened.rulesets, scheme.rulesets)
        let nodes = [ProxyNode(kind: .trojan, name: "JP keep", server: "example.com", port: 443, password: "test", rawURI: ""),
                     ProxyNode(kind: .trojan, name: "HK other", server: "example.com", port: 443, password: "test", rawURI: "")]
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: reopened, target: .clashVerge, preferRuleSets: false)
        XCTAssertFalse(output.hasInvalidPolicyReferences)
        XCTAssertTrue(output.content.contains("GEOSITE,category-ai-!cn,OpenAI"))
        XCTAssertTrue(output.content.contains("AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT"))
        XCTAssertLessThan(output.content.utf8.count, 20_000)
        let groups = try XCTUnwrap(try read(output.content)["proxy-groups"] as? [[String: Any]])
        XCTAssertEqual(groups.first { $0["name"] as? String == "Japan" }?["proxies"] as? [String], ["JP keep"])
    }

    func testPrivateMihomoRuleImportEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["TOWER_MIHOMO_IMPORT_FIXTURE"] else {
            throw XCTSkip("Set TOWER_MIHOMO_IMPORT_FIXTURE for the opt-in public configuration check")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleDownloadStore(folderURL: folder)
        let service = RuleSchemeImportService(store: store)
        let text = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let result = try await service.importScheme(text: text, name: "Mihomo Import")
        XCTAssertEqual(result.failedRulesetCount, 0)
        XCTAssertEqual(result.scheme.groups.count, 30)
        XCTAssertEqual(result.scheme.rulesets.count, 34)
        let ruleURL = try XCTUnwrap(result.scheme.remoteRulesetURLs.first)
        XCTAssertGreaterThan(store.lines(for: ruleURL)?.count ?? 0, 0)
        let saved = try JSONDecoder().decode(RuleScheme.self, from: JSONEncoder().encode(result.scheme))
        let reopened = try RuleSchemeTextEditorService().validatedScheme(
            from: XCTUnwrap(saved.rawConfigurationText), replacing: saved)
        XCTAssertEqual(reopened.groups, saved.groups)
        XCTAssertEqual(reopened.rulesets, saved.rulesets)
        XCTAssertFalse(try XCTUnwrap(saved.rawConfigurationText).contains("example.com/airport"))
        let node = ProxyNode(kind: .trojan, name: "JP Test", server: "example.com", port: 443, password: "test", rawURI: "")
        let output = ConfigurationGenerator().generate(nodes: [node], scheme: reopened, target: .clashVerge,
            schemes: RuleSchemeRepository(downloadStore: store), preferRuleSets: false)
        XCTAssertFalse(output.hasInvalidPolicyReferences)
        XCTAssertTrue(output.content.contains("GEOSITE,category-ai-!cn,境外AI"))
        XCTAssertLessThan(output.content.utf8.count, 200_000)
        if let outputPath = environment["TOWER_MIHOMO_IMPORT_OUTPUT"] {
            try Data(output.content.utf8).write(to: URL(fileURLWithPath: outputPath), options: [.atomic, .completeFileProtection])
        }
    }

}
