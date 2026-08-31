import XCTest
@testable import Tower

final class NodeSelectionTests: XCTestCase {
    @MainActor
    func testSubscriptionInfoNodesAreVisibleByDefaultAndCanBeFiltered() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-info-filter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let source = SubscriptionSource(name: "机场", urlString: "https://example.com/sub")
        let normal = ProxyNode(
            sourceID: source.id, kind: .shadowsocks, name: "香港 01",
            server: "hk.example.com", port: 443, rawURI: "ss://normal"
        )
        let info = ProxyNode(
            sourceID: source.id, kind: .shadowsocks, name: "剩余流量：10 GB",
            server: "1.1.1.1", port: 1, rawURI: "ss://info",
            isSubscriptionMetadata: true
        )
        try store.save(AppSnapshot(
            subscriptions: [source], nodes: [normal, info],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))

        let model = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(model.availableNodes.count, 2)

        model.setFilterSubscriptionInfoNodes(true)
        XCTAssertEqual(model.availableNodes.map(\.id), [normal.id])
        XCTAssertEqual(try store.load()?.filterSubscriptionInfoNodes, true)
    }

    @MainActor
    func testSubscriptionInfoSettingControlsNodeOnlyExportWithoutCreatingSkippedNodes() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-info-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let normal = ProxyNode(
            kind: .shadowsocks, name: "香港 01", server: "hk.example.com", port: 443,
            cipher: "aes-128-gcm", password: "secret", rawURI: "ss://normal"
        )
        let info = ProxyNode(
            kind: .shadowsocks, name: "剩余流量：10 GB", server: "1.1.1.1", port: 1,
            cipher: "aes-128-gcm", password: "notice", rawURI: "ss://info",
            isSubscriptionMetadata: true
        )
        try store.save(AppSnapshot(
            subscriptions: [], nodes: [normal, info],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .hiddify
        ))
        let model = AppModel(persistence: store, arguments: [])

        let visible = model.configuration(target: .hiddify, contentMode: .nodesOnly)
        XCTAssertEqual(visible.supportedNodeCount, 2)
        XCTAssertEqual(visible.skippedNodeCount, 0)

        model.setFilterSubscriptionInfoNodes(true)
        let filtered = model.configuration(target: .hiddify, contentMode: .nodesOnly)
        XCTAssertEqual(filtered.supportedNodeCount, 1)
        XCTAssertEqual(filtered.skippedNodeCount, 0)
    }

    @MainActor
    func testSubscriptionNameCanBeAppendedWithoutChangingStoredNode() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-source-suffix-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let source = SubscriptionSource(name: "云帆", urlString: "https://example.com/sub")
        let node = ProxyNode(
            sourceID: source.id, kind: .shadowsocks, name: "香港 01",
            server: "hk.example.com", port: 443, rawURI: "ss://node"
        )
        try store.save(AppSnapshot(
            subscriptions: [source], nodes: [node],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        model.setAppendSubscriptionNameToNodes(true)

        XCTAssertEqual(model.nodeForPresentation(node).name, "香港 01 · 云帆")
        XCTAssertEqual(model.nodes.first?.name, "香港 01")
        XCTAssertTrue(model.configuration().content.contains("香港 01 · 云帆"))
    }

    @MainActor
    func testExcludedNodesStayManagedButAreNotGeneratedAndPersist() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-node-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let source = SubscriptionSource(name: "机场", urlString: "https://example.com/sub")
        let node = ProxyNode(
            sourceID: source.id,
            kind: .shadowsocks,
            name: "香港 01",
            server: "hk.example.com",
            port: 443,
            cipher: "aes-128-gcm",
            password: "secret",
            rawURI: "ss://example"
        )
        try store.save(AppSnapshot(
            subscriptions: [source],
            nodes: [node],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge
        ))

        let model = AppModel(persistence: store, arguments: [])
        model.setNode(node, included: false)

        XCTAssertEqual(model.availableNodes.map(\.id), [node.id])
        XCTAssertTrue(model.enabledNodes.isEmpty)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertFalse(reloaded.isNodeIncluded(node))
        XCTAssertTrue(reloaded.enabledNodes.isEmpty)
    }

    @MainActor
    func testBulkNodeSelectionChangesAllVisibleNodesAndPersistsOnce() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-bulk-node-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let nodes = (1...3).map { index in
            ProxyNode(
                kind: .shadowsocks,
                name: "节点 \(index)",
                server: "node-\(index).example.com",
                port: 443,
                rawURI: "ss://\(index)"
            )
        }
        try store.save(AppSnapshot(
            subscriptions: [],
            nodes: nodes,
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        model.setNodes(Array(nodes.prefix(2)), included: false)
        XCTAssertEqual(model.enabledNodes.map(\.id), [nodes[2].id])

        model.setNodes(Array(nodes.prefix(2)), included: true)
        XCTAssertEqual(Set(model.enabledNodes.map(\.id)), Set(nodes.map(\.id)))
        XCTAssertNil(try store.load()?.excludedNodeIDs)
    }
}
