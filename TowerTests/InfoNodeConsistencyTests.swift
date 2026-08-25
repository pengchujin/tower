import XCTest
@testable import Tower

/// "过滤订阅节点信息" is one switch with one meaning. Whatever it decides has to
/// hold on the subscription card, in the node filter and in the exported
/// configuration alike — a card that reports fewer nodes than it exports hides
/// exactly the rows worth deleting.
@MainActor
final class InfoNodeConsistencyTests: XCTestCase {
    func testCardCountMatchesTheExportedNodesWhileTheFilterIsOff() throws {
        let model = try makeModel()
        let source = try XCTUnwrap(model.subscriptions.first)

        XCTAssertFalse(model.filterSubscriptionInfoNodes)
        XCTAssertEqual(model.nodeCount(for: source), 2)
        XCTAssertEqual(model.nodes(for: source).count, 2)
        XCTAssertEqual(model.availableNodes.count, 2)
        XCTAssertEqual(model.enabledNodes.count, 2)
    }

    func testTurningTheFilterOnHidesTheNoticeEverywhereAtOnce() throws {
        let model = try makeModel()
        let source = try XCTUnwrap(model.subscriptions.first)

        model.setFilterSubscriptionInfoNodes(true)

        XCTAssertEqual(model.nodeCount(for: source), 1)
        XCTAssertEqual(model.nodes(for: source).map(\.name), ["🇭🇰 香港 01"])
        XCTAssertEqual(model.availableNodes.count, 1)
        XCTAssertEqual(model.enabledNodes.count, 1)
    }

    private func makeModel() throws -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-info-node-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: stateURL) }

        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            arguments: []
        )
        let source = SubscriptionSource(name: "机场", urlString: "https://airport.example/sub")
        model.subscriptions = [source]
        model.nodes = [
            ProxyNode(
                sourceID: source.id,
                kind: .shadowsocks,
                name: "🇭🇰 香港 01",
                server: "hk.example.com",
                port: 8388,
                cipher: "aes-128-gcm",
                password: "pw",
                rawURI: "ss://hk"
            ),
            ProxyNode(
                sourceID: source.id,
                kind: .shadowsocks,
                name: "剩余流量：101.69 GB",
                server: "8.8.8.8",
                port: 8,
                cipher: "aes-128-gcm",
                password: "pw",
                rawURI: "ss://notice",
                isSubscriptionMetadata: true
            ),
        ]
        return model
    }
}
