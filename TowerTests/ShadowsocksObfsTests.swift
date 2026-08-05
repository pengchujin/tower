import XCTest
@testable import Tower

/// A real subscription was returning ninety nodes that all carried
/// `plugin: obfs`, and every one of them was rejected, leaving the import
/// empty. simple-obfs is expressible in all five formats, so it is carried
/// through instead.
final class ShadowsocksObfsTests: XCTestCase {
    private let parser = SubscriptionParser()

    private let inlineClashYAML = """
    proxies:
      - {name: HK 01, server: hk.example.com, port: 10016, type: ss, cipher: aes-128-gcm, password: pw, plugin: obfs, plugin-opts: {mode: http, host: cover.example.com}, udp: true}
      - {name: JP 02, server: jp.example.com, port: 10026, type: ss, cipher: aes-128-gcm, password: pw, udp: true}
    """

    // MARK: - Parsing

    func testClashInlinePluginNodeIsImportedNotRejected() {
        let result = parser.parse(data: Data(inlineClashYAML.utf8))

        XCTAssertEqual(result.nodes.count, 2, "带 obfs 插件的节点被拒了")
        XCTAssertEqual(result.rejectedLineCount, 0)
    }

    func testClashPluginOptionsBecomeObfsFields() throws {
        let node = try XCTUnwrap(
            parser.parse(data: Data(inlineClashYAML.utf8)).nodes.first { $0.name == "HK 01" }
        )

        XCTAssertEqual(node.obfs, "http")
        XCTAssertEqual(node.obfsParam, "cover.example.com")
    }

    func testNodeWithoutPluginKeepsNoObfs() throws {
        let node = try XCTUnwrap(
            parser.parse(data: Data(inlineClashYAML.utf8)).nodes.first { $0.name == "JP 02" }
        )

        XCTAssertNil(node.obfs)
    }

    func testShadowsocksURIPluginIsParsed() throws {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388"
            + "?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dcover.example.com#HK"

        let node = try XCTUnwrap(parser.parseURI(uri))

        XCTAssertEqual(node.obfs, "http")
        XCTAssertEqual(node.obfsParam, "cover.example.com")
    }

    func testUnsupportedPluginIsStillRejected() {
        // v2ray-plugin changes the transport in ways these five formats cannot
        // all express, so importing it would produce a broken node.
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388?plugin=v2ray-plugin%3Bmode%3Dwebsocket#HK"

        XCTAssertNil(parser.parseURI(uri))
    }

    // MARK: - Generation

    func testEveryTargetEmitsTheObfsPlugin() {
        let node = obfsNode()
        let expected: [ClientTarget: [String]] = [
            .clash: ["plugin: obfs", "mode: \"http\"", "host: \"cover.example.com\""],
            .surge: ["obfs=http", "obfs-host=cover.example.com"],
            .shadowrocket: ["obfs=http", "obfs-host=cover.example.com"],
            .loon: ["obfs-name=http", "obfs-host=cover.example.com"],
            .quanx: ["obfs=http", "obfs-host=cover.example.com"]
        ]

        for (target, fragments) in expected {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            ).content

            for fragment in fragments {
                XCTAssertTrue(content.contains(fragment), "\(target.name) 缺少 \(fragment)")
            }
        }
    }

    func testPlainShadowsocksNodeGainsNoObfsFields() {
        let plain = ProxyNode(
            kind: .shadowsocks,
            name: "Plain",
            server: "plain.example.com",
            port: 8388,
            cipher: "aes-128-gcm",
            password: "pw",
            rawURI: "ss://plain"
        )

        for target in ClientTarget.allCases {
            let content = ConfigurationGenerator().generate(
                nodes: [plain],
                preset: RulePreset.builtIns[0],
                target: target
            ).content
            XCTAssertFalse(content.contains("obfs"), "\(target.name) 给无插件节点加了 obfs")
        }
    }

    func testShadowsocksRObfuscationIsNotMistakenForAPlugin() {
        // SSR uses the same obfs fields for something else entirely; its values
        // must not be emitted as a SIP003 plugin.
        let ssr = ProxyNode(
            kind: .shadowsocksR,
            name: "SSR",
            server: "ssr.example.com",
            port: 8388,
            cipher: "aes-256-cfb",
            password: "pw",
            protocolName: "auth_aes128_md5",
            obfs: "tls1.2_ticket_auth",
            obfsParam: "cover.example.com",
            rawURI: "ssr://x"
        )

        let content = ConfigurationGenerator().generate(
            nodes: [ssr],
            preset: RulePreset.builtIns[0],
            target: .clash
        ).content

        XCTAssertFalse(content.contains("plugin: obfs"), content)
    }

    // MARK: - Sharing

    func testSharedLinkKeepsThePlugin() {
        let link = ProxyNodeShareLinkGenerator().link(for: obfsNode())

        XCTAssertTrue(link.contains("plugin="), link)
        XCTAssertTrue(link.contains("obfs-host"), link)

        // The link must survive a round trip through the importer.
        let reparsed = SubscriptionParser().parseURI(link)
        XCTAssertEqual(reparsed?.obfs, "http")
        XCTAssertEqual(reparsed?.obfsParam, "cover.example.com")
    }

    private func obfsNode() -> ProxyNode {
        ProxyNode(
            kind: .shadowsocks,
            name: "HK 01",
            server: "hk.example.com",
            port: 10016,
            cipher: "aes-128-gcm",
            password: "pw",
            obfs: "http",
            obfsParam: "cover.example.com",
            rawURI: "clash://local/test"
        )
    }
}
