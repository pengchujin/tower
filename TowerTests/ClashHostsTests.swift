import XCTest
@testable import Tower

/// Airports rotate entry domains through the profile's top-level `hosts:`.
/// Mihomo dials the remapped address, so the import must too.
final class ClashHostsTests: XCTestCase {
    private let profile = """
    mixed-port: 7890
    hosts:
      old-hk.example.com: new-hk.cdn-agent.example.net
      '+.legacy.example.org': 203.0.113.9
      list.example.com: [198.51.100.1, 198.51.100.2]
      block.example.com:
        - 198.51.100.7
      bad.example.com: "evil host\\nDOMAIN,x"
    proxies:
      - {name: "香港 AnyTLS", type: anytls, server: old-hk.example.com, port: 443, password: pw}
      - {name: "日本 WS", type: vmess, server: jp.legacy.example.org, port: 443, uuid: 5d1c3d8f-77b7-45c7-98c7-6fa54d37766e, alterId: 0, cipher: auto, tls: true, network: ws, ws-opts: {path: /ws}}
      - {name: "SNI 已设置", type: trojan, server: list.example.com, port: 443, password: pw, sni: custom.example.net}
      - {name: "块列表", type: anytls, server: block.example.com, port: 443, password: pw}
      - {name: "非法目标", type: anytls, server: bad.example.com, port: 443, password: pw}
      - {name: "未映射", type: anytls, server: other.example.com, port: 443, password: pw}
    proxy-groups: []
    """

    private func nodes() -> [String: ProxyNode] {
        let result = SubscriptionParser().parse(data: Data(profile.utf8), sourceID: UUID())
        return Dictionary(uniqueKeysWithValues: result.nodes.map { ($0.name, $0) })
    }

    func testRemapsServerAndPinsOriginalSNI() throws {
        let node = try XCTUnwrap(nodes()["香港 AnyTLS"])
        XCTAssertEqual(node.server, "new-hk.cdn-agent.example.net")
        XCTAssertEqual(node.sni, "old-hk.example.com")
        XCTAssertEqual(node.hostsSourceServer, "old-hk.example.com")
    }

    func testWildcardEntryAlsoPinsWebSocketHost() throws {
        let node = try XCTUnwrap(nodes()["日本 WS"])
        XCTAssertEqual(node.server, "203.0.113.9")
        XCTAssertEqual(node.sni, "jp.legacy.example.org")
        XCTAssertEqual(node.hostHeader, "jp.legacy.example.org")
    }

    func testKeepsExplicitSNIAndTakesFirstListEntry() throws {
        let all = nodes()
        let explicit = try XCTUnwrap(all["SNI 已设置"])
        XCTAssertEqual(explicit.server, "198.51.100.1")
        XCTAssertEqual(explicit.sni, "custom.example.net")
        XCTAssertEqual(try XCTUnwrap(all["块列表"]).server, "198.51.100.7")
    }

    func testIgnoresInvalidTargetsAndUnmappedServers() throws {
        let all = nodes()
        let invalid = try XCTUnwrap(all["非法目标"])
        XCTAssertEqual(invalid.server, "bad.example.com")
        XCTAssertNil(invalid.hostsSourceServer)
        let unmapped = try XCTUnwrap(all["未映射"])
        XCTAssertEqual(unmapped.server, "other.example.com")
        XCTAssertNil(unmapped.sni)
    }

    func testExclusionSurvivesRotatedEntryAddress() throws {
        var before = try XCTUnwrap(nodes()["香港 AnyTLS"])
        before.server = "old-hk.example.com"
        before.hostsSourceServer = nil
        let after = try XCTUnwrap(nodes()["香港 AnyTLS"])
        XCTAssertEqual(AppModel.nodeStableIdentity(before), AppModel.nodeStableIdentity(after))
    }
}
