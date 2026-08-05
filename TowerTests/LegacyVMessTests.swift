import XCTest
@testable import Tower

/// Some clients, Shadowrocket among them, do not use the base64-JSON form of a
/// vmess link. They base64 only `method:uuid@host:port` and put the options in
/// a query string, which the JSON parser rejected outright.
final class LegacyVMessTests: XCTestCase {
    private let parser = SubscriptionParser()

    /// base64 of `auto:5d1c3d8f-77b7-45c7-98c7-6fa54d37766e@203.0.113.9:53837`
    private let endpoint = "YXV0bzo1ZDFjM2Q4Zi03N2I3LTQ1YzctOThjNy02ZmE1NGQzNzc2NmVAMjAzLjAuMTEzLjk6NTM4Mzc"

    func testParsesEndpointOnlyForm() throws {
        let node = try XCTUnwrap(parser.parseURI("vmess://\(endpoint)"))

        XCTAssertEqual(node.kind, .vmess)
        XCTAssertEqual(node.server, "203.0.113.9")
        XCTAssertEqual(node.port, 53837)
        XCTAssertEqual(node.uuid, "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e")
        XCTAssertEqual(node.cipher, "auto")
    }

    func testRemarksBecomeTheNodeName() throws {
        let node = try XCTUnwrap(
            parser.parseURI("vmess://\(endpoint)?remarks=%E6%97%A5%E6%9C%AC%E9%98%BF%E9%87%8C%E4%BA%91&udp=1&alterId=0")
        )

        XCTAssertEqual(node.name, "日本阿里云")
        XCTAssertEqual(node.alterID, 0)
    }

    func testFallsBackToTheHostWhenUnnamed() throws {
        let node = try XCTUnwrap(parser.parseURI("vmess://\(endpoint)"))

        XCTAssertEqual(node.name, "203.0.113.9")
    }

    func testWebsocketObfsBecomesTheTransport() throws {
        let node = try XCTUnwrap(
            parser.parseURI("vmess://\(endpoint)?obfs=websocket&path=%2Fgw&obfsParam=a.example.com&tls=1&peer=a.example.com")
        )

        // This dialect names the transport obfs, not net.
        XCTAssertEqual(node.transport, "ws")
        XCTAssertEqual(node.path, "/gw")
        XCTAssertEqual(node.hostHeader, "a.example.com")
        XCTAssertEqual(node.sni, "a.example.com")
        XCTAssertTrue(node.tls)
    }

    func testPlainTransportStaysUnset() throws {
        let node = try XCTUnwrap(parser.parseURI("vmess://\(endpoint)?obfs=none"))

        XCTAssertNil(node.transport)
        XCTAssertFalse(node.tls)
    }

    func testUUIDWithoutMethodStillParses() throws {
        // base64 of `5d1c3d8f-77b7-45c7-98c7-6fa54d37766e@203.0.113.9:443`
        let bare = "NWQxYzNkOGYtNzdiNy00NWM3LTk4YzctNmZhNTRkMzc3NjZlQDIwMy4wLjExMy45OjQ0Mw"
        let node = try XCTUnwrap(parser.parseURI("vmess://\(bare)"))

        XCTAssertEqual(node.uuid, "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e")
        XCTAssertEqual(node.cipher, "auto")
    }

    // MARK: - The standard form must keep working

    func testBase64JSONFormIsUnaffected() throws {
        let json = #"{"v":"2","ps":"JSON 节点","add":"198.51.100.4","port":"443","id":"5d1c3d8f-77b7-45c7-98c7-6fa54d37766e","aid":"0","net":"ws","tls":"tls"}"#
        let link = "vmess://" + Data(json.utf8).base64EncodedString()

        let node = try XCTUnwrap(parser.parseURI(link))

        XCTAssertEqual(node.name, "JSON 节点")
        XCTAssertEqual(node.server, "198.51.100.4")
        XCTAssertEqual(node.transport, "ws")
        XCTAssertTrue(node.tls)
    }

    func testGarbageStillFails() {
        XCTAssertNil(parser.parseURI("vmess://not-valid-base64-at-all!!!"))
    }

    // MARK: - Add panel

    func testDetectorAcceptsTheLegacyForm() {
        XCTAssertEqual(
            SourceInputDetector().detect("vmess://\(endpoint)?remarks=x"),
            .node(.vmess)
        )
    }

    func testGeneratesForEveryTargetThatSupportsVMess() throws {
        let node = try XCTUnwrap(
            parser.parseURI("vmess://\(endpoint)?obfs=websocket&path=%2Fgw&tls=1")
        )

        for target in ClientTarget.allCases where target.supports(.vmess) {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            ).content
            XCTAssertTrue(content.contains("203.0.113.9"), "\(target.name) 没写出节点")
        }
    }
}
