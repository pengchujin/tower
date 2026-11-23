import XCTest
@testable import Tower

/// Regressions for the 2026-09-28 rule export audit (docs/RULE_EXPORT_AUDIT.md).
final class RuleExportAuditFixTests: XCTestCase {
    private let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")

    private func surge(_ rules: [String]) throws -> RuleScheme {
        try RuleSchemeParser().parse(
            text: "[Proxy Group]\nOpenAI = select,Test\n[Rule]\n" + rules.joined(separator: "\n"),
            id: "audit", name: "Audit", summary: ""
        )
    }

    private func mihomo(_ rules: [String]) throws -> RuleScheme {
        try RuleSchemeParser().parse(
            text: "proxy-groups:\n  - name: OpenAI\n    type: select\n    proxies: [Test]\nrules:\n" + rules.map { "  - " + $0 }.joined(separator: "\n"),
            id: "audit", name: "Audit", summary: ""
        )
    }

    private func output(
        _ scheme: RuleScheme,
        _ target: ClientTarget,
        schemes: RuleSchemeRepository = RuleSchemeRepository(),
        preferRuleSets: Bool = false
    ) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, schemes: schemes, preferRuleSets: preferRuleSets)
    }

    /// No published local rules unless a test asks: the bundled manifest's
    /// GEOIP,CN list would otherwise change what these cases are about.
    private func repository(
        _ lists: [URL: String],
        publishedLocalRules: RuleSchemeRepository.PublishedLocalRules = .init()
    ) throws -> RuleSchemeRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = RuleDownloadStore(folderURL: folder)
        for (url, content) in lists { try store.store(content, for: url) }
        return RuleSchemeRepository(downloadStore: store, publishedLocalRules: publishedLocalRules)
    }

    // MARK: - Loon filters

    func testLoonRegionGroupsNameNoFilterWithoutRemoteSubscriptions() throws {
        let scheme = try XCTUnwrap(RuleSchemeRepository().bundledSchemes().first { $0.id == "acl4ssr-full" })
        let hongKong = ProxyNode(kind: .trojan, name: "🇭🇰 香港 01", server: "hk.example.com", port: 443, password: "pw", rawURI: "")
        let content = ConfigurationGenerator().generate(nodes: [node, hongKong], scheme: scheme, target: .loon, preferRuleSets: false).content

        XCTAssertFalse(content.contains("塔台筛选"), content)
        let groups = try XCTUnwrap(content.components(separatedBy: "[Proxy Group]\n").last?.components(separatedBy: "\n[").first)
        let defined = Set(content.components(separatedBy: "\n")
            .filter { $0.contains(" = ") }
            .map { String($0.prefix { $0 != "=" }).trimmingCharacters(in: .whitespaces) })
        for line in groups.split(separator: "\n") {
            let members = line.split(separator: "=", maxSplits: 1).last?.split(separator: ",").dropFirst() ?? []
            for member in members where !member.contains("=") {
                let name = member.trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(defined.contains(name) || ["DIRECT", "REJECT"].contains(name), "\(name) in \(line)")
            }
        }
        let hongKongGroup = try XCTUnwrap(content.components(separatedBy: "\n").first { $0.hasPrefix(exportedGroupName("🇭🇰 香港节点", for: .surge) + " = ") })
        XCTAssertTrue(hongKongGroup.contains("🇭🇰 香港 01"), hongKongGroup)
    }

    // MARK: - Options

    func testLoonAndShadowrocketWriteOptionsAfterThePolicy() throws {
        let scheme = try surge([
            "DOMAIN-SUFFIX,ads.example,REJECT,pre-matching",
            "DOMAIN-SUFFIX,openai.com,OpenAI,extended-matching",
            "FINAL,OpenAI"
        ])

        let shadowrocket = output(scheme, .shadowrocket)
        XCTAssertTrue(shadowrocket.content.contains("DOMAIN-SUFFIX,ads.example,REJECT,pre-matching"), shadowrocket.content)
        XCTAssertTrue(shadowrocket.content.contains("DOMAIN-SUFFIX,openai.com,OpenAI,extended-matching"), shadowrocket.content)

        let loon = output(scheme, .loon)
        XCTAssertFalse(loon.hasInvalidPolicyReferences)
        XCTAssertTrue(loon.content.contains("DOMAIN-SUFFIX,ads.example,REJECT\n"), loon.content)
        XCTAssertTrue(loon.content.contains("DOMAIN-SUFFIX,openai.com,OpenAI\n"), loon.content)
        XCTAssertFalse(loon.content.contains("matching"), loon.content)
        XCTAssertTrue(loon.diagnostics.contains { $0.contains("extended-matching, pre-matching") }, "\(loon.diagnostics)")
    }

    func testSurgeOnlyOptionsNoLongerBlockOtherClients() throws {
        let scheme = try surge(["DOMAIN-SUFFIX,ads.example,REJECT,pre-matching", "FINAL,OpenAI"])
        for target in [ClientTarget.clashMi, .clash, .singBox, .hiddify, .egern, .quanx] {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, "\(target): \(result.diagnostics)")
            XCTAssertTrue(result.content.contains("ads.example"), "\(target): \(result.content)")
        }
        XCTAssertTrue(output(scheme, .clashMi).content.contains("DOMAIN-SUFFIX,ads.example,REJECT\n"))
    }

    // MARK: - Source addresses

    func testSourceAddressRuleIsNeverWrittenAsDestination() throws {
        let scheme = try mihomo(["IP-CIDR,192.168.0.0/16,OpenAI,src", "MATCH,OpenAI"])
        for target in [ClientTarget.quanx, .loon, .shadowrocket, .egern] {
            let result = output(scheme, target)
            XCTAssertFalse(result.content.contains("192.168.0.0/16"), "\(target): \(result.content)")
            XCTAssertTrue(result.diagnostics.contains { $0.contains("192.168.0.0/16") }, "\(target)")
        }
    }

    // MARK: - Dialects

    func testLogicalRulesReachLoonShadowrocketAndEgern() throws {
        let scheme = try surge(["AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT", "FINAL,OpenAI"])
        XCTAssertTrue(output(scheme, .loon).content.contains("AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT"))
        XCTAssertTrue(output(scheme, .shadowrocket).content.contains("AND,((PROTOCOL,UDP),(DST-PORT,443)),REJECT"))
        let egern = output(scheme, .egern)
        XCTAssertFalse(egern.hasInvalidPolicyReferences, "\(egern.diagnostics)")
        XCTAssertTrue(egern.content.contains("""
          - and:
              match:
                - protocol:
                    match: "udp"
                - dest_port:
                    match: "443"
              policy: "REJECT"
        """), egern.content)
    }

    func testEgernNotTakesOneMapping() throws {
        let scheme = try surge(["NOT,((DOMAIN-SUFFIX,example.com)),OpenAI", "FINAL,OpenAI"])
        XCTAssertTrue(output(scheme, .egern).content.contains("""
          - not:
              match:
                domain_suffix:
                  match: "example.com"
              policy: "OpenAI"
        """))
    }

    func testShadowrocketPortAndProtocolSpelling() throws {
        let scheme = try surge(["DEST-PORT,8443,OpenAI", "PROTOCOL,UDP,OpenAI", "FINAL,OpenAI"])
        let content = output(scheme, .shadowrocket).content
        XCTAssertTrue(content.contains("DST-PORT,8443,OpenAI"), content)
        // PROTOCOL is only valid inside a logical rule on Shadowrocket.
        XCTAssertFalse(content.contains("PROTOCOL,UDP"), content)
    }

    func testMihomoPortRuleReachesLoonAndShadowrocket() throws {
        let scheme = try mihomo(["DST-PORT,8443,OpenAI", "NETWORK,UDP,OpenAI", "MATCH,OpenAI"])
        let loon = output(scheme, .loon).content
        XCTAssertTrue(loon.contains("DEST-PORT,8443,OpenAI"), loon)
        XCTAssertTrue(loon.contains("PROTOCOL,UDP,OpenAI"), loon)
        XCTAssertTrue(output(scheme, .shadowrocket).content.contains("DST-PORT,8443,OpenAI"))
    }

    func testUndocumentedTypesAreLeftOutOfLoonAndShadowrocket() throws {
        let scheme = try surge(["PROCESS-NAME,Telegram,OpenAI", "SUBNET,TYPE:WIFI,OpenAI", "SRC-IP,192.168.1.2,OpenAI",
                                "RULE-SET,SYSTEM,DIRECT", "DOMAIN,keep.example,OpenAI", "FINAL,OpenAI"])
        for target in [ClientTarget.loon, .shadowrocket] {
            let content = output(scheme, target).content
            for type in ["PROCESS-NAME", "SUBNET", "SRC-IP", "RULE-SET"] {
                XCTAssertFalse(content.contains(type + ","), "\(target) \(type): \(content)")
            }
            XCTAssertTrue(content.contains("DOMAIN,keep.example,OpenAI"), content)
        }
    }

    func testSkippedProcessRulesCollapseIntoOneNotice() throws {
        let scheme = try surge(["PROCESS-NAME,apsd,OpenAI", "PROCESS-NAME,trustd,OpenAI", "PROCESS-NAME,fmfd,OpenAI",
                                "SUBNET,TYPE:WIFI,OpenAI", "DOMAIN,keep.example,OpenAI", "FINAL,OpenAI"])
        let diagnostics = output(scheme, .loon).diagnostics
        XCTAssertFalse(diagnostics.contains { $0.contains("PROCESS-NAME,") }, "\(diagnostics)")
        XCTAssertEqual(diagnostics.filter { $0.contains("3 条进程规则") }.count, 1, "\(diagnostics)")
        // Other unsupported rules still get their own line.
        XCTAssertTrue(diagnostics.contains { $0.contains("SUBNET,TYPE:WIFI") }, "\(diagnostics)")
    }

    func testEgernUsesItsOwnRuleKeys() throws {
        let scheme = try surge([
            "IP-CIDR6,2001:db8::/32,OpenAI,no-resolve",
            "IP-CIDR,10.0.0.0/8,OpenAI,no-resolve",
            "IP-ASN,13335,OpenAI,no-resolve",
            "DOMAIN-WILDCARD,*.openai.*,OpenAI",
            "USER-AGENT,ChatGPT*,OpenAI",
            "FINAL,OpenAI"
        ])
        let content = output(scheme, .egern).content
        XCTAssertTrue(content.contains("  - ip_cidr6:\n      match: \"2001:db8::/32\"\n      no_resolve: true\n"), content)
        XCTAssertTrue(content.contains("  - ip_cidr:\n      match: \"10.0.0.0/8\"\n      no_resolve: true\n"), content)
        XCTAssertTrue(content.contains("  - asn:\n      match: \"13335\"\n      no_resolve: true\n"), content)
        XCTAssertTrue(content.contains("  - domain_wildcard:\n      match: \"*.openai.*\"\n"), content)
        XCTAssertTrue(content.contains("  - user_agent:\n      match: \"ChatGPT*\"\n"), content)
    }

    func testStashDoesNotReceiveUndocumentedPortTypes() throws {
        let scheme = try mihomo(["SRC-PORT,5353,OpenAI", "IN-PORT,7890,OpenAI", "DST-PORT,443,OpenAI", "MATCH,OpenAI"])
        let content = output(scheme, .clash).content
        XCTAssertFalse(content.contains("SRC-PORT"), content)
        XCTAssertFalse(content.contains("IN-PORT"), content)
        XCTAssertTrue(content.contains("DST-PORT,443,OpenAI"), content)
    }

    // MARK: - Built-in rejects

    func testSurgeOnlyRejectsBecomeTheNearestReject() throws {
        let scheme = try surge([
            "AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT-NO-DROP",
            "DOMAIN-SUFFIX,ads.example,REJECT-TINYGIF",
            "FINAL,OpenAI"
        ])
        let expected: [ClientTarget: (String, String)] = [
            .clashMi: ("AND,((NETWORK,UDP),(DST-PORT,443)),REJECT", "DOMAIN-SUFFIX,ads.example,REJECT"),
            // Stash has its own PROTOCOL rule.
            .clash: ("AND,((PROTOCOL,UDP),(DST-PORT,443)),REJECT", "DOMAIN-SUFFIX,ads.example,REJECT"),
            .shadowrocket: ("AND,((PROTOCOL,UDP),(DST-PORT,443)),REJECT-NO-DROP", "DOMAIN-SUFFIX,ads.example,REJECT-TINYGIF"),
            .loon: ("AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT", "DOMAIN-SUFFIX,ads.example,REJECT-IMG")
        ]
        for (target, lines) in expected {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, "\(target): \(result.diagnostics)")
            XCTAssertTrue(result.content.contains(lines.0 + "\n"), "\(target): \(result.content)")
            XCTAssertTrue(result.content.contains(lines.1 + "\n"), "\(target): \(result.content)")
        }
        let loon = output(scheme, .loon)
        XCTAssertTrue(loon.diagnostics.contains { $0.contains("REJECT-TINYGIF") && $0.contains("REJECT-IMG") }, "\(loon.diagnostics)")

        let quanX = output(try surge(["DOMAIN-SUFFIX,ads.example,REJECT-TINYGIF", "FINAL,OpenAI"]), .quanx)
        XCTAssertFalse(quanX.hasInvalidPolicyReferences, "\(quanX.diagnostics)")
        // reject-img is a Quantumult X rewrite action, not a filter policy:
        // the client rejects the profile with 未知策略或节点 "reject-img".
        XCTAssertTrue(quanX.content.contains("host-suffix, ads.example, REJECT"), quanX.content)
        XCTAssertFalse(quanX.content.lowercased().contains("reject-img"), quanX.content)

        let singBox = output(scheme, .singBox)
        XCTAssertFalse(singBox.hasInvalidPolicyReferences, "\(singBox.diagnostics)")
        XCTAssertFalse(singBox.content.contains("REJECT-"), singBox.content)
    }

    func testCellularPolicyStillBlocksOtherClients() throws {
        let scheme = try surge(["DOMAIN,example.com,CELLULAR", "FINAL,OpenAI"])
        XCTAssertTrue(output(scheme, .clashMi).hasInvalidPolicyReferences)
    }

    // MARK: - GEOIP on sing-box

    func testSingBoxSpellsOutGeoIPFromTheBundledDatabase() throws {
        let scheme = try surge(["GEOIP,CN,DIRECT", "GEOIP,LAN,DIRECT", "FINAL,OpenAI"])
        for target in [ClientTarget.singBox, .hiddify] {
            let result = output(scheme, target)
            XCTAssertFalse(result.diagnostics.contains { $0.contains("GEOIP") }, "\(target): \(result.diagnostics)")
            let data = try XCTUnwrap(result.content.data(using: .utf8))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let route = try XCTUnwrap(json["route"] as? [String: Any])
            let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
            if target == .singBox {
                // One inline rule set, referenced by the route rule.
                let country = try XCTUnwrap(rules.first { ($0["rule_set"] as? [String]) == ["tower-geoip-cn"] })
                XCTAssertEqual(country["outbound"] as? String, "DIRECT")
                let sets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
                let inline = try XCTUnwrap(sets.first { $0["tag"] as? String == "tower-geoip-cn" })
                XCTAssertEqual(inline["type"] as? String, "inline")
                XCTAssertGreaterThan(((inline["rules"] as? [[String: Any]])?.first?["ip_cidr"] as? [String])?.count ?? 0, 1000)
                XCTAssertEqual(sets.filter { $0["tag"] as? String == "tower-geoip-cn" }.count, 1)
            } else {
                // Hiddify keeps the ranges inline: its core is versioned separately.
                let country = try XCTUnwrap(rules.first { ($0["ip_cidr"] as? [String])?.count ?? 0 > 1000 })
                XCTAssertEqual(country["outbound"] as? String, "DIRECT")
            }
            XCTAssertTrue(rules.contains { $0["ip_is_private"] as? Bool == true && $0["outbound"] as? String == "DIRECT" })
        }
        let cidrs = IPCountryDatabase.cidrs(forCountry: "CN")
        XCTAssertTrue(cidrs.contains { !$0.contains(":") })
        XCTAssertTrue(cidrs.contains { $0.contains(":") })
        XCTAssertEqual(IPCountryDatabase(bundle: .main).countryCode(forIPAddress: String(cidrs[0].prefix { $0 != "/" })), "CN")
    }

    func testRangeToCIDRBlocks() {
        typealias Word = IPCountryDatabase.AddressWord
        func v4(_ a: UInt64) -> Word { Word(high: 0, low: a) }
        XCTAssertEqual(IPCountryDatabase.blocks(from: v4(0x0A00_0000), to: v4(0x0A00_01FF), width: 32), ["10.0.0.0/23"])
        XCTAssertEqual(IPCountryDatabase.blocks(from: v4(0x0102_0304), to: v4(0x0102_0306), width: 32), ["1.2.3.4/31", "1.2.3.6/32"])
        XCTAssertEqual(IPCountryDatabase.blocks(from: v4(0), to: v4(0xFFFF_FFFF), width: 32), ["0.0.0.0/0"])
        XCTAssertEqual(
            IPCountryDatabase.blocks(from: Word(high: 0x2001_0DB8_0000_0000, low: 0),
                                     to: Word(high: 0x2001_0DB8_FFFF_FFFF, low: .max), width: 128),
            ["2001:db8::/32"]
        )
        XCTAssertEqual(
            IPCountryDatabase.blocks(from: Word(high: 0x2400_0000_0000_0000, low: 0),
                                     to: Word(high: 0x2400_0000_0000_0000, low: 1), width: 128),
            ["2400::/127"]
        )
    }

    // MARK: - Rule list order and downloads

    func testLoonAndQuanXInlineListsThatALocalRuleFollows() throws {
        let url = URL(string: "https://rules.example.com/ads.list")!
        let repository = try repository([url: "DOMAIN-SUFFIX,ads.example\nIP-CIDR,203.0.113.0/24,no-resolve"])
        let before = try surge(["RULE-SET,\(url.absoluteString),REJECT", "GEOIP,CN,DIRECT", "FINAL,OpenAI"])
        for target in [ClientTarget.loon, .quanx] {
            let content = output(before, target, schemes: repository, preferRuleSets: true).content
            XCTAssertFalse(content.contains(url.absoluteString), "\(target): \(content)")
            let ads = try XCTUnwrap(content.range(of: "ads.example"), content)
            let geoIP = try XCTUnwrap(content.range(of: target == .loon ? "GEOIP,CN" : "geoip, CN"), content)
            XCTAssertLessThan(ads.lowerBound, geoIP.lowerBound)
        }

        let after = try surge(["GEOIP,CN,DIRECT", "RULE-SET,\(url.absoluteString),REJECT", "FINAL,OpenAI"])
        let loon = output(after, .loon, schemes: repository, preferRuleSets: true).content
        XCTAssertTrue(loon.contains("[Remote Rule]\n\(url.absoluteString),policy=REJECT"), loon)
    }

    func testPublishedGeoIPListKeepsLoonAndQuanXListsRemoteAndInOrder() throws {
        let url = URL(string: "https://rules.example.com/ads.list")!
        let loonGeoIP = URL(string: "https://rules.example.com/geoip-cn-loon.list")!
        let quanXGeoIP = URL(string: "https://rules.example.com/geoip-cn-quanx.list")!
        let catchAll = URL(string: "https://rules.example.com/catch-all.list")!
        let repository = try repository(
            [url: "DOMAIN-SUFFIX,ads.example\nIP-CIDR,203.0.113.0/24,no-resolve"],
            publishedLocalRules: .init(inlineRules: ["GEOIP,CN": [.loon: loonGeoIP, .quanx: quanXGeoIP]], quanXCatchAll: catchAll)
        )
        let scheme = try surge(["RULE-SET,\(url.absoluteString),REJECT", "GEOIP,CN,DIRECT", "FINAL,OpenAI"])

        let loon = output(scheme, .loon, schemes: repository, preferRuleSets: true).content
        let remote = try XCTUnwrap(loon.components(separatedBy: "[Remote Rule]\n").last)
        XCTAssertTrue(remote.hasPrefix("\(url.absoluteString),policy=REJECT,"), loon)
        XCTAssertTrue(remote.contains("\n\(loonGeoIP.absoluteString),policy=DIRECT,"), loon)
        XCTAssertFalse(loon.contains("GEOIP,CN,"), "no local GEOIP left to overtake the list")

        // Quantumult X references only lists already in its own format.
        let quanXRepository = try self.repository(
            [url: "host-suffix, ads.example, reject"],
            publishedLocalRules: .init(inlineRules: ["GEOIP,CN": [.loon: loonGeoIP, .quanx: quanXGeoIP]], quanXCatchAll: catchAll)
        )
        let quanX = output(scheme, .quanx, schemes: quanXRepository, preferRuleSets: true).content
        let filters = try XCTUnwrap(quanX.components(separatedBy: "[filter_remote]\n").last?.components(separatedBy: "\n\n").first)
        XCTAssertEqual(filters.components(separatedBy: "\n").map { $0.components(separatedBy: ",").first ?? "" },
                       [url.absoluteString, quanXGeoIP.absoluteString, catchAll.absoluteString], quanX)
        XCTAssertTrue(filters.hasSuffix("force-policy=OpenAI, enabled=true"), filters)
        XCTAssertFalse(quanX.contains("host-keyword, ., "), "the catch-all is not also local")
        XCTAssertFalse(quanX.contains("geoip, CN"))

        // Without the published lists nothing changes.
        let local = output(scheme, .quanx, schemes: try self.repository([url: "host-suffix, ads.example, reject"]), preferRuleSets: true).content
        XCTAssertFalse(local.contains(catchAll.absoluteString))
    }

    func testQuanXCatchAllDoesNotShadowRemoteLists() throws {
        let url = URL(string: "https://rules.example.com/qx.list")!
        let repository = try repository([url: "host-suffix, ads.example, reject"])
        // The no-resolve IP rule is what makes Tower add the catch-all.
        let scheme = try surge(["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve", "RULE-SET,\(url.absoluteString),REJECT", "FINAL,OpenAI"])
        let content = output(scheme, .quanx, schemes: repository, preferRuleSets: true).content
        XCTAssertTrue(content.contains("\(url.absoluteString), tag="), content)
        XCTAssertFalse(content.contains("host-keyword, ., "), content)
        let local = output(scheme, .quanx, schemes: repository, preferRuleSets: false).content
        XCTAssertTrue(local.contains("host-keyword, ., OpenAI\nfinal, OpenAI"), local)
    }

    func testUndownloadedRuleListBlocksExportInsteadOfVanishing() throws {
        let scheme = try surge(["RULE-SET,https://rules.example.com/missing.list,REJECT", "FINAL,OpenAI"])
        for target in [ClientTarget.surge, .clashMi, .loon, .singBox] {
            let result = output(scheme, target)
            XCTAssertTrue(result.hasInvalidPolicyReferences, "\(target)")
            XCTAssertTrue(result.diagnostics.contains { $0.contains("部分规则还没下载完成") }, "\(target): \(result.diagnostics)")
        }
        let url = URL(string: "https://rules.example.com/missing.list")!
        let downloaded = try repository([url: "DOMAIN-SUFFIX,ads.example"])
        XCTAssertFalse(output(scheme, .surge, schemes: downloaded).hasInvalidPolicyReferences)
    }

    // MARK: - sing-box DNS

    private func dns(_ content: String) throws -> (dns: [String: Any], route: [String: Any]) {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        return (try XCTUnwrap(json["dns"] as? [String: Any]), try XCTUnwrap(json["route"] as? [String: Any]))
    }

    /// Unlisted domains used to resolve through the proxy to CDN edges near
    /// the exit. The remote resolver is now asked once more with a Chinese
    /// client subnet, and only a Chinese answer is kept.
    func testSingBoxAsksForChineseAnswersWithoutLeakingToTheLocalResolver() throws {
        let scheme = try surge(["DOMAIN-SUFFIX,cn.example,DIRECT", "DOMAIN-SUFFIX,google.com,OpenAI", "GEOIP,CN,DIRECT", "FINAL,OpenAI"])
        let (dns, route) = try dns(output(scheme, .singBox).content)
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        let ecs = try XCTUnwrap(servers.first { $0["tag"] as? String == "remote-cn" })
        XCTAssertEqual(ecs["server"] as? String, "8.8.8.8")
        XCTAssertNotNil(ecs["detour"])
        let rules = try XCTUnwrap(dns["rules"] as? [[String: Any]])
        // sing-box 1.14 response matching, not the deprecated address filter
        // (the official apps pop up "profile outdated" for that).
        let evaluate = try XCTUnwrap(rules.dropLast().last)
        XCTAssertEqual(evaluate["action"] as? String, "evaluate")
        XCTAssertEqual(evaluate["server"] as? String, "remote-cn")
        XCTAssertEqual(evaluate["client_subnet"] as? String, "114.114.114.0/24")
        XCTAssertEqual(evaluate["query_type"] as? [String], ["A", "AAAA"])
        let respond = try XCTUnwrap(rules.last)
        XCTAssertEqual(respond["match_response"] as? Bool, true)
        XCTAssertEqual(respond["rule_set"] as? [String], ["tower-geoip-cn"])
        XCTAssertEqual(respond["action"] as? String, "respond")
        XCTAssertFalse(rules.contains { $0["rule_set"] != nil && $0["match_response"] == nil }, "不能再有旧式地址过滤")
        // Listed domains keep their projected resolver ahead of the hint.
        XCTAssertTrue(rules.contains { ($0["domain_suffix"] as? [String]) == ["cn.example"] && $0["server"] as? String == "local" })
        XCTAssertTrue(rules.contains { ($0["domain_suffix"] as? [String]) == ["google.com"] && $0["server"] as? String == "remote" })
        XCTAssertEqual(dns["final"] as? String, "remote")
        let sets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        XCTAssertEqual(sets.filter { $0["tag"] as? String == "tower-geoip-cn" }.count, 1)
    }

    func testFollowSchemeGetsNoChinaHint() throws {
        var scheme = try surge(["DOMAIN-SUFFIX,google.com,OpenAI", "FINAL,OpenAI"])
        scheme.networkSettings = RuleSchemeNetworkSettings(dnsServers: ["223.5.5.5"], encryptedDNSServers: ["https://1.1.1.1/dns-query"], dnsProtectionMode: .followScheme)
        let (dns, _) = try dns(output(scheme, .singBox).content)
        XCTAssertFalse((dns["servers"] as? [[String: Any]] ?? []).contains { $0["tag"] as? String == "remote-cn" })
        let (hiddify, _) = try self.dns(output(try surge(["FINAL,OpenAI"]), .hiddify).content)
        XCTAssertFalse((hiddify["servers"] as? [[String: Any]] ?? []).contains { $0["tag"] as? String == "remote-cn" })
    }
}
