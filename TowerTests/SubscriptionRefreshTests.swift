import XCTest
@testable import Tower

private enum RefreshTestError: Error {
    case rejected
}

private actor RefreshRecordingFetcher: SubscriptionFetching {
    private let failingID: UUID
    private(set) var requestedIDs: [UUID] = []

    init(failingID: UUID) {
        self.failingID = failingID
    }

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        requestedIDs.append(source.id)
        if source.id == failingID { throw RefreshTestError.rejected }
        return ImportResult(nodes: [], rejectedLineCount: 0, usage: nil)
    }
}

private actor BatchSubscriptionFetcher: SubscriptionFetching {
    private(set) var requestedURLs: [String] = []

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        requestedURLs.append(source.urlString)
        return ImportResult(
            nodes: [
                ProxyNode(
                    sourceID: source.id,
                    kind: .shadowsocks,
                    name: source.name,
                    server: source.safeHost,
                    port: 443,
                    password: "test",
                    rawURI: "ss://test"
                )
            ],
            rejectedLineCount: 0,
            usage: nil
        )
    }
}

private actor RateLimitedSubscriptionFetcher: SubscriptionFetching {
    private var activeRequestCount = 0
    private(set) var maximumActiveRequestCount = 0
    private(set) var requestedIDs: [UUID] = []

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        activeRequestCount += 1
        maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)
        requestedIDs.append(source.id)
        defer { activeRequestCount -= 1 }

        try await Task.sleep(for: .milliseconds(30))
        return ImportResult(nodes: [], rejectedLineCount: 0, usage: nil)
    }
}

private actor CancellationSensitiveFetcher: SubscriptionFetching {
    private(set) var requestedIDs: [UUID] = []

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        requestedIDs.append(source.id)
        try await Task.sleep(for: .milliseconds(60))
        try Task.checkCancellation()
        return ImportResult(nodes: [], rejectedLineCount: 0, usage: nil)
    }
}

private actor OverlappingRefreshFetcher: SubscriptionFetching {
    private let failingIDs: Set<UUID>
    private(set) var requestedIDs: [UUID] = []
    private(set) var cancellationCount = 0

    init(failingIDs: Set<UUID> = []) {
        self.failingIDs = failingIDs
    }

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        requestedIDs.append(source.id)
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            cancellationCount += 1
            throw error
        }
        if failingIDs.contains(source.id) { throw RefreshTestError.rejected }
        return ImportResult(nodes: [], rejectedLineCount: 0, usage: nil)
    }
}

private struct NamedSubscriptionFetcher: SubscriptionFetching {
    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        ImportResult(
            nodes: [
                ProxyNode(
                    sourceID: source.id,
                    kind: .shadowsocks,
                    name: "香港 01",
                    server: "hk.example.com",
                    port: 443,
                    rawURI: "ss://node"
                )
            ],
            rejectedLineCount: 0,
            usage: nil,
            suggestedName: "云帆官方"
        )
    }
}

@MainActor
final class SubscriptionRefreshTests: XCTestCase {
    /// Speed comes from hitting different providers at once. Hitting one
    /// provider several times at once is the thing that gets rate-limited, and
    /// a 429 costs more than the wait it saved.
    func testRefreshRunsProvidersInParallelAndOneProviderInOrder() {
        let a1 = SubscriptionSource(name: "A1", urlString: "https://panel.a.example/sub?token=1")
        let b = SubscriptionSource(name: "B", urlString: "https://panel.b.example/sub")
        let a2 = SubscriptionSource(name: "A2", urlString: "https://panel.a.example/sub?token=2")
        let sources = [a1, b, a2]

        let lanes = AppModel.subscriptionIDsGroupedByHost(sources.map(\.id), in: sources)

        XCTAssertEqual(lanes.count, 2, "两个机场应该并行，不该被压成一条队列")
        XCTAssertEqual(lanes[0], [a1.id, a2.id], "同一机场必须排队，并保持用户排的顺序")
        XCTAssertEqual(lanes[1], [b.id])
    }

    /// Case and port-less/ported spellings of the same panel are still one
    /// panel, and one panel is one lane.
    func testHostLanesIgnoreCase() {
        let upper = SubscriptionSource(name: "1", urlString: "https://Panel.A.Example/sub")
        let lower = SubscriptionSource(name: "2", urlString: "https://panel.a.example/other")
        let sources = [upper, lower]

        let lanes = AppModel.subscriptionIDsGroupedByHost(sources.map(\.id), in: sources)

        XCTAssertEqual(lanes, [[upper.id, lower.id]])
    }

    /// Two URLs that will not parse are not evidence of a shared server, so
    /// they must not be serialised behind each other.
    func testUnparseableURLsDoNotShareALane() {
        let first = SubscriptionSource(name: "1", urlString: "")
        let second = SubscriptionSource(name: "2", urlString: "   ")
        let sources = [first, second]

        let lanes = AppModel.subscriptionIDsGroupedByHost(sources.map(\.id), in: sources)

        XCTAssertEqual(lanes.count, 2)
    }

