import XCTest
@testable import Tower

/// End-to-end DNS conversion tests: one subscription DNS block, seven targets,
/// both the built-in preset and the imported-scheme generation paths.
final class DNSConversionTests: XCTestCase {
    private let nodes = [
        ProxyNode(
            kind: .shadowsocks,
            name: "Hong Kong",
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://test"
        ),
        ProxyNode(
            kind: .vmess,
            name: "Tokyo",
            server: "jp.example.com",
            port: 443,
            uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            transport: "ws",
            tls: true,
            sni: "jp.example.com",
            hostHeader: "jp.example.com",
            path: "/gateway",
            rawURI: "vmess://test"
        )
    ]

    private var preset: RulePreset { RulePreset.builtIns[0] }

    private func generate(
        _ target: ClientTarget,
        dns: SubscriptionDNSConfiguration?
    ) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(
            nodes: nodes,
            preset: preset,
            target: target,
            dnsConfiguration: dns
        )
    }

    private func dns(
        enable: Bool? = nil,
        defaultNameservers: [String] = [],
        nameservers: [String] = ["https://dns.alidns.com/dns-query"],
        fallbacks: [String] = [],
        policy: [NameserverPolicyEntry] = [],
        proxyNameservers: [String] = [],
        proxyPolicy: [NameserverPolicyEntry] = []
    ) -> SubscriptionDNSConfiguration {
        SubscriptionDNSConfiguration(
            enable: enable,
            defaultNameservers: defaultNameservers,
            nameservers: nameservers,
            fallbacks: fallbacks,
            nameserverPolicy: policy,
            proxyServerNameservers: proxyNameservers,
            proxyServerNameserverPolicy: proxyPolicy
        )
    }

    // MARK: - Stash / Clash (native)

    func testStashWritesNativeDNSFields() {
        let config = dns(
            enable: false,
            defaultNameservers: ["223.5.5.5"],
            nameservers: ["https://dns.alidns.com/dns-query"],
            fallbacks: ["https://dns.google/dns-query"],
            policy: [.init(matcher: "+.example.com", nameservers: ["tls://1.1.1.1"])]
        )
        let content = generate(.clash, dns: config).content

        XCTAssertTrue(content.contains("dns:\n  enable: false"))
        XCTAssertTrue(content.contains("  default-nameserver:\n    - \"223.5.5.5\""))
        XCTAssertTrue(content.contains("  nameserver:\n    - \"https://dns.alidns.com/dns-query\""))
        XCTAssertTrue(content.contains("  fallback:\n    - \"https://dns.google/dns-query\""))
        XCTAssertTrue(content.contains("  nameserver-policy:\n    \"+.example.com\":\n      - \"tls://1.1.1.1\""))
    }

    func testStashSkipsMihomoProxyFieldsWithWarning() {
        let config = dns(
            proxyNameservers: ["tls://1.1.1.1"],
            proxyPolicy: [.init(matcher: "+.example.com", nameservers: ["https://dns.alidns.com/dns-query"])]
        )
        let result = generate(.clash, dns: config)

        XCTAssertFalse(result.content.contains("proxy-server-nameserver"))
        XCTAssertTrue(result.conversionWarnings.contains { $0.contains("proxy-server-nameserver") })
        XCTAssertTrue(result.conversionWarnings.contains { $0.contains("proxy-server-nameserver-policy") })
    }

    // MARK: - Surge

    func testSurgeSplitsDNSByProtocolAndMapsPolicyToHost() {
        let config = dns(
            nameservers: ["223.5.5.5", "https://1.1.1.1/dns-query"],
            policy: [
                .init(matcher: "+.example.com", nameservers: ["8.8.8.8", "9.9.9.9"]),
                .init(matcher: "geosite:cn", nameservers: ["https://dns.alidns.com/dns-query"])
            ]
        )
        let result = generate(.surge, dns: config)

        XCTAssertTrue(result.content.contains("dns-server = system, 223.5.5.5"))
        XCTAssertTrue(result.content.contains("encrypted-dns-server = https://1.1.1.1/dns-query"))
        XCTAssertTrue(result.content.contains("[Host]\n*.example.com = server:8.8.8.8,9.9.9.9"))
        XCTAssertTrue(result.conversionWarnings.contains { $0.contains("geosite") })
    }

    func testSurgeDropsDoTWithWarning() {
        let config = dns(
            nameservers: ["tls://1.1.1.1"],
            policy: [.init(matcher: "example.com", nameservers: ["tls://8.8.8.8"])]
        )
        let result = generate(.surge, dns: config)

        XCTAssertTrue(result.content.contains("dns-server = system"))
        XCTAssertFalse(result.content.contains("tls://1.1.1.1"))
        XCTAssertTrue(result.conversionWarnings.contains { $0.contains("DoT") })
    }

    // MARK: - Shadowrocket

    func testShadowrocketUsesDedicatedFallbackAndProxyKeys() {
        let config = dns(
            nameservers: ["223.5.5.5"],
            fallbacks: ["8.8.4.4"],
            policy: [.init(matcher: "*.example.com", nameservers: ["8.8.8.8"])],
            proxyNameservers: ["9.9.9.9"],
            proxyPolicy: [.init(matcher: "+.example.net", nameservers: ["1.1.1.1"])]
        )
        let result = generate(.shadowrocket, dns: config)

        XCTAssertTrue(result.content.contains("dns-server = system, 223.5.5.5"))
        XCTAssertTrue(result.content.contains("fallback-dns-server = 8.8.4.4"))
        XCTAssertTrue(result.content.contains("proxy-dns-server = 9.9.9.9"))
        XCTAssertTrue(result.content.contains("[Host]\n*.example.com = server:8.8.8.8"))
        // Per-domain proxy policy has no home in Shadowrocket.
        XCTAssertTrue(result.conversionWarnings.contains { $0.contains("按域区分代理节点 DNS") })
    }

    // MARK: - Loon

    func testLoonSplitsDNSByProtocolAndMapsPolicyToHost() {
        let config = dns(
            nameservers: ["223.5.5.5", "https://dns.alidns.com/dns-query", "quic://dns.adguard.com"],
            fallbacks: ["h3://223.6.6.6/dns-query"],
            policy: [.init(matcher: "*.example.com", nameservers: ["8.8.8.8"])]
        )
        let result = generate(.loon, dns: config)

        XCTAssertTrue(result.content.contains("dns-server = system, 223.5.5.5"))
        XCTAssertTrue(result.content.contains("doh-server = https://dns.alidns.com/dns-query"))
        XCTAssertTrue(result.content.contains("doq-server = quic://dns.adguard.com"))
        XCTAssertTrue(result.content.contains("doh3-server = h3://223.6.6.6/dns-query"))
        XCTAssertTrue(result.content.contains("[Host]\n*.example.com = server:8.8.8.8"))
    }

    // MARK: - Quantumult X

    func testQuanXDNSAndDomainBinding() {
        let config = dns(
            nameservers: ["223.5.5.5", "https://dns.alidns.com/dns-query"],
            policy: [
                .init(matcher: "example.com", nameservers: ["8.8.8.8"]),
                .init(matcher: "+.example.org", nameservers: ["https://dns.google/dns-query"])
            ]
        )
        let result = generate(.quanx, dns: config)

        XCTAssertTrue(result.content.contains("[dns]\nno-system"))
        XCTAssertTrue(result.content.contains("server = 223.5.5.5"))
        XCTAssertTrue(result.content.contains("doh-server = https://dns.alidns.com/dns-query"))
        XCTAssertTrue(result.content.contains("server = /example.com/8.8.8.8"))
        XCTAssertTrue(result.content.contains("doh-server = /*.example.org/https://dns.google/dns-query"))
    }

    // MARK: - Egern

    func testEgernBuildsBootstrapUpstreamsAndForward() {
        let config = dns(
            defaultNameservers: ["223.5.5.5"],
            nameservers: ["https://dns.alidns.com/dns-query"],
            policy: [
                .init(matcher: "+.example.com", nameservers: ["8.8.8.8"]),
                .init(matcher: "*.example.net", nameservers: ["tls://1.1.1.1", "https://8.8.8.8/dns-query"])
            ],
            proxyNameservers: ["9.9.9.9"]
        )
        let result = generate(.egern, dns: config)

        XCTAssertTrue(result.content.contains("dns:"))
        XCTAssertTrue(result.content.contains("  bootstrap:\n    - \"223.5.5.5\""))
        XCTAssertTrue(result.content.contains("  upstreams:\n    main:\n      - \"https://dns.alidns.com/dns-query\""))
        // A single-resolver policy is forwarded inline.
        XCTAssertTrue(result.content.contains("    - domain_wildcard:\n        match: \"*.example.com\"\n        value: \"8.8.8.8\""))
        // A multi-resolver policy keeps its group intact.
        XCTAssertTrue(result.content.contains("    policy-example-net:\n      - \"tls://1.1.1.1\"\n      - \"https://8.8.8.8/dns-query\""))
        XCTAssertTrue(result.content.contains("  proxy_nameservers:\n    - \"9.9.9.9\""))
        // Without a catch-all, Egern would answer everything with bootstrap and
        // never touch the airport's upstreams, so a catch-all follows the
        // policy rules.
        XCTAssertTrue(result.content.contains("    - domain_regex:\n        match: \".*\"\n        value: \"main\""))
    }

    // MARK: - Hiddify (sing-box)

    func testHiddifyBuildsDNSServersRulesAndDomainResolver() throws {
        let config = dns(
            nameservers: ["https://dns.alidns.com/dns-query", "https://1.1.1.1/dns-query"],
            policy: [.init(matcher: "+.example.com", nameservers: ["tls://1.1.1.1"])],
            proxyNameservers: ["9.9.9.9"]
        )
        let result = generate(.hiddify, dns: config)
        XCTAssertTrue(result.conversionWarnings.isEmpty)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any]
        )
        let dnsBlock = try XCTUnwrap(object["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dnsBlock["servers"] as? [[String: Any]])
        XCTAssertTrue(servers.contains { ($0["address"] as? String) == "https://dns.alidns.com/dns-query" })
        XCTAssertTrue(servers.contains { ($0["address"] as? String) == "9.9.9.9" })

        let rules = try XCTUnwrap(dnsBlock["rules"] as? [[String: Any]])
        XCTAssertTrue(rules.contains { ($0["domain_suffix"] as? [String]) == [".example.com"] })

        // Node hostnames resolve through the proxy nameserver, which gets the
        // next tag after the two local resolvers and the policy rule's server.
        let outbounds = try XCTUnwrap(object["outbounds"] as? [[String: Any]])
        let node = try XCTUnwrap(outbounds.first { ($0["server"] as? String) == "hk.example.com" })
        XCTAssertEqual((node["domain_resolver"] as? [String: Any])?["server"] as? String, "ns-3")
    }

    func testHiddifyDistinguishesApexSuffixFromWildcard() throws {
        let config = dns(policy: [
            .init(matcher: "+.example.com", nameservers: ["https://dns.alidns.com/dns-query"]),
            .init(matcher: "*.example.net", nameservers: ["https://1.1.1.1/dns-query"])
        ])
        let result = generate(.hiddify, dns: config)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any]
        )
        let rules = try XCTUnwrap((object["dns"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertTrue(rules.contains { ($0["domain_suffix"] as? [String]) == [".example.com"] })
        XCTAssertTrue(rules.contains { ($0["domain_wildcard"] as? [String]) == ["*.example.net"] })
    }

    func testEmptyDNSBlockFallsBackToBuiltInDefaults() {
        for target in ClientTarget.allCases {
            let empty = generate(target, dns: SubscriptionDNSConfiguration())
            let absent = generate(target, dns: nil)
            XCTAssertEqual(empty.content, absent.content, target.name)
            XCTAssertTrue(empty.conversionWarnings.isEmpty, target.name)
        }
    }

    // MARK: - Shared rules

    func testGeositeOnlySurvivesInStash() {
        let config = dns(policy: [
            .init(matcher: "geosite:cn", nameservers: ["https://dns.alidns.com/dns-query"])
        ])

        for target in ClientTarget.allCases {
            let result = generate(target, dns: config)
            if target == .clash {
                XCTAssertTrue(result.content.contains("geosite:cn"), target.name)
                XCTAssertTrue(result.conversionWarnings.isEmpty, target.name)
            } else {
                XCTAssertFalse(result.content.contains("geosite:cn"), target.name)
                XCTAssertTrue(result.conversionWarnings.contains { $0.contains("geosite") }, target.name)
            }
        }
    }

    func testUnsupportedProtocolIsNeverDowngradedInStash() {
        // Everything Mihomo speaks stays verbatim in the Stash target.
        let config = dns(nameservers: [
            "223.5.5.5", "tls://1.1.1.1", "https://dns.google/dns-query", "quic://dns.adguard.com", "h3://dns.google/dns-query"
        ])
        let content = generate(.clash, dns: config).content
        for resolver in config.nameservers {
            XCTAssertTrue(content.contains(resolver), resolver)
        }
    }

    func testConversionWarningsAreDeduplicated() {
        let config = dns(policy: [
            .init(matcher: "geosite:cn", nameservers: ["https://dns.alidns.com/dns-query"]),
            .init(matcher: "geosite:cn", nameservers: ["https://8.8.8.8/dns-query"])
        ])
        let result = generate(.surge, dns: config)

        XCTAssertEqual(result.conversionWarnings.filter { $0.contains("geosite") }.count, 1)
    }

    func testDefaultsAreUsedWhenAirportShipsNoDNS() {
        for target in ClientTarget.allCases {
            let result = generate(target, dns: nil)
            XCTAssertTrue(result.conversionWarnings.isEmpty, target.name)
        }
        XCTAssertTrue(generate(.clash, dns: nil).content.contains("https://223.5.5.5/dns-query"))
        XCTAssertTrue(generate(.surge, dns: nil).content.contains("dns-server = system, 223.5.5.5, 1.1.1.1"))
        XCTAssertTrue(generate(.quanx, dns: nil).content.contains("[dns]\nno-system\nserver = 223.5.5.5"))
    }

    // MARK: - Imported scheme path

    func testSchemeGenerationCarriesDNSForEveryClient() {
        let scheme = RuleScheme(
            id: "dns-test",
            name: "DNS Test",
            summary: "DNS Test",
            groups: [
                RuleSchemeGroup(name: "🚀 节点选择", kind: .select, members: [.nodePattern(".*")])
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "🚀 节点选择", resource: .inline("[]FINAL"))
            ]
        )
        let config = dns(
            nameservers: ["223.5.5.5"],
            policy: [.init(matcher: "+.example.com", nameservers: ["8.8.8.8"])]
        )

        for target in ClientTarget.allCases {
            let result = ConfigurationGenerator().generate(
                nodes: nodes,
                scheme: scheme,
                target: target,
                dnsConfiguration: config
            )
            XCTAssertGreaterThan(result.content.count, 100, target.name)
            XCTAssertFalse(result.content.isEmpty, target.name)
        }

        let clash = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .clash, dnsConfiguration: config).content
        XCTAssertTrue(clash.contains("  nameserver:\n    - \"223.5.5.5\""))
        let surge = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .surge, dnsConfiguration: config).content
        XCTAssertTrue(surge.contains("dns-server = system, 223.5.5.5"))
        XCTAssertTrue(surge.contains("[Host]\n*.example.com = server:8.8.8.8"))
    }

    // MARK: - Escaping / injection

    func testNewlineInjectionCannotOpenASectionInINITargets() {
        // A hostile nameserver pretends to end the line and open a new section.
        let config = SubscriptionDNSConfiguration(
            nameservers: ["223.5.5.5\n[Proxy]\nDIRECT = direct"],
            nameserverPolicy: [
                .init(matcher: "example.com", nameservers: ["1.1.1.1\n[General]\ndns-server = hijacked"])
            ]
        )

        let surge = generate(.surge, dns: config).content
        // confValue folds the newline into the value line, so no second
        // [Proxy] section header appears: the header occurs exactly once.
        XCTAssertEqual(surge.components(separatedBy: "\n[Proxy]\n").count, 2)
        XCTAssertFalse(surge.split(separator: "\n").contains("DIRECT = direct"))

        let clash = generate(.clash, dns: config).content
        // yaml() folds the value, keeping it a single quoted scalar inside
        // the dns block rather than a top-level key.
        XCTAssertEqual(clash.split(separator: "\n").filter { $0 == "proxies:" }.count, 1)
    }

    func testEgernGroupNameSurvivesWeirdMatcherCharacters() {
        let config = dns(policy: [
            .init(matcher: "*.Example.Com", nameservers: ["tls://1.1.1.1", "https://8.8.8.8/dns-query"])
        ])
        let result = generate(.egern, dns: config)

        XCTAssertTrue(result.content.contains("policy-Example-Com"))
    }
}
