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
