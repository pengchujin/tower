import XCTest
@testable import Tower

/// Domestic and remote resolvers are separate lists (2026-09-29). Before,
/// sing-box's "remote" servers were the domestic list reached through the
/// proxy, and mihomo's fallback asked 1.1.1.1 directly for every lookup.
final class DNSSplitTests: XCTestCase {
    private let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")

    private func scheme(_ settings: RuleSchemeNetworkSettings?) throws -> RuleScheme {
        var scheme = try RuleSchemeParser().parse(
            text: "[Proxy Group]\nOpenAI = select,Test\n[Rule]\nDOMAIN-SUFFIX,cn.example,DIRECT\nDOMAIN-SUFFIX,google.com,OpenAI\nGEOIP,CN,DIRECT\nFINAL,OpenAI",
            id: "dns", name: "DNS", summary: ""
        )
        scheme.networkSettings = settings
        return scheme
    }

    private func content(_ scheme: RuleScheme, _ target: ClientTarget) -> String {
        ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, schemes: RuleSchemeRepository()).content
    }

    private func singBoxDNS(_ scheme: RuleScheme) throws -> [String: Any] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content(scheme, .singBox).utf8)) as? [String: Any])
        return try XCTUnwrap(json["dns"] as? [String: Any])
    }

    private func settings(remote: [String] = [], mode: RuleSchemeDNSProtectionMode = .standard) -> RuleSchemeNetworkSettings {
        RuleSchemeNetworkSettings(dnsServers: ["223.5.5.5"], encryptedDNSServers: ["https://223.5.5.5/dns-query"],
                                  remoteDNSServers: remote, dnsProtectionMode: mode)
    }

    func testSingBoxRemoteServersComeFromTheRemoteList() throws {
        let dns = try singBoxDNS(scheme(settings(remote: ["https://9.9.9.9/dns-query", "tls://dns.google"])))
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        let remote = servers.filter { ($0["tag"] as? String)?.hasPrefix("remote-") == true || $0["tag"] as? String == "remote" }
        XCTAssertEqual(servers.first { $0["tag"] as? String == "remote" }?["server"] as? String, "9.9.9.9")
        XCTAssertEqual(servers.first { $0["tag"] as? String == "remote-2" }?["server"] as? String, "dns.google")
        XCTAssertEqual(servers.first { $0["tag"] as? String == "remote-2" }?["domain_resolver"] as? String, "local")
        XCTAssertFalse(remote.contains { $0["server"] as? String == "223.5.5.5" }, "\(servers)")
        // The user's own ECS-capable resolver answers the Chinese lookup.
        let hint = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote-cn" })
        XCTAssertEqual(hint["server"] as? String, "dns.google")
        XCTAssertEqual(hint["type"] as? String, "tls")
    }

    func testSettingsSavedBeforeTheSplitUseTheDefaultRemoteList() throws {
        let data = Data(#"{"dnsServers":["223.5.5.5"],"encryptedDNSServers":["https://223.5.5.5/dns-query"],"dnsProtectionMode":"standard"}"#.utf8)
        let legacy = try JSONDecoder().decode(RuleSchemeNetworkSettings.self, from: data)
        XCTAssertEqual(legacy.remoteDNSServers, [])
        XCTAssertEqual(legacy.effectiveRemoteDNSServers, RuleSchemeNetworkSettings.towerDefault.remoteDNSServers)
        XCTAssertEqual(RuleSchemeNetworkSettingsDraft(settings: legacy).remoteDNSServers, legacy.effectiveRemoteDNSServers)
        let servers = try XCTUnwrap(try singBoxDNS(scheme(legacy))["servers"] as? [[String: Any]])
        // Literal addresses: a domestic resolver may answer dns.google with a
        // forged address, so the defaults never need one to be looked up.
        XCTAssertEqual(servers.first { $0["tag"] as? String == "remote" }?["server"] as? String, "8.8.8.8")
        XCTAssertNil(servers.first { $0["tag"] as? String == "remote" }?["domain_resolver"])
        XCTAssertEqual((servers.first { $0["tag"] as? String == "remote" }?["tls"] as? [String: Any])?["server_name"] as? String, "dns.google")
        XCTAssertEqual(servers.first { $0["tag"] as? String == "remote-cn" }?["server"] as? String, "8.8.8.8")
    }

    func testDraftRequiresAValidRemoteResolver() {
        var draft = RuleSchemeNetworkSettingsDraft(settings: nil)
        draft.remoteDNSServers = ["  "]
        XCTAssertThrowsError(try draft.validatedSettings()) { error in
            XCTAssertEqual(error as? RuleSchemeNetworkSettingsDraftError, .missingRemoteDNS)
        }
        draft.remoteDNSServers = ["dns.google"]
        XCTAssertThrowsError(try draft.validatedSettings())
        draft.remoteDNSServers = ["h3://dns.google/dns-query"]
        XCTAssertEqual(try draft.validatedSettings().remoteDNSServers, ["h3://dns.google/dns-query"])
    }

    /// Strict mode keeps direct names off the domestic resolver, yet they
    /// still need a Chinese CDN edge, so they ask the remote with ECS.
    func testSingBoxStrictResolvesDirectNamesRemotelyWithChineseSubnet() throws {
        let dns = try singBoxDNS(scheme(settings(mode: .strict)))
        let rules = try XCTUnwrap(dns["rules"] as? [[String: Any]])
        let direct = try XCTUnwrap(rules.first { ($0["domain_suffix"] as? [String]) == ["cn.example"] })
        XCTAssertEqual(direct["server"] as? String, "remote-cn")
        XCTAssertEqual(direct["client_subnet"] as? String, SingBoxDNSPolicy.chinaClientSubnet)
        XCTAssertEqual(dns["final"] as? String, "remote")
        // Standard mode still sends them to the domestic resolver.
        let standard = try XCTUnwrap(try singBoxDNS(scheme(settings()))["rules"] as? [[String: Any]])
        XCTAssertEqual(standard.first { ($0["domain_suffix"] as? [String]) == ["cn.example"] }?["server"] as? String, "local")
    }

    func testMihomoStandardModeDropsFallback() throws {
        for settings in [nil, settings()] {
            let clash = content(try scheme(settings), .clashMi)
            XCTAssertTrue(clash.contains("enhanced-mode: fake-ip"), clash)
            XCTAssertTrue(clash.contains("proxy-server-nameserver:\n    - https://223.5.5.5/dns-query"), clash)
            XCTAssertFalse(clash.contains("fallback:"), clash)
            XCTAssertFalse(clash.contains("fallback-filter:"), clash)
            XCTAssertFalse(clash.contains("1.1.1.1"), clash)
        }
        let preset = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clashMi).content
        XCTAssertFalse(preset.contains("fallback-filter:"), preset)
    }

    func testMihomoStrictModeResolvesThroughTheProxyWithChineseSubnet() throws {
        let strict = try scheme(settings(remote: ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"], mode: .strict))
        // The "Clash" app runs a mihomo 1.19.33-derived core (clash.md), not
        // Stash's dialect, so it takes the suffix like the other mihomo apps.
        for target in [ClientTarget.clashMi, .clashApple] {
            let clash = content(strict, target)
            XCTAssertTrue(clash.contains("  nameserver:\n    - \"https://dns.google/dns-query#OpenAI&ecs=114.114.114.0/24&ecs-override=true\"\n"), clash)
            XCTAssertFalse(clash.contains("https://1.1.1.1/dns-query#"), "Cloudflare ignores ECS: \(clash)")
            XCTAssertTrue(clash.contains("proxy-server-nameserver:\n    - https://223.5.5.5/dns-query"), clash)
        }
        // Stash keeps the domestic resolver: its document has no such suffix.
        let stash = content(strict, .clash)
        XCTAssertFalse(stash.contains("#OpenAI"), stash)
        // Karing documents neither the suffix nor the TUN block.
        let karing = content(strict, .karing)
        XCTAssertFalse(karing.contains("#OpenAI"), karing)
        XCTAssertTrue(karing.contains("  nameserver:\n    - https://223.5.5.5/dns-query"), karing)
    }

    func testMihomoStrictModeFallsBackToGoogleWhenNoRemoteHonoursECS() throws {
        let clash = content(try scheme(settings(remote: ["https://1.1.1.1/dns-query"], mode: .strict)), .clashVerge)
        XCTAssertTrue(clash.contains("https://8.8.8.8/dns-query#OpenAI&ecs="), clash)
    }

    // MARK: - Terminal GEOIP (D01 revisited)

    private func rules(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "rules:") else { return [] }
        return lines[(start + 1)...].filter { $0.hasPrefix("  - ") }.map { String($0.dropFirst(4)) }
    }

    /// Unlisted Chinese sites used to fall through to MATCH and the proxy.
    /// The terminal GEOIP now resolves, through the proxy with a Chinese
    /// subnet, and the direct connection asks the domestic resolvers again.
    func testMihomoStandardResolvesTheTerminalGeoIPThroughTheProxy() throws {
        let clash = content(try scheme(settings()), .clashMi)
        let lines = rules(clash)
        XCTAssertEqual(Array(lines.suffix(2)), ["GEOIP,CN,DIRECT", "MATCH,OpenAI"], clash)
        XCTAssertTrue(clash.contains("  nameserver:\n    - \"https://8.8.8.8/dns-query#OpenAI&ecs=114.114.114.0/24&ecs-override=true\"\n  direct-nameserver:\n    - https://223.5.5.5/dns-query\n"), clash)
        // Strict mode: every lookup through the proxy, no domestic direct resolver.
        let strict = content(try scheme(settings(mode: .strict)), .clashMi)
        XCTAssertTrue(rules(strict).contains("GEOIP,CN,DIRECT"), strict)
        XCTAssertFalse(strict.contains("direct-nameserver"), strict)
        // Follow-scheme already resolves every name with the scheme's DNS.
        let follow = content(try scheme(settings(mode: .followScheme)), .clashMi)
        XCTAssertTrue(rules(follow).contains("GEOIP,CN,DIRECT"), follow)
        XCTAssertFalse(follow.contains("#OpenAI"), follow)
    }

    func testOtherClashClientsKeepNoResolve() throws {
        for target in [ClientTarget.karing, .clash, .shadowrocket] {
            let output = content(try scheme(settings()), target)
            XCTAssertTrue(rules(output).contains("GEOIP,CN,DIRECT,no-resolve"), "\(target.name): \(output)")
            XCTAssertFalse(output.contains("direct-nameserver"), output)
        }
    }

    func testOnlyTheTerminalAutomaticNoResolveIsReleased() throws {
        func scheme(_ rules: [String]) throws -> RuleScheme {
            var scheme = try RuleSchemeParser().parse(text: "[Proxy Group]\nOpenAI = select,Test\n[Rule]\n" + rules.joined(separator: "\n"), id: "t", name: "T", summary: "")
            scheme.networkSettings = settings()
            return scheme
        }
        let midList = rules(content(try scheme(["GEOIP,US,OpenAI", "DOMAIN-SUFFIX,cn.example,DIRECT", "FINAL,OpenAI"]), .clashMi))
        XCTAssertTrue(midList.contains("GEOIP,US,OpenAI,no-resolve"), "\(midList)")
        let explicit = rules(content(try scheme(["GEOIP,CN,DIRECT,no-resolve", "FINAL,OpenAI"]), .clashMi))
        XCTAssertTrue(explicit.contains("GEOIP,CN,DIRECT,no-resolve"), "\(explicit)")
        // Without any node there is no proxy path for DNS, so the lookup
        // would reach the domestic resolver: keep no-resolve.
        let output = ConfigurationGenerator().generate(nodes: [], scheme: try scheme(["GEOIP,CN,DIRECT", "FINAL,OpenAI"]),
                                                       target: .clashMi, schemes: RuleSchemeRepository()).content
        XCTAssertTrue(rules(output).contains("GEOIP,CN,DIRECT,no-resolve"), output)
        XCTAssertTrue(output.contains("  nameserver:\n    - https://223.5.5.5/dns-query\n"), output)
    }

    /// Every group also offering DIRECT used to mean no proxy path for DNS.
    func testMixedSelectorsGetADedicatedDNSGroup() throws {
        var mixed = try RuleSchemeParser().parse(text: "[Proxy Group]\nOpenAI = select,Test,DIRECT\n[Rule]\nGEOIP,CN,DIRECT\nFINAL,OpenAI", id: "m", name: "M", summary: "")
        mixed.networkSettings = settings()
        let output = content(mixed, .clashMi)
        XCTAssertTrue(output.contains("#DNS 自动选择&ecs="), output)
        XCTAssertTrue(rules(output).contains("GEOIP,CN,DIRECT"), output)
        // A reusable group of nodes means no extra group.
        XCTAssertFalse(content(try scheme(settings()), .clashMi).contains("DNS 自动选择"))
        // Karing keeps the domestic resolvers and gets no such group.
        XCTAssertFalse(content(mixed, .karing).contains("DNS 自动选择"))
    }

    /// Self-Configuration rules are downloaded by the user, so the test
    /// bundle has none; the terminal GEOIP shares `releasingTerminalGeoIP`
    /// with the scheme path covered above.
    func testPresetResolvesThroughTheAutomaticGroup() {
        let preset = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clashMi).content
        XCTAssertTrue(preset.contains("#\(RulePolicy.auto.configurationName)&ecs=114.114.114.0/24"), preset)
        XCTAssertTrue(preset.contains("  direct-nameserver:\n"), preset)
        XCTAssertTrue(preset.hasPrefix("# Generated locally by 塔台 for Clash Mi"), preset)
        XCTAssertTrue(preset.contains("ipv6: true\n\ndns:\n"), preset)
        let karing = ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: .karing).content
        XCTAssertFalse(karing.contains("direct-nameserver"), karing)
        XCTAssertTrue(karing.contains("  nameserver:\n    - https://223.5.5.5/dns-query\n"), karing)
        let empty = ConfigurationGenerator().generate(nodes: [], preset: RulePreset.builtIns[0], target: .clashMi).content
        XCTAssertFalse(empty.contains("&ecs="), empty)
    }

    func testFollowSchemeSummaryMentionsLocalResolution() {
        XCTAssertTrue(RuleSchemeDNSProtectionMode.followScheme.summary.contains("Clash"))
    }

    func testParserSeparatesProxiedResolvers() throws {
        let clash = try RuleSchemeParser().parse(text: """
        dns:
          default-nameserver:
            - 223.5.5.5
          nameserver:
            - https://doh.pub/dns-query
            - 'https://dns.google/dns-query#Proxy&ecs=1.2.3.0/24'
            - https://dns.alidns.com/dns-query#DIRECT
            - https://cloudflare-dns.com/dns-query#h3=true
          fallback:
            - tls://1.1.1.1
        proxy-groups:
          - {name: Proxy, type: select, proxies: [DIRECT]}
        rules:
          - MATCH,Proxy
        """, id: "p", name: "P", summary: "")
        let settings = try XCTUnwrap(clash.networkSettings)
        XCTAssertEqual(settings.encryptedDNSServers, ["https://doh.pub/dns-query", "https://dns.alidns.com/dns-query", "h3://cloudflare-dns.com/dns-query"])
        XCTAssertEqual(settings.remoteDNSServers, ["https://dns.google/dns-query", "tls://1.1.1.1"])

        let surge = try RuleSchemeParser().parse(text: """
        [General]
        encrypted-dns-server = https://223.5.5.5/dns-query
        tower-remote-dns-server = https://dns.google/dns-query, quic://dns.adguard-dns.com
        [Proxy Group]
        Proxy = select,DIRECT
        [Rule]
        FINAL,Proxy
        """, id: "s", name: "S", summary: "")
        XCTAssertEqual(surge.networkSettings?.remoteDNSServers, ["https://dns.google/dns-query", "quic://dns.adguard-dns.com"])
    }

    func testClientSubnetSupportIsLimitedToKnownResolvers() {
        XCTAssertTrue(RuleSchemeNetworkSettings.supportsClientSubnet("https://dns.google/dns-query"))
        XCTAssertTrue(RuleSchemeNetworkSettings.supportsClientSubnet("tls://8.8.8.8"))
        XCTAssertFalse(RuleSchemeNetworkSettings.supportsClientSubnet("https://1.1.1.1/dns-query"))
        XCTAssertFalse(RuleSchemeNetworkSettings.supportsClientSubnet("https://dns.quad9.net/dns-query"))
    }
}
