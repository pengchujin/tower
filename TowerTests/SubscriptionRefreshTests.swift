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
    func testPullToRefreshStopsAfterFirstFailedSubscription() async throws {
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let failing = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let neverRequested = SubscriptionSource(name: "三", urlString: "https://three.example/sub")
        let fetcher = RefreshRecordingFetcher(failingID: failing.id)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: storeURL),
            subscriptionService: fetcher,
            arguments: []
        )
        model.subscriptions = [first, failing, neverRequested]

        await model.refreshEnabledSubscriptions()

        let requestedIDs = await fetcher.requestedIDs
        XCTAssertEqual(requestedIDs, [first.id, failing.id])
        XCTAssertEqual(model.subscriptions[1].lastError, RefreshTestError.rejected.localizedDescription)
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
