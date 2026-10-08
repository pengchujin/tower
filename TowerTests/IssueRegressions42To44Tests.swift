import XCTest
@testable import Tower

/// Source-level reports filed on 2026-10-08 (issues #42, #43, #44).
final class IssueRegressions42To44Tests: XCTestCase {
    private let parser = SubscriptionParser()

    // MARK: - #42 Snell imported from Clash

    func testClashImportedSnellSharesPortableSurgeLineInsteadOfPlaceholder() {
        let yaml = """
        proxies:
          - {name: "Snell JP", type: snell, server: snell.example, port: 443, psk: secret, version: 4, obfs-opts: {mode: http, host: bing.com}}
        """
        guard let node = parser.parse(data: Data(yaml.utf8)).nodes.first else {
            return XCTFail("Clash Snell node was not imported")
        }
        XCTAssertTrue(node.rawURI.hasPrefix("clash://local/"))

        let shared = ProxyNodeShareLinkGenerator().link(for: node)

        XCTAssertFalse(shared.contains("clash://local/"))
        XCTAssertTrue(shared.contains("= snell, snell.example, 443, psk=secret, version=4"), shared)
        let reparsed = parser.parse(data: Data(shared.utf8)).nodes.first
        XCTAssertEqual(reparsed?.kind, .snell)
        XCTAssertEqual(reparsed?.password, "secret")
        XCTAssertEqual(reparsed?.obfs, "http")
        XCTAssertEqual(reparsed?.obfsParam, "bing.com")
    }

    func testSurgeImportedSnellKeepsItsOriginalLine() {
        let line = "Snell JP = snell, snell.example, 443, psk=secret, version=4"
        let node = ProxyNode(kind: .snell, name: "Snell JP", server: "snell.example", port: 443,
                             password: "secret", version: 4, rawURI: line)

        XCTAssertEqual(ProxyNodeShareLinkGenerator().link(for: node), line)
    }

    // MARK: - #43 HTTP proxy batches

    func testBatchOfBareHTTPProxiesIsNotTreatedAsSubscriptions() {
        let detector = SourceInputDetector()
        let value = """
        http://one.example:8080
        http://two.example:8080
        """

        XCTAssertEqual(detector.detect("http://one.example:8080"), .node(.http))
        XCTAssertEqual(detector.detect(value), .nodeBatch(count: 2))
        XCTAssertTrue(detector.subscriptionURLs(value).isEmpty)
    }

    // MARK: - #44 SIP003 separators inside option values

    func testShadowsocksV2RayPluginPathWithSemicolonRoundTrips() {
        let node = ProxyNode(
            kind: .shadowsocks, name: "WS", server: "ss.example", port: 443,
            cipher: "aes-256-gcm", password: "secret", plugin: "v2ray-plugin",
            tls: true, hostHeader: "cdn.example", path: "/foo;bar",
            rawURI: "clash://local/example"
        )

        let link = ProxyNodeShareLinkGenerator().link(for: node)
        let reparsed = parser.parseURI(link)

        XCTAssertEqual(reparsed?.plugin, "v2ray-plugin")
        XCTAssertEqual(reparsed?.path, "/foo;bar")
        XCTAssertEqual(reparsed?.hostHeader, "cdn.example")
        XCTAssertEqual(reparsed?.tls, true)
    }

    func testEscapedSemicolonInIncomingV2RayPluginPathIsPreserved() {
        let plugin = "v2ray-plugin;mode=websocket;host=cdn.example;path=/foo\\;bar"
        let encoded = plugin.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let uri = "ss://YWVzLTI1Ni1nY206c2VjcmV0@ss.example:443?plugin=\(encoded)#WS"

        XCTAssertEqual(parser.parseURI(uri)?.path, "/foo;bar")
    }
}
