import XCTest
@testable import Tower

/// Issue #41: URLComponents already percent-decodes the userinfo and query
/// values, so a second `removingPercentEncoding` rewrote or erased secrets that
/// contain a literal `%`.
final class ProxyCredentialPercentDecodingTests: XCTestCase {
    private let parser = SubscriptionParser()

    func testTrojanPasswordIsDecodedOnlyOnce() {
        XCTAssertEqual(parser.parseURI("trojan://abc%2541@example.org:443#JP")?.password, "abc%41")
        XCTAssertEqual(parser.parseURI("trojan://abc%25@example.org:443#JP")?.password, "abc%")
    }

    func testSocksCredentialsAreDecodedOnlyOnce() {
        let node = parser.parseURI("socks5://us%2541er:pa%25ss@example.org:1080#HK")

        XCTAssertEqual(node?.username, "us%41er")
        XCTAssertEqual(node?.password, "pa%ss")
    }

    func testHTTPCredentialsAreDecodedOnlyOnce() {
        let node = parser.parseURI("http://user:abc%2541@example.org:8080#US")

        XCTAssertEqual(node?.username, "user")
        XCTAssertEqual(node?.password, "abc%41")
    }

    func testTUICCredentialsAreDecodedOnlyOnce() {
        let uuid = "00000000-0000-4000-8000-000000000000"
        let node = parser.parseURI("tuic://\(uuid):abc%25@example.org:443?congestion_control=bbr#SG")

        XCTAssertEqual(node?.uuid, uuid)
        XCTAssertEqual(node?.password, "abc%")
    }

    func testTUICQueryPasswordIsDecodedOnlyOnce() {
        let uuid = "00000000-0000-4000-8000-000000000000"
        let node = parser.parseURI("tuic://example.org:443?uuid=\(uuid)&password=abc%2541#SG")

        XCTAssertEqual(node?.password, "abc%41")
    }

    func testOrdinaryPercentEncodedPasswordStillDecodes() {
        XCTAssertEqual(parser.parseURI("trojan://p%40ss%3Aword@example.org:443#JP")?.password, "p@ss:word")
    }
}
