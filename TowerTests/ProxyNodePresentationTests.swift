import XCTest
@testable import Tower

final class ProxyNodePresentationTests: XCTestCase {
    func testProtocolSummaryIncludesTransportSecurityAndUDP() {
        let node = ProxyNode(
            kind: .vmess,
            name: "Tokyo",
            server: "jp.example.com",
            port: 443,
            uuid: UUID().uuidString,
            transport: "ws",
            tls: true,
            rawURI: "vmess://test"
        )

        XCTAssertEqual(node.protocolSummary, "VMess / WS / TLS / UDP")
    }

    func testProtocolSummaryMatchesCommonProxyKinds() {
        XCTAssertEqual(node(kind: .shadowsocks).protocolSummary, "Shadowsocks / UDP")
        XCTAssertEqual(node(kind: .hysteria2, tls: true).protocolSummary, "Hysteria 2 / UDP")
        XCTAssertEqual(node(kind: .http, tls: true).protocolSummary, "HTTPS")
    }

    private func node(kind: ProxyKind, tls: Bool = false) -> ProxyNode {
        ProxyNode(
            kind: kind,
            name: "Test",
            server: "example.com",
            port: 443,
            password: "test",
            tls: tls,
            rawURI: "test://node"
        )
    }
}
