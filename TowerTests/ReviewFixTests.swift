import XCTest
@testable import Tower

private enum ReviewFixTestError: LocalizedError {
    case unreachable

    var errorDescription: String? { "订阅服务器无法连接" }
}

/// Answers per URL so a batch can succeed partly and fail partly.
private actor ScriptedFetcher: SubscriptionFetching {
    private let nodesByURL: [String: [ProxyNode]]
    private let failingURLs: Set<String>
    private(set) var requestedURLs: [String] = []

    init(nodesByURL: [String: [ProxyNode]] = [:], failingURLs: Set<String> = []) {
        self.nodesByURL = nodesByURL
        self.failingURLs = failingURLs
    }

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        requestedURLs.append(source.urlString)
        if failingURLs.contains(source.urlString) { throw ReviewFixTestError.unreachable }
        let nodes = (nodesByURL[source.urlString] ?? []).map { node -> ProxyNode in
            var copy = node
            copy.sourceID = source.id
            return copy
        }
        return ImportResult(nodes: nodes, rejectedLineCount: 0, usage: nil)
    }
}

final class ReviewFixTests: XCTestCase {
    private func makeNode(
        name: String,
        server: String,
        port: Int = 443,
        password: String = "secret",
        rawURI: String = "ss://node"
    ) -> ProxyNode {
        ProxyNode(
            kind: .shadowsocks,
            name: name,
            server: server,
            port: port,
            cipher: "chacha20-ietf-poly1305",
            password: password,
            rawURI: rawURI
        )
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-review-fix-\(UUID().uuidString).json")
    }

    @MainActor
    func testWarmConfigurationPerformanceAudit() {
        let model = AppModel(arguments: ["--demo"])
        model.nodes = (0..<1_000).map {
            makeNode(name: "香港 · Perf \($0)", server: "192.0.2.1")
        }
        let coldStart = ContinuousClock.now
        _ = model.configuration()
        print("PERF_COLD_CONFIGURATION_1000_NODES \(coldStart.duration(to: .now))")
        let generations = model.configurationGenerationCount
        let start = ContinuousClock.now
        for _ in 0..<100 { _ = model.configuration() }
        print("PERF_WARM_CONFIGURATION_100_CALLS \(start.duration(to: .now))")
        XCTAssertEqual(model.configurationGenerationCount, generations)
    }

    @MainActor
    func testBulkCountryResolutionAtFiveThousandNodes() async {
        let service = IPCountryLookupService(database: IPCountryDatabase(
            ipv4Data: Data([1,1,1,0,1,1,1,255] + Array("SG".utf8)), ipv6Data: Data()))
        let model = AppModel(ipCountryLookupService: service, arguments: ["--demo"])
        model.nodes = (0..<5_000).map { makeNode(name: "Node \($0)", server: "1.1.1.1") }
        let start = ContinuousClock.now
        await model.resolveIPCountries(for: model.nodes)
        print("COUNTRY_5000_SECONDS \(start.duration(to: .now))")
        XCTAssertEqual(model.nodeIPCountryCodes.count, 5_000)
    }

    @MainActor
    func testSubscriptionSelectionPreservesRulePresentationCache() throws {
        let model = AppModel(arguments: ["--demo"])
        let scheme = try XCTUnwrap(model.selectedScheme)
        _ = model.customizableScheme(for: scheme)
        let count = model.ruleSchemeMaterializationCount
        model.setSubscriptions(model.subscriptions, enabled: false)
        _ = model.customizableScheme(for: scheme)
        XCTAssertEqual(model.ruleSchemeMaterializationCount, count)
    }

