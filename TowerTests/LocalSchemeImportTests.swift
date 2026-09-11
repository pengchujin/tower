import XCTest
@testable import Tower

final class LocalSchemeImportTests: XCTestCase {
    private let clash = """
    proxies:
      - {name: 'JP Fixture', type: trojan, server: node.example.com, port: 443, password: DO_NOT_STORE_PROXY_SECRET}
    proxy-groups:
      - {name: OpenAI, type: select, proxies: ['JP Fixture', DIRECT]}
    rules:
      - 'AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT'
      - DOMAIN-SUFFIX,openai.com,OpenAI
      - MATCH,OpenAI
    """
    private let surge = """
    [Proxy]
    JP Fixture = trojan, node.example.com, 443, password=DO_NOT_STORE_PROXY_SECRET
    [Proxy Group]
    OpenAI = select, JP Fixture, DIRECT
    [Rule]
    AND,((PROTOCOL,UDP),(DEST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT
    DOMAIN-SUFFIX,openai.com,OpenAI
    FINAL,OpenAI
    [MITM]
    ca-p12 = DO_NOT_STORE_MITM_SECRET
    [Script]
    script = type=http-request,script-path=DO_NOT_STORE_SCRIPT
    """

    func testFullClashAndSurgeTextKeepRulesAndDropEmbeddedSecrets() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        for text in [clash, surge] {
            let result = try await fixture.service.importScheme(text: text, name: "Rules")
            XCTAssertNil(result.scheme.sourceURLString)
            XCTAssertEqual(result.scheme.name, "Rules")
            XCTAssertEqual(result.scheme.groups.count, 1)
            XCTAssertEqual(result.scheme.rulesets.count, 3)
            XCTAssertEqual(result.scheme.groups[0].members, [.nodePattern("^JP Fixture$"), .reference("DIRECT")])
            let encoded = String(decoding: try JSONEncoder().encode(result.scheme), as: UTF8.self)
            for secret in ["DO_NOT_STORE_PROXY_SECRET", "DO_NOT_STORE_MITM_SECRET", "DO_NOT_STORE_SCRIPT", "node.example.com"] {
                XCTAssertFalse(encoded.contains(secret), secret)
            }
            let restored = try RuleSchemeParser().parse(text: XCTUnwrap(result.scheme.rawConfigurationText), id: "reparsed", name: "Rules", summary: "")
            XCTAssertEqual(restored.groups, result.scheme.groups)
            XCTAssertEqual(restored.rulesets, result.scheme.rulesets)
            let node = ProxyNode(kind: .trojan, name: "JP Fixture", server: "local.example.com", port: 443, password: "fixture", rawURI: "")
            for target in [ClientTarget.clashMi, .surge, .singBox] {
                let output = ConfigurationGenerator().generate(nodes: [node], scheme: result.scheme, target: target)
                XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
                XCTAssertTrue(output.content.contains("openai.com"))
                XCTAssertTrue(output.content.contains("JP Fixture"))
            }
        }
    }

    func testFileInputUTF8AndUTF16UsesOnlyFilename() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        for encoding in [String.Encoding.utf8, .utf16] {
            let file = fixture.folder.appendingPathComponent("规则.conf")
            try XCTUnwrap(surge.data(using: encoding)).write(to: file)
            let content = try RuleSchemeImportService.readConfigurationFile(at: file)
            let result = try await fixture.service.importScheme(text: content, name: "", fileName: file.lastPathComponent)
            XCTAssertEqual(result.scheme.name, "规则.conf")
            XCTAssertNil(result.scheme.sourceURLString)
            XCTAssertEqual(result.scheme.rulesets.count, 3)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(result.scheme), as: UTF8.self).contains(fixture.folder.path))
        }
    }

    func testLocalRemoteRuleReferencesAreCachedThroughExistingPipeline() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        let input = "[custom]\ncustom_proxy_group=Proxy`select`.*\nruleset=Proxy,https://example.invalid/rules.list\nruleset=Proxy,[]FINAL"
        let result = try await fixture.service.importScheme(text: input, name: "")
        XCTAssertEqual(result.failedRulesetCount, 0)
        XCTAssertEqual(result.scheme.remoteRulesetURLs.count, 1)
        XCTAssertEqual(fixture.store.lines(for: URL(string: "https://example.invalid/rules.list")!), ["DOMAIN,fixture.example"])
    }

    @MainActor
    func testTextImportPersistsSchemeWithoutAddingNodesOrSubscriptions() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        let persistence = PersistenceStore(fileURL: fixture.folder.appendingPathComponent("state.json"))
        let model = AppModel(persistence: persistence, schemeImportService: fixture.service, downloadStore: fixture.store, arguments: [])
        let previousNodeIDs = model.nodes.map(\.id)
        let previousSources = model.subscriptions.map(\.id)
        try await model.importScheme(name: "Local", text: clash)
        XCTAssertEqual(model.nodes.map(\.id), previousNodeIDs)
        XCTAssertEqual(model.subscriptions.map(\.id), previousSources)
        XCTAssertEqual(model.importedSchemes.count, 1)
        let restored = AppModel(persistence: persistence, arguments: [])
        XCTAssertEqual(restored.importedSchemes.first?.name, "Local")
        XCTAssertEqual(restored.selectedPresetID, model.importedSchemes.first?.id)
    }

    func testInvalidBinaryEmptyAndOversizedInputAreRejected() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        for text in ["", "<html>not a config</html>", "not a configuration", String(repeating: "a", count: RuleSchemeImportService.maximumLocalBytes + 1)] {
            do { _ = try await fixture.service.importScheme(text: text, name: ""); XCTFail("Invalid input accepted") }
            catch { }
        }
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        let file = fixture.folder.appendingPathComponent("binary.conf")
        try Data([0, 1, 2, 3]).write(to: file)
        XCTAssertThrowsError(try RuleSchemeImportService.readConfigurationFile(at: file))
        try Data(repeating: 97, count: RuleSchemeImportService.maximumLocalBytes + 1).write(to: file)
        XCTAssertThrowsError(try RuleSchemeImportService.readConfigurationFile(at: file)) { XCTAssertEqual($0 as? RuleImportError, .fileTooLarge) }
    }

    func testRuleImportSeparatesSubscriptionProvidersGroupsAndRoutingRules() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        // CNIX occurs in all three namespaces; the URL hosts deliberately differ.
        let input = """
        proxy-providers:
          CNIX: {type: http, url: "请替换为订阅链接"}
          UnusedSubscription: {type: http, url: https://subscription.invalid/secret}
        proxy-groups:
          - {name: PROXY, type: select, proxies: [CNIX, DIRECT]}
          - {name: CNIX, type: select, use: [CNIX], filter: JP, exclude-filter: drop}
        rule-providers:
          CNIX: {type: http, behavior: classical, url: https://example.invalid/cnix.list}
          reject: {type: http, behavior: classical, url: https://example.invalid/reject.list}
          unused: {type: http, behavior: classical, url: https://example.invalid/unused.list}
        rules:
          - RULE-SET,reject,REJECT
          - DOMAIN,local.example,DIRECT
          - RULE-SET,CNIX,PROXY
          - MATCH,PROXY
        """
        let result = try await fixture.service.importScheme(text: input, name: "Provider template")
        let scheme = result.scheme
        XCTAssertEqual(scheme.groups.map(\.name), ["PROXY", "CNIX"])
        XCTAssertEqual(scheme.groups[0].members, [.reference("CNIX"), .reference("DIRECT")])
        XCTAssertEqual(scheme.groups[1].members, [.nodePattern("JP")])
        XCTAssertNil(scheme.groups[1].parameters?["use"])
        XCTAssertNil(scheme.groups[1].parameters?["tower-source-bindings"])
        XCTAssertEqual(scheme.rulesets.map(\.groupName), ["REJECT", "DIRECT", "PROXY", "PROXY"])
        XCTAssertEqual(scheme.remoteRulesetURLs.count, 2)
        XCTAssertNil(fixture.store.lines(for: URL(string: "https://example.invalid/unused.list")!))
        let reopened = try RuleSchemeTextEditorService().validatedScheme(
            from: XCTUnwrap(scheme.rawConfigurationText), replacing: scheme)
        XCTAssertEqual(reopened.groups, scheme.groups)
        XCTAssertEqual(reopened.rulesets, scheme.rulesets)
        let nodes = ["JP keep", "JP drop", "HK other"].map {
            ProxyNode(kind: .trojan, name: $0, server: "local.example.com", port: 443, password: "fixture", rawURI: "")
        }
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: reopened, target: .clashMi,
            schemes: RuleSchemeRepository(downloadStore: fixture.store), preferRuleSets: true)
        var reader = SchemeYAMLReader(output.content)
        let root = try XCTUnwrap(try reader.read() as? [String: Any])
        let groups = try XCTUnwrap(root["proxy-groups"] as? [[String: Any]])
        let cnix = try XCTUnwrap(groups.first { $0["name"] as? String == "CNIX" })
        XCTAssertEqual(cnix["proxies"] as? [String], ["JP keep"])
        XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
        XCTAssertFalse(output.content.contains("subscription.invalid"))
        XCTAssertFalse(output.content.contains("请替换"))
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let generated = ConfigurationGenerator().generate(nodes: nodes, scheme: reopened, target: target,
                schemes: RuleSchemeRepository(downloadStore: fixture.store), preferRuleSets: false)
            XCTAssertFalse(generated.content.isEmpty, "\(target): \(generated.diagnostics)")
            XCTAssertFalse(generated.hasInvalidPolicyReferences, "\(target): \(generated.diagnostics)")
            XCTAssertTrue(generated.content.contains("local.example"), target.rawValue)
            if target == .surge || target == .surgeMac {
                let policy = try XCTUnwrap(generated.content.components(separatedBy: .newlines).first { $0.hasPrefix("CNIX =") })
                XCTAssertTrue(policy.contains("JP keep"), policy)
                XCTAssertFalse(policy.contains("JP drop"), policy)
                XCTAssertFalse(policy.contains("HK other"), policy)
            }
            if target == .singBox {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(generated.content.utf8)) as? [String: Any])
                let outbounds = try XCTUnwrap(json["outbounds"] as? [[String: Any]])
                XCTAssertEqual(outbounds.first { $0["tag"] as? String == "CNIX" }?["outbounds"] as? [String], ["JP keep"])
            }
            if [.surgeMac, .singBox].contains(target) {
                let audit = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent(".artifacts/provider-import-redo")
                if FileManager.default.fileExists(atPath: audit.path) {
                    try generated.content.write(to: audit.appendingPathComponent("small-\(target.rawValue).conf"), atomically: true, encoding: .utf8)
                }
            }
        }

    }

    func testURLImportUsesSameRuleTemplateAsText() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        let result = try await fixture.service.importScheme(from: "https://example.invalid/config.yaml", name: "URL")
        XCTAssertEqual(result.scheme.groups.map(\.name), ["PROXY", "CNIX"])
        XCTAssertNil(result.scheme.groups[1].parameters?["use"])
        let reopened = try RuleSchemeTextEditorService().validatedScheme(
            from: XCTUnwrap(result.scheme.rawConfigurationText), replacing: result.scheme)
        XCTAssertEqual(reopened.groups, result.scheme.groups)
        XCTAssertEqual(result.scheme.sourceURLString, "https://example.invalid/config.yaml")
    }

    func testRuleTemplateRejectsUnknownSubscriptionProvider() {
        let input = "proxy-groups:\n  - {name: PROXY, type: select, use: [typo]}\nrules: ['MATCH,PROXY']"
        XCTAssertThrowsError(try RuleSchemeParser().parse(text: input, id: "bad", name: "", summary: "", useSelectedNodes: true))
    }

    func testPublicLoyalsoldierConfigurationUsesSelectedNodes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sourceFolder = root.appendingPathComponent(".artifacts/loyalsoldier-import")
        guard FileManager.default.fileExists(atPath: sourceFolder.appendingPathComponent("config.yaml").path) else {
            throw XCTSkip("Local upstream audit fixture is not present")
        }
        let source = try String(contentsOf: sourceFolder.appendingPathComponent("config.yaml"), encoding: .utf8)
        let scheme = try RuleSchemeParser().parse(text: source, id: "audit", name: "Loyalsoldier", summary: "", useSelectedNodes: true)
        XCTAssertEqual(scheme.groups.map(\.name), ["PROXY", "CNIX"])
        XCTAssertEqual(scheme.rulesets.map(\.groupName), ["DIRECT", "DIRECT", "DIRECT", "DIRECT", "REJECT", "PROXY", "PROXY", "DIRECT", "PROXY", "PROXY", "PROXY", "DIRECT", "DIRECT", "DIRECT", "PROXY", "PROXY"])
        XCTAssertEqual(scheme.remoteRulesetURLs.count, 11)
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.folder) }
        for url in scheme.remoteRulesetURLs {
            try fixture.store.store(String(contentsOf: sourceFolder.appendingPathComponent(url.lastPathComponent), encoding: .utf8), for: url)
        }
        let node = ProxyNode(kind: .trojan, name: "Selected node", server: "example.com", port: 443, password: "fixture", rawURI: "")
        let output = ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: .clashMi,
            schemes: RuleSchemeRepository(downloadStore: fixture.store), preferRuleSets: true)
        var reader = SchemeYAMLReader(output.content)
        let document = try XCTUnwrap(try reader.read() as? [String: Any])
        let groups = try XCTUnwrap(document["proxy-groups"] as? [[String: Any]])
        XCTAssertEqual(groups.first { $0["name"] as? String == "CNIX" }?["proxies"] as? [String], ["Selected node"])
        XCTAssertEqual(output.content.components(separatedBy: "RULE-SET,").count - 1, 11)
        XCTAssertLessThan(output.content.utf8.count, 20_000)
        try output.content.write(to: root.appendingPathComponent(".artifacts/provider-import-redo/generated-clash.yaml"), atomically: true, encoding: .utf8)
    }

    private func makeFixture() -> (service: RuleSchemeImportService, store: RuleDownloadStore, session: URLSession, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalImportURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = RuleDownloadStore(folderURL: folder.appendingPathComponent("rules"))
        return (RuleSchemeImportService(store: store, session: session), store, session, folder)
    }
}

private final class LocalImportURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if url.lastPathComponent == "config.yaml" {
            let text = "proxy-providers:\n  CNIX: {type: http, url: '请填写订阅'}\nproxy-groups:\n  - {name: PROXY, type: select, proxies: [CNIX, DIRECT]}\n  - {name: CNIX, type: select, use: [CNIX]}\nrules: ['MATCH,PROXY']"
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let content = url.pathExtension == "txt" ? "payload:\n  - 'DOMAIN,\(name).example'\n" : "DOMAIN,fixture.example\n"
        client?.urlProtocol(self, didLoad: Data(content.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
