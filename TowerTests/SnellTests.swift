import XCTest
@testable import Tower

/// Snell has no URI scheme at all — it is shared as the Surge proxy line it is
/// written as, so that line is what Tower accepts. Surge, Shadowrocket, the
/// Clash family and sing-box implement it with different version ceilings.
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

    /// Snell v6 `mode` must match the server and Tower stores none, so only
    /// the default mode is imported; the others are rejected and counted.
    func testSnellV6ImportsOnlyTheDefaultMode() throws {
        let base = "JP = snell, 198.51.100.4, 443, psk=abc, version=6"
        XCTAssertEqual(try XCTUnwrap(parser.parseURI(base)).version, 6)
        XCTAssertNotNil(parser.parseURI(base + ", mode=default"))
        XCTAssertNil(parser.parseURI(base + ", mode=unshaped"))
        XCTAssertNil(parser.parseURI(base + ", mode=unsafe-raw"))

        let text = "\(base), mode=unshaped\nHK = snell, 198.51.100.5, 443, psk=abc, version=6, mode=default\n"
        let result = parser.parse(data: Data(text.utf8))
        XCTAssertEqual(result.nodes.map(\.name), ["HK"])
        XCTAssertEqual(result.rejectedLineCount, 1)

        let yaml = """
        proxies:
          - {name: A, type: snell, server: 198.51.100.4, port: 443, psk: abc, version: 6, mode: unsafe-raw}
          - {name: B, type: snell, server: 198.51.100.5, port: 443, psk: abc, version: 6, mode: default}
        """
        XCTAssertEqual(parser.parse(data: Data(yaml.utf8)).nodes.map(\.name), ["B"])
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

    func testSnellCapabilityMatrixIncludesOfficialSingBox() {
        XCTAssertTrue(ClientTarget.surge.supports(.snell))
        XCTAssertTrue(ClientTarget.shadowrocket.supports(.snell))
        XCTAssertTrue(ClientTarget.clash.supports(.snell))
        XCTAssertTrue(ClientTarget.clashMi.supports(.snell))
        XCTAssertTrue(ClientTarget.singBox.supports(.snell))
        XCTAssertFalse(ClientTarget.karing.supports(.snell))
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

    func testStashSkipsModernSnellWithoutLeavingGroupReferences() {
        let generator = ConfigurationGenerator()
        let versions: [Int?] = [nil, 1, 2, 3, 4, 5, 6]
        let nodes = versions.map { version in
            ProxyNode(kind: .snell, name: "Snell-\(version ?? 0)", server: "example.com",
                      port: 443, password: "fixture", version: version, rawURI: "")
        }
        let result = generator.generate(nodes: nodes, preset: RulePreset.builtIns[0], target: .clash)
        XCTAssertEqual(result.supportedNodeCount, 4)
        XCTAssertEqual(result.skippedNodeCount, 3)
        for version in 0...3 {
            XCTAssertTrue(result.content.contains("Snell-\(version)"))
        }
        for version in 4...6 {
            XCTAssertFalse(result.content.contains("Snell-\(version)"), "Skipped nodes must not remain in policy groups")
        }
        let parsed = SubscriptionParser().parse(data: Data(result.content.utf8)).nodes
        XCTAssertEqual(parsed.count, 4)
        XCTAssertFalse(parsed.contains { ($0.version ?? 1) > 3 })
    }

    func testMihomoTargetsKeepSnellVersionFour() throws {
        let v4 = try XCTUnwrap(parser.parseURI(line))
        let v3 = try XCTUnwrap(parser.parseURI("HK = snell, 198.51.100.4, 443, psk=abc, version=3"))

        // Mihomo supports Snell v4/v5 independently of Stash.
        for target in [ClientTarget.clashApple, .clashMi] {
            XCTAssertEqual(
                ConfigurationGenerator().generate(nodes: [v4], preset: RulePreset.builtIns[0], target: target).skippedNodeCount,
                0,
                target.name
            )
            XCTAssertEqual(
                ConfigurationGenerator().generate(nodes: [v3], preset: RulePreset.builtIns[0], target: target).supportedNodeCount,
                1,
                target.name
            )
        }
    }

    /// The Clash App (1.0.18), FlClash (0.9.4) and Clash Party (2.0.5) ship
    /// mihomo 1.19.34, which documents v6; the other mihomo clients still run
    /// an older core that refuses `version: 6` and with it the whole file.
    func testOnlyClientsOnMihomo1_19_34TakeSnellV6() {
        let v6 = ProxyNode(kind: .snell, name: "V6", server: "198.51.100.6", port: 443,
                           password: "twelve-bytes-psk", version: 6, rawURI: "")
        let generator = ConfigurationGenerator()

        for target in [ClientTarget.clashApple, .flClash, .mihomoParty] {
            let result = generator.generate(nodes: [v6], preset: RulePreset.builtIns[0], target: target)
            XCTAssertEqual(result.supportedNodeCount, 1, target.name)
            XCTAssertEqual(result.skippedNodeCount, 0, target.name)
            for fragment in ["type: snell", "version: 6", "udp: true"] {
                XCTAssertTrue(result.content.contains(fragment), "\(target.name) 缺少 \(fragment)")
            }
            XCTAssertFalse(result.content.contains("obfs-opts"), target.name)
        }

        for target in [ClientTarget.clashVerge, .clashMac, .clashMi] {
            let result = generator.generate(nodes: [v6], preset: RulePreset.builtIns[0], target: target)
            XCTAssertEqual(result.supportedNodeCount, 0, target.name)
            XCTAssertEqual(result.skippedNodeCount, 1, target.name)
            XCTAssertFalse(result.content.contains("198.51.100.6"), target.name)
        }
    }

    /// clash.md: v6 drops HTTP/TLS obfs and needs a 12–255 byte PSK. Writing
    /// either would make mihomo reject the profile, so skip and count.
    func testMihomoClientsSkipSnellV6TheyCannotLoad() {
        let obfuscated = ProxyNode(kind: .snell, name: "Obfs", server: "198.51.100.7", port: 443,
                                   password: "twelve-bytes-psk", obfs: "http", version: 6, rawURI: "")
        let shortKey = ProxyNode(kind: .snell, name: "Short", server: "198.51.100.8", port: 443,
                                 password: "abc", version: 6, rawURI: "")
        for target in [ClientTarget.clashApple, .flClash, .mihomoParty] {
            let result = ConfigurationGenerator().generate(
                nodes: [obfuscated, shortKey], preset: RulePreset.builtIns[0], target: target
            )
            XCTAssertEqual(result.supportedNodeCount, 0, target.name)
            XCTAssertEqual(result.skippedNodeCount, 2, target.name)
            XCTAssertFalse(result.content.contains("198.51.100.7"), target.name)
            XCTAssertFalse(result.content.contains("198.51.100.8"), target.name)
        }
    }

    // MARK: - Generation

    func testSurgeAndShadowrocketPreserveEverySnellField() throws {
        let node = try XCTUnwrap(parser.parseURI(line))

        let surge = ConfigurationGenerator().generate(
            nodes: [node], preset: RulePreset.builtIns[0], target: .surge
        ).content
        for fragment in ["snell, 203.0.113.9, 8388", "psk=secret-key", "version=4", "obfs=http", "obfs-host=cover.example.com"] {
            XCTAssertTrue(surge.contains(fragment), "Surge 缺少 \(fragment)")
        }

        let shadowrocket = ConfigurationGenerator().generate(
            nodes: [node], preset: RulePreset.builtIns[0], target: .shadowrocket
        ).content
        for fragment in ["type: snell", "server: \"203.0.113.9\"", "psk: \"secret-key\"", "version: 4", "obfs-opts:", "mode: \"http\"", "host: \"cover.example.com\""] {
            XCTAssertTrue(shadowrocket.contains(fragment), "Shadowrocket 缺少 \(fragment)")
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

    // MARK: - ShadowTLS

    /// TestFlight 反馈（1.0.33 (80)）：Snell + ShadowTLS 转 Surge 后丢了
    /// shadow-tls 的密码和版本，导出成连不上的普通 Snell。
    private let shadowTLSLine = "JP STLS = snell, 203.0.113.20, 443, psk=pwd1, version=4, shadow-tls-password=p%25w;d2, shadow-tls-sni=cover.example.com, shadow-tls-version=3"

    func testSnellLineKeepsShadowTLS() throws {
        let node = try XCTUnwrap(parser.parseURI(shadowTLSLine))

        XCTAssertEqual(node.password, "pwd1")
        XCTAssertEqual(node.plugin, "shadow-tls")
        XCTAssertEqual(node.shadowTLS, ShadowTLSOptions(version: 3, host: "cover.example.com", password: "p%w;d2"))
        XCTAssertNil(node.udpRelayEnabled)
    }

    func testSnellShadowTLSWithUnknownOrIncompleteFieldsIsRejected() {
        let base = "JP = snell, 203.0.113.20, 443, psk=pwd1, version=4"
        XCTAssertNil(parser.parseURI(base + ", shadow-tls-password=x, shadow-tls-sni=a.example, shadow-tls-foo=1"))
        XCTAssertNil(parser.parseURI(base + ", shadow-tls-password=x, shadow-tls-version=3"), "缺 SNI 不能静默导入")
        XCTAssertNil(parser.parseURI(base + ", shadow-tls-sni=a.example, shadow-tls-version=3"), "缺密码不能静默导入")
    }

    func testSurgeWritesSnellShadowTLSAndRoundTrips() throws {
        let node = try XCTUnwrap(parser.parseURI(shadowTLSLine))

        for target in [ClientTarget.surge, .surgeMac] {
            let result = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            XCTAssertEqual(result.supportedNodeCount, 1, target.name)
            for fragment in ["snell, 203.0.113.20, 443", "psk=pwd1", "version=4",
                             "shadow-tls-password=p%25w;d2", "shadow-tls-sni=cover.example.com", "shadow-tls-version=3"] {
                XCTAssertTrue(result.content.contains(fragment), "\(target.name) 缺少 \(fragment)")
            }
            // ShadowTLS 只包 TCP，来源没写 udp-relay 就不替它打开。
            XCTAssertFalse(result.content.contains("udp-relay=true"))
        }

        let exported = ConfigurationGenerator().snellShareLine(node)
        XCTAssertEqual(parser.parseURI(exported)?.shadowTLS, node.shadowTLS)
    }

    func testSnellShadowTLSKeepsExplicitUDPRelay() throws {
        let node = try XCTUnwrap(parser.parseURI(shadowTLSLine + ", udp-relay=true"))
        let content = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: .surge).content
        XCTAssertTrue(content.contains("udp-relay=true"))
    }

    func testOtherClientsSkipSnellShadowTLSInsteadOfDroppingIt() throws {
        let node = try XCTUnwrap(parser.parseURI(shadowTLSLine))

        for target in ClientTarget.allCases where ![.surge, .surgeMac].contains(target) {
            let result = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            XCTAssertEqual(result.supportedNodeCount, 0, "\(target.name) 不能把 Snell + ShadowTLS 写成普通 Snell")
            XCTAssertFalse(result.content.contains("203.0.113.20"), target.name)
        }
        XCTAssertFalse(ConfigurationGenerator.surfboardAccepts(node))
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
