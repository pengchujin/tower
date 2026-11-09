import XCTest
@testable import Tower

/// Egern's YAML nests by type: proxies, policy groups and rules are each a
/// single-key mapping whose key names the kind. Shapes follow the published
/// example at egernapp.com/docs/configuration/example.
final class EgernGenerationTests: XCTestCase {
    private let generator = ConfigurationGenerator()
    private let preset = RulePreset.builtIns[0]

    private func node(_ kind: ProxyKind, name: String = "HK 01", transport: String? = nil) -> ProxyNode {
        ProxyNode(
            kind: kind, name: name, server: "hk.example.com", port: 443,
            cipher: kind == .shadowsocks ? "chacha20-ietf-poly1305" : "auto",
            password: "pw", uuid: "b831381d-6324-4d53-ad4f-8cda48b30811",
            username: "user", transport: transport, tls: kind != .shadowsocks,
            sni: "hk.example.com", hostHeader: "hk.example.com",
            path: transport == "ws" ? "/ws" : nil, rawURI: "x://y"
        )
    }

    private func content(_ nodes: [ProxyNode]) -> String {
        generator.generate(nodes: nodes, preset: preset, target: .egern).content
    }

    func testProxiesNestUnderTheirType() {
        let output = content([node(.shadowsocks)])

        XCTAssertTrue(output.contains("  - shadowsocks:\n      name: \"HK 01\""), output)
        XCTAssertTrue(output.contains("      server: \"hk.example.com\""))
        XCTAssertTrue(output.contains("      port: 443"))
    }

    func testShadowsocksCipherLosesTheIETFInfix() {
        let output = content([node(.shadowsocks)])

        XCTAssertTrue(output.contains("      method: \"chacha20-poly1305\""), output)
        XCTAssertFalse(output.contains("chacha20-ietf-poly1305"))
    }

    func testPolicyGroupsUseSelectAndAutoTest() {
        let output = content([node(.trojan)])

        XCTAssertTrue(output.contains("  - select:\n      name: "), output)
        XCTAssertTrue(output.contains("  - auto_test:\n      name: "))
        XCTAssertTrue(output.contains("      policies:\n"))
        XCTAssertTrue(output.contains("      interval: 600"))
    }

    func testRulesCarryMatchAndPolicyAndEndWithDefault() {
        // The legacy RulePreset payloads were deliberately removed from the
        // bundle. Exercise the RuleScheme path the app now ships instead of
        // expecting a deleted Self-Configuration list to produce a rule.
        let scheme = RuleScheme(
            id: "egern-rules",
            name: "Egern Rules",
            summary: "inline fixture",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.nodePattern(".*")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "节点选择",
                    resource: .inline("DOMAIN-SUFFIX,example.com")
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL")),
            ]
        )
        let output = generator.generate(nodes: [node(.trojan)], scheme: scheme, target: .egern).content

