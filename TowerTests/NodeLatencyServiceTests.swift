import XCTest
@testable import Tower

final class NodeLatencyServiceTests: XCTestCase {
    func testLocalhostReturnsRealICMPLatency() async throws {
        let service = NodeLatencyService(icmpTimeout: 1, tcpTimeout: 0.1)
        let node = ProxyNode(
            kind: .socks5,
            name: "Local ICMP",
            server: "127.0.0.1",
            port: 9,
            rawURI: "socks5://127.0.0.1:9"
        )

        let result = try await service.measure(node)

        XCTAssertEqual(result.method, .icmp)
        XCTAssertNotNil(result.milliseconds)
        XCTAssertNil(result.errorMessage)
    }

    func testFallsBackToTCPWhenICMPIsBlocked() async throws {
        let service = NodeLatencyService(
            icmpProbe: { _, _ in throw LatencyProbeError.timeout },
            tcpProbe: { _, _, _ in 38 }
        )
        let node = ProxyNode(
            kind: .trojan,
            name: "Fallback",
            server: "fallback.example.com",
            port: 443,
            rawURI: "trojan://fallback"
        )

        let result = try await service.measure(node)

        XCTAssertEqual(result.method, .tcp)
        XCTAssertEqual(result.milliseconds, 38)
        XCTAssertNil(result.errorMessage)
    }
}
