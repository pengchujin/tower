import XCTest
@testable import Tower

final class ProxyNodeShareLinkGeneratorTests: XCTestCase {
    func testKeepsOriginalProtocolLink() {
        let original = "trojan://secret@example.com:443?sni=example.com#Tokyo"
        let node = ProxyNode(
            kind: .trojan,
            name: "Tokyo",
            server: "example.com",
            port: 443,
            password: "secret",
            tls: true,
            rawURI: original
        )

        XCTAssertEqual(ProxyNodeShareLinkGenerator().link(for: node), original)
    }

    func testRebuildsClashShadowsocksNodeAsParsableLink() {
        let node = ProxyNode(
            kind: .shadowsocks,
            name: "Hong Kong",
            server: "hk.example.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "secret",
            rawURI: "clash://local/example"
        )

        let link = ProxyNodeShareLinkGenerator().link(for: node)
        let reparsed = SubscriptionParser().parseURI(link)

        XCTAssertTrue(link.hasPrefix("ss://"))
        XCTAssertEqual(reparsed?.kind, .shadowsocks)
        XCTAssertEqual(reparsed?.server, node.server)
        XCTAssertEqual(reparsed?.password, node.password)
    }

    func testRebuildsClashVMessNodeAsParsableLink() {
        let node = ProxyNode(
            kind: .vmess,
            name: "Tokyo",
            server: "jp.example.com",
            port: 443,
            cipher: "auto",
            uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            transport: "ws",
            tls: true,
            hostHeader: "jp.example.com",
            path: "/gateway",
            rawURI: "clash://local/example"
        )

        let link = ProxyNodeShareLinkGenerator().link(for: node)
        let reparsed = SubscriptionParser().parseURI(link)

        XCTAssertTrue(link.hasPrefix("vmess://"))
        XCTAssertEqual(reparsed?.kind, .vmess)
        XCTAssertEqual(reparsed?.transport, "ws")
        XCTAssertEqual(reparsed?.path, "/gateway")
    }
}