    @MainActor
    func testRetestKeepsPreviousMethodUntilNewMeasurementArrives() async {
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let service = NodeLatencyService(
            icmpProbe: { _, _ in 1 },
            tcpProbe: { _, _, _ in
                started.continuation.yield(())
                for await _ in release.stream { break }
                return 42
            }
        )
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: stateURL), latencyService: service, arguments: [])
        let node = makeNode(name: "Retest", server: "192.0.2.1")
        let previous = NodeLatencyMeasurement.success(milliseconds: 80, method: .icmp)
        model.nodeLatencies[node.id] = previous
        model.selectedLatencyTestMode = .tcp
        let task = Task { await model.testLatency(node) }
        for await _ in started.stream { break }
        XCTAssertTrue(model.latencyTestingNodeIDs.contains(node.id))
        XCTAssertEqual(model.nodeLatencies[node.id], previous)
        release.continuation.yield(())
        await task.value
        XCTAssertEqual(model.nodeLatencies[node.id]?.method, .tcp)
        XCTAssertEqual(model.nodeLatencies[node.id]?.milliseconds, 42)
        XCTAssertFalse(model.latencyTestingNodeIDs.contains(node.id))
        started.continuation.finish()
        release.continuation.finish()
    }

    // MARK: - Export selection survives a refresh

    func testExclusionSurvivesTheProviderRewritingTheNodeName() {
        // Airports write remaining traffic and multipliers into the remark, and
        // Tower renumbers bare-flag names itself, so the name changing is the
        // normal case rather than the exception.
        let previous = [
            makeNode(name: "🇭🇰 香港 01 | 剩余 120GB", server: "hk1.example.com"),
            makeNode(name: "🇯🇵 东京 01", server: "jp1.example.com"),
        ]
        let refreshed = [
            makeNode(name: "🇭🇰 香港 01 | 剩余 44GB", server: "hk1.example.com"),
            makeNode(name: "🇯🇵 东京 01", server: "jp1.example.com"),
        ]

        let carried = AppModel.carriedOverExclusions(
            previous: previous,
            previouslyExcludedIDs: [previous[0].id],
            refreshed: refreshed
        )

        XCTAssertEqual(carried, [refreshed[0].id])
    }

    func testUnchangedNodeStillMatchesExactly() {
        let node = makeNode(name: "🇸🇬 新加坡", server: "sg.example.com")
        let refreshed = [node, makeNode(name: "🇰🇷 首尔", server: "kr.example.com")]

        let carried = AppModel.carriedOverExclusions(
            previous: [node],
            previouslyExcludedIDs: [node.id],
            refreshed: refreshed
        )

        XCTAssertEqual(carried, [node.id])
    }

    func testRenamedNodeIsNotCarriedWhenItsEndpointIsAmbiguous() {
        // An airport may publish several distinct routes through one endpoint
        // and credential. Excluding a node the user never excluded is the same
        // silent error as losing the exclusion, so the looser match is refused
        // rather than guessed.
        let previous = [
            makeNode(name: "🇭🇰 香港 直连", server: "hk.example.com"),
            makeNode(name: "🇭🇰 香港 中转", server: "hk.example.com"),
        ]
        let refreshed = [
            makeNode(name: "🇭🇰 香港 直连 v2", server: "hk.example.com"),
            makeNode(name: "🇭🇰 香港 中转 v2", server: "hk.example.com"),
        ]

        let carried = AppModel.carriedOverExclusions(
            previous: previous,
            previouslyExcludedIDs: [previous[0].id],
            refreshed: refreshed
        )

        XCTAssertTrue(carried.isEmpty)
    }

    func testRemovedNodeCarriesNothing() {
        let previous = [makeNode(name: "🇺🇸 洛杉矶", server: "la.example.com")]
        let refreshed = [makeNode(name: "🇬🇧 伦敦", server: "lon.example.com")]

        let carried = AppModel.carriedOverExclusions(
            previous: previous,
            previouslyExcludedIDs: [previous[0].id],
            refreshed: refreshed
        )

        XCTAssertTrue(carried.isEmpty)
    }

    @MainActor
    func testRefreshReusesFreshHostCountryBeforePublishingNewNodeIDs() async throws {
        let url = "https://provider.example.com/sub"
        let old = makeNode(name: "Premium", server: "203.0.113.5")
        let fresh = makeNode(name: "Premium renamed", server: "203.0.113.5")
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = PersistenceStore(fileURL: stateURL)
        let first = AppModel(persistence: store, subscriptionService: ScriptedFetcher(nodesByURL: [url: [old]]),
            ipCountryLookupService: makeIPCountryService(range: 0xCB00_7100...0xCB00_71FF, code: "SG"), arguments: [])
        try await first.addSubscription(name: "机场", urlString: url)
        await first.resolveIPCountries(for: first.nodes)
        let model = AppModel(persistence: store, subscriptionService: ScriptedFetcher(nodesByURL: [url: [fresh]]), arguments: [])
        await model.resolveIPCountries(for: model.nodes)
        let source = try XCTUnwrap(model.subscriptions.first)
        _ = await model.updateSubscription(id: source.id, showResult: false)
        let refreshed = try XCTUnwrap(model.nodes.first)
        XCTAssertNotEqual(refreshed.id, old.id)
        XCTAssertEqual(model.countryCode(for: refreshed), "SG", "发布新节点时应已有同服务器的有效地区，不等待视图异步补回")
    }

    @MainActor
    func testRefreshKeepsTheExportSelectionWhenOnlyTheRemarkChanged() async throws {
        let url = "https://provider.example.com/sub"
        let original = makeNode(name: "🇭🇰 香港 01 | 剩余 120GB", server: "hk1.example.com")
        let renamed = makeNode(name: "🇭🇰 香港 01 | 剩余 44GB", server: "hk1.example.com")

        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let firstFetcher = ScriptedFetcher(nodesByURL: [url: [original]])
        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            subscriptionService: firstFetcher,
            arguments: []
        )
        try await model.addSubscription(name: "机场", urlString: url)
        let importedNode = try XCTUnwrap(model.nodes.first)
        model.setNode(importedNode, included: false)
        XCTAssertTrue(model.enabledNodes.isEmpty)

        let refreshed = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            subscriptionService: ScriptedFetcher(nodesByURL: [url: [renamed]]),
            arguments: []
        )
        let source = try XCTUnwrap(refreshed.subscriptions.first)
        _ = await refreshed.updateSubscription(id: source.id, showResult: false)

        XCTAssertEqual(refreshed.nodes.count, 1)
        XCTAssertTrue(
            refreshed.enabledNodes.isEmpty,
            "A renamed node must stay excluded instead of silently re-entering every export"
        )
    }

    // MARK: - Batch add reports failures without discarding successes

    @MainActor
    func testBatchAddKeepsReachableSubscriptionsAndReportsTheRest() async throws {
        let good = "https://good.example.com/sub"
        let bad = "https://bad.example.com/sub"
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            subscriptionService: ScriptedFetcher(
                nodesByURL: [good: [makeNode(name: "🇭🇰 香港", server: "hk.example.com")]],
                failingURLs: [bad]
            ),
            arguments: []
        )

        try await model.addSubscriptions(name: "", urlStrings: [good, bad])

        XCTAssertEqual(model.subscriptions.map(\.urlString), [good])
        XCTAssertEqual(model.nodes.count, 1)
        let report = try XCTUnwrap(model.subscriptionRefreshReport)
        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(report.totalCount, 2)
        XCTAssertEqual(report.failures.count, 1)
    }

    @MainActor
    func testBatchAddStillThrowsWhenNothingIsReachable() async throws {
        let bad = "https://bad.example.com/sub"
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            subscriptionService: ScriptedFetcher(failingURLs: [bad]),
            arguments: []
        )

        // Throwing is what keeps the add sheet open with the reason on it.
        do {
            try await model.addSubscriptions(name: "", urlStrings: [bad])
            XCTFail("Expected the add to fail when no link resolved")
        } catch {
            XCTAssertTrue(model.subscriptions.isEmpty)
            XCTAssertNil(model.subscriptionRefreshReport)
        }
    }

    // MARK: - iCloud must not lose a local edit to an older remote snapshot

    func testASnapshotLoadedFromDiskKeepsItsEditTimeSoAnOlderRemoteLoses() {
        let localEditedAt = Date(timeIntervalSince1970: 2_000)
        let staleRemote = Date(timeIntervalSince1970: 1_000)

        // The launch path applies the on-disk snapshot; before this it dropped
        // `updatedAt`, so the next foreground sync compared `.distantPast` and
        // took whatever iCloud held — including an older copy, which then
        // overwrote the local file.
        XCTAssertEqual(
            CloudSyncResolution.resolve(local: localEditedAt, remote: staleRemote),
            .keepLocal
        )
        XCTAssertEqual(
            CloudSyncResolution.resolve(local: nil, remote: staleRemote),
            .takeRemote,
            "A snapshot with no date at all still loses, which is the pre-sync case"
        )
    }

    @MainActor
    func testLaunchRestoresTheSnapshotEditTime() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = PersistenceStore(fileURL: stateURL)
        let editedAt = Date(timeIntervalSince1970: 2_000)

        try store.save(
            AppSnapshot(
                subscriptions: [],
                nodes: [],
                selectedPresetID: AppModel.defaultRuleSchemeID,
                selectedTarget: .surge,
                updatedAt: editedAt
            )
        )

        let model = AppModel(persistence: store, arguments: [])

        XCTAssertEqual(model.lastLocalEditAt, editedAt)
    }

    // MARK: - Resolved countries survive a relaunch

    /// A two-record offline database, so the lookup path can be exercised
    /// without a network and without the 10 MB bundled table.
    private func makeIPCountryService(range: ClosedRange<UInt32>, code: String) -> IPCountryLookupService {
        var record = Data()
        for value in [range.lowerBound, range.upperBound] {
            record.append(contentsOf: [
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
            ])
        }
        record.append(contentsOf: Array(code.utf8))
        return IPCountryLookupService(
            database: IPCountryDatabase(ipv4Data: record, ipv6Data: Data())
        )
    }

    @MainActor
    func testResolvedCountriesArePersistedByHostAndPrunedWithTheirNodes() async throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = PersistenceStore(fileURL: stateURL)
        // A literal address, so resolution never reaches DNS.
        let host = "203.0.113.5"
        let node = makeNode(name: "无名节点", server: host)

        let model = AppModel(
            persistence: store,
            ipCountryLookupService: makeIPCountryService(
                range: 0xCB00_7100...0xCB00_71FF,
                code: "SG"
            ),
            arguments: []
        )
        model.nodes = [node]

        await model.resolveIPCountries(for: [node])
        XCTAssertEqual(model.ipCountryCode(for: node), "SG")

        let snapshot = try XCTUnwrap(try store.load())
        XCTAssertEqual(
            try XCTUnwrap(snapshot.resolvedHostCountryCodes)[host],
            "SG",
            "A resolved country must outlive the process that resolved it"
        )
        XCTAssertNotNil(snapshot.resolvedHostCountryCodeUpdatedAt?[host])

        // Relaunching answers from the snapshot rather than resolving again.
        let relaunched = AppModel(
            persistence: store,
            ipCountryLookupService: makeIPCountryService(range: 0...0, code: "ZZ"),
            arguments: []
        )
        let restoredNode = try XCTUnwrap(relaunched.nodes.first)
        await relaunched.resolveIPCountries(for: [restoredNode])
        XCTAssertEqual(relaunched.ipCountryCode(for: restoredNode), "SG")

        // A host that no longer backs any node must not accumulate forever.
        relaunched.deleteNode(restoredNode)
        let pruned = try XCTUnwrap(try store.load())
        XCTAssertNil(pruned.resolvedHostCountryCodes?[host])
        XCTAssertNil(pruned.resolvedHostCountryCodeUpdatedAt?[host])
    }

    @MainActor
    func testResolvedCountryCacheExpiresInsteadOfPinningAHostnameForever() async throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = PersistenceStore(fileURL: stateURL)
        let host = "203.0.113.5"
        let node = makeNode(name: "会漂移的域名", server: host)

        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: [node],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            resolvedHostCountryCodes: [host: "SG"],
            resolvedHostCountryCodeUpdatedAt: [host: .distantPast]
        ))

        let model = AppModel(
            persistence: store,
            ipCountryLookupService: makeIPCountryService(
                range: 0xCB00_7100...0xCB00_71FF,
                code: "ZZ"
            ),
            arguments: []
        )
        let restoredNode = try XCTUnwrap(model.nodes.first)

        await model.resolveIPCountries(for: [restoredNode])

        XCTAssertEqual(model.ipCountryCode(for: restoredNode), "ZZ")
        XCTAssertNotEqual(try store.load()?.resolvedHostCountryCodes?[host], "SG")
    }

    // MARK: - Node-only export is its own cached document

    @MainActor
    func testNodeOnlyExportCarriesNoRulesAndIsCachedSeparatelyFromTheFullProfile() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = AppModel(persistence: PersistenceStore(fileURL: stateURL), arguments: [])
        model.nodes = [makeNode(name: "🇭🇰 香港", server: "hk.example.com")]

        let full = model.configuration(target: .shadowrocket, contentMode: .fullConfiguration)
        let nodesOnly = model.configuration(target: .shadowrocket, contentMode: .nodesOnly)

        XCTAssertGreaterThan(full.ruleCount, 0)
        XCTAssertEqual(nodesOnly.ruleCount, 0)
        XCTAssertNotEqual(full.content, nodesOnly.content)

        // Asking again in either order must keep serving the right document.
        XCTAssertEqual(
            model.configuration(target: .shadowrocket, contentMode: .fullConfiguration).content,
            full.content
        )
        XCTAssertEqual(
            model.configuration(target: .shadowrocket, contentMode: .nodesOnly).content,
            nodesOnly.content
        )
    }

    // MARK: - Coalesced writes

    @MainActor
    func testCoalescedPersistenceWritesOnceAndFlushesOnBackgrounding() async throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let store = PersistenceStore(fileURL: stateURL)
        let model = AppModel(
            persistence: store,
            persistencePolicy: .coalesced(.milliseconds(50)),
            arguments: []
        )
        model.nodes = (0..<3).map { makeNode(name: "节点 \($0)", server: "n\($0).example.com") }

        for node in model.nodes {
            model.setNode(node, included: false)
        }
        XCTAssertNil(try store.load(), "A burst of edits must not write once per edit")

        model.flushPendingWrite()
        let snapshot = try XCTUnwrap(try store.load())
        XCTAssertEqual(snapshot.excludedNodeIDs?.count, 3)
    }

    @MainActor
    func testCoalescedPersistenceDefersSnapshotConstructionUntilFlush() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            persistencePolicy: .coalesced(.seconds(30)),
            arguments: []
        )
        let node = makeNode(name: "节点", server: "node.example.com")
        model.nodes = [node]

        model.setNode(node, included: false)

        XCTAssertEqual(
            model.persistenceSnapshotBuildCount,
            0,
            "A coalesced edit must return before constructing the full snapshot"
        )

        model.flushPendingWrite()

        XCTAssertEqual(model.persistenceSnapshotBuildCount, 1)
    }
}
