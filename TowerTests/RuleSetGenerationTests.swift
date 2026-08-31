import XCTest
@testable import Tower

final class RuleSetGenerationTests: XCTestCase {
    private let url = URL(string: "https://rules.example.com/Streaming.list")!

    func testClashUsesClassicalRuleProviderWhenEnabled() throws {
        let fixture = try makeFixture(content: "DOMAIN-SUFFIX,example.com")
        let content = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .clash,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(content.contains("rule-providers:"), content)
        XCTAssertTrue(content.contains("behavior: classical"), content)
        XCTAssertTrue(content.contains("format: text"), content)
        XCTAssertTrue(content.contains(url.absoluteString), content)
        XCTAssertTrue(content.contains("RULE-SET,tower-streaming-1,Proxy"), content)
        XCTAssertFalse(content.contains("DOMAIN-SUFFIX,example.com,Proxy"), content)
    }

    func testClashKeepsGeoSiteClassicalRuleProviderWhenEnabled() throws {
        let fixture = try makeFixture(content: "GEOSITE,CN")

        for target in [ClientTarget.clash, .clashApple] {
            let content = fixture.generator.generate(
                nodes: [],
                scheme: fixture.scheme,
                target: target,
                schemes: fixture.repository,
                preferRuleSets: true
            ).content

            XCTAssertTrue(content.contains("rule-providers:"), content)
            XCTAssertTrue(content.contains("RULE-SET,tower-streaming-1,Proxy"), content)
        }

        let shadowrocket = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .shadowrocket,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        XCTAssertFalse(shadowrocket.contains("rule-providers:"), shadowrocket)
        XCTAssertFalse(shadowrocket.contains("GEOSITE"), shadowrocket)
    }

    func testSurgeAndShadowrocketUseNativeRemoteRuleSetsWhenEnabled() throws {
        let fixture = try makeFixture(content: "DOMAIN-SUFFIX,example.com")

        let surge = fixture.generator.generate(
            nodes: [], scheme: fixture.scheme, target: .surge,
            schemes: fixture.repository, preferRuleSets: true
        ).content
        XCTAssertTrue(surge.contains("RULE-SET,\(url.absoluteString),Proxy,update-interval=86400"), surge)
        XCTAssertFalse(surge.contains("DOMAIN-SUFFIX,example.com,Proxy"), surge)

        let shadowrocket = fixture.generator.generate(
            nodes: [], scheme: fixture.scheme, target: .shadowrocket,
            schemes: fixture.repository, preferRuleSets: true
        ).content
        XCTAssertTrue(shadowrocket.contains("rule-providers:"), shadowrocket)
        XCTAssertTrue(shadowrocket.contains("url: \"\(url.absoluteString)\""), shadowrocket)
        XCTAssertTrue(shadowrocket.contains("RULE-SET,tower-streaming-1,Proxy"), shadowrocket)
        XCTAssertFalse(shadowrocket.contains("DOMAIN-SUFFIX,example.com,Proxy"), shadowrocket)
    }

    func testSurgeAddsNoResolveToImportedGeoIPBeforeLaterDomainRule() throws {
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

        let content = ConfigurationGenerator().generate(
            nodes: [],
            scheme: scheme,
            target: .surge,
            schemes: repository,
            preferRuleSets: false
        ).content

        XCTAssertTrue(
            content.contains("GEOIP,CN,🎯 全球直连,no-resolve"),
            content
        )
        XCTAssertLessThan(
            try XCTUnwrap(content.range(of: "GEOIP,CN")?.lowerBound),
            try XCTUnwrap(content.range(of: "DOMAIN-SUFFIX,issue12.example")?.lowerBound)
        )
    }

    func testLoonUsesRemoteRuleSectionWhenEnabled() throws {
        let fixture = try makeFixture(content: "DOMAIN-SUFFIX,example.com")
        let content = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .loon,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(content.contains("[Remote Rule]"), content)
        XCTAssertTrue(
            content.contains("\(url.absoluteString),policy=Proxy,tag=tower-streaming-1,enabled=true"),
            content
        )
        XCTAssertFalse(content.contains("DOMAIN-SUFFIX,example.com,Proxy"), content)
    }

