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
            tcpProbe: { _, _, _ in 27 }
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

    @MainActor
    func testModesExcludeHTTPAndDefaultToAutomatic() {
        XCTAssertEqual(NodeLatencyTestMode.allCases, [.automatic, .icmp, .tcp])
        XCTAssertEqual(AppModel(arguments: ["--demo"]).selectedLatencyTestMode, .automatic)
    }

    func testUDPProtocolsNeverUseTCP() async throws {
        for kind in [ProxyKind.hysteria, .hysteria2, .tuic, .wireguard] {
            let node = ProxyNode(kind: kind, name: "UDP", server: "example.com", port: 443, rawURI: "")
            for reliable in [true, false] {
                let service = NodeLatencyService(
                    isICMPReliable: { _ in reliable },
                    icmpProbe: { _, _ in throw LatencyProbeError.timeout },
                    tcpProbe: { _, _, _ in
                        XCTFail("UDP-only protocols must not be probed with TCP")
                        return 1
                    }
                )
                for mode in NodeLatencyTestMode.allCases {
                    let result = try await service.measure(node, mode: mode)
                    XCTAssertNil(result.milliseconds)
                    XCTAssertNotNil(result.errorMessage)
                }
            }
            let service = NodeLatencyService(icmpProbe: { _, _ in 23 }, tcpProbe: { _, _, _ in
                XCTFail("Must keep the ICMP result")
                return 1
            })
            let result = try await service.measure(node)
            XCTAssertEqual(result.method, .icmp)
            XCTAssertEqual(result.milliseconds, 23)
        }
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
