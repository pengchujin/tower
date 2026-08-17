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

    func testParsesHTTPAndHTTPSProxyDefaultPorts() throws {
        let parser = SubscriptionParser()

        let http = try XCTUnwrap(parser.parseURI("http://alice:secret@plain.example.com#HTTP"))
        let https = try XCTUnwrap(parser.parseURI("https://alice:secret@secure.example.com#HTTPS"))

        XCTAssertEqual(http.port, 80)
        XCTAssertFalse(http.tls)
        XCTAssertEqual(https.port, 443)
        XCTAssertTrue(https.tls)
    }

    func testParsesShadowrocketBase64HTTPAndHTTPSLinks() throws {
        let parser = SubscriptionParser()
        let httpAuthority = Data("alice:plain-secret@plain.example.com:8080".utf8)
            .base64EncodedString()
        let httpsAuthority = Data("bob:tls-secret@secure.example.com:8443".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let http = try XCTUnwrap(
            parser.parseURI("http://\(httpAuthority)?remarks=Office%20HTTP")
        )
        let https = try XCTUnwrap(
            parser.parseURI("https://\(httpsAuthority)?remarks=Office%20HTTPS")
        )

        XCTAssertEqual(http.name, "Office HTTP")
        XCTAssertEqual(http.server, "plain.example.com")
        XCTAssertEqual(http.port, 8080)
        XCTAssertEqual(http.username, "alice")
        XCTAssertEqual(http.password, "plain-secret")
        XCTAssertFalse(http.tls)
        XCTAssertEqual(https.name, "Office HTTPS")
        XCTAssertEqual(https.server, "secure.example.com")
        XCTAssertEqual(https.port, 8443)
        XCTAssertEqual(https.username, "bob")
        XCTAssertEqual(https.password, "tls-secret")
        XCTAssertTrue(https.tls)
    }

    func testDecodesNamesFromPureBase64HTTPSSubscriptionDialects() throws {
        func urlSafeBase64(_ value: String) -> String {
            Data(value.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        let queryAuthority = urlSafeBase64("alice:secret@uk.example.com:443")
        let queryName = urlSafeBase64("🇬🇧 London HTTPS")
        let embeddedAuthority = urlSafeBase64(
            "bob:secret@jp.example.com:443#🇯🇵 Tokyo HTTPS"
        )
        let links = [
            "https://\(queryAuthority)?remarks=\(queryName)",
            "https://\(embeddedAuthority)",
            "socks5://carol:secret@sg.example.com:1080#Singapore%20SOCKS",
            "anytls://secret@hk.example.com:443#Hong%20Kong%20AnyTLS"
        ].joined(separator: "\n")
        let subscription = Data(links.utf8).base64EncodedString()

        let result = SubscriptionParser().parse(data: Data(subscription.utf8))

        XCTAssertEqual(result.nodes.count, 4)
        XCTAssertEqual(
            result.nodes.map(\.name),
            ["🇬🇧 London HTTPS", "🇯🇵 Tokyo HTTPS", "Singapore SOCKS", "Hong Kong AnyTLS"]
        )
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
    func testShadowrocketFullProfilePreservesStructuredClashConnectionFields() throws {
        let yaml = """
        proxies:
          - name: VLESS TLS
            type: vless
            server: vless.example.com
            port: 443
            uuid: 11111111-2222-3333-4444-555555555555
            tls: true
            servername: cover.example.com
            fingerprint: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            client-fingerprint: chrome
            network: ws
            ws-opts:
              path: /vless
              headers:
                Host: cdn.example.com
          - name: Hysteria2 Hop
            type: hysteria2
            server: hy2.example.com
            port: 443
            ports: 20000-30000
            password: hy2-secret
            sni: cover.example.com
            alpn: [h3]
            fingerprint: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
          - name: TUIC QUIC
            type: tuic
            server: tuic.example.com
            port: 443
            uuid: 66666666-7777-8888-9999-aaaaaaaaaaaa
            password: tuic-secret
            sni: cover.example.com
            alpn: [h3]
            client-fingerprint: chrome
            congestion-controller: bbr
            udp-relay-mode: native
          - name: AnyTLS TLS
            type: anytls
            server: anytls.example.com
            port: 443
            password: anytls-secret
            sni: cover.example.com
            alpn: [h2, http/1.1]
            client-fingerprint: chrome
        """

        let parsed = SubscriptionParser().parse(data: Data(yaml.utf8))
        XCTAssertEqual(parsed.nodes.count, 4)

        let result = ConfigurationGenerator().generate(
            nodes: parsed.nodes,
            preset: RulePreset.builtIns[0],
            target: .shadowrocket
        )

        // Shadowrocket accepts Clash YAML directly. Keeping the structured
        // representation prevents a lossy conversion into one-line fields.
        XCTAssertTrue(result.content.contains("proxies:"), result.content)
        XCTAssertFalse(result.content.contains("[Proxy]"), result.content)
        XCTAssertTrue(result.content.contains("ports: \"20000-30000\""), result.content)
        XCTAssertEqual(result.content.components(separatedBy: "client-fingerprint: \"chrome\"").count - 1, 3, result.content)
        XCTAssertTrue(result.content.contains("fingerprint: \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""), result.content)
        XCTAssertTrue(result.content.contains("fingerprint: \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\""), result.content)
        XCTAssertTrue(result.content.contains("congestion-controller: \"bbr\""), result.content)
        XCTAssertTrue(result.content.contains("udp-relay-mode: \"native\""), result.content)
        XCTAssertTrue(result.content.contains("ws-opts:"), result.content)
    }

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

    func testInlineClashYAMLPreservesRealityAndNestedTransportOptions() throws {
        let yaml = """
        proxies:
          - {name: "Reality inline", type: vless, server: reality.example.com, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true, flow: xtls-rprx-vision, client-fingerprint: chrome, servername: cover.example.com, reality-opts: {public-key: TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, short-id: 0123456789abcdef}}
          - {name: "WebSocket inline", type: vless, server: ws.example.com, port: 443, uuid: 22222222-2222-2222-2222-222222222222, tls: true, network: ws, ws-opts: {path: /liangxin/ws1, headers: {Host: ws-cover.example.com}}}
        """

        let parsed = SubscriptionParser().parse(data: Data(yaml.utf8))
        XCTAssertEqual(parsed.nodes.count, 2)

        let reality = parsed.nodes[0]
        XCTAssertTrue(reality.usesReality)
        XCTAssertEqual(reality.realityPublicKey, "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(reality.realityShortID, "0123456789abcdef")
        XCTAssertEqual(reality.flow, "xtls-rprx-vision")

        let websocket = parsed.nodes[1]
        XCTAssertEqual(websocket.transport, "ws")
        XCTAssertEqual(websocket.exportablePath, "/liangxin/ws1")
        XCTAssertEqual(websocket.hostHeader, "ws-cover.example.com")
    }
}
