import XCTest
@testable import Tower

@MainActor
final class RuleOperationLifecycleTests: XCTestCase {
    func testResetWhileImportIsDownloadingDoesNotRestoreScheme() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.directory) }
        let started = expectation(description: "request started")
        AuditRuleURLProtocol.onStart = { started.fulfill() }
        let operation = Task { try await fixture.model.importScheme(name: "Late", urlString: "https://example.invalid/scheme.yaml") }
        await fulfillment(of: [started], timeout: 3)
        await fixture.model.resetAllConfiguration()
        AuditRuleURLProtocol.complete("proxy-groups:\n  - name: Proxy\n    type: select\n    proxies: [DIRECT]\nrules:\n  - MATCH,Proxy\n")
        _ = try? await operation.value
        XCTAssertTrue(fixture.model.importedSchemes.isEmpty, "Reset must invalidate pending imports")
        XCTAssertEqual(fixture.model.selectedPresetID, AppModel.defaultRuleSchemeID)
    }

    func testResetWhileLocalRulesDownloadDoesNotRestoreRuleSet() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.directory) }
        let started = expectation(description: "request started")
        AuditRuleURLProtocol.onStart = { started.fulfill() }
        let ruleSet = LocalRuleSet(name: "Late", rulesText: "https://example.invalid/test.list")
        let operation = Task { try await fixture.model.saveLocalRuleSet(ruleSet) }
        await fulfillment(of: [started], timeout: 3)
        await fixture.model.resetAllConfiguration()
        AuditRuleURLProtocol.complete("DOMAIN,example.com")
        _ = try? await operation.value
        XCTAssertTrue(fixture.model.localRuleSets.isEmpty, "Reset must invalidate pending saves")
        let store = RuleDownloadStore(folderURL: fixture.directory.appendingPathComponent("rules"))
        XCTAssertFalse(store.hasCachedRules(for: URL(string: "https://example.invalid/test.list")!))
    }

    func testCancellingImportDoesNotSaveLateResponse() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.directory) }
        let started = expectation(description: "request started")
        AuditRuleURLProtocol.onStart = { started.fulfill() }
        let operation = Task { try await fixture.model.importScheme(name: "Cancelled", urlString: "https://example.invalid/scheme.yaml") }
        await fulfillment(of: [started], timeout: 3)
        operation.cancel()
        fixture.model.cancelRuleImport()
        AuditRuleURLProtocol.complete("proxy-groups:\n  - name: Proxy\n    type: select\n    proxies: [DIRECT]\nrules:\n  - MATCH,Proxy\n")
        _ = try? await operation.value
        XCTAssertFalse(fixture.model.isImportingScheme)
        XCTAssertTrue(fixture.model.importedSchemes.isEmpty)
    }

    func testAlreadyCancelledLocalSaveDoesNotWrite() async throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.directory) }
        let operation = Task { try await fixture.model.saveLocalRuleSet(LocalRuleSet(name: "Cancelled", rulesText: "DOMAIN,example.com")) }
        operation.cancel()
        _ = try? await operation.value
        XCTAssertTrue(fixture.model.localRuleSets.isEmpty)
    }

    func testExportFallbackUsesCapturedConfigurationAfterTargetChanges() throws {
        let fixture = makeFixture()
        defer { fixture.session.invalidateAndCancel(); try? FileManager.default.removeItem(at: fixture.directory) }
        let captured = GeneratedConfiguration(target: .surge, content: "[General]\nloglevel = notify", supportedNodeCount: 1, skippedNodeCount: 0, ruleCount: 0)
        fixture.model.selectTarget(.shadowrocket)
        let url = try fixture.model.makeExportURL(configuration: captured)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), captured.content)
        XCTAssertEqual(url.lastPathComponent, captured.fileName)
    }

    func testStoppingLatencyKeepsPreviousResultsAndRejectsLateProbe() async throws {
        let started = expectation(description: "probe started")
        let gate = AsyncStream<Void>.makeStream()
        let service = NodeLatencyService(icmpProbe: { _, _ in
            started.fulfill()
            for await _ in gate.stream {}
            return 777
        }, tcpProbe: { _, _, _ in 888 })
        let model = AppModel(latencyService: service, arguments: ["--demo"])
        let node = try XCTUnwrap(model.nodes.first)
        let previous = model.nodeLatencies[node.id]
        let operation = Task { await model.testLatency(node) }
        await fulfillment(of: [started], timeout: 3)
        model.cancelLatencyTests()
        XCTAssertTrue(model.latencyTestingNodeIDs.isEmpty)
        gate.continuation.finish()
        await operation.value
        XCTAssertEqual(model.nodeLatencies[node.id], previous)
    }

    private func makeFixture() -> (model: AppModel, session: URLSession, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuditRuleURLProtocol.self]
        let session = URLSession(configuration: config)
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        return (AppModel(persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")), schemeImportService: RuleSchemeImportService(store: store, session: session), downloadStore: store, arguments: []), session, directory)
    }
}

private final class AuditRuleURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) static var onStart: (() -> Void)?
    nonisolated(unsafe) private static var pending: AuditRuleURLProtocol?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.pending = self; Self.lock.unlock()
        Self.onStart?()
    }
    override func stopLoading() {}
    static func complete(_ content: String) {
        lock.lock(); let operation = pending; pending = nil; lock.unlock()
        guard let operation, let url = operation.request.url else { return }
        operation.client?.urlProtocol(operation, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        operation.client?.urlProtocol(operation, didLoad: Data(content.utf8))
        operation.client?.urlProtocolDidFinishLoading(operation)
    }
}
