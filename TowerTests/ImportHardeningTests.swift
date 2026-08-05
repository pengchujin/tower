import XCTest
@testable import Tower

/// Regression cover for the parsing, region and on-disk issues found in the
/// 2026-08-04 review.
final class ImportHardeningTests: XCTestCase {
    private let parser = SubscriptionParser()

    // MARK: - IPv6 literals

    func testIPv6LiteralHostIsStoredWithoutBrackets() {
        let node = parser.parseURI("trojan://pw@[2001:db8::1]:443#JP")

        XCTAssertEqual(node?.server, "2001:db8::1")
    }

    func testIPv6ShadowsocksEndpointIsStoredWithoutBrackets() {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@[2001:db8::2]:8388#HK"

        XCTAssertEqual(parser.parseURI(uri)?.server, "2001:db8::2")
    }

    func testBareIPv6HostResolvesThroughTheOfflineCountryDatabase() {
        // A bracketed address fails inet_pton, which previously left every
        // IPv6 literal node without a region and without an ICMP probe.
        let database = IPCountryDatabase(
            ipv4Data: Data(),
            ipv6Data: ipv6Record(prefixByte: 0x20, code: "JP")
        )

        XCTAssertEqual(database.countryCode(forIPAddress: "2001:db8::1"), "JP")
        XCTAssertNil(database.countryCode(forIPAddress: "[2001:db8::1]"))
    }

    func testIPv6EndpointAddsBracketsWhenCombiningHostAndPort() {
        let node = ProxyNode(
            kind: .trojan,
            name: "IPv6",
            server: "2001:db8::1",
            port: 443,
            password: "pw",
            rawURI: "trojan://test"
        )

        XCTAssertEqual(node.endpoint, "[2001:db8::1]:443")
    }

    // MARK: - SIP003 plugins

    /// simple-obfs used to be rejected along with every other plugin, which
    /// emptied whole subscriptions that use it. It is expressible in all five
    /// formats, so it is imported; see ShadowsocksObfsTests for the details.
    func testShadowsocksSimpleObfsPluginIsImported() {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388"
            + "?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dwww.bing.com#HK"

        let node = parser.parseURI(uri)

        XCTAssertEqual(node?.obfs, "http")
        XCTAssertEqual(node?.obfsParam, "www.bing.com")
    }

    func testShadowsocksNodeWithUnsupportedPluginIsStillRejected() {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388?plugin=v2ray-plugin%3Bmode%3Dwebsocket#HK"

        XCTAssertNil(parser.parseURI(uri))
    }

    func testShadowsocksNodeWithoutPluginStillParses() {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#HK"

        XCTAssertEqual(parser.parseURI(uri)?.server, "1.2.3.4")
    }

