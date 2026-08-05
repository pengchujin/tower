import XCTest
@testable import Tower

/// Snell has no URI scheme at all — it is shared as the Surge proxy line it is
/// written as, so that line is what Tower accepts. Only Surge, Shadowrocket and
/// the Clash family implement it, and Clash stops at version 3.
final class SnellTests: XCTestCase {
    private let parser = SubscriptionParser()

    private let line = "日本 IEPL = snell, 203.0.113.9, 8388, psk=\"secret-key\", version=4, obfs=http, obfs-host=cover.example.com"

    // MARK: - Parsing

    func testParsesASurgeSnellLine() throws {
        let node = try XCTUnwrap(parser.parseURI(line))

        XCTAssertEqual(node.kind, .snell)
        XCTAssertEqual(node.name, "日本 IEPL")
        XCTAssertEqual(node.server, "203.0.113.9")
        XCTAssertEqual(node.port, 8388)
        XCTAssertEqual(node.password, "secret-key")
        XCTAssertEqual(node.version, 4)
        XCTAssertEqual(node.obfs, "http")
        XCTAssertEqual(node.obfsParam, "cover.example.com")
    }

    func testOptionOrderDoesNotMatter() throws {
        let node = try XCTUnwrap(
            parser.parseURI("HK = snell, 198.51.100.4, 443, version=3, obfs=tls, psk=abc")
        )

        XCTAssertEqual(node.version, 3)
        XCTAssertEqual(node.password, "abc")
        XCTAssertEqual(node.obfs, "tls")
    }

    func testLineWithoutPSKIsRejected() {
        XCTAssertNil(parser.parseURI("Bad = snell, 198.51.100.4, 443, version=4"))
    }

    func testOtherSurgeProtocolsAreNotMistakenForSnell() {
        // A Surge line for something else must not be swallowed by this path.
        XCTAssertNil(parser.parseURI("HK = ss, 198.51.100.4, 443, encrypt-method=aes-128-gcm, password=x"))
    }

    func testDetectorRecognisesTheLine() {
        XCTAssertEqual(SourceInputDetector().detect(line), .node(.snell))
    }

    func testSubscriptionOfSurgeLinesImports() {
        let list = [
            "A = snell, 203.0.113.1, 443, psk=one, version=4",
            "B = snell, 203.0.113.2, 443, psk=two, version=3"
        ].joined(separator: "\n")

        let result = parser.parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.rejectedLineCount, 0)
    }

    // MARK: - Client support

    func testOnlySurgeShadowrocketAndClashAcceptSnell() {
        XCTAssertTrue(ClientTarget.surge.supports(.snell))
        XCTAssertTrue(ClientTarget.shadowrocket.supports(.snell))
        XCTAssertTrue(ClientTarget.clash.supports(.snell))
        XCTAssertFalse(ClientTarget.loon.supports(.snell))
        XCTAssertFalse(ClientTarget.quanx.supports(.snell))
    }

    func testLoonAndQuanXSkipSnellInsteadOfWritingIt() throws {
        let node = try XCTUnwrap(parser.parseURI(line))

        for target in [ClientTarget.loon, .quanx] {
            let result = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            )
            XCTAssertEqual(result.supportedNodeCount, 0, "\(target.name) 不该写出 Snell")
            XCTAssertEqual(result.skippedNodeCount, 1)
            XCTAssertFalse(result.content.contains("203.0.113.9"))
        }
    }

    func testClashSkipsSnellVersionFourAndAbove() throws {
        let v4 = try XCTUnwrap(parser.parseURI(line))
        let v3 = try XCTUnwrap(parser.parseURI("HK = snell, 198.51.100.4, 443, psk=abc, version=3"))

        // Clash and Stash implement Snell only up to version 3.
        XCTAssertEqual(
            ConfigurationGenerator().generate(nodes: [v4], preset: RulePreset.builtIns[0], target: .clash).skippedNodeCount,
            1
        )
        XCTAssertEqual(
            ConfigurationGenerator().generate(nodes: [v3], preset: RulePreset.builtIns[0], target: .clash).supportedNodeCount,
            1
        )
    }

    // MARK: - Generation

    func testSurgeAndShadowrocketWriteTheProxyLine() throws {
        let node = try XCTUnwrap(parser.parseURI(line))

        for target in [ClientTarget.surge, .shadowrocket] {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            ).content

            for fragment in ["snell, 203.0.113.9, 8388", "psk=secret-key", "version=4", "obfs=http", "obfs-host=cover.example.com"] {
                XCTAssertTrue(content.contains(fragment), "\(target.name) 缺少 \(fragment)")
            }
        }
    }

    func testClashWritesSnellAsYAML() throws {
        let v3 = try XCTUnwrap(
            parser.parseURI("HK = snell, 198.51.100.4, 443, psk=abc, version=3, obfs=tls, obfs-host=cover.example.com")
        )
        let content = ConfigurationGenerator().generate(
            nodes: [v3],
            preset: RulePreset.builtIns[0],
            target: .clash
        ).content

        for fragment in ["type: snell", "psk: \"abc\"", "version: 3", "obfs-opts:", "mode: \"tls\"", "host: \"cover.example.com\""] {
            XCTAssertTrue(content.contains(fragment), "Clash 缺少 \(fragment)")
        }
    }

    func testUDPOnlyFromVersionThree() throws {
        let v2 = try XCTUnwrap(parser.parseURI("Old = snell, 198.51.100.4, 443, psk=abc, version=2"))
        let v3 = try XCTUnwrap(parser.parseURI("New = snell, 198.51.100.5, 443, psk=abc, version=3"))

        let oldLine = ConfigurationGenerator().generate(nodes: [v2], preset: RulePreset.builtIns[0], target: .surge).content
        let newLine = ConfigurationGenerator().generate(nodes: [v3], preset: RulePreset.builtIns[0], target: .surge).content

        XCTAssertFalse(oldLine.contains("udp-relay=true"), "Snell v2 不支持 UDP")
        XCTAssertTrue(newLine.contains("udp-relay=true"))
    }

    // MARK: - Sharing

    func testSharingGivesBackTheProxyLine() throws {
        let node = try XCTUnwrap(parser.parseURI(line))
        let shared = ProxyNodeShareLinkGenerator().link(for: node)

        // There is no snell:// to build, so the original line is what is shared,
        // and it must survive a round trip back through the importer.
        XCTAssertEqual(parser.parseURI(shared)?.password, "secret-key")
        XCTAssertEqual(parser.parseURI(shared)?.version, 4)
    }
}
