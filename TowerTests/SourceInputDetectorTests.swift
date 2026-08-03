import XCTest
@testable import Tower

final class SourceInputDetectorTests: XCTestCase {
    func testDetectsHTTPSSubscription() {
        XCTAssertEqual(
            SourceInputDetector().detect("https://example.com/api/v1/client/subscribe?token=secret"),
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

    func testRejectsArbitraryClipboardText() {
        XCTAssertEqual(SourceInputDetector().detect("hello tower"), .unknown)
    }
}