    func testRejectedNodesAreCounted() {
        let list = [
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#OK",
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.5:8388?plugin=v2ray-plugin#Plugin",
            "definitely-not-a-node"
        ].joined(separator: "\n")

        let result = parser.parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.rejectedLineCount, 2)
    }

    func testClashYAMLCarriesSimpleObfsAndStillRejectsOtherPlugins() {
        let yaml = """
        proxies:
          - name: Obfs SS
            type: ss
            server: obfs.example.com
            port: 8388
            cipher: aes-256-gcm
            password: secret
            plugin: obfs
            plugin-opts: { mode: http, host: www.example.com }
          - name: V2Ray SS
            type: ss
            server: v2ray.example.com
            port: 8388
            cipher: aes-256-gcm
            password: secret
            plugin: v2ray-plugin
            plugin-opts: { mode: websocket }
          - name: Plain SS
            type: ss
            server: plain.example.com
            port: 8388
            cipher: aes-256-gcm
            password: secret
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.map(\.server), ["obfs.example.com", "plain.example.com"])
        XCTAssertEqual(result.rejectedLineCount, 1, "只有 v2ray-plugin 该被拒")
        XCTAssertEqual(result.nodes.first?.obfsParam, "www.example.com")
    }

    // MARK: - Duplicate query keys

    func testRepeatedQueryKeyDoesNotTrap() {
        let node = parser.parseURI("vless://uuid@example.com:443?sni=a.example.com&sni=b.example.com#X")

        XCTAssertEqual(node?.sni, "b.example.com")
    }

    // MARK: - Region resolution

    func testOrdinaryWordsAreNotMistakenForCountryCodes() {
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "My fast node")), "my → 马来西亚")
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "Rio de Janeiro")), "de → 德国")
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "Contact us for help")), "us → 美国")
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "Built in relay")), "in → 印度")
    }

    func testCapitalisedCountryCodesStillResolve() {
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "US West 01"))?.code, "US")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "DE-Frankfurt-02"))?.code, "DE")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "MY Kuala 03"))?.code, "MY")
    }

    func testLowercaseCountryCodeInServerHostnameStillResolves() {
        XCTAssertEqual(
            NodeRegionResolver.region(for: node(name: "Premium", server: "us.example.com"))?.code,
            "US"
        )
        XCTAssertEqual(
            NodeRegionResolver.region(for: node(name: "Premium", server: "de-01.example.com"))?.code,
            "DE"
        )
    }

    func testFrankfurtCodeStaysWithGermany() {
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "FRA 01"))?.code, "DE")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "Paris Premium"))?.code, "FR")
    }

    // MARK: - Exported files

    /// The Simulator runs on APFS and does not implement iOS data protection, so
    /// the class it reports back is meaningless there. The write itself is still
    /// exercised on both platforms; only the resulting class is device-only.
    func testExportedConfigurationIsWrittenWithCompleteFileProtection() throws {
        let service = ExportFileService()
        let url = try service.write(configuration())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        #if targetEnvironment(simulator)
        throw XCTSkip("模拟器不实现数据保护，`.complete` 需在真机验证")
        #else
        let protection = try url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        XCTAssertEqual(protection, .complete, "实际保护级别：\(protection?.rawValue ?? "nil")")
        #endif
    }

    func testPurgeRemovesStaleExportsButKeepsRecentOnes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TowerExportPurgeTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let stale = folder.appendingPathComponent("old.conf")
        let fresh = folder.appendingPathComponent("new.conf")
        try Data("old".utf8).write(to: stale)
        try Data("new".utf8).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)],
            ofItemAtPath: stale.path
        )

        ExportFileService().purge(in: folder)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    // MARK: - Preview formatter

    func testSummaryDoesNotDependOnTheLengthOfTheRestOfTheConfiguration() {
        let content = (["header"] + (1...50_000).map { "DOMAIN-SUFFIX,host\($0).example.com,国际流量" })
            .joined(separator: "\n")

        let summary = ConfigurationPreviewFormatter.summary(from: content)

        XCTAssertEqual(
            summary.components(separatedBy: .newlines).count,
            ConfigurationPreviewFormatter.summaryLineLimit
        )
        XCTAssertTrue(summary.hasPrefix("header\n"))
    }

    // MARK: - Helpers

    private func node(name: String, server: String = "203.0.113.8") -> ProxyNode {
        ProxyNode(
            kind: .shadowsocks,
            name: name,
            server: server,
            port: 443,
            password: "test",
            rawURI: "ss://test"
        )
    }

    private func configuration() -> GeneratedConfiguration {
        GeneratedConfiguration(
            target: .surge,
            content: "# test\npassword=secret",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 1
        )
    }

    /// One IPv6 range record: 16 start bytes, 16 end bytes, two ASCII letters.
    private func ipv6Record(prefixByte: UInt8, code: String) -> Data {
        var start = [UInt8](repeating: 0, count: 16)
        start[0] = prefixByte
        var end = [UInt8](repeating: 0xFF, count: 16)
        end[0] = prefixByte
        return Data(start) + Data(end) + Data(code.utf8)
    }
}
