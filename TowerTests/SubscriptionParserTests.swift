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

    func testParsesClashNameserverPolicyScalarsAndLists() {
        let yaml = """
        dns:
          enable: true
          nameserver-policy:
            "geosite:cn,private":
              - https://dns.alidns.com/dns-query
              - "https://doh.pub/dns-query"
            '+.example.com': 'tls://1.1.1.1'
            "geosite:geolocation-!cn": [https://1.1.1.1/dns-query, "https://8.8.8.8/dns-query"]
        proxies:
          - { name: HK, type: ss, server: hk.example.com, port: 8388, cipher: aes-256-gcm, password: secret }
        """

        let result = SubscriptionParser().parse(data: Data(yaml.utf8))
        let expected: [NameserverPolicyEntry] = [
            .init(
                matcher: "geosite:cn,private",
                nameservers: ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]
            ),
            .init(matcher: "+.example.com", nameservers: ["tls://1.1.1.1"]),
            .init(
                matcher: "geosite:geolocation-!cn",
                nameservers: ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"]
            )
        ]

        XCTAssertEqual(result.dnsConfiguration?.nameserverPolicy, expected)
        XCTAssertEqual(
            SubscriptionParser().parseDNSConfiguration(data: Data(yaml.utf8)),
            result.dnsConfiguration,
            "Clash 元数据探测不需要采用探测响应中的节点"
        )
    }

    func testParsesEveryFieldOfTheDNSBlock() {
        let yaml = """
        dns:
          enable: false
          default-nameserver:
            - 223.5.5.5
          nameserver: [https://dns.alidns.com/dns-query, "https://1.1.1.1/dns-query"]
          fallback:
            - 'https://dns.google/dns-query'
          nameserver-policy:
            "geosite:cn": https://doh.pub/dns-query
          proxy-server-nameserver:
            - tls://1.1.1.1
          proxy-server-nameserver-policy:
            '+.example.com':
              - https://dns.alidns.com/dns-query
        proxies:
          - { name: HK, type: ss, server: hk.example.com, port: 8388, cipher: aes-256-gcm, password: secret }
        """

        let config = SubscriptionParser().parse(data: Data(yaml.utf8)).dnsConfiguration
        let expected = SubscriptionDNSConfiguration(
            enable: false,
            defaultNameservers: ["223.5.5.5"],
            nameservers: ["https://dns.alidns.com/dns-query", "https://1.1.1.1/dns-query"],
            fallbacks: ["https://dns.google/dns-query"],
            nameserverPolicy: [.init(matcher: "geosite:cn", nameservers: ["https://doh.pub/dns-query"])],
            proxyServerNameservers: ["tls://1.1.1.1"],
            proxyServerNameserverPolicy: [
                .init(matcher: "+.example.com", nameservers: ["https://dns.alidns.com/dns-query"])
            ]
        )

        XCTAssertEqual(config, expected)
    }

    func testDNSBlockInlineCommentsAreStrippedButURLFragmentsSurvive() {
        let yaml = """
        dns:
          enable: true # enabled by the airport
          nameserver:
            - https://dns.alidns.com/dns-query#probe
          nameserver-policy:
            "geosite:cn": https://doh.pub/dns-query # domestic
        proxies:
          - { name: HK, type: ss, server: hk.example.com, port: 8388, cipher: aes-256-gcm, password: secret }
        """

        let config = SubscriptionParser().parse(data: Data(yaml.utf8)).dnsConfiguration
        XCTAssertEqual(config?.enable, true)
        XCTAssertEqual(config?.nameservers, ["https://dns.alidns.com/dns-query#probe"])
        XCTAssertEqual(
            config?.nameserverPolicy,
            [.init(matcher: "geosite:cn", nameservers: ["https://doh.pub/dns-query"])]
        )
    }

    func testUnknownDNSBlockFieldsAndIgnoredExtensionsAreDropped() {
        let yaml = """
        dns:
          enable: true
          enhanced-mode: fake-ip
          fake-ip-range: 198.18.0.1/16
          respect-rules: false
          nameserver:
            - 223.5.5.5
        proxies:
          - { name: HK, type: ss, server: hk.example.com, port: 8388, cipher: aes-256-gcm, password: secret }
        """

        let config = SubscriptionParser().parse(data: Data(yaml.utf8)).dnsConfiguration
        XCTAssertEqual(config?.enable, true)
        XCTAssertEqual(config?.nameservers, ["223.5.5.5"])
        // Out-of-scope extensions do not leak into the model.
        XCTAssertTrue(config?.fallbacks.isEmpty ?? false)
        XCTAssertTrue(config?.proxyServerNameservers.isEmpty ?? false)
    }
}
