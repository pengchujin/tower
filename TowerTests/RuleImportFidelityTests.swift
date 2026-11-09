import XCTest
@testable import Tower

/// Regressions for importing real public configurations (docs/RULE_EXPORT_AUDIT.md,
/// 导入这一侧).
final class RuleImportFidelityTests: XCTestCase {
    private let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")

    private func parse(_ text: String) throws -> RuleScheme {
        try RuleSchemeParser().parse(text: text, id: "import", name: "Import", summary: "")
    }

    private func output(_ scheme: RuleScheme, _ target: ClientTarget, preferRuleSets: Bool = false) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, preferRuleSets: preferRuleSets)
    }

    // MARK: - subconverter

    func testSubconverterRulesetTypePrefixesAndIntervals() throws {
        let scheme = try parse("""
        [custom]
        ruleset=Proxy,clash-classic:https://rules.example.com/GitHub.yaml,86400
        ruleset=Proxy,clash-domain:https://rules.example.com/domains.yaml
        ruleset=Proxy,clash-ipcidr:https://rules.example.com/cidr.yaml
        ruleset=Proxy,quanx:https://rules.example.com/qx.list
        ruleset=Proxy,surge:https://rules.example.com/surge.list,43200
        ruleset=Proxy,https://rules.example.com/plain.list
        ruleset=Proxy,[]FINAL
        custom_proxy_group=Proxy`select`.*
        """)
        XCTAssertEqual(scheme.remoteRulesetURLs.map(\.absoluteString), [
            "https://rules.example.com/GitHub.yaml", "https://rules.example.com/domains.yaml",
            "https://rules.example.com/cidr.yaml", "https://rules.example.com/qx.list",
            "https://rules.example.com/surge.list", "https://rules.example.com/plain.list"
        ])
        XCTAssertEqual(scheme.rulesets.prefix(6).map { $0.provider?.behavior }, ["classical", "domain", "ipcidr", nil, nil, nil])
    }

    /// Issue #50: DustinWin's INI declares `clash-domain:` / `clash-ipcidr:`
    /// for lists of typed rules. Referenced as `behavior: domain`, mihomo
    /// matched none of them and ChatGPT fell through to MATCH.
    func testDeclaredDomainProviderOverTypedRulesIsReferencedAsClassical() throws {
        let ai = URL(string: "https://rules.example.com/ai.list")!
        let cnip = URL(string: "https://rules.example.com/cnip.list")!
        let bare = URL(string: "https://rules.example.com/bare.list")!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleDownloadStore(folderURL: folder)
        try store.store("DOMAIN,ai.google.dev\nDOMAIN-SUFFIX,chatgpt.com\n", for: ai)
        try store.store("IP-CIDR,1.0.1.0/24\nIP-CIDR6,2400:da00::/32\n", for: cnip)
        try store.store("+.example.org\nexample.net\n", for: bare)
        let repository = RuleSchemeRepository(downloadStore: store)
        let scheme = try parse("""
        [custom]
        ruleset=AI,clash-domain:\(ai.absoluteString),86400
        ruleset=DIRECT,clash-ipcidr:\(cnip.absoluteString),86400
        ruleset=Proxy,clash-domain:\(bare.absoluteString),86400
        ruleset=Proxy,[]FINAL
        custom_proxy_group=AI`select`[]Proxy
        custom_proxy_group=Proxy`select`.*
        """)
        func block(_ content: String, _ host: String) -> String {
            let blocks = content.components(separatedBy: "\n  tower-")
            return blocks.first { $0.contains("rules.example.com/\(host)") } ?? ""
        }
        for target in [ClientTarget.clashVerge, .clashMi, .clash] {
            let content = ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target,
                                                            schemes: repository, preferRuleSets: true).content
            XCTAssertTrue(block(content, "ai.list").contains("behavior: classical"), "\(target)\n\(content)")
            XCTAssertTrue(block(content, "cnip.list").contains("behavior: classical"), "\(target)\n\(content)")
            // A list that really is bare keeps its declared behavior.
            XCTAssertTrue(block(content, "bare.list").contains("behavior: domain"), "\(target)\n\(content)")
            let inline = ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target,
                                                           schemes: repository, preferRuleSets: false).content
            XCTAssertTrue(inline.contains("DOMAIN-SUFFIX,chatgpt.com,"), "\(target)\n\(inline)")
        }
    }

    // MARK: - mihomo

    func testMihomoDirectOutboundBecomesTheBuiltInPolicy() throws {
        let scheme = try parse("""
        proxies:
          - {name: 直连, type: direct}
          - {name: 拦截, type: reject}
        proxy-groups:
          - {name: 默认, type: select, proxies: [直连, 拦截]}
        rules:
          - DOMAIN-SUFFIX,cn.example,直连
          - DOMAIN-SUFFIX,ads.example,拦截
          - MATCH,直连
        """)
        XCTAssertEqual(scheme.rulesets.map(\.groupName), ["DIRECT", "REJECT", "DIRECT"])
        XCTAssertEqual(scheme.groups.first?.members, [.reference("DIRECT"), .reference("REJECT")])
        for target in [ClientTarget.clashMi, .surge, .loon, .singBox] {
            XCTAssertFalse(output(scheme, target).hasInvalidPolicyReferences, "\(target)")
        }
    }

    func testMRSRuleSetsAreReferencedByMihomoAndReportedElsewhere() throws {
        let scheme = try parse("""
        proxy-groups:
          - {name: Proxy, type: select, proxies: [DIRECT]}
        rule-providers:
          ads: {type: http, behavior: domain, format: mrs, url: "https://rules.example.com/ads.mrs", interval: 86400}
          cn: {type: http, behavior: ipcidr, format: mrs, url: "https://rules.example.com/cn.mrs", interval: 86400}
        rules:
          - RULE-SET,ads,REJECT
          - RULE-SET,cn,DIRECT,no-resolve
          - MATCH,Proxy
        """)
        // Never downloaded or read as text.
        XCTAssertTrue(scheme.remoteRulesetURLs.isEmpty)

        let mihomo = output(scheme, .clashMi)
        XCTAssertFalse(mihomo.hasInvalidPolicyReferences, "\(mihomo.diagnostics)")
        XCTAssertTrue(mihomo.content.contains("behavior: domain\n    format: mrs\n    url: \"https://rules.example.com/ads.mrs\""), mihomo.content)
        XCTAssertTrue(mihomo.content.contains("behavior: ipcidr\n    format: mrs"), mihomo.content)
        XCTAssertTrue(mihomo.content.contains("RULE-SET,tower-ads-domain-1,REJECT\n"), mihomo.content)
        XCTAssertTrue(mihomo.content.contains("RULE-SET,tower-cn-ip-2,DIRECT,no-resolve\n"), mihomo.content)

        // Stash reads domain and ipcidr MRS since 3.1.0.
        let stash = output(scheme, .clash)
        XCTAssertTrue(stash.content.contains("RULE-SET,tower-ads-domain-1,REJECT\n"), stash.content)
        XCTAssertTrue(stash.diagnostics.filter { $0.contains("MRS") }.isEmpty, "\(stash.diagnostics)")

        for target in [ClientTarget.surge, .loon, .singBox, .karing] {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, "\(target): \(result.diagnostics)")
            XCTAssertFalse(result.content.contains(".mrs"), "\(target)")
            XCTAssertEqual(result.diagnostics.filter { $0.contains("MRS") }.count, 2, "\(target): \(result.diagnostics)")
            XCTAssertTrue(result.diagnostics.first?.contains("1 条拦截规则") == true, "\(target): \(result.diagnostics)")
        }
    }

    func testBinaryDownloadIsNotReadAsRules() {
        XCTAssertNil(RuleSchemeImportService.ruleListText(Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x58, 0x41])))
        XCTAssertEqual(RuleSchemeImportService.ruleListText(Data("DOMAIN,example.com\n".utf8)), "DOMAIN,example.com\n")
    }

    // MARK: - Surge

    func testListOptionsReachOnlyTheRuleTypesThatTakeThem() {
        XCTAssertEqual(RuleResourceContent.applying(["pre-matching"], to: "URL-REGEX,^http://ads.example/x"), "URL-REGEX,^http://ads.example/x")
        XCTAssertEqual(RuleResourceContent.applying(["pre-matching"], to: "DOMAIN-SUFFIX,ads.example"), "DOMAIN-SUFFIX,ads.example,pre-matching")
        XCTAssertEqual(RuleResourceContent.applying(["pre-matching"], to: "USER-AGENT,Ads*"), "USER-AGENT,Ads*")
        XCTAssertEqual(RuleResourceContent.applying(["extended-matching"], to: "IP-CIDR,1.2.3.0/24"), "IP-CIDR,1.2.3.0/24")
        XCTAssertEqual(RuleResourceContent.applying(["extended-matching"], to: "URL-REGEX,^http://a"), "URL-REGEX,^http://a,extended-matching")
    }

    // MARK: - Empty groups

    /// ACL4SSR's 🎥 奈飞视频 lists 🎥 奈飞节点 first. With no Netflix-tagged
    /// node that group falls back to DIRECT, and the parent used to default
    /// to it: Netflix went direct. Parents now skip such groups.
    func testEmptyGroupIsDroppedFromParentsInsteadOfDefaultingToDirect() throws {
        let scheme = try parse("""
        [custom]
        ruleset=🎥 奈飞视频,[]DOMAIN-SUFFIX,netflix.com
        ruleset=🚀 节点选择,[]FINAL
        custom_proxy_group=🚀 节点选择`select`.*
        custom_proxy_group=🎥 奈飞节点`select`(NF|奈飞|Netflix)
        custom_proxy_group=🎥 奈飞视频`select`[]🎥 奈飞节点`[]🚀 节点选择`[]DIRECT
        custom_proxy_group=📦 仅奈飞`select`[]🎥 奈飞节点
        """)
        for target in [ClientTarget.clashMi, .surge, .loon, .singBox] {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, "\(target): \(result.diagnostics)")
            XCTAssertTrue(result.diagnostics.contains { $0.contains(exportedGroupName("🎥 奈飞节点", for: target)) && $0.contains("不再引用") }, "\(target)")
        }
        let mihomo = output(scheme, .clashMi).content
        XCTAssertTrue(mihomo.contains("name: \"🎥 奈飞视频\"\n    type: select\n    proxies:\n      - \"🚀 节点选择\"\n      - \"DIRECT\""), mihomo)
        // The empty group itself stays, so a rule could still name it.
        XCTAssertTrue(mihomo.contains("name: \"🎥 奈飞节点\"\n    type: select\n    proxies:\n      - \"DIRECT\""), mihomo)
        // A parent left with nothing falls back the same way.
        XCTAssertTrue(mihomo.contains("name: \"📦 仅奈飞\"\n    type: select\n    proxies:\n      - \"DIRECT\""), mihomo)
        let surge = output(scheme, .surge).content
        // Surge draws group icons, so the names carry no emoji there.
        XCTAssertTrue(surge.contains("\n奈飞视频 = select, 节点选择, DIRECT"), surge)
    }

    // MARK: - DNS

    /// Surge's DNS-over-HTTP/3 scheme. mihomo refused the whole profile with
    /// "unsupport scheme: h3"; sing-box silently lost the resolver.
    func testSurgeHTTP3ResolverIsWrittenInEachDialect() throws {
        let scheme = try parse("""
        [General]
        dns-server = 223.5.5.5
        encrypted-dns-server = h3://223.5.5.5/dns-query, quic://dns.alidns.com
        [Proxy Group]
        Proxy = select, DIRECT
        [Rule]
        FINAL,Proxy
        """)
        let mihomo = output(scheme, .clashMi).content
        XCTAssertTrue(mihomo.contains("- https://223.5.5.5/dns-query#h3=true\n"), mihomo)
        XCTAssertTrue(mihomo.contains("- quic://dns.alidns.com\n"), mihomo)
        XCTAssertFalse(mihomo.contains("h3://"), mihomo)
        let stash = output(scheme, .clash).content
        XCTAssertTrue(stash.contains("- https://223.5.5.5/dns-query\n"), stash)
        XCTAssertFalse(stash.contains("h3"), stash)
        let singBox = output(scheme, .singBox).content
        XCTAssertTrue(singBox.contains(#""type" : "h3""#), singBox)
        XCTAssertTrue(output(scheme, .surge).content.contains("encrypted-dns-server = h3://223.5.5.5/dns-query, quic://dns.alidns.com"))
    }

    // MARK: - Rewrites

    func testLoonRewritesSimpleWildcards() throws {
        let scheme = try parse("""
        [Proxy Group]
        Proxy = select, DIRECT
        [Rule]
        DOMAIN-WILDCARD,*.ads.example,REJECT
        DOMAIN-WILDCARD,exact.example,Proxy
        DOMAIN-WILDCARD,ads-*.example.com,REJECT
        FINAL,Proxy
        """)
        let loon = output(scheme, .loon)
        // Every subdomain but not the apex, as the wildcard meant.
        XCTAssertTrue(loon.content.contains("AND,((DOMAIN-SUFFIX,ads.example),(NOT,((DOMAIN,ads.example)))),REJECT\n"), loon.content)
        XCTAssertTrue(loon.content.contains("DOMAIN,exact.example,Proxy\n"), loon.content)
        // Other globs use DOMAIN-WILDCARD (Loon 3.5.3, build 1008+).
        XCTAssertTrue(loon.content.contains("DOMAIN-WILDCARD,ads-*.example.com,REJECT\n"), loon.content)
        XCTAssertFalse(loon.diagnostics.contains { $0.contains("拦截规则") }, "\(loon.diagnostics)")
    }

    func testSingBoxSpellsOutIPASNFromTheBundledDatabase() throws {
        let scheme = try parse("[Proxy Group]\nProxy = select, DIRECT\n[Rule]\nIP-ASN,13335,Proxy,no-resolve\nFINAL,Proxy")
        let result = output(scheme, .singBox)
        XCTAssertFalse(result.diagnostics.contains { $0.contains("IP-ASN") }, "\(result.diagnostics)")
        let cidrs = IPASNDatabase.cidrs(forASN: 13335)
        XCTAssertFalse(cidrs.isEmpty)
        XCTAssertTrue(result.content.contains(cidrs[0]))
        let first = String(cidrs[0].prefix { $0 != "/" })
        XCTAssertEqual(IPASNDatabase().organization(forIPAddress: first)?.asn, 13335)
    }

    func testRejectDropBecomesRejectWhereItIsMissing() throws {
        let scheme = try parse("[Proxy Group]\nProxy = select, DIRECT\n[Rule]\nDOMAIN-SUFFIX,ads.example,REJECT-DROP\nFINAL,Proxy")
        for target in [ClientTarget.quanx, .egern, .singBox] {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, "\(target): \(result.diagnostics)")
            XCTAssertFalse(result.content.contains("REJECT-DROP"), "\(target)")
        }
        XCTAssertTrue(output(scheme, .clashMi).content.contains("DOMAIN-SUFFIX,ads.example,REJECT-DROP"))
    }
}
