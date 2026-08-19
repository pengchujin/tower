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

    func testExplicitTCPModeDoesNotAttemptICMP() async throws {
        let service = NodeLatencyService(
            icmpProbe: { _, _ in
                XCTFail("明确选择 TCP 时不应先探测 ICMP")
                throw LatencyProbeError.timeout
            },
            tcpProbe: { _, _, _ in 27 },
            httpProbe: { _, _ in
                XCTFail("明确选择 TCP 时不应探测 HTTP")
                throw LatencyProbeError.timeout
            }
        )
        let node = ProxyNode(
            kind: .trojan,
            name: "TCP",
            server: "tcp.example.com",
            port: 443,
            rawURI: "trojan://tcp"
        )

        let result = try await service.measure(node, mode: .tcp)

        XCTAssertEqual(result.method, .tcp)
        XCTAssertEqual(result.milliseconds, 27)
    }

    func testExplicitHTTPModeUsesHTTPProbe() async throws {
        let service = NodeLatencyService(
            icmpProbe: { _, _ in
                XCTFail("明确选择 HTTP 时不应探测 ICMP")
                throw LatencyProbeError.timeout
            },
            tcpProbe: { _, _, _ in
                XCTFail("明确选择 HTTP 时不应探测 TCP")
                throw LatencyProbeError.timeout
            },
            httpProbe: { node, _ in
                XCTAssertEqual(node.server, "web.example.com")
                return 46
            }
        )
        let node = ProxyNode(
            kind: .http,
            name: "HTTPS",
            server: "web.example.com",
            port: 443,
            tls: true,
            rawURI: "https://web.example.com"
        )

        let result = try await service.measure(node, mode: .http)

        XCTAssertEqual(result.method, .http)
        XCTAssertEqual(result.milliseconds, 46)
    }

    func testExplicitICMPModeFallsBackToTCPWhenVPNInterceptsTheRoute() async throws {
        let service = NodeLatencyService(
            isICMPReliable: { _ in false },
            icmpProbe: { _, _ in
                XCTFail("VPN 虚拟路由会本地代答 ICMP，不应采用其虚假延迟")
                return 1
            },
            tcpProbe: { _, _, _ in 43 }
        )
        let node = ProxyNode(
            kind: .vless,
            name: "VPN route",
            server: "vpn-routed.example.com",
            port: 443,
            rawURI: "vless://vpn-route"
        )

        let result = try await service.measure(node, mode: .icmp)

        XCTAssertEqual(result.method, .tcp)
        XCTAssertEqual(result.milliseconds, 43)
        XCTAssertNil(result.errorMessage)
    }

    func testAutomaticModeFallsBackToTCPWhenVPNInterceptsTheRoute() async throws {
        let service = NodeLatencyService(
            isICMPReliable: { _ in false },
            icmpProbe: { _, _ in 1 },
            tcpProbe: { _, _, _ in 51 }
        )
        let node = ProxyNode(
            kind: .trojan,
            name: "Automatic VPN route",
            server: "automatic-vpn.example.com",
            port: 443,
            rawURI: "trojan://automatic-vpn"
        )

        let result = try await service.measure(node)

        XCTAssertEqual(result.method, .tcp)
        XCTAssertEqual(result.milliseconds, 51)
    }
}
