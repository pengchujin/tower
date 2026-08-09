import XCTest
@testable import Tower

final class SourceInputDetectorTests: XCTestCase {
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
