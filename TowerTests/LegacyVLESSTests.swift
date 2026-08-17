import XCTest
@testable import Tower

/// Shadowrocket base64-encodes only `uuid@host:port` for some VLESS links and
/// leaves its REALITY options in a readable query string.
final class LegacyVLESSTests: XCTestCase {
    private let parser = SubscriptionParser()

    private var link: String {
        let endpoint = ":b831381d-6324-4d53-ad4f-8cda48b30811@edge.example.net:12001"
        let encoded = Data(endpoint.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "vless://\(encoded)"
            + "?remarks=%F0%9F%87%B9%F0%9F%87%BC%20Taiwan%2001"
            + "&tls=1&peer=cdn.example.com&udp=1&xtls=2"
            + "&pbk=TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            + "&sid=0123456789abcdef&fingerprint=chrome"
    }

    func testParsesBase64EncodedEndpoint() throws {
        let node = try XCTUnwrap(parser.parseURI(link))

        XCTAssertEqual(node.kind, .vless)
        XCTAssertEqual(node.server, "edge.example.net")
        XCTAssertEqual(node.port, 12001)
        XCTAssertEqual(node.uuid, "b831381d-6324-4d53-ad4f-8cda48b30811")
        XCTAssertEqual(node.name, "🇹🇼 Taiwan 01")
    }

    func testParsesAutoPrefixedBase64Endpoint() throws {
        let endpoint = "auto:b831381d-6324-4d53-ad4f-8cda48b30811@edge.example.net:12001"
        let encoded = Data(endpoint.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let node = try XCTUnwrap(parser.parseURI("vless://\(encoded)"))

        XCTAssertEqual(node.uuid, "b831381d-6324-4d53-ad4f-8cda48b30811")
        XCTAssertEqual(node.exportableUUID, "b831381d-6324-4d53-ad4f-8cda48b30811")
    }

    func testPreservesShadowrocketRealityOptions() throws {
        let node = try XCTUnwrap(parser.parseURI(link))

        XCTAssertTrue(node.tls)
        XCTAssertTrue(node.usesReality)
        XCTAssertEqual(node.realityPublicKey, "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(node.realityShortID, "0123456789abcdef")
        XCTAssertEqual(node.sni, "cdn.example.com")
        XCTAssertEqual(node.fingerprint, "chrome")
        XCTAssertEqual(node.flow, "xtls-rprx-vision")
    }

    func testAddPanelRecognizesTheLinkAsVLESS() {
        XCTAssertEqual(SourceInputDetector().detect(link), .node(.vless))
    }
}
