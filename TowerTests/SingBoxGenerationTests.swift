import XCTest
@testable import Tower

/// sing-box MT and Hiddify both consume the sing-box JSON document dialect.
final class SingBoxGenerationTests: XCTestCase {
    private static let rejectTag = "REJECT"
    private let generator = ConfigurationGenerator()
    private let preset = RulePreset.builtIns[0]

    private func node(
        _ kind: ProxyKind,
        name: String = "HK 01",
        transport: String? = nil,
        tls: Bool = true,
        version: Int? = nil
    ) -> ProxyNode {
        ProxyNode(
            kind: kind, name: name, server: "hk.example.com", port: 443,
            cipher: kind == .shadowsocks ? "aes-256-gcm" : "auto",
            password: "pw", uuid: "b831381d-6324-4d53-ad4f-8cda48b30811",
            username: "user", transport: transport, tls: tls,
            sni: "hk.example.com", hostHeader: "hk.example.com",
            path: transport == "ws" ? "/ws" : nil,
            version: version, rawURI: "x://y"
        )
    }

    private func json(_ target: ClientTarget, nodes: [ProxyNode]) throws -> [String: Any] {
        let content = generator.generate(nodes: nodes, preset: preset, target: target).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - Document shape

    func testOutputIsValidJSON() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks)])

        XCTAssertNotNil(config["outbounds"])
        XCTAssertNotNil(config["route"])
        XCTAssertNotNil(config["inbounds"])
    }

    func testDNSUsesCurrentTypedServerFormat() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks)])
        let dns = try XCTUnwrap(config["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])

        XCTAssertEqual(servers.count, 2)
        for server in servers {
            XCTAssertEqual(server["type"] as? String, "https")
            XCTAssertNotNil(server["server"] as? String)
            XCTAssertNil(server["address"], "legacy DNS server format is rejected by current sing-box")
            XCTAssertNil(
                server["detour"],
                "literal-IP DNS servers should use sing-box's direct dialer default"
            )
            let tls = try XCTUnwrap(server["tls"] as? [String: Any])
            XCTAssertEqual(tls["enabled"] as? Bool, true)
            XCTAssertNotNil(tls["server_name"] as? String)
        }
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertEqual(route["default_domain_resolver"] as? String, "local")
    }

    func testImportedSchemeAlsoIncludesCurrentDNSResolver() throws {
        let scheme = RuleScheme(
            id: "sing-box-dns",
            name: "Sing-box DNS",
            summary: "Imported scheme DNS regression",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.nodePattern(".*"), .reference("DIRECT")]
                )
            ],
            rulesets: [RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))]
        )
        let content = generator.generate(
            nodes: [node(.shadowsocks)],
            scheme: scheme,
            target: .hiddify
        ).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        let config = try XCTUnwrap(object as? [String: Any])
        let dns = try XCTUnwrap(config["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertTrue(servers.allSatisfy { $0["type"] as? String == "https" })
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertEqual(route["default_domain_resolver"] as? String, "local")
    }

    func testImportedSchemeDNSDetoursResolveToExistingOutbounds() throws {
        let scheme = RuleScheme(
            id: "sing-box-dns-detour",
            name: "Sing-box DNS detour",
            summary: "Imported scheme DNS dependency regression",
            groups: [
                RuleSchemeGroup(
                    name: "🚀 节点选择",
                    kind: .select,
                    members: [.nodePattern(".*"), .reference("DIRECT")]
                )
            ],
            rulesets: [RuleSchemeRuleset(groupName: "🚀 节点选择", resource: .inline("FINAL"))]
        )
        let content = generator.generate(
            nodes: [node(.shadowsocks)],
            scheme: scheme,
            target: .hiddify
        ).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        let config = try XCTUnwrap(object as? [String: Any])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let outboundTags = Set(outbounds.compactMap { $0["tag"] as? String })
        let dns = try XCTUnwrap(config["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])

        for detour in servers.compactMap({ $0["detour"] as? String }) {
            XCTAssertTrue(
                outboundTags.contains(detour),
                "DNS detour \(detour) 没有对应的 outbound"
            )
        }
    }

    func testOfficialSingBoxSkipsSSRAndLegacySnellButKeepsSnellV4() throws {
        let generated = generator.generate(
            nodes: [
                node(.shadowsocksR, name: "Legacy SSR"),
                node(.snell, name: "Legacy Snell", version: 3),
                node(.snell, name: "Snell v4", version: 4)
            ],
            preset: preset,
            target: .singBox
        )
        let object = try JSONSerialization.jsonObject(with: Data(generated.content.utf8))
        let config = try XCTUnwrap(object as? [String: Any])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        XCTAssertEqual(generated.supportedNodeCount, 1)
        XCTAssertEqual(generated.skippedNodeCount, 2)
        XCTAssertTrue(outbounds.contains { $0["type"] as? String == "snell" })
        XCTAssertFalse(outbounds.contains { $0["type"] as? String == "shadowsocksr" })
    }

    func testHiddifyAndSingBoxMTAreTheTargetsOnThisFormat() {
        XCTAssertEqual(ClientTarget.allCases.filter(\.usesSingBoxFormat), [.hiddify, .singBox])
    }

    func testHiddifyAndSingBoxMTGenerateTheSameSharedDialect() {
        let nodes = [node(.shadowsocks), node(.vless, name: "VLESS", transport: "grpc")]

        XCTAssertEqual(
            generator.generate(nodes: nodes, preset: preset, target: .hiddify).content,
            generator.generate(nodes: nodes, preset: preset, target: .singBox).content
        )
    }

    func testRejectIsARuleActionNotABlockOutbound() throws {
        let scheme = RuleScheme(
            id: "reject-rule-test",
            name: "Reject",
            summary: "Reject action regression",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "REJECT",
                    resource: .inline("DOMAIN-SUFFIX,ads.example")
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL"))
            ]
        )
        let content = generator.generate(
            nodes: [node(.shadowsocks)],
            scheme: scheme,
            target: .hiddify
        ).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        let config = try XCTUnwrap(object as? [String: Any])
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        // 1.11 deprecated the block outbound in favour of rule actions.
        XCTAssertFalse(outbounds.contains { $0["type"] as? String == "block" })
        XCTAssertTrue(rules.contains { $0["action"] as? String == "reject" }, "没有生成拒绝动作")
        // And with no outbound to point at, the blocking policies must not be
        // emitted as selector groups either.
        let tags = Set(outbounds.compactMap { $0["tag"] as? String })
        XCTAssertFalse(tags.contains(Self.rejectTag))
    }

    func testImportedRejectSelectorHasResolvableBlockOutbound() throws {
        let scheme = RuleScheme(
            id: "reject-selector-test",
            name: "Reject selector",
            summary: "Reject selector dependency regression",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.nodePattern(".*"), .reference("DIRECT")]
                ),
                RuleSchemeGroup(
                    name: "🛑 全球拦截",
                    kind: .select,
                    members: [.reference("REJECT"), .reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "🛑 全球拦截",
                    resource: .inline("DOMAIN-SUFFIX,ads.example")
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL"))
            ]
        )
        let content = generator.generate(
            nodes: [node(.shadowsocks)],
            scheme: scheme,
            target: .hiddify
        ).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        let config = try XCTUnwrap(object as? [String: Any])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let tags = Set(outbounds.compactMap { $0["tag"] as? String })

        XCTAssertTrue(
            outbounds.contains {
                $0["tag"] as? String == Self.rejectTag && $0["type"] as? String == "block"
            },
            "引用 REJECT 的 selector 需要一个真实的拦截出站"
        )
        for outbound in outbounds {
            for member in outbound["outbounds"] as? [String] ?? [] {
                XCTAssertTrue(tags.contains(member), "出站 \(member) 没有对应定义")
            }
        }
    }

    func testEveryGroupReferenceResolvesToSomething() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks), node(.trojan, name: "JP 01")])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let tags = Set(outbounds.compactMap { $0["tag"] as? String })

        for outbound in outbounds {
            for member in outbound["outbounds"] as? [String] ?? [] {
                XCTAssertTrue(tags.contains(member), "出站 \(member) 没有对应定义")
            }
        }
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertTrue(tags.contains(try XCTUnwrap(route["final"] as? String)))
    }

    func testEmptyGroupStillResolves() throws {
        // sing-box refuses to start on a dangling reference, so a group with no
        // members has to point somewhere.
        let config = try json(.hiddify, nodes: [])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        for outbound in outbounds {
            if let members = outbound["outbounds"] as? [String] {
                XCTAssertFalse(members.isEmpty, "\(outbound["tag"] ?? "?") 是空组")
            }
        }
    }

    // MARK: - Outbounds

    func testProtocolTypesMatchSingBoxNames() throws {
        let expected: [ProxyKind: String] = [
            .shadowsocks: "shadowsocks", .vmess: "vmess", .vless: "vless",
            .trojan: "trojan", .hysteria2: "hysteria2", .anytls: "anytls",
            .socks5: "socks", .http: "http"
        ]

        for (kind, type) in expected {
            let config = try json(.hiddify, nodes: [node(kind)])
            let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
            XCTAssertTrue(
                outbounds.contains { $0["type"] as? String == type },
                "\(kind.rawValue) 应写成 \(type)"
            )
        }
    }

    func testWebsocketBecomesATransportBlock() throws {
        let config = try json(.hiddify, nodes: [node(.vmess, transport: "ws")])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let vmess = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vmess" })
        let transport = try XCTUnwrap(vmess["transport"] as? [String: Any])

        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/ws")
    }

    func testTLSCarriesServerNameAndInsecureFlag() throws {
        let config = try json(.hiddify, nodes: [node(.trojan)])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let trojan = try XCTUnwrap(outbounds.first { $0["type"] as? String == "trojan" })
        let tls = try XCTUnwrap(trojan["tls"] as? [String: Any])

        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual(tls["server_name"] as? String, "hk.example.com")
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    func testHysteria2CarriesOfficialObfuscationBlock() throws {
        let hysteria2 = ProxyNode(
            kind: .hysteria2,
            name: "HY2",
            server: "hy2.example.com",
            port: 443,
            password: "authentication-password",
            tls: true,
            obfs: "salamander",
            obfsParam: "obfuscation-password",
            rawURI: "hysteria2://x"
        )
        let config = try json(.hiddify, nodes: [hysteria2])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let outbound = try XCTUnwrap(outbounds.first { $0["type"] as? String == "hysteria2" })
        let obfs = try XCTUnwrap(outbound["obfs"] as? [String: Any])

        XCTAssertEqual(obfs["type"] as? String, "salamander")
        XCTAssertEqual(obfs["password"] as? String, "obfuscation-password")
    }

    func testAnyTLSSessionTuningUsesDurationStrings() throws {
        let anyTLS = ProxyNode(
            kind: .anytls,
            name: "AnyTLS",
            server: "anytls.example.com",
            port: 443,
            password: "password",
            tls: true,
            idleSessionCheckInterval: 20,
            idleSessionTimeout: 45,
            minIdleSession: 3,
            rawURI: "anytls://x"
        )
        let config = try json(.hiddify, nodes: [anyTLS])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let outbound = try XCTUnwrap(outbounds.first { $0["type"] as? String == "anytls" })

        XCTAssertEqual(outbound["idle_session_check_interval"] as? String, "20s")
        XCTAssertEqual(outbound["idle_session_timeout"] as? String, "45s")
        XCTAssertEqual(outbound["min_idle_session"] as? Int, 3)
    }

    func testVMessNeverWritesAutoAsAConcreteCipher() throws {
        let config = try json(.hiddify, nodes: [node(.vmess)])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let vmess = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vmess" })

        XCTAssertEqual(vmess["security"] as? String, "auto")
        XCTAssertEqual(vmess["alter_id"] as? Int, 0)
    }

    // MARK: - Snell

    func testSnellIsSkippedWhateverItsVersion() {
        // sing-box the project implements Snell; the core Hiddify ships does
        // not, so the version does not come into it.
        for version in [3, 4] {
            let output = generator.generate(
                nodes: [node(.snell, version: version)], preset: preset, target: .hiddify
            )

            XCTAssertEqual(output.supportedNodeCount, 0, "v\(version)")
            XCTAssertEqual(output.skippedNodeCount, 1, "v\(version)")
        }
        XCTAssertFalse(ClientTarget.hiddify.supports(.snell))
    }

    func testTheClientsThatDoSupportSnellAreUnaffected() {
        // Surge takes any version, Clash stops at v3.
        let v3 = node(.snell, version: 3)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .surge).supportedNodeCount, 1)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .clash).supportedNodeCount, 1)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .egern).supportedNodeCount, 1)
    }

    // MARK: - Untrusted names

    func testHostileNodeNameCannotBreakTheDocument() throws {
        let hostile = node(.shadowsocks, name: "HK\n\"},{\"tag\":\"pwned\",\"type\":\"direct\"},{\"x\":\"")
        let config = try json(.hiddify, nodes: [hostile])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        // Serialising rather than string-building is what makes this safe.
        XCTAssertFalse(outbounds.contains { $0["tag"] as? String == "pwned" })
    }
}
