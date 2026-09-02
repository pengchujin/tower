import CryptoKit
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

    func testStashAndClashUseVerifiedMRSWithoutDroppingResidualRules() throws {
        let domainURL = URL(string: "https://rules.example.com/Streaming_domain.mrs")!
        let ipURL = URL(string: "https://rules.example.com/Streaming_ip.mrs")!
        let fixture = try makeFixture(
            content: """
            DOMAIN,exact.example
            DOMAIN-SUFFIX,example.com
            DOMAIN-KEYWORD,example
            IP-CIDR,203.0.113.0/24,no-resolve
            IP-CIDR6,2001:db8::/32,no-resolve
            PROCESS-NAME,Example
            """,
            mrsResources: [
                .init(behavior: .domain, url: domainURL),
                .init(behavior: .ipcidr, url: ipURL)
            ]
        )

        for target in [ClientTarget.clash, .clashApple] {
            let content = fixture.generator.generate(
                nodes: [],
                scheme: fixture.scheme,
                target: target,
                schemes: fixture.repository,
                preferRuleSets: true
            ).content

            XCTAssertTrue(content.contains("behavior: domain\n    format: mrs"), content)
            XCTAssertTrue(content.contains("behavior: ipcidr\n    format: mrs"), content)
            XCTAssertTrue(content.contains(domainURL.absoluteString), content)
            XCTAssertTrue(content.contains(ipURL.absoluteString), content)
            XCTAssertTrue(content.contains("path: ./ruleset/tower-streaming-domain-1.mrs"), content)
            XCTAssertTrue(content.contains("path: ./ruleset/tower-streaming-ip-2.mrs"), content)
            XCTAssertTrue(content.contains("RULE-SET,tower-streaming-domain-1,Proxy"), content)
            XCTAssertTrue(content.contains("RULE-SET,tower-streaming-ip-2,Proxy,no-resolve"), content)
            XCTAssertTrue(content.contains("DOMAIN-KEYWORD,example,Proxy"), content)
            XCTAssertTrue(content.contains("PROCESS-NAME,Example,Proxy"), content)
            XCTAssertFalse(content.contains("DOMAIN,exact.example,Proxy"), content)
            XCTAssertFalse(content.contains("DOMAIN-SUFFIX,example.com,Proxy"), content)
            XCTAssertFalse(content.contains("IP-CIDR,203.0.113.0/24,Proxy"), content)
        }

        let shadowrocket = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .shadowrocket,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        XCTAssertFalse(shadowrocket.contains(domainURL.absoluteString), shadowrocket)
        XCTAssertFalse(shadowrocket.contains(ipURL.absoluteString), shadowrocket)
        XCTAssertTrue(shadowrocket.contains(url.absoluteString), shadowrocket)

        let inline = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .clashApple,
            schemes: fixture.repository,
            preferRuleSets: false
        ).content
        XCTAssertFalse(inline.contains(domainURL.absoluteString), inline)
        XCTAssertFalse(inline.contains(ipURL.absoluteString), inline)
        XCTAssertTrue(inline.contains("DOMAIN-SUFFIX,example.com,Proxy"), inline)
        XCTAssertTrue(inline.contains("IP-CIDR,203.0.113.0/24,Proxy,no-resolve"), inline)
    }

    func testMissingMRSBehaviorKeepsThoseRulesInline() throws {
        let domainURL = URL(string: "https://rules.example.com/Streaming_domain.mrs")!
        let fixture = try makeFixture(
            content: """
            DOMAIN-SUFFIX,example.com
            IP-CIDR,203.0.113.0/24,no-resolve
            """,
            mrsResources: [.init(behavior: .domain, url: domainURL)]
        )
        let content = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .clash,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content

        XCTAssertTrue(content.contains(domainURL.absoluteString), content)
        XCTAssertTrue(content.contains("IP-CIDR,203.0.113.0/24,Proxy,no-resolve"), content)
        XCTAssertFalse(content.contains("behavior: ipcidr"), content)
    }

    func testBundledBinaryMetadataFailsClosedWhenSourceDigestDoesNotMatch() throws {
        let fixture = try makeBinaryMetadataBundle(
            sourceSHA: String(repeating: "0", count: 64)
        )
        let bundleURL = fixture.bundleURL
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)

        let lines = repository.lines(for: resource)
        XCTAssertEqual(repository.clashMRSResources(for: resource, matching: lines), [])
        XCTAssertNil(repository.singBoxSRSResource(for: resource, matching: lines))
    }

    func testBundledBinaryMetadataRejectsHTTPSURLsWithoutAHost() throws {
        let fixture = try makeBinaryMetadataBundle(
            sourceSHA: "145f7fd7beed2e748e7cfadb10fa168d309267d703f0ec09358ede2e8081bc9a",
            mrsURL: "https:Test_domain.mrs",
            srsURL: "https:Test.srs"
        )
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)

        let lines = repository.lines(for: resource)
        XCTAssertEqual(repository.clashMRSResources(for: resource, matching: lines), [])
        XCTAssertNil(repository.singBoxSRSResource(for: resource, matching: lines))
    }

    func testBundledBinaryMetadataAcceptsCoverageRecomputedFromSource() throws {
        let fixture = try makeBinaryMetadataBundle()
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        let lines = repository.lines(for: resource)

        XCTAssertEqual(
            repository.clashMRSResources(for: resource, matching: lines),
            [.init(
                behavior: .domain,
                url: URL(string: fixture.mrsURL)!
            )]
        )
        XCTAssertEqual(
            repository.singBoxSRSResource(for: resource, matching: lines)?.coveredRuleTypes,
            ["DOMAIN-SUFFIX"]
        )
    }

    func testDownloadedChangeAtBundledURLCannotReuseStaleBinaryRules() throws {
        let fixture = try makeBinaryMetadataBundle()
        let rulesFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tower-ChangedRules-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rulesFolder)
            try? FileManager.default.removeItem(at: fixture.bundleURL)
        }

        let store = RuleDownloadStore(folderURL: rulesFolder)
        try store.store(
            "DOMAIN-SUFFIX,example.com\nDOMAIN-SUFFIX,user-added.example\n",
            for: fixture.sourceURL
        )
        let repository = RuleSchemeRepository(bundle: fixture.bundle, downloadStore: store)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        let changedLines = repository.lines(for: resource)

        XCTAssertEqual(
            changedLines,
            ["DOMAIN-SUFFIX,example.com", "DOMAIN-SUFFIX,user-added.example"]
        )
        XCTAssertEqual(
            repository.clashMRSResources(for: resource, matching: changedLines),
            []
        )
        XCTAssertNil(repository.singBoxSRSResource(for: resource, matching: changedLines))

        let scheme = RuleScheme(
            id: "changed-bundled-rule",
            name: "Changed Rules",
            summary: "Stale binary regression",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "Proxy", resource: resource),
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))
            ]
        )
        let generator = ConfigurationGenerator()

        for target in [ClientTarget.clash, .clashApple] {
            let content = generator.generate(
                nodes: [],
                scheme: scheme,
                target: target,
                schemes: repository,
                preferRuleSets: true
            ).content
            XCTAssertFalse(content.contains("format: mrs"), content)
            XCTAssertFalse(content.contains(fixture.mrsURL), content)
            XCTAssertTrue(content.contains("format: text"), content)
            XCTAssertTrue(content.contains(fixture.sourceURL.absoluteString), content)
        }

        let singBoxContent = generator.generate(
            nodes: [],
            scheme: scheme,
            target: .singBox,
            schemes: repository,
            preferRuleSets: true
        ).content
        let route = try XCTUnwrap(try json(singBoxContent)["route"] as? [String: Any])
        XCTAssertNil(route["rule_set"])
        XCTAssertTrue((route["rules"] as? [[String: Any]])?.contains {
            ($0["domain_suffix"] as? [String])?.contains("user-added.example") == true
        } == true)
    }

    func testDownloadedEquivalentRulesCanReuseVerifiedBinaryRules() throws {
        let fixture = try makeBinaryMetadataBundle()
        let rulesFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tower-EquivalentRules-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rulesFolder)
            try? FileManager.default.removeItem(at: fixture.bundleURL)
        }

        let store = RuleDownloadStore(folderURL: rulesFolder)
        try store.store(
            "# equivalent after sanitizing\n  DOMAIN-SUFFIX,example.com  \n",
            for: fixture.sourceURL
        )
        let repository = RuleSchemeRepository(bundle: fixture.bundle, downloadStore: store)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        let resolvedLines = repository.lines(for: resource)

        XCTAssertEqual(resolvedLines, ["DOMAIN-SUFFIX,example.com"])
        XCTAssertFalse(
            repository.clashMRSResources(for: resource, matching: resolvedLines).isEmpty
        )
        XCTAssertNotNil(
            repository.singBoxSRSResource(for: resource, matching: resolvedLines)
        )
    }

    func testBundledBinaryMetadataRejectsStagingManifestWithoutArtifactCommit() throws {
        let fixture = try makeBinaryMetadataBundle(artifactCommit: nil)
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)

        let lines = repository.lines(for: resource)
        XCTAssertEqual(repository.clashMRSResources(for: resource, matching: lines), [])
        XCTAssertNil(repository.singBoxSRSResource(for: resource, matching: lines))
    }

    func testBundledBinaryMetadataRejectsURLsNotBoundToArtifactCommit() throws {
        let revision = String(repeating: "1", count: 40)
        let fixture = try makeBinaryMetadataBundle(
            mrsURL: "https://raw.githubusercontent.com/pengchujin/tower/main/Rulesets/ACL4SSR/\(revision)/ACL4SSR_Test_domain.mrs",
            srsURL: "https://raw.githubusercontent.com/pengchujin/tower/main/Rulesets/ACL4SSR/\(revision)/ACL4SSR_Test_singbox.srs"
        )
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)

        let lines = repository.lines(for: resource)
        XCTAssertEqual(repository.clashMRSResources(for: resource, matching: lines), [])
        XCTAssertNil(repository.singBoxSRSResource(for: resource, matching: lines))
    }

    func testBundledMRSMetadataFailsClosedWhenInputCountDoesNotMatchSource() throws {
        let fixture = try makeBinaryMetadataBundle(mrsInputRuleCount: 2)
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        XCTAssertEqual(
            repository.clashMRSResources(
                for: resource,
                matching: repository.lines(for: resource)
            ),
            []
        )
    }

    func testBundledMRSMetadataCannotClaimNoResolveMissingFromSource() throws {
        let fixture = try makeBinaryMetadataBundle(
            sourceContent: "IP-CIDR,203.0.113.0/24\n",
            mrsBehavior: "ipcidr",
            mrsNoResolve: true,
            srsCoveredRuleTypes: ["IP-CIDR"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        XCTAssertEqual(
            repository.clashMRSResources(
                for: resource,
                matching: repository.lines(for: resource)
            ),
            []
        )
    }

    func testBundledSRSMetadataFailsClosedWhenCoveredTypesDoNotMatchSource() throws {
        let fixture = try makeBinaryMetadataBundle(
            srsCoveredRuleTypes: ["DOMAIN"]
        )
        defer { try? FileManager.default.removeItem(at: fixture.bundleURL) }

        let repository = RuleSchemeRepository(bundle: fixture.bundle)
        let resource = RuleSchemeRuleset.Resource.remote(fixture.sourceURL)
        XCTAssertNil(
            repository.singBoxSRSResource(
                for: resource,
                matching: repository.lines(for: resource)
            )
        )
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
        XCTAssertNil(nativeJSON["http_clients"], "Hiddify's embedded core is versioned separately")
        XCTAssertNil(nativeRoute["default_http_client"])

        let singBoxJSON = try json(native.generator.generate(
            nodes: [],
            scheme: native.scheme,
            target: .singBox,
            schemes: native.repository,
            preferRuleSets: true
        ).content)
        let singBoxRoute = try XCTUnwrap(singBoxJSON["route"] as? [String: Any])
        let httpClients = try XCTUnwrap(singBoxJSON["http_clients"] as? [[String: Any]])
        XCTAssertEqual(httpClients.count, 1)
        XCTAssertEqual(httpClients[0]["tag"] as? String, "tower-rule-set")
        XCTAssertEqual(httpClients[0]["engine"] as? String, "go")
        XCTAssertEqual(httpClients[0]["detour"] as? String, "Proxy")
        XCTAssertEqual(singBoxRoute["default_http_client"] as? String, "tower-rule-set")

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

    func testSingBoxUsesVerifiedBinarySRSAndKeepsUncoveredTypesInline() throws {
        let srsURL = URL(string: "https://rules.example.com/Streaming_singbox.srs")!
        let fixture = try makeFixture(
            content: """
            DOMAIN,exact.example
            DOMAIN-SUFFIX,example.com
            DOMAIN-KEYWORD,keep-inline
            IP-CIDR,203.0.113.0/24,no-resolve
            """,
            srsResource: .init(
                url: srsURL,
                coveredRuleTypes: ["DOMAIN", "DOMAIN-SUFFIX", "IP-CIDR"]
            )
        )

        let content = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .singBox,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        let configuration = try json(content)
        let route = try XCTUnwrap(configuration["route"] as? [String: Any])
        let remoteRuleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let httpClients = try XCTUnwrap(configuration["http_clients"] as? [[String: Any]])

        XCTAssertEqual(remoteRuleSets.count, 1)
        XCTAssertEqual(remoteRuleSets[0]["type"] as? String, "remote")
        XCTAssertEqual(remoteRuleSets[0]["format"] as? String, "binary")
        XCTAssertEqual(remoteRuleSets[0]["url"] as? String, srsURL.absoluteString)
        XCTAssertTrue((remoteRuleSets[0]["tag"] as? String)?.hasSuffix("-srs-1") == true)
        XCTAssertEqual(httpClients.first?["tag"] as? String, "tower-rule-set")
        XCTAssertEqual(httpClients.first?["engine"] as? String, "go")
        XCTAssertEqual(route["default_http_client"] as? String, "tower-rule-set")
        XCTAssertTrue(rules.contains { ($0["rule_set"] as? [String])?.count == 1 })
        XCTAssertTrue(rules.contains {
            ($0["domain_keyword"] as? [String]) == ["keep-inline"]
        })
        XCTAssertFalse(rules.contains { $0["domain"] != nil })
        XCTAssertFalse(rules.contains { $0["domain_suffix"] != nil })
        XCTAssertFalse(rules.contains { $0["ip_cidr"] != nil })

        let hiddifyContent = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .hiddify,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        let hiddifyRoute = try XCTUnwrap(try json(hiddifyContent)["route"] as? [String: Any])
        XCTAssertNil(hiddifyRoute["rule_set"])
        XCTAssertTrue((hiddifyRoute["rules"] as? [[String: Any]])?.contains {
            ($0["domain_suffix"] as? [String]) == ["example.com"]
        } == true)

        let inlineContent = fixture.generator.generate(
            nodes: [],
            scheme: fixture.scheme,
            target: .singBox,
            schemes: fixture.repository,
            preferRuleSets: false
        ).content
        let inlineRoute = try XCTUnwrap(try json(inlineContent)["route"] as? [String: Any])
        XCTAssertNil(inlineRoute["rule_set"])
        XCTAssertTrue((inlineRoute["rules"] as? [[String: Any]])?.contains {
            ($0["ip_cidr"] as? [String]) == ["203.0.113.0/24"]
        } == true)
    }

    func testUserAddedInlineRuleStaysLocalBesideBinaryRuleSets() throws {
        let mrsURL = URL(string: "https://rules.example.com/Streaming_domain.mrs")!
        let srsURL = URL(string: "https://rules.example.com/Streaming_singbox.srs")!
        let fixture = try makeFixture(
            content: "DOMAIN-SUFFIX,bundled.example",
            mrsResources: [.init(behavior: .domain, url: mrsURL)],
            srsResource: .init(
                url: srsURL,
                coveredRuleTypes: ["DOMAIN-SUFFIX"]
            )
        )
        var scheme = fixture.scheme
        scheme.rulesets.insert(
            RuleSchemeRuleset(
                groupName: "Proxy",
                resource: .inline("DOMAIN-SUFFIX,user-added.example")
            ),
            at: 1
        )

        let clash = fixture.generator.generate(
            nodes: [],
            scheme: scheme,
            target: .clashApple,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        XCTAssertTrue(clash.contains(mrsURL.absoluteString), clash)
        XCTAssertTrue(clash.contains("DOMAIN-SUFFIX,user-added.example,Proxy"), clash)

        let singBox = fixture.generator.generate(
            nodes: [],
            scheme: scheme,
            target: .singBox,
            schemes: fixture.repository,
            preferRuleSets: true
        ).content
        let route = try XCTUnwrap(try json(singBox)["route"] as? [String: Any])
        XCTAssertTrue((route["rule_set"] as? [[String: Any]])?.contains {
            $0["url"] as? String == srsURL.absoluteString
        } == true)
        XCTAssertTrue((route["rules"] as? [[String: Any]])?.contains {
            ($0["domain_suffix"] as? [String]) == ["user-added.example"]
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

    func testBundledACL4SSRPublishedManifestUsesBinaryRuleSetsOnSupportedClients() throws {
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
        let singBox = generator.generate(
            nodes: [], scheme: scheme, target: .singBox, schemes: repository
        ).content
        let egern = generator.generate(
            nodes: [], scheme: scheme, target: .egern, schemes: repository
        ).content

        XCTAssertTrue(clash.contains("rule-providers:"), clash)
        XCTAssertTrue(clash.contains("format: mrs"), clash)
        XCTAssertTrue(clash.contains("https://raw.githubusercontent.com/pengchujin/tower/"), clash)
        XCTAssertTrue(clash.contains("/Rulesets/ACL4SSR/"), clash)
        XCTAssertFalse(clash.contains("/main/Rulesets/ACL4SSR/"), clash)
        XCTAssertTrue(surge.contains("RULE-SET,https://raw.githubusercontent.com/"), surge)
        XCTAssertTrue(loon.contains("[Remote Rule]"), loon)

        // Most ACL4SSR lists use classical Clash syntax. A pure IP-CIDR list is
        // also valid Quantumult X filter syntax, so that individual source can
        // stay remote while unsupported sources remain mapped locally.
        XCTAssertTrue(quanX.contains("ChinaCompanyIp.list, tag="), quanX)
        XCTAssertTrue(quanX.contains("host-suffix, acl4.ssr, "), quanX)

        XCTAssertTrue(singBox.contains(#""format" : "binary""#), singBox)
        XCTAssertTrue(singBox.contains("_singbox.srs"), singBox)
        XCTAssertTrue(singBox.contains(#""rule_set""#), singBox)
        XCTAssertTrue(singBox.contains("https://raw.githubusercontent.com/pengchujin/tower/"), singBox)
        XCTAssertFalse(singBox.contains("/main/Rulesets/ACL4SSR/"), singBox)

        // Hiddify and Egern require their own verified remote formats. SRS is
        // intentionally enabled only for the standalone sing-box MT target.
        XCTAssertFalse(hiddify.contains(#""rule_set""#), hiddify)
        XCTAssertFalse(egern.contains("  - rule_set:"), egern)
    }

    private func makeFixture(
        url: URL? = nil,
        content: String,
        mrsResources: [RuleSchemeRepository.ClashMRSResource]? = nil,
        srsResource: RuleSchemeRepository.SingBoxSRSResource? = nil
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
            RuleSchemeRepository(
                downloadStore: store,
                clashMRSResources: mrsResources.map { [resolvedURL: $0] },
                singBoxSRSResources: srsResource.map { [resolvedURL: $0] }
            )
        )
    }

    private func makeBinaryMetadataBundle(
        sourceSHA: String? = nil,
        sourceContent: String = "DOMAIN-SUFFIX,example.com\n",
        revision: String = "1111111111111111111111111111111111111111",
        artifactCommit: String? = "2222222222222222222222222222222222222222",
        mrsURL: String? = nil,
        srsURL: String? = nil,
        mrsBehavior: String = "domain",
        mrsInputRuleCount: Int = 1,
        mrsNoResolve: Bool? = nil,
        srsCoveredRuleTypes: [String] = ["DOMAIN-SUFFIX"]
    ) throws -> (
        bundle: Bundle,
        bundleURL: URL,
        sourceURL: URL,
        mrsURL: String,
        srsURL: String
    ) {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tower-RuleSetBundle-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.jzb.tower.tests.ruleset.\(UUID().uuidString)",
            "CFBundleName": "RuleSetFixture",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1",
            "CFBundleVersion": "1"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleURL.appendingPathComponent("Info.plist"))
        try Data(sourceContent.utf8)
            .write(to: bundleURL.appendingPathComponent("ACL4SSR_Test.list"))

        let sourceURL = URL(string: "https://rules.example.com/Test.list")!
        let resolvedSourceSHA = sourceSHA ?? SHA256.hash(data: Data(sourceContent.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let artifactSHA = String(repeating: "a", count: 64)
        let artifactReference = artifactCommit ?? "main"
        let artifactBase = "https://raw.githubusercontent.com/pengchujin/tower/"
            + "\(artifactReference)/Rulesets/ACL4SSR/\(revision)"
        let resolvedMRSURL = mrsURL ?? "\(artifactBase)/ACL4SSR_Test_\(mrsBehavior).mrs"
        let resolvedSRSURL = srsURL ?? "\(artifactBase)/ACL4SSR_Test_singbox.srs"
        var mrsMetadata: [String: Any] = [
            "compilerVersion": "v1",
            "inputRuleCount": mrsInputRuleCount,
            "ruleCount": 1,
            "sha256": artifactSHA,
            "sourceSha256": resolvedSourceSHA,
            "url": resolvedMRSURL
        ]
        if let mrsNoResolve {
            mrsMetadata["noResolve"] = mrsNoResolve
        }
        var manifest: [String: Any] = [
            "revision": revision,
            "rulesets": [
                "ACL4SSR_Test.list": [
                    "source": sourceURL.absoluteString,
                    "sha256": resolvedSourceSHA,
                    "ruleCount": 1,
                    "mrs": [
                        mrsBehavior: mrsMetadata
                    ],
                    "mrsResidualRuleCount": 0,
                    "srs": [
                        "compilerVersion": "1.14.0",
                        "coveredRuleTypes": srsCoveredRuleTypes,
                        "inputRuleCount": 1,
                        "residualRuleCount": 0,
                        "sha256": artifactSHA,
                        "sourceFormatVersion": 2,
                        "sourceSha256": resolvedSourceSHA,
                        "url": resolvedSRSURL
                    ]
                ]
            ]
        ]
        if let artifactCommit {
            manifest["artifactCommit"] = artifactCommit
        }
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: bundleURL.appendingPathComponent("ACL4SSR_manifest.json"))

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        XCTAssertNotNil(bundle.url(forResource: "ACL4SSR_Test", withExtension: "list"))
        XCTAssertNotNil(bundle.url(forResource: "ACL4SSR_manifest", withExtension: "json"))
        return (bundle, bundleURL, sourceURL, resolvedMRSURL, resolvedSRSURL)
    }

    private func json(_ content: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]
        )
    }
}
