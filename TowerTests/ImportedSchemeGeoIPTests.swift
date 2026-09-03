import XCTest
@testable import Tower

/// A GEOIP rule without `no-resolve` makes the engine resolve every domain no
/// earlier rule matched, purely to test its country. Built-in presets write the
/// flag for all seven clients; an imported scheme must not route differently on
/// Stash than it does on Surge.
final class ImportedSchemeGeoIPTests: XCTestCase {
    func testEveryClientSkipsResolutionForAnImportedGeoIPRule() throws {
        let repository = RuleSchemeRepository(bundle: .main)
        let mini = try XCTUnwrap(
            repository.bundledSchemes().first { $0.id == "acl4ssr-mini" }
        )
        let customFlow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: mini.id,
            name: "Issue 12",
            rulesText: "DOMAIN-SUFFIX,issue12.example",
            defaultPolicyName: "🚀 节点选择"
        )
        let scheme = mini.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [customFlow]
        )

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = ConfigurationGenerator().generate(
                nodes: [],
                scheme: scheme,
                target: target,
                schemes: repository,
                preferRuleSets: false
            ).content

            if target.usesSingBoxFormat {
                // sing-box has no GEOIP matcher — it replaced the built-in
                // database with rule-sets — so `singBoxRuleFields` drops the
                // rule instead of writing one that cannot resolve.
                XCTAssertFalse(content.lowercased().contains("geoip"), content)
                continue
            }

            if target == .egern {
                guard let range = content.range(of: "  - geoip:\n") else {
                    XCTFail("Egern 缺少 GEOIP 规则")
                    continue
                }
                let entry = content[range.lowerBound...].prefix(200)
                XCTAssertTrue(
                    entry.contains("no_resolve: true"),
                    "Egern 的 GEOIP 规则缺少 no_resolve：\(entry)"
                )
                continue
            }

            if target == .quanx {
                let finalGroup = try XCTUnwrap(scheme.finalGroupName)
                XCTAssertFalse(content.lowercased().contains("no-resolve"), content)
                XCTAssertTrue(
                    content.localizedCaseInsensitiveContains("geoip, cn, 🎯 全球直连"),
                    content
                )
                XCTAssertTrue(
                    content.contains("host-keyword, ., \(finalGroup)\nfinal, \(finalGroup)"),
                    content
                )
                continue
            }

            let geoIPRules = content
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.lowercased().contains("geoip,") }
            XCTAssertFalse(geoIPRules.isEmpty, "\(target.name) 没有生成 GEOIP 规则")
            for rule in geoIPRules {
                XCTAssertTrue(
                    rule.lowercased().contains("no-resolve"),
                    "\(target.name) 的导入方案 GEOIP 规则缺少 no-resolve：\(rule)"
                )
            }
        }
    }

    func testQuanXConvertsAnExplicitNoResolveRuleToItsDocumentedFallback() {
        let scheme = RuleScheme(
            id: "quanx-no-resolve-source",
            name: "QuanX 来源规则",
            summary: "测试",
            groups: [
                RuleSchemeGroup(name: "Proxy", kind: .select, members: [.reference("DIRECT")]),
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "Proxy",
                    resource: .inline("IP-CIDR,10.0.0.0/8,no-resolve")
                ),
                RuleSchemeRuleset(
                    groupName: "Proxy",
                    resource: .inline("IP-ASN,6185,no-resolve")
                ),
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL")),
            ],
            networkSettings: RuleSchemeNetworkSettings(dnsProtectionMode: .followScheme)
        )

        let content = ConfigurationGenerator().generate(
            nodes: [],
            scheme: scheme,
            target: .quanx,
            preferRuleSets: false
        ).content

        XCTAssertTrue(content.contains("ip-cidr, 10.0.0.0/8, Proxy"), content)
        XCTAssertTrue(content.contains("ip-asn, 6185, Proxy"), content)
        XCTAssertTrue(content.contains("host-keyword, ., Proxy\nfinal, Proxy"), content)
        XCTAssertFalse(content.lowercased().contains("no-resolve"), content)
    }

    /// Egern spells the flag as a neighbouring key, which is why a source rule
    /// that asked for it used to lose it silently.
    func testEgernKeepsNoResolveWrittenByTheSourceFile() throws {
        let scheme = RuleScheme(
            id: "no-resolve-source",
            name: "来源规则",
            summary: "测试",
            groups: [
                RuleSchemeGroup(name: "🎯 全球直连", kind: .select, members: [.reference("DIRECT")]),
                RuleSchemeGroup(name: "🐟 漏网之鱼", kind: .select, members: [.reference("DIRECT")]),
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "🎯 全球直连",
                    resource: .inline("IP-CIDR,10.0.0.0/8,no-resolve")
                ),
                RuleSchemeRuleset(groupName: "🐟 漏网之鱼", resource: .inline("FINAL")),
            ]
        )

        let content = ConfigurationGenerator().generate(
            nodes: [],
            scheme: scheme,
            target: .egern,
            schemes: RuleSchemeRepository(bundle: .main),
            preferRuleSets: false
        ).content

        let entry = try XCTUnwrap(content.range(of: "  - ip_cidr:\n"))
        XCTAssertTrue(
            content[entry.lowerBound...].prefix(200).contains("no_resolve: true"),
            content
        )
    }

    /// A domain rule has nothing to skip, so the flag must not leak onto it.
    func testDomainRulesNeverGainTheFlag() throws {
        let scheme = RuleScheme(
            id: "domain-only",
            name: "域名规则",
            summary: "测试",
            groups: [
                RuleSchemeGroup(name: "🚀 节点选择", kind: .select, members: [.reference("DIRECT")]),
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "🚀 节点选择",
                    resource: .inline("DOMAIN-SUFFIX,example.com")
                ),
            ]
        )

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = ConfigurationGenerator().generate(
                nodes: [],
                scheme: scheme,
                target: target,
                schemes: RuleSchemeRepository(bundle: .main),
                preferRuleSets: false
            ).content
            let domainRules = content
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.contains("example.com") }
            for rule in domainRules {
                XCTAssertFalse(
                    rule.lowercased().contains("no-resolve"),
                    "\(target.name) 给域名规则加了 no-resolve：\(rule)"
                )
            }
            XCTAssertFalse(content.contains("      no_resolve: true\n      policy"), content)
        }
    }
}