    func testPullToRefreshFinishesQueueWhenSwiftUICancelsGestureTask() async throws {
        let sources = (1...3).map {
            SubscriptionSource(name: "\($0)", urlString: "https://\($0).example/sub")
        }
        let fetcher = CancellationSensitiveFetcher()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-cancelled-gesture-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = sources

        let gestureTask = Task { await model.refreshAllSubscriptions() }
        try await Task.sleep(for: .milliseconds(80))
        gestureTask.cancel()
        _ = await gestureTask.value

        let deadline = ContinuousClock.now + .seconds(2)
        while model.subscriptions.contains(where: { $0.lastUpdatedAt == nil }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let requestedIDs = await fetcher.requestedIDs
        XCTAssertEqual(Set(requestedIDs), Set(sources.map(\.id)))
        XCTAssertTrue(model.subscriptions.allSatisfy { $0.lastUpdatedAt != nil })
    }

    func testSelectedRefreshJoinsOverlappingFullRefreshWithoutDuplicateFetch() async throws {
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let fetcher = OverlappingRefreshFetcher()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-overlapping-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = [first, second]

        let fullRefresh = Task { await model.refreshAllSubscriptions() }
        try await Task.sleep(for: .milliseconds(20))
        let selectedRefresh = Task { await model.refreshSubscriptions([first]) }
        await fullRefresh.value
        await selectedRefresh.value

        let requestedIDs = await fetcher.requestedIDs
        XCTAssertEqual(requestedIDs.filter { $0 == first.id }.count, 1)
        XCTAssertEqual(requestedIDs.filter { $0 == second.id }.count, 1)
        XCTAssertTrue(model.toast?.text.contains("2 个订阅已全部更新") == true)
    }

    func testJoiningFailedRefreshDoesNotReportFalseSuccess() async throws {
        let source = SubscriptionSource(name: "失败源", urlString: "https://fail.example/sub")
        let fetcher = OverlappingRefreshFetcher(failingIDs: [source.id])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-overlapping-failure-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = [source]

        let fullRefresh = Task { await model.refreshAllSubscriptions() }
        try await Task.sleep(for: .milliseconds(20))
        let selectedRefresh = Task { await model.refreshSubscriptions([source]) }
        await fullRefresh.value
        await selectedRefresh.value

        let requestedIDs = await fetcher.requestedIDs
        XCTAssertEqual(requestedIDs, [source.id])
        XCTAssertNil(model.toast)
        XCTAssertEqual(model.subscriptionRefreshReport?.succeededCount, 0)
        XCTAssertEqual(model.subscriptionRefreshReport?.failures.map(\.sourceName), ["失败源"])
    }

    func testResetCancelsEveryInFlightSubscriptionRefresh() async throws {
        let source = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let fetcher = OverlappingRefreshFetcher()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = [source]

        let refresh = Task { await model.refreshAllSubscriptions() }
        while await fetcher.requestedIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        await model.resetAllConfiguration()
        await refresh.value

        let cancellationCount = await fetcher.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertTrue(model.subscriptions.isEmpty)
        XCTAssertTrue(model.refreshingSourceIDs.isEmpty)
    }

    func testPullToRefreshStartsEverySubscriptionRequestConcurrently() async throws {
        let sources = (1...7).map {
            SubscriptionSource(name: "\($0)", urlString: "https://\($0).example/sub")
        }
        let fetcher = RateLimitedSubscriptionFetcher()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rate-limited-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = sources

        await model.refreshAllSubscriptions()

        let requestedIDs = await fetcher.requestedIDs
        let maximumActiveRequestCount = await fetcher.maximumActiveRequestCount

        XCTAssertEqual(Set(requestedIDs), Set(sources.map(\.id)))
        XCTAssertEqual(maximumActiveRequestCount, sources.count)
        XCTAssertTrue(model.subscriptions.allSatisfy { $0.lastUpdatedAt != nil })
        XCTAssertTrue(model.toast?.text.contains("7 个订阅已全部更新") == true)
    }

    func testPullToRefreshContinuesAfterOneSubscriptionFails() async throws {
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let failing = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let finalSource = SubscriptionSource(
            name: "三",
            urlString: "https://three.example/sub",
            isEnabled: false
        )
        let fetcher = RefreshRecordingFetcher(failingID: failing.id)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = [first, failing, finalSource]

        await model.refreshAllSubscriptions()

        let requestedIDs = await fetcher.requestedIDs
        XCTAssertEqual(Set(requestedIDs), Set([first.id, failing.id, finalSource.id]))
        XCTAssertEqual(model.subscriptions[1].lastError, RefreshTestError.rejected.localizedDescription)
        XCTAssertNotNil(model.subscriptions[2].lastUpdatedAt)
        XCTAssertFalse(model.subscriptions[2].isEnabled, "Refreshing must not change whether the source participates in conversion")
        XCTAssertNil(model.toast, "Partial failure details belong in the result sheet, not a transient toast")
        XCTAssertEqual(model.subscriptionRefreshReport?.succeededCount, 2)
        XCTAssertEqual(model.subscriptionRefreshReport?.failures.map(\.sourceName), ["二"])
        XCTAssertEqual(model.subscriptionRefreshReport?.failures.first?.message, RefreshTestError.rejected.localizedDescription)
    }

    func testBatchAddImportsEverySubscriptionInOneOperation() async throws {
        let fetcher = BatchSubscriptionFetcher()
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-batch-add-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        let urls = [
            "https://one.example/sub/a",
            "https://two.example/sub/b",
            "https://three.example/sub/c"
        ]

        try await model.addSubscriptions(name: "", urlStrings: urls)

        let requestedURLs = await fetcher.requestedURLs
        XCTAssertEqual(requestedURLs, urls)
        XCTAssertEqual(model.subscriptions.count, 3)
        XCTAssertEqual(model.nodes.count, 3)
        XCTAssertEqual(Set(model.subscriptions.map(\.name)), ["one", "two", "three"])
    }

    func testAutomaticDomainNameYieldsToProviderTitleButTypedNameDoesNot() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-provider-name-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: fileURL),
            subscriptionService: NamedSubscriptionFetcher(),
            arguments: []
        )

        try await model.addSubscription(name: "", urlString: "https://sub.example.com/token")
        try await model.addSubscription(name: "我的机场", urlString: "https://another.example.com/token")

        XCTAssertEqual(model.subscriptions[0].name, "云帆官方")
        XCTAssertEqual(model.subscriptions[1].name, "我的机场")
    }
}
