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

    func testYAMLNullFlowIsAbsentButQuotedCredentialsSurvive() throws {
        for rawNull in ["null", "Null", "NULL", "~", ""] {
            for inline in [false, true] {
                let fields = ["name: test", "type: vless", "server: example.com", "port: 443",
                              "uuid: 00000000-0000-4000-8000-000000000001", "flow: \(rawNull)"]
                let yaml = inline ? "proxies:\n  - { \(fields.joined(separator: ", ")) }"
                    : "proxies:\n  - \(fields.joined(separator: "\n    "))"
                let parsed = SubscriptionParser().parse(data: Data(yaml.utf8), sourceID: nil)
                XCTAssertEqual(parsed.nodes.count, 1)
                let config = try json(.singBox, nodes: parsed.nodes)
                let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
                let vless = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vless" })
                XCTAssertNil(vless["flow"], "YAML value: \(rawNull)")
            }
        }
        for credential in ["'null'", "\"null\"", "'~'"] {
            let yaml = "proxies:\n  - { name: test, type: trojan, server: example.com, port: 443, password: \(credential) }"
            let parsed = SubscriptionParser().parse(data: Data(yaml.utf8), sourceID: nil)
            XCTAssertEqual(parsed.nodes.first?.password, credential.contains("~") ? "~" : "null")
        }
    }

    func testOfficialSingBoxSkipsTLSSOCKSWithoutChangingPlainSOCKSOrHTTPS() throws {
        let nodes = [node(.socks5, name: "TLS SOCKS"), node(.socks5, name: "Plain SOCKS", tls: false), node(.http, name: "HTTPS")]
        let generated = generator.generate(nodes: nodes, preset: preset, target: .singBox)
        XCTAssertEqual(generated.supportedNodeCount, 2)
        XCTAssertEqual(generated.skippedNodeCount, 1)
        let config = try json(.singBox, nodes: nodes)
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.filter { $0["type"] as? String == "socks" }.count, 1)
        XCTAssertNil(outbounds.first { $0["type"] as? String == "socks" }?["tls"])
        XCTAssertNotNil(outbounds.first { $0["type"] as? String == "http" }?["tls"])
        XCTAssertFalse(generated.content.contains("TLS SOCKS"))
    }

    func testSnellV5UsesV4WireProtocolAndPreservesHTTPObfuscation() throws {
        var proxy = node(.snell, version: 5)
        proxy.obfs = "http"
        proxy.obfsParam = "cdn.example.com"
        let config = try json(.singBox, nodes: [proxy])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let snell = try XCTUnwrap(outbounds.first { $0["type"] as? String == "snell" })
        XCTAssertEqual(snell["version"] as? Int, 4)
        XCTAssertEqual(snell["obfs_mode"] as? String, "http")
        XCTAssertEqual(snell["obfs_host"] as? String, "cdn.example.com")
        XCTAssertNil(snell["tls"])
        proxy.obfs = "tls"
        XCTAssertEqual(generator.generate(nodes: [proxy], preset: preset, target: .singBox).skippedNodeCount, 1)
    }

    func testWireGuardEndpointsPreservePeersAndGroupReferencesInBothLayouts() throws {
        let key = Data((0..<32).map(UInt8.init)).base64EncodedString()
        let proxy = ProxyNode(kind: .wireguard, name: "WG", server: "wg.example.com", port: 51820,
                              wireGuardPrivateKey: key, wireGuardPublicKey: key, wireGuardPreSharedKey: key,
                              wireGuardIPv4: "10.0.0.2", wireGuardIPv6: "fd00::2/128",
                              wireGuardAllowedIPs: "0.0.0.0/0,::/0", wireGuardReserved: "1,2,3",
                              wireGuardMTU: 1400, wireGuardPersistentKeepalive: 25, rawURI: "wg://test")
        let scheme = RuleScheme(id: "wg-test", name: "WG test", summary: "", groups: [
            RuleSchemeGroup(name: "Proxy", kind: .select, members: [.nodePattern(".*"), .reference("DIRECT")])
        ], rulesets: [RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))])
        let schemeContent = generator.generate(nodes: [proxy], scheme: scheme, target: .singBox).content
        let schemeJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(schemeContent.utf8)) as? [String: Any]
        )
        let configs = [try json(.singBox, nodes: [proxy]), schemeJSON]
        for config in configs {
            let endpoints = try XCTUnwrap(config["endpoints"] as? [[String: Any]])
            XCTAssertEqual(endpoints.count, 1)
            let endpoint = try XCTUnwrap(endpoints.first)
            XCTAssertEqual(endpoint["address"] as? [String], ["10.0.0.2/32", "fd00::2/128"])
            XCTAssertEqual(endpoint["private_key"] as? String, key)
            XCTAssertEqual(endpoint["mtu"] as? Int, 1400)
            let peer = try XCTUnwrap((endpoint["peers"] as? [[String: Any]])?.first)
            XCTAssertEqual(peer["address"] as? String, proxy.server)
            XCTAssertEqual(peer["port"] as? Int, 51820)
            XCTAssertEqual(peer["public_key"] as? String, key)
            XCTAssertEqual(peer["pre_shared_key"] as? String, key)
            XCTAssertEqual(peer["allowed_ips"] as? [String], ["0.0.0.0/0", "::/0"])
            XCTAssertEqual(peer["reserved"] as? [Int], [1, 2, 3])
            XCTAssertEqual(peer["persistent_keepalive_interval"] as? Int, 25)
            let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
            XCTAssertFalse(outbounds.contains { $0["type"] as? String == "wireguard" })
            let tag = try XCTUnwrap(endpoint["tag"] as? String)
            XCTAssertTrue(outbounds.contains { ($0["outbounds"] as? [String])?.contains(tag) == true })
        }
        let hiddify = try json(.hiddify, nodes: [proxy])
        XCTAssertNil(hiddify["endpoints"])
        XCTAssertTrue((hiddify["outbounds"] as? [[String: Any]])?.contains { $0["type"] as? String == "wireguard" } == true)
    }

    func testCustomSchemeDNSIsPreservedWithIndependentBootstrapAndIPv4Only() throws {
        for target in [ClientTarget.singBox, .hiddify] {
            let scheme = RuleScheme(id: "dns", name: "DNS", summary: "", groups: [
                RuleSchemeGroup(name: "Proxy", kind: .select, members: [.nodePattern(".*")])
            ], rulesets: [.init(groupName: "Proxy", resource: .inline("FINAL"))], networkSettings: .init(
                ipv6Enabled: false, dnsServers: ["9.9.9.9", "149.112.112.112"],
                encryptedDNSServers: ["https://dns.quad9.net:8443/custom-dns?key=test", "tls://1.0.0.1:8853", "quic://[2606:4700:4700::1111]:8854"]
            ))
            let content = generator.generate(nodes: [node(.trojan)], scheme: scheme, target: target).content
            let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            let dns = try XCTUnwrap(config["dns"] as? [String: Any])
            let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
            XCTAssertEqual(dns["strategy"] as? String, "ipv4_only")
            let local = try XCTUnwrap(servers.first { $0["tag"] as? String == "local" })
            XCTAssertEqual(local["server"] as? String, "dns.quad9.net")
            XCTAssertEqual(local["server_port"] as? Int, 8443)
            XCTAssertEqual(local["path"] as? String, "/custom-dns?key=test")
            let bootstrapTag = try XCTUnwrap(local["domain_resolver"] as? String)
            XCTAssertEqual(servers.first { $0["tag"] as? String == bootstrapTag }?["server"] as? String, "9.9.9.9")
            XCTAssertTrue(servers.contains { $0["server"] as? String == "149.112.112.112" })
            XCTAssertTrue(servers.contains { $0["type"] as? String == "tls" && $0["server_port"] as? Int == 8853 })
            XCTAssertTrue(servers.contains { $0["type"] as? String == "quic" && $0["server"] as? String == "2606:4700:4700::1111" })
            XCTAssertNil(local["detour"])
            XCTAssertEqual(servers.first { $0["tag"] as? String == "remote" }?["detour"] as? String, "Proxy")
            let inbound = try XCTUnwrap((config["inbounds"] as? [[String: Any]])?.first)
            XCTAssertEqual(inbound["address"] as? [String], ["172.19.0.1/30"])
        }
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
            let tls = try XCTUnwrap(server["tls"] as? [String: Any])
            XCTAssertEqual(tls["enabled"] as? Bool, true)
            XCTAssertNotNil(tls["server_name"] as? String)
        }
        let remote = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote" })
        let local = try XCTUnwrap(servers.first { $0["tag"] as? String == "local" })
        XCTAssertEqual(remote["detour"] as? String, RulePolicy.select.configurationName)
        XCTAssertNil(local["detour"], "bootstrap DNS must not depend on the proxy it resolves")
        XCTAssertEqual(dns["final"] as? String, "remote")
        XCTAssertEqual(dns["reverse_mapping"] as? Bool, true)
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let outboundTags = Set(outbounds.compactMap { $0["tag"] as? String })
        XCTAssertTrue(outboundTags.contains(try XCTUnwrap(remote["detour"] as? String)))
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertEqual(route["default_domain_resolver"] as? String, "local")
    }

    func testDirectOnlyDocumentKeepsBootstrapDNSWithoutDanglingDetour() throws {
        let config = try json(.singBox, nodes: [])
        let dns = try XCTUnwrap(config["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        let remote = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote" })

        XCTAssertNil(remote["detour"])
        XCTAssertEqual(dns["final"] as? String, "local")
        XCTAssertEqual(dns["reverse_mapping"] as? Bool, true)
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
        let remote = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote" })
        XCTAssertEqual(remote["detour"] as? String, "Proxy")
        XCTAssertEqual(dns["final"] as? String, "remote")
        XCTAssertEqual(dns["reverse_mapping"] as? Bool, true)
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertEqual(route["default_domain_resolver"] as? String, "local")
        let routeRules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(routeRules.count, 2)
        XCTAssertEqual(routeRules[0]["action"] as? String, "sniff")
        XCTAssertEqual(routeRules[1]["type"] as? String, "logical")
        XCTAssertEqual(routeRules[1]["mode"] as? String, "or")
        XCTAssertEqual(routeRules[1]["action"] as? String, "hijack-dns")
    }

    func testRouteSniffsDomainsAndHijacksDNSBeforeBusinessRules() throws {
        for target in [ClientTarget.hiddify, .singBox] {
            let config = try json(target, nodes: [node(.shadowsocks)])
            let route = try XCTUnwrap(config["route"] as? [String: Any])
            let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])

            XCTAssertGreaterThanOrEqual(rules.count, 2)
            XCTAssertEqual(rules[0]["action"] as? String, "sniff", target.rawValue)
            XCTAssertEqual(rules[1]["type"] as? String, "logical", target.rawValue)
            XCTAssertEqual(rules[1]["mode"] as? String, "or", target.rawValue)
            XCTAssertEqual(rules[1]["action"] as? String, "hijack-dns", target.rawValue)
            let dnsRules = try XCTUnwrap(rules[1]["rules"] as? [[String: Any]])
            XCTAssertTrue(dnsRules.contains { $0["protocol"] as? String == "dns" })
            XCTAssertTrue(dnsRules.contains { $0["port"] as? Int == 53 })
        }
    }

    func testAppleProfilesDropUnsupportedProcessRulesWithoutDroppingDomainRules() throws {
        let scheme = RuleScheme(
            id: "sing-box-process-rule",
            name: "Process rule",
            summary: "Apple process lookup is unavailable",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.nodePattern(".*"), .reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "Proxy",
                    resource: .inline("PROCESS-NAME,example-app")
                ),
                RuleSchemeRuleset(
                    groupName: "Proxy",
                    resource: .inline("DOMAIN-SUFFIX,example.com")
                ),
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))
            ]
        )

        for target in [ClientTarget.hiddify, .singBox] {
            let content = generator.generate(
                nodes: [node(.shadowsocks)],
                scheme: scheme,
                target: target
            ).content
            let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
            let config = try XCTUnwrap(object as? [String: Any])
            let route = try XCTUnwrap(config["route"] as? [String: Any])
            let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])

            XCTAssertFalse(rules.contains { $0["process_name"] != nil }, target.rawValue)
            XCTAssertTrue(
                rules.contains {
                    ($0["domain_suffix"] as? [String])?.contains("example.com") == true
                },
                "dropping PROCESS-NAME must not drop sibling domain rules for \(target.rawValue)"
            )
        }
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
        let remote = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote" })
        let detour = try XCTUnwrap(remote["detour"] as? String)
        XCTAssertTrue(
            outboundTags.contains(detour),
            "DNS detour \(detour) 没有对应的 outbound"
        )
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