        XCTAssertTrue(output.contains("  - domain_suffix:\n      match: "), output)
        XCTAssertTrue(output.contains("      policy: "))
        XCTAssertTrue(output.contains("  - default:\n      policy: "), "缺少兜底规则")
    }

    func testWebsocketNestsUnderTransport() {
        let output = content([node(.vmess, transport: "ws")])

        XCTAssertTrue(output.contains("      transport:\n        wss:"), output)
        XCTAssertTrue(output.contains("          path: \"/ws\""))
        XCTAssertTrue(output.contains("            Host: \"hk.example.com\""))
    }

    func testVMessUsesUserIDNotUUID() {
        let output = content([node(.vmess)])

        XCTAssertTrue(output.contains("      user_id: "), output)
        XCTAssertFalse(output.contains("      uuid: "))
    }

    func testUnsupportedProtocolIsSkippedAndCounted() {
        let hysteria = ProxyNode(
            kind: .hysteria, name: "HY1", server: "h.example.com", port: 443,
            password: "pw", rawURI: "hysteria://x"
        )
        let result = generator.generate(nodes: [hysteria], preset: preset, target: .egern)

        XCTAssertEqual(result.supportedNodeCount, 0)
        XCTAssertEqual(result.skippedNodeCount, 1)
    }

    /// Egern 2.21 SSR, keys and whitelists as in Sub-Store's Egern producer.
    func testShadowsocksRUsesEgernKeysAndOnlyStreamCiphers() {
        let ssr = ProxyNode(
            kind: .shadowsocksR, name: "SSR", server: "s.example.com", port: 8388,
            cipher: "aes-256-cfb", password: "pw", protocolName: "auth_aes128_md5", protocolParam: "1:abc",
            obfs: "tls1.2_ticket_auth", obfsParam: "cover.example.com", rawURI: "ssr://x"
        )
        let result = generator.generate(nodes: [ssr], preset: preset, target: .egern)
        XCTAssertEqual(result.supportedNodeCount, 1)
        for line in ["  - shadowsocksr:\n", "      method: \"aes-256-cfb\"\n", "      protocol: \"auth_aes128_md5\"\n",
                     "      protocol_param: \"1:abc\"\n", "      obfs: \"tls1.2_ticket_auth\"\n",
                     "      obfs_param: \"cover.example.com\"\n", "      udp_relay: true\n"] {
            XCTAssertTrue(result.content.contains(line), line + result.content)
        }
        XCTAssertFalse(result.content.contains("skip_tls_verify"), result.content)

        var aead = ssr; aead.cipher = "aes-256-gcm"
        var oddProtocol = ssr; oddProtocol.protocolName = "auth_chain_d"
        var oddObfs = ssr; oddObfs.obfs = "simple_obfs_http"
        let skipped = generator.generate(nodes: [aead, oddProtocol, oddObfs], preset: preset, target: .egern)
        XCTAssertEqual(skipped.supportedNodeCount, 0)
        XCTAssertEqual(skipped.skippedNodeCount, 3)
    }

    func testHostileNodeNameCannotAddAProxyEntry() {
        let hostile = node(.shadowsocks, name: "HK\n  - trojan:\n      name: pwned")
        let output = content([hostile])

        // The name stays one quoted scalar, so the injected text survives
        // inside it — what must not happen is a new entry on its own line.
        let entries = output.split(separator: "\n").filter { $0.hasPrefix("  - trojan:") }
        XCTAssertTrue(entries.isEmpty, "节点名注入出了新代理条目")
        XCTAssertTrue(output.contains(#""HK   - trojan:       name: pwned""#), output)
    }

    func testTargetMetadata() {
        XCTAssertEqual(ClientTarget.egern.fileExtension, "yaml")
        XCTAssertFalse(ClientTarget.egern.usesSingBoxFormat)
        // Egern documents egern:/profiles/new, so it gets one-tap import.
        XCTAssertTrue(ClientTarget.egern.supportsDirectConfigurationImport)
    }
}

extension EgernGenerationTests {
    /// Egern requires Hysteria 2's secret under `auth`; `password` rejects the
    /// whole profile with "missing field `auth`".
    func testHysteria2UsesAuthNotPassword() {
        let hysteria2 = ProxyNode(
            kind: .hysteria2, name: "TW 01", server: "tw.example.com", port: 443,
            password: "secret", tls: true, sni: "tw.example.com", rawURI: "hysteria2://x"
        )
        let output = generator.generate(
            nodes: [hysteria2], preset: RulePreset.builtIns[0], target: .egern
        ).content

        XCTAssertTrue(output.contains("  - hysteria2:"), output)
        XCTAssertTrue(output.contains("      auth: \"secret\""), output)
        XCTAssertFalse(output.contains("      password: \"secret\""))
    }

    /// The protocols that really do use `password` must keep it.
    func testTrojanAndAnyTLSKeepPassword() {
        for kind in [ProxyKind.trojan, .anytls] {
            let node = ProxyNode(
                kind: kind, name: "N", server: "n.example.com", port: 443,
                password: "secret", tls: true, sni: "n.example.com", rawURI: "x://y"
            )
            let output = generator.generate(
                nodes: [node], preset: RulePreset.builtIns[0], target: .egern
            ).content

            XCTAssertTrue(output.contains("      password: \"secret\""), "\(kind.rawValue): \(output)")
            XCTAssertFalse(output.contains("      auth: "), kind.rawValue)
        }
    }
}
