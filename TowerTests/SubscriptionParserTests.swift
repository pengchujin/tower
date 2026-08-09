import XCTest
@testable import Tower

final class SubscriptionParserTests: XCTestCase {
    func testParsesBase64EncodedURIList() throws {
        let auth = Data("chacha20-ietf-poly1305:secret".utf8).base64EncodedString()
        let ss = "ss://\(auth)@hk.example.com:8388#Hong%20Kong"
        let vmessJSON: [String: Any] = [
            "v": "2",
            "ps": "Tokyo",
            "add": "jp.example.com",
            "port": "443",
            "id": "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            "aid": "0",
            "net": "ws",
            "tls": "tls",
            "host": "jp.example.com",
            "path": "/gateway"
        ]
        let vmessData = try JSONSerialization.data(withJSONObject: vmessJSON)
        let vmess = "vmess://\(vmessData.base64EncodedString())"
        let subscription = Data("\(ss)\n\(vmess)".utf8).base64EncodedString()
        let sourceID = UUID()

        let result = SubscriptionParser().parse(data: Data(subscription.utf8), sourceID: sourceID)

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.nodes.map(\.kind), [.shadowsocks, .vmess])
        XCTAssertEqual(result.nodes[0].name, "Hong Kong")
        XCTAssertEqual(result.nodes[1].transport, "ws")
        XCTAssertTrue(result.nodes.allSatisfy { $0.sourceID == sourceID })
    }

    func testParsesClashInlineAndBlockNodes() {
        let yaml = """
        proxies:
          - { name: "HK SS", type: ss, server: hk.example.com, port: 8388, cipher: aes-256-gcm, password: secret }
          - name: Tokyo Trojan
            type: trojan
            server: jp.example.com
            port: 443
            password: secret
            sni: jp.example.com
        proxy-groups:
          - name: Proxy
        """

        let result = SubscriptionParser().parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.nodes[0].name, "HK SS")
        XCTAssertEqual(result.nodes[0].cipher, "aes-256-gcm")
        XCTAssertEqual(result.nodes[1].kind, .trojan)
        XCTAssertEqual(result.nodes[1].sni, "jp.example.com")
    }

    func testRejectsUnknownNodeScheme() {
        let result = SubscriptionParser().parse(data: Data("unknown://example.com:443".utf8))
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertEqual(result.rejectedLineCount, 1)
    }

    func testParsesBase64SubscriptionContainingOnlyHTTPAndSocksNodes() {
        let links = """
        https://user:password@secure.example.com:443#HTTPS
        socks://user:password@socks.example.com:1080#SOCKS
        """
        let subscription = Data(links.utf8).base64EncodedString()

        let result = SubscriptionParser().parse(data: Data(subscription.utf8))

        XCTAssertEqual(result.nodes.map(\.kind), [.http, .socks5])
        XCTAssertTrue(result.nodes[0].tls)
        XCTAssertEqual(result.nodes[1].username, "user")
    }

    func testParsesNestedClashWebSocketOptionsCaseInsensitively() {
        let yaml = """
        proxies:
          - name: Tokyo VMess
            type: vmess
            server: jp.example.com
            port: 443
            uuid: 5d1c3d8f-77b7-45c7-98c7-6fa54d37766e
            alterId: 0
            network: ws
            tls: true
            ws-opts:
              path: /gateway
              headers:
                Host: cdn.example.com
        proxy-groups:
          - name: Proxy
        """

        let result = SubscriptionParser().parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes[0].transport, "ws")
        XCTAssertEqual(result.nodes[0].path, "/gateway")
        XCTAssertEqual(result.nodes[0].hostHeader, "cdn.example.com")
        XCTAssertEqual(result.nodes[0].alterID, 0)
    }

    func testKeepsNamedNodesThatShareEndpointAndCredential() {
        let list = """
        trojan://shared-secret@edge.example.com:443?sni=origin.example.com#Hong%20Kong
        trojan://shared-secret@edge.example.com:443?sni=origin.example.com#Tokyo
        """

        let result = SubscriptionParser().parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.map(\.name), ["Hong Kong", "Tokyo"])
    }

    func testKeepsNodesThatDifferByRoutingParameters() {
        let list = """
        trojan://shared-secret@edge.example.com:443?sni=hk.example.com#Premium
        trojan://shared-secret@edge.example.com:443?sni=jp.example.com#Premium
        """

        let result = SubscriptionParser().parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.map(\.sni), ["hk.example.com", "jp.example.com"])
    }

    func testStillDeduplicatesAnExactlyRepeatedNode() {
        let node = "trojan://shared-secret@edge.example.com:443?sni=origin.example.com#Hong%20Kong"
        let list = [node, node].joined(separator: "\n")

        let result = SubscriptionParser().parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.count, 1)
    }
}

extension SubscriptionParserTests {
    func testClashYAMLPreservesRealityAndNestedTransportOptions() throws {
        let yaml = """
        proxies:
          - name: "🇯🇵 日本高速 01"
            type: vless
            server: jp.example.com
            port: 443
            uuid: 11111111-1111-1111-1111-111111111111
            tls: true
            network: ws
            servername: jp-sni.example.com
            ws-opts:
              path: /liangxin/jp1
              headers:
                Host: jp-sni.example.com
          - name: "🇭🇰 香港高速 01"
            type: vless
            server: hk.example.com
            port: 36458
            uuid: 22222222-2222-2222-2222-222222222222
            tls: true
            servername: iosapps.itunes.apple.com
            client-fingerprint: chrome
            flow: xtls-rprx-vision
            reality-opts:
              public-key: TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
              short-id: 0123456789abcdef
        """

        let parsed = SubscriptionParser().parse(data: Data(yaml.utf8))
        XCTAssertEqual(parsed.nodes.count, 2)

        let websocket = try XCTUnwrap(parsed.nodes.first)
        XCTAssertEqual(websocket.transport, "ws")
        XCTAssertEqual(websocket.exportablePath, "/liangxin/jp1")
        XCTAssertEqual(websocket.hostHeader, "jp-sni.example.com")

        let reality = try XCTUnwrap(parsed.nodes.last)
        XCTAssertTrue(reality.usesReality)
        XCTAssertEqual(reality.realityPublicKey, "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(reality.realityShortID, "0123456789abcdef")
        XCTAssertEqual(reality.fingerprint, "chrome")
        XCTAssertEqual(reality.flow, "xtls-rprx-vision")

        let stash = ConfigurationGenerator().generate(
            nodes: parsed.nodes,
            preset: RulePreset.builtIns[0],
            target: .clash
        ).content
        XCTAssertTrue(stash.contains("    reality-opts:"), stash)
        XCTAssertTrue(stash.contains("      public-key: \"TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""), stash)
        XCTAssertTrue(stash.contains("      short-id: \"0123456789abcdef\""), stash)
        XCTAssertTrue(stash.contains("    client-fingerprint: \"chrome\""), stash)
        XCTAssertTrue(stash.contains("    flow: \"xtls-rprx-vision\""), stash)
    }
}
