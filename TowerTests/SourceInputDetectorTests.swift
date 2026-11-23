import XCTest
@testable import Tower

final class SourceInputDetectorTests: XCTestCase {
    func testDetectsAllCanonicalNodeProtocolsAndAliases() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let detector = SourceInputDetector()
        for kind in ProxyKind.allCases where kind != .unknown {
            let node = ProxyNode(kind: kind, name: "Fixture", server: "example.com", port: 443,
                cipher: "aes-128-gcm", password: "fixture", uuid: "11111111-1111-4111-8111-111111111111",
                username: "fixture", tls: false, protocolName: "origin", obfs: "plain",
                wireGuardPrivateKey: key, wireGuardPublicKey: key,
                wireGuardIPv4: "10.0.0.2/32", wireGuardAllowedIPs: "0.0.0.0/0", rawURI: "")
            let link = ProxyNodeShareLinkGenerator().canonicalLink(for: node)
            XCTAssertEqual(detector.detect(link), .node(kind), "\(kind)")
            if kind == .wireguard {
                XCTAssertEqual(detector.detect(link.replacingOccurrences(of: "wireguard://", with: "wg://")), .node(.wireguard))
                XCTAssertEqual(detector.detect("  \(link)\n"), .node(.wireguard))
                XCTAssertEqual(detector.detect(link + "\n" + link.replacingOccurrences(of: "example.com", with: "second.example.com")), .nodeBatch(count: 2))
            }
            for (original, alias) in [("hysteria2://", "hy2://"), ("hysteria://", "hy://"), ("socks5://", "socks://")] where link.hasPrefix(original) {
                XCTAssertEqual(detector.detect(link.replacingOccurrences(of: original, with: alias)), .node(kind))
            }
        }
        XCTAssertEqual(detector.detect("wg://"), .unknown)
        XCTAssertEqual(detector.detect("unrecognized://example.com"), .unknown)
    }

    func testDetectsHTTPSSubscription() {
        XCTAssertEqual(
            SourceInputDetector().detect("https://example.com/api/v1/client/subscribe?token=secret"),
            .subscription
        )
    }

    func testDetectsHTTPSubscriptionWithAPath() {
        XCTAssertEqual(
            SourceInputDetector().detect("http://192.168.1.105:65171/sub/private-token?target=auto"),
            .subscription
        )
    }

    func testDetectsProtocolNode() {
        let auth = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        XCTAssertEqual(
            SourceInputDetector().detect("ss://\(auth)@hk.example.com:8388#HK"),
            .node(.shadowsocks)
        )
    }

    func testDetectsHTTPProxyWithPort() {
        XCTAssertEqual(
            SourceInputDetector().detect("http://proxy.example.com:8080"),
            .node(.http)
        )
    }

    func testDetectsHTTPSProxyWithoutCredentialsWhenItHasAnExplicitName() {
        XCTAssertEqual(
            SourceInputDetector().detect("https://proxy.example.com:8443#Office"),
            .node(.http)
        )
    }

    func testDetectsBareHTTPSProxyWithExplicitPortAsNode() {
        let detector = SourceInputDetector()
        XCTAssertEqual(detector.detect("https://proxy.example.com:8443"), .node(.http))
        XCTAssertEqual(detector.detect("https://203.0.113.7:443"), .node(.http))
        XCTAssertEqual(
            detector.detect("https://one.example.com:8443\nhttps://two.example.com:8443"),
            .nodeBatch(count: 2)
        )
        XCTAssertTrue(detector.subscriptionURLs("https://proxy.example.com:8443").isEmpty)
    }

    func testKeepsHTTPSURLsWithAPathOrQueryAsSubscriptions() {
        let detector = SourceInputDetector()
        XCTAssertEqual(detector.detect("https://sub.example.com:2096?token=secret"), .subscription)
        XCTAssertEqual(detector.detect("https://sub.example.com:8443/"), .subscription)
        XCTAssertEqual(detector.detect("https://sub.example.com/link/abc"), .subscription)
        XCTAssertEqual(detector.detect("https://sub.example.com"), .subscription)
    }

    func testDetectsHTTPSProxyWithImplicitDefaultPort() {
        XCTAssertEqual(
            SourceInputDetector().detect("https://alice:secret@proxy.example.com#Office"),
            .node(.http)
        )
    }

    func testDetectsShadowrocketBase64HTTPSProxy() {
        let authority = Data("alice:secret@proxy.example.com:443".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let link = "https://\(authority)?remarks=Office"
        let detector = SourceInputDetector()
        XCTAssertEqual(detector.detect(link), .node(.http))
        XCTAssertTrue(detector.subscriptionURLs(link).isEmpty)
    }

    func testDetectsMultipleProtocolLinksAsABatch() {
        let auth = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        let value = """
        ss://\(auth)@hk.example.com:8388#HK
        trojan://secret@jp.example.com:443#JP
        """

        XCTAssertEqual(SourceInputDetector().detect(value), .nodeBatch(count: 2))
    }

    func testDetectsMultipleHTTPSSubscriptionsAsABatch() {
        let value = """
        https://one.example/sub/token-a
        https://two.example/api/subscribe?token=b
        https://three.example/client/subscription/c
        """

        XCTAssertEqual(SourceInputDetector().detect(value), .subscriptionBatch(count: 3))
    }

    func testExtractsMixedHTTPAndHTTPSSubscriptionsAsABatch() {
        let value = """
        http://192.168.1.105:65171/sub/local-token?target=auto
        https://airport.example/api/subscribe?token=remote-token
        """

        XCTAssertEqual(SourceInputDetector().detect(value), .subscriptionBatch(count: 2))
        XCTAssertEqual(
            SourceInputDetector().subscriptionURLs(value),
            [
                "http://192.168.1.105:65171/sub/local-token?target=auto",
                "https://airport.example/api/subscribe?token=remote-token"
            ]
        )
    }

    func testRejectsArbitraryClipboardText() {
        XCTAssertEqual(SourceInputDetector().detect("hello tower"), .unknown)
    }
}
