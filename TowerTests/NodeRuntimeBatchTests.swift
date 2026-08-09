import XCTest
@testable import Tower

final class NodeRuntimeBatchTests: XCTestCase {
    private func nodes(count: Int) -> [ProxyNode] {
        (0..<count).map { index in
            ProxyNode(
                kind: .shadowsocks,
                name: "Node \(index)",
                server: "192.0.2.\(index + 1)",
                port: 443,
                cipher: "aes-128-gcm",
                password: "demo",
                rawURI: "ss://\(index)"
            )
        }
    }

    func testCountryResolutionCollectsAWholeNetworkBatchBeforePublishing() async {
        let nodes = nodes(count: 8)

        let batch = await NodeCountryResolutionBatch.resolve(nodes: nodes) { node in
            node.port == 443 ? "US" : nil
        }

        XCTAssertEqual(batch.completedIDs, Set(nodes.map(\.id)))
        XCTAssertEqual(batch.countryCodes.count, nodes.count)
        XCTAssertTrue(batch.countryCodes.values.allSatisfy { $0 == "US" })
    }

    func testLatencyResolutionKeepsFailuresInsideTheSameBatch() async {
        let nodes = nodes(count: 8)
        let failedID = nodes[3].id

        let batch = await NodeLatencyResultBatch.resolve(nodes: nodes) { node in
            guard node.id != failedID else { return nil }
            return .success(milliseconds: node.port, method: .tcp)
        }

        XCTAssertEqual(batch.completedIDs, Set(nodes.map(\.id)))
        XCTAssertEqual(batch.measurements.count, nodes.count - 1)
        XCTAssertNil(batch.measurements[failedID])
    }
}