    func testClashProviderYAMLStaysRemoteForStructuredClashProfiles() throws {
        let fixture = try makeFixture(
            url: URL(string: "https://rules.example.com/Streaming.yaml")!,
            content: "payload:\n  - DOMAIN-SUFFIX,example.com"
        )

        let clash = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .clash,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        XCTAssertTrue(clash.contains("format: yaml"), clash)
        XCTAssertFalse(clash.contains("format: text"), clash)

        let shadowrocket = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .shadowrocket,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        XCTAssertTrue(shadowrocket.contains("format: yaml"), shadowrocket)
        XCTAssertTrue(shadowrocket.contains("https://rules.example.com/Streaming.yaml"), shadowrocket)

        for target in [ClientTarget.surge, .loon, .quanx] {
            let content = fixture.generator.generate(
                nodes: [],
                scheme: fixture.scheme,
                target: target,
                schemes: fixture.repository,
                preferRuleSets: true
            ).content

            XCTAssertFalse(
                content.contains("https://rules.example.com/Streaming.yaml"),
                "\(target.name): \(content)"
            )
            XCTAssertTrue(content.localizedCaseInsensitiveContains("example.com"), content)
        }
    }

    func testQuanXUsesFilterRemoteOnlyForNativeFilterSyntax() throws {
        let native = try makeFixture(content: "host-suffix, example.com")
        let nativeContent = native.generator.generate(
            nodes: [],
            scheme: native.scheme,
            target: .quanx,
            schemes: native.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(
            nativeContent.contains("\(url.absoluteString), tag=tower-streaming-1, force-policy=Proxy, enabled=true"),
            nativeContent
        )
        XCTAssertFalse(nativeContent.contains("host-suffix, example.com, Proxy"), nativeContent)

        let clash = try makeFixture(content: "DOMAIN-SUFFIX,example.com")
        let fallback = clash.generator.generate(
            nodes: [],
            scheme: clash.scheme,
            target: .quanx,
            schemes: clash.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(fallback.contains("host-suffix, example.com, Proxy"), fallback)
        XCTAssertFalse(fallback.contains("https://rules.example.com/Streaming.list, tag="), fallback)
    }

    func testSingBoxUsesNativeRemoteRuleSetAndFallsBackForClashLists() throws {
        let nativeURL = URL(string: "https://rules.example.com/Streaming.json")!
        let native = try makeFixture(
            url: nativeURL,
            content: #"{"version":1,"rules":[{"domain_suffix":["example.com"]}]}"#
        )
        let nativeContent = native.generator.generate(
            nodes: [],
            scheme: native.scheme,
            target: .hiddify,
            schemes: native.repository,
            preferRuleSets: true
        ).content
        let nativeJSON = try json(nativeContent)
        let nativeRoute = try XCTUnwrap(nativeJSON["route"] as? [String: Any])
        let nativeRuleSets = try XCTUnwrap(nativeRoute["rule_set"] as? [[String: Any]])
        let nativeRules = try XCTUnwrap(nativeRoute["rules"] as? [[String: Any]])

        XCTAssertEqual(nativeRuleSets.first?["type"] as? String, "remote")
        XCTAssertEqual(nativeRuleSets.first?["format"] as? String, "source")
        XCTAssertEqual(nativeRuleSets.first?["url"] as? String, nativeURL.absoluteString)
        XCTAssertTrue(nativeRules.contains { ($0["rule_set"] as? [String]) == ["tower-streaming-1"] })

        let clash = try makeFixture(content: "DOMAIN-SUFFIX,example.com")
        let fallbackContent = clash.generator.generate(
            nodes: [],
            scheme: clash.scheme,
            target: .hiddify,
            schemes: clash.repository,
            preferRuleSets: true
        ).content
        let fallbackJSON = try json(fallbackContent)
        let fallbackRoute = try XCTUnwrap(fallbackJSON["route"] as? [String: Any])

        XCTAssertNil(fallbackRoute["rule_set"])
        XCTAssertTrue((fallbackRoute["rules"] as? [[String: Any]])?.contains {
            ($0["domain_suffix"] as? [String]) == ["example.com"]
        } == true)
    }

    func testEgernUsesNativeRemoteRuleSetAndFallsBackForClashLists() throws {
        let nativeURL = URL(string: "https://rules.example.com/Streaming.yaml")!
        let native = try makeFixture(
            url: nativeURL,
            content: "domain_suffix_set:\n  - example.com"
        )
        let nativeContent = native.generator.generate(
            nodes: [],
            scheme: native.scheme,
            target: .egern,
            schemes: native.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(nativeContent.contains("  - rule_set:"), nativeContent)
        XCTAssertTrue(nativeContent.contains("      match: \"\(nativeURL.absoluteString)\""), nativeContent)
        XCTAssertTrue(nativeContent.contains("      update_interval: 86400"), nativeContent)

        let clash = try makeFixture(content: "DOMAIN-SUFFIX,example.com")
        let fallback = clash.generator.generate(
            nodes: [],
            scheme: clash.scheme,
            target: .egern,
            schemes: clash.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(fallback.contains("  - domain_suffix:"), fallback)
        XCTAssertFalse(fallback.contains("  - rule_set:"), fallback)
    }

    func testDisablingPreferenceRestoresInlineRulesForEveryTarget() throws {
        let fixture = try makeFixture(content: "DOMAIN-SUFFIX,example.com")

        for target in ClientTarget.allCases {
            let content = fixture.generator.generate(
                nodes: [],
                scheme: fixture.scheme,
                target: target,
                schemes: fixture.repository,
                preferRuleSets: false
            ).content

            switch target {
            case .clash, .clashApple, .surge, .shadowrocket, .loon:
                XCTAssertTrue(content.contains("DOMAIN-SUFFIX,example.com,Proxy"), "\(target.name): \(content)")
            case .quanx:
                XCTAssertTrue(content.contains("host-suffix, example.com, Proxy"), content)
            case .hiddify, .singBox:
                XCTAssertFalse(content.contains(#""rule_set""#), content)
            case .egern:
                XCTAssertTrue(content.contains("  - domain_suffix:"), content)
            case .v2box:
                XCTAssertTrue(content.isEmpty, "V2Box 只接收节点订阅，不生成完整规则配置")
            }
        }
    }

    func testBundledACL4SSRUsesRemoteReferencesOnlyOnCompatibleClients() throws {
        let repository = RuleSchemeRepository(bundle: .main)
        let scheme = try XCTUnwrap(
            repository.bundledSchemes().first { $0.id == "acl4ssr-default" }
        )
        let generator = ConfigurationGenerator()

        let clash = generator.generate(
            nodes: [], scheme: scheme, target: .clash, schemes: repository
        ).content
        let surge = generator.generate(
            nodes: [], scheme: scheme, target: .surge, schemes: repository
        ).content
        let loon = generator.generate(
            nodes: [], scheme: scheme, target: .loon, schemes: repository
        ).content
        let quanX = generator.generate(
            nodes: [], scheme: scheme, target: .quanx, schemes: repository
        ).content
        let hiddify = generator.generate(
            nodes: [], scheme: scheme, target: .hiddify, schemes: repository
        ).content
        let egern = generator.generate(
            nodes: [], scheme: scheme, target: .egern, schemes: repository
        ).content

        XCTAssertTrue(clash.contains("rule-providers:"), clash)
        XCTAssertTrue(surge.contains("RULE-SET,https://raw.githubusercontent.com/"), surge)
        XCTAssertTrue(loon.contains("[Remote Rule]"), loon)

        // Most ACL4SSR lists use classical Clash syntax. A pure IP-CIDR list is
        // also valid Quantumult X filter syntax, so that individual source can
        // stay remote while unsupported sources remain mapped locally.
        XCTAssertTrue(quanX.contains("ChinaCompanyIp.list, tag="), quanX)
        XCTAssertTrue(quanX.contains("host-suffix, acl4.ssr, "), quanX)

        // sing-box/Hiddify and Egern require their own structured remote
        // formats, so the classical ACL4SSR sources must remain local there.
        XCTAssertFalse(hiddify.contains(#""rule_set""#), hiddify)
        XCTAssertFalse(egern.contains("  - rule_set:"), egern)
    }

    private func makeFixture(
        url: URL? = nil,
        content: String
    ) throws -> (generator: ConfigurationGenerator, scheme: RuleScheme, repository: RuleSchemeRepository) {
        let resolvedURL = url ?? self.url
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tower-RuleSetTests-\(UUID().uuidString)", isDirectory: true)
        let store = RuleDownloadStore(folderURL: directory)
        try store.store(content, for: resolvedURL)

        let scheme = RuleScheme(
            id: "remote-rule-test",
            name: "Remote Rules",
            summary: "Compatibility fixture",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "Proxy", resource: .remote(resolvedURL)),
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))
            ]
        )
        return (
            ConfigurationGenerator(),
            scheme,
            RuleSchemeRepository(downloadStore: store)
        )
    }

    private func json(_ content: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]
        )
    }
}
