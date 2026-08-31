import XCTest
@testable import Tower

/// The DNS settings Tower writes when the subscription supplies none.
///
/// A rule-based client has to answer DNS itself, because a rule written against
/// a domain cannot match a connection that arrives as an IP. What it answers
/// with decides whether the query was observable, so these defaults are part of
/// the configuration's correctness rather than a nicety.
final class DNSDefaultsTests: XCTestCase {
    private func configuration(for target: ClientTarget) -> String {
        let node = SubscriptionParser().parseURI("trojan://pw@a.example.com:443?sni=c.example.com#T")!
        return ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            .content
    }

    /// `system` is not "unset" — it tells the client to prefer the carrier's
    /// resolver, which is the exact path a leak takes. Writing it was worse
    /// than writing nothing at all.
    func testNoTargetAsksForTheSystemResolver() {
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = configuration(for: target)
            XCTAssertFalse(
                content.contains("dns-server = system") || content.contains("dns-server=system"),
                "\(target.name) 仍然把系统 DNS 排在第一位"
            )
        }
    }

    /// Mihomo queries every resolver in a list concurrently and takes the
    /// fastest answer. One plaintext entry beside encrypted ones therefore
    /// sends the query in the clear anyway and makes the encrypted entries
    /// pointless — so the general lists have to be encrypted throughout.
    func testClashResolverListsCarryNoPlaintextServer() throws {
        let content = configuration(for: .clash)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("dns:") }, content)

        var section: String?
        for line in lines[(start + 1)...] {
            let indent = line.prefix { $0 == " " }.count
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, indent == 0 { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"), indent == 2 {
                section = String(trimmed.dropLast())
                continue
            }
            guard ["nameserver", "fallback"].contains(section ?? ""), trimmed.hasPrefix("- ") else {
                continue
            }
            let server = String(trimmed.dropFirst(2))
            XCTAssertTrue(
                server.hasPrefix("https://") || server.hasPrefix("tls://") || server.hasPrefix("quic://"),
                "\(section ?? "") 里混入了明文解析器 \(server)，同列表里的加密解析器会因此失效"
            )
        }
    }

    /// Resolving the node's own hostname cannot go through the node. Without
    /// this key a fake-ip client answers that lookup with a fake address and
    /// nothing connects at all — the one mistake that turns a DNS improvement
    /// into a total outage.
    func testClashResolvesNodeHostnamesOutsideFakeIP() {
        let content = configuration(for: .clash)

        XCTAssertTrue(content.contains("enhanced-mode: fake-ip"), content)
        XCTAssertTrue(content.contains("proxy-server-nameserver:"), content)
        XCTAssertTrue(content.contains("default-nameserver:"), content)
    }

    /// An IP-based rule without `no-resolve` makes the engine resolve a domain
    /// locally just to evaluate the rule — before any domain rule has had a
    /// chance to match. The domains it happens to are the ones no rule list
    /// covered, which are the ones worth protecting.
    func testEveryGeoIPRuleSkipsResolution() {
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = configuration(for: target)

            // Egern writes the rule as a mapping, so its flag is a neighbouring
            // key rather than a trailing field.
            if target == .egern {
                if content.contains("- geoip:") {
                    XCTAssertTrue(content.contains("no_resolve: true"), content)
                }
                continue
            }

            // A rule, not a setting: `GEOIP,CN,DIRECT` has the comma, while the
            // `geoip: true` inside `fallback-filter` does not.
            let rules = content
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.lowercased().contains("geoip,") }
            for rule in rules {
                XCTAssertTrue(
                    rule.lowercased().contains("no-resolve"),
                    "\(target.name) 的 GEOIP 规则缺少 no-resolve：\(rule)"
                )
            }
        }
    }

    func testImportedSchemeNetworkSettingsOverrideTargetDNSDefaults() throws {
        let scheme = RuleScheme(
            id: "custom-dns",
            name: "Custom DNS",
            summary: "Custom DNS",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))],
            networkSettings: RuleSchemeNetworkSettings(
                ipv6Enabled: false,
                dnsServers: ["9.9.9.9"],
                encryptedDNSServers: ["https://dns.quad9.net/dns-query"],
                proxyTestURLString: "https://example.com/generate_204"
            )
        )
        let node = SubscriptionParser().parseURI(
            "trojan://pw@a.example.com:443?sni=c.example.com#T"
        )!
        let generator = ConfigurationGenerator()

        let surge = generator.generate(nodes: [node], scheme: scheme, target: .surge).content
        XCTAssertTrue(surge.contains("ipv6 = false"), surge)
        XCTAssertTrue(surge.contains("dns-server = 9.9.9.9"), surge)
        XCTAssertTrue(
            surge.contains("encrypted-dns-server = https://dns.quad9.net/dns-query"),
            surge
        )

        let clash = generator.generate(nodes: [node], scheme: scheme, target: .clash).content
        XCTAssertTrue(clash.contains("ipv6: false"), clash)
        XCTAssertTrue(clash.contains("- https://dns.quad9.net/dns-query"), clash)

        let quanX = generator.generate(nodes: [node], scheme: scheme, target: .quanx).content
        XCTAssertTrue(quanX.contains("server_check_url = https://example.com/generate_204"), quanX)
        XCTAssertTrue(quanX.contains("server = 9.9.9.9"), quanX)
    }

    func testGeneratorsDefensivelyReplaceLegacyUnsafePlainDNS() {
        let scheme = makeScheme(dnsProtectionMode: .standard).withNetworkSettings(
            RuleSchemeNetworkSettings(
                dnsServers: ["system", "dns.example.com"],
                encryptedDNSServers: ["https://cloudflare-dns.com/dns-query"]
            )
        )

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = generatedScheme(scheme, target: target)
            let lines = content.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for unsafe in ["system", "dns.example.com"] {
                XCTAssertFalse(
                    lines.contains("dns-server = \(unsafe)")
                        || lines.contains("dns-server=\(unsafe)")
                        || lines.contains("server = \(unsafe)")
                        || lines.contains("- \(unsafe)"),
                    "\(target.name):\n\(content)"
                )
            }
        }
    }

    func testFollowingSchemeDNSDoesNotAddTowerFakeIPProtection() {
        let scheme = makeScheme(dnsProtectionMode: .followScheme)
        let clash = generatedScheme(scheme, target: .clashApple)

        XCTAssertTrue(clash.contains("dns:\n"), clash)
        XCTAssertTrue(clash.contains("nameserver:\n"), clash)
        XCTAssertFalse(clash.contains("enhanced-mode: fake-ip"), clash)
        XCTAssertFalse(clash.contains("proxy-server-nameserver:"), clash)
        XCTAssertFalse(clash.contains("fallback-filter:"), clash)
        XCTAssertFalse(clash.contains("tun:\n"), clash)
    }

    func testStrictProtectionAddsSurgeDNSInterception() {
        let scheme = makeScheme(dnsProtectionMode: .strict)
        let surge = generatedScheme(scheme, target: .surge)

        XCTAssertTrue(surge.contains("hijack-dns = *:53"), surge)
        XCTAssertTrue(
            surge.contains("encrypted-dns-follow-outbound-mode = true"),
            surge
        )
    }

    func testStrictProtectionAddsMihomoTUNInterceptionOnlyToClashTarget() {
        let scheme = makeScheme(dnsProtectionMode: .strict)
        let clash = generatedScheme(scheme, target: .clashApple)

        XCTAssertTrue(clash.contains("tun:\n"), clash)
        XCTAssertTrue(clash.contains("dns-hijack:\n"), clash)
        XCTAssertTrue(clash.contains("- any:53"), clash)
        XCTAssertTrue(clash.contains("- tcp://any:53"), clash)
        XCTAssertTrue(clash.contains("strict-route: true"), clash)

        let stash = generatedScheme(scheme, target: .clash)
        XCTAssertFalse(stash.contains("tun:\n"), stash)
        XCTAssertFalse(stash.contains("strict-route: true"), stash)
    }

    func testStandardProtectionKeepsCurrentClashAndSurgeBehavior() {
        let scheme = makeScheme(dnsProtectionMode: .standard)
        let clash = generatedScheme(scheme, target: .clashApple)
        let surge = generatedScheme(scheme, target: .surge)

        XCTAssertTrue(clash.contains("enhanced-mode: fake-ip"), clash)
        XCTAssertTrue(clash.contains("proxy-server-nameserver:"), clash)
        XCTAssertFalse(clash.contains("tun:\n"), clash)
        XCTAssertFalse(surge.contains("hijack-dns = *:53"), surge)
    }

    private func makeScheme(
        dnsProtectionMode: RuleSchemeDNSProtectionMode
    ) -> RuleScheme {
        RuleScheme(
            id: "dns-protection-\(dnsProtectionMode.rawValue)",
            name: "DNS Protection",
            summary: "DNS Protection",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))
            ],
            networkSettings: RuleSchemeNetworkSettings(
                ipv6Enabled: true,
                dnsServers: ["1.1.1.1"],
                encryptedDNSServers: ["https://cloudflare-dns.com/dns-query"],
                proxyTestURLString: "https://cp.cloudflare.com/generate_204",
                dnsProtectionMode: dnsProtectionMode
            )
        )
    }

    private func generatedScheme(
        _ scheme: RuleScheme,
        target: ClientTarget
    ) -> String {
        let node = SubscriptionParser().parseURI(
            "trojan://pw@a.example.com:443?sni=c.example.com#T"
        )!
        return ConfigurationGenerator()
            .generate(nodes: [node], scheme: scheme, target: target)
            .content
    }
}

private extension RuleScheme {
    func withNetworkSettings(_ settings: RuleSchemeNetworkSettings) -> Self {
        var copy = self
        copy.networkSettings = settings
        return copy
    }
}
