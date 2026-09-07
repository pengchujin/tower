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

    @MainActor
    func testFastResultPublishesBeforeSlowProbeCompletes() async {
        let nodes = nodes(count: 2)
        let fastID = nodes[0].id
        let gate = AsyncStream<Void>.makeStream()
        let published = expectation(description: "Fast result appears while slow probe is pending")
        var completed: Set<UUID> = []
        let task = Task {
            await NodeLatencyResultBatch.resolve(nodes: nodes, onProgress: { batch in
                completed.formUnion(batch.completedIDs)
                if batch.completedIDs.contains(fastID) { published.fulfill() }
            }) { node in
                if node.id != fastID { for await _ in gate.stream { break } }
                return .success(milliseconds: 80, method: .tcp)
            }
        }
        await fulfillment(of: [published], timeout: 2)
        XCTAssertEqual(completed, [fastID])
        gate.continuation.finish()
        _ = await task.value
        XCTAssertEqual(completed, Set(nodes.map(\.id)))
    }

    func testRollingPoolStartsNextProbeBeforeSlowFirstProbeFinishes() async {
        let nodes = nodes(count: 3)
        let firstID = nodes[0].id
        let lastID = nodes[2].id
        let gate = AsyncStream<Void>.makeStream()
        let nextStarted = expectation(description: "Third probe replaces completed second probe")
        let task = Task {
            await NodeLatencyResultBatch.resolve(nodes: nodes, concurrency: 2) { node in
                if node.id == firstID { for await _ in gate.stream { break } }
                if node.id == lastID { nextStarted.fulfill() }
                return .success(milliseconds: 80, method: .tcp)
            }
        }
        await fulfillment(of: [nextStarted], timeout: 2)
        gate.continuation.finish()
        let result = await task.value
        XCTAssertEqual(result.completedIDs.count, 3)
    }

    func testRollingPoolBoundsConcurrentProbesForThousandNodes() async {
        actor Counter {
            var active = 0
            var peak = 0
            func begin() { active += 1; peak = max(peak, active) }
            func end() { active -= 1 }
        }
        let counter = Counter()
        let batch = await NodeLatencyResultBatch.resolve(nodes: nodes(count: 1157)) { _ in
            await counter.begin()
            try? await Task.sleep(for: .milliseconds(2))
            await counter.end()
            return .success(milliseconds: 80, method: .icmp)
        }
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 32)
        XCTAssertGreaterThan(peak, 8)
        XCTAssertEqual(batch.measurements.count, 1157)
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
