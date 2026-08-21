import XCTest
@testable import Tower

final class RuleCatalogTests: XCTestCase {
    func testBuiltInCatalogContainsBothMaintainersAndRepresentativeRoutes() throws {
        let catalog = RuleCatalog.builtIn

        XCTAssertEqual(Set(catalog.entries.map(\.provider)), [.acl4ssr, .blackmatrix7])
        XCTAssertEqual(Set(catalog.entries.map(\.id)).count, catalog.entries.count)
        XCTAssertEqual(catalog.entries.filter { $0.provider == .acl4ssr }.count, 182)
        XCTAssertEqual(catalog.entries.filter { $0.provider == .blackmatrix7 }.count, 689)
        XCTAssertEqual(catalog.entries.count, 871)

        XCTAssertTrue(catalog.entries.contains {
            $0.sourceURLString.hasSuffix("/Clash/Ruleset/Whatsapp.list")
        })
        XCTAssertTrue(catalog.entries.contains {
            $0.sourceURLString.hasSuffix("/rule/Clash/PrivateTracker/PrivateTracker.list")
        })
        XCTAssertTrue(catalog.entries.contains {
            $0.sourceURLString.hasSuffix("/rule/Clash/AdGuardSDNSFilter/Direct/Direct.list")
        })

        let openAI = try XCTUnwrap(catalog.entries.first { $0.id == "blackmatrix7-openai" })
        XCTAssertEqual(openAI.defaultRoute, .proxy)
        XCTAssertEqual(openAI.suggestedPolicyName, "AI 服务")

        let advertising = try XCTUnwrap(catalog.entries.first { $0.id == "blackmatrix7-advertising" })
        XCTAssertEqual(advertising.defaultRoute, .reject)

        let china = try XCTUnwrap(catalog.entries.first { $0.id == "blackmatrix7-china-max" })
        XCTAssertEqual(china.defaultRoute, .direct)

        for entry in catalog.entries {
            let url = try XCTUnwrap(URL(string: entry.sourceURLString), entry.id)
            XCTAssertEqual(url.scheme, "https", entry.id)
            XCTAssertNotNil(url.host, entry.id)
        }
    }

    func testBuiltInCatalogSearchesChatGPTAndChineseAliases() {
        let catalog = RuleCatalog.builtIn

        XCTAssertTrue(catalog.search("ChatGPT").contains { $0.id == "blackmatrix7-openai" })
        XCTAssertTrue(catalog.search("油管").contains { $0.name == "YouTube" })
        XCTAssertTrue(catalog.search("国内直连").contains { $0.defaultRoute == .direct })
    }

    func testEveryCatalogEntryHasAnEmojiForUnifiedCustomization() {
        for entry in RuleCatalog.builtIn.entries {
            XCTAssertFalse(entry.emoji.isEmpty, entry.id)
            XCTAssertTrue(entry.displayName.hasPrefix(entry.emoji), entry.id)
        }
    }

    func testEffectiveSchemeIncludesCatalogRulesInRemoteURLList() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let flow = try makeAIEntry().makeCustomization(for: scheme)

        let effective = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(effective.remoteRulesetURLs, [try XCTUnwrap(flow.remoteRuleURL)])
    }

    func testDownloadedCatalogRuleReachesEveryClientWhenRuleSetsAreDisabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-generation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory)
        let scheme = makeScheme(includeAIGroup: false)
        let flow = try makeAIEntry().makeCustomization(for: scheme)
        let remoteURL = try XCTUnwrap(flow.remoteRuleURL)
        try store.store("DOMAIN-SUFFIX,openai.com", for: remoteURL)
        let effective = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )
        let repository = RuleSchemeRepository(downloadStore: store)
        let node = ProxyNode(
            kind: .shadowsocks,
            name: "香港 01",
            server: "hk.example.com",
            port: 443,
            cipher: "aes-128-gcm",
            password: "demo",
            rawURI: "ss://demo"
        )

        for target in ClientTarget.allCases {
            let result = ConfigurationGenerator().generate(
                nodes: [node],
                scheme: effective,
                target: target,
                schemes: repository,
                preferRuleSets: false
            )
            XCTAssertTrue(result.content.contains("openai.com"), "\(target.name) 丢失目录规则")
        }
    }

    @MainActor
    func testBundledSchemeIsNotReadyUntilAddedCatalogRuleIsCached() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-cache-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            downloadStore: store,
            arguments: []
        )
        var scheme = makeScheme(includeAIGroup: true)
        scheme.isBundled = true
        let flow = try makeAIEntry().makeCustomization(for: scheme)
        let url = try XCTUnwrap(flow.remoteRuleURL)
        model.upsertCustomRuleFlow(flow)

        XCTAssertFalse(model.isSchemeReady(scheme))

        try store.store("DOMAIN-SUFFIX,openai.com", for: url)
        XCTAssertTrue(model.isSchemeReady(scheme))
    }

    func testCatalogRuleDownloaderCachesTheRemoteList() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-download-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory)
        let url = try XCTUnwrap(URL(string: "https://rules.example.com/openai.list"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuleCatalogURLProtocol.self]
        RuleCatalogURLProtocol.payloads = [url: Data("DOMAIN-SUFFIX,openai.com".utf8)]
        let service = RuleSchemeImportService(
            store: store,
            session: URLSession(configuration: configuration)
        )

        let failed = await service.cacheRulesets([url])

        XCTAssertEqual(failed, 0)
        XCTAssertEqual(store.lines(for: url), ["DOMAIN-SUFFIX,openai.com"])
    }

    @MainActor
    func testInstallingCatalogEntryDownloadsAndUpsertsByCatalogID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let url = try XCTUnwrap(URL(string: "https://rules.example.com/ai.list"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuleCatalogURLProtocol.self]
        RuleCatalogURLProtocol.payloads = [url: Data("DOMAIN-SUFFIX,openai.com".utf8)]
        let service = RuleSchemeImportService(
            store: store,
            session: URLSession(configuration: configuration)
        )
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            schemeImportService: service,
            downloadStore: store,
            arguments: []
        )
        let scheme = makeScheme(includeAIGroup: false)
        let entry = makeAIEntry()

        try await model.installCatalogEntry(entry, for: scheme)
        let firstID = try XCTUnwrap(model.customRuleFlows(for: scheme).first?.id)
        try await model.installCatalogEntry(entry, for: scheme)

        let flows = model.customRuleFlows(for: scheme)
        XCTAssertEqual(flows.count, 1)
        XCTAssertEqual(flows.first?.id, firstID)
        XCTAssertTrue(store.hasCachedRules(for: url))
        XCTAssertEqual(model.toast?.tone, .success)
    }

    @MainActor
    func testInstallingUserCreatedRemoteRuleDownloadsBeforePersisting() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-user-rule-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let url = try XCTUnwrap(URL(string: "https://rules.example.com/unban.list"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuleCatalogURLProtocol.self]
        RuleCatalogURLProtocol.payloads = [url: Data("DOMAIN-SUFFIX,example.com".utf8)]
        let service = RuleSchemeImportService(
            store: store,
            session: URLSession(configuration: configuration)
        )
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            schemeImportService: service,
            downloadStore: store,
            arguments: []
        )
        let scheme = makeScheme(includeAIGroup: false)
        let flow = CustomRuleFlow.userCreatedRuleSet(
            schemeID: scheme.id,
            name: "UnBan",
            rulesText: url.absoluteString,
            defaultPolicyName: "节点选择"
        )

        try await model.installCustomRuleFlow(flow)

        XCTAssertEqual(model.customRuleFlows(for: scheme).map(\.id), [flow.id])
        XCTAssertTrue(store.hasCachedRules(for: url))
    }

    @MainActor
    func testCatalogCheckmarkRepresentsAddedFlowRatherThanDownloadedCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-membership-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleDownloadStore(folderURL: directory.appendingPathComponent("rules"))
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            downloadStore: store,
            arguments: []
        )
        let scheme = makeScheme(includeAIGroup: false)
        let entry = makeAIEntry()
        let url = try XCTUnwrap(URL(string: entry.sourceURLString))
        try store.store("DOMAIN-SUFFIX,openai.com", for: url)

        XCTAssertTrue(store.hasCachedRules(for: url))
        XCTAssertFalse(model.isCatalogEntryAdded(entry, to: scheme))

        model.upsertCustomRuleFlow(try entry.makeCustomization(for: scheme))

        XCTAssertTrue(model.isCatalogEntryAdded(entry, to: scheme))
    }

    @MainActor
    func testRemovingCatalogEntryClearsOnlyItsCustomRuleMembership() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-rule-catalog-removal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(
            persistence: PersistenceStore(fileURL: directory.appendingPathComponent("state.json")),
            arguments: []
        )
        let scheme = makeScheme(includeAIGroup: false)
        let entry = makeAIEntry()
        model.upsertCustomRuleFlow(try entry.makeCustomization(for: scheme))

        XCTAssertTrue(model.isCatalogEntryAdded(entry, to: scheme))

        model.removeCatalogEntry(entry, from: scheme)

        XCTAssertFalse(model.isCatalogEntryAdded(entry, to: scheme))
        XCTAssertTrue(model.customRuleFlows(for: scheme).isEmpty)
    }

    func testSearchMatchesLocalizedAliasAndProviderName() {
        let catalog = RuleCatalog(entries: [
            RuleCatalogEntry(
                id: "acl4ssr-netflix",
                name: "Netflix",
                aliases: ["奈飞", "流媒体"],
                category: .streaming,
                provider: .acl4ssr,
                sourceURLString: "https://rules.example.com/netflix.list",
                defaultRoute: .proxy,
                suggestedPolicyName: "奈飞视频"
            )
        ])

        XCTAssertEqual(catalog.search("奈飞").map(\.id), ["acl4ssr-netflix"])
        XCTAssertEqual(catalog.search("ACL4SSR").map(\.id), ["acl4ssr-netflix"])
        XCTAssertTrue(catalog.search("广告").isEmpty)
    }

    func testProxyCatalogEntryReusesExistingPolicyGroup() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeAIEntry()

        let flow = try entry.makeCustomization(for: scheme)

        XCTAssertEqual(flow.name, "AI 服务")
        XCTAssertEqual(flow.policyName, "AI 服务")
        XCTAssertNil(flow.generatedPolicyGroup)
        XCTAssertEqual(flow.sourceURLString, entry.sourceURLString)
        XCTAssertEqual(flow.catalogID, entry.id)
    }

    func testOpenAICatalogEntryKeepsItsOwnRuleGroupIdentity() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()

        let flow = try entry.makeCustomization(for: scheme)
        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(flow.name, "OpenAI")
        XCTAssertEqual(flow.policyName, "🤖 OpenAI")
        XCTAssertEqual(flow.generatedPolicyGroup?.name, "🤖 OpenAI")
        XCTAssertEqual(
            flow.generatedPolicyGroup?.members,
            [.reference("节点选择"), .reference("DIRECT")]
        )
        XCTAssertTrue(customized.groups.contains { $0.name == "🤖 OpenAI" })
        XCTAssertEqual(
            customized.rulesets.first { $0.resource == .remote(URL(string: entry.sourceURLString)!) }?.groupName,
            "🤖 OpenAI"
        )
    }

    func testOpenAICatalogFlowExpandsIntoSeparateRuleSetPolicyGroupAndBinding() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()

        let expansion = try entry.makeCustomization(for: scheme).expansion

        XCTAssertEqual(expansion.ruleSet.name, "OpenAI")
        XCTAssertEqual(expansion.ruleSet.remoteURL?.absoluteString, entry.sourceURLString)
        XCTAssertEqual(expansion.policyGroup?.name, "🤖 OpenAI")
        XCTAssertEqual(expansion.binding.policyGroupName, "🤖 OpenAI")
    }

    func testLegacyOpenAICatalogFlowMigratesWithoutOverwritingUserState() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()
        let flowID = UUID()
        let legacy = CustomRuleFlow(
            id: flowID,
            schemeID: scheme.id,
            name: "OpenAI",
            policyName: "AI 服务",
            rulesText: "DOMAIN-SUFFIX,custom.example",
            isEnabled: false,
            catalogID: entry.id,
            sourceURLString: entry.sourceURLString
        )

        let migrated = try XCTUnwrap(entry.migratedLegacyCustomization(legacy, for: scheme))

        XCTAssertEqual(migrated.id, flowID)
        XCTAssertEqual(migrated.name, "OpenAI")
        XCTAssertEqual(migrated.policyName, "🤖 OpenAI")
        XCTAssertEqual(migrated.generatedPolicyGroup?.name, "🤖 OpenAI")
        XCTAssertEqual(migrated.rulesText, legacy.rulesText)
        XCTAssertFalse(migrated.isEnabled)
    }

    func testLegacyOpenAIFlowWhoseNameWasOverwrittenByAIServiceMigrates() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()
        let legacy = CustomRuleFlow(
            schemeID: scheme.id,
            name: "AI 服务",
            policyName: "AI 服务",
            rulesText: "",
            catalogID: entry.id,
            sourceURLString: entry.sourceURLString
        )

        let migrated = try XCTUnwrap(entry.migratedLegacyCustomization(legacy, for: scheme))

        XCTAssertEqual(migrated.name, "OpenAI")
        XCTAssertEqual(migrated.policyName, "🤖 OpenAI")
        XCTAssertEqual(migrated.generatedPolicyGroup?.name, "🤖 OpenAI")
    }

    func testLegacyMigrationDoesNotOverwriteAnEditedOpenAIPolicy() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()
        let edited = CustomRuleFlow(
            schemeID: scheme.id,
            name: "OpenAI",
            policyName: "🇯🇵 日本节点",
            rulesText: "",
            catalogID: entry.id,
            sourceURLString: entry.sourceURLString
        )

        XCTAssertNil(entry.migratedLegacyCustomization(edited, for: scheme))
    }

    func testLegacyGeneratedAIServiceGroupIsRenamedWithoutLosingCandidates() throws {
        let scheme = makeScheme(includeAIGroup: true)
        let entry = makeOpenAIEntry()
        let legacy = CustomRuleFlow(
            schemeID: scheme.id,
            name: "OpenAI",
            policyName: "AI 服务",
            rulesText: "",
            catalogID: entry.id,
            sourceURLString: entry.sourceURLString,
            generatedPolicyGroup: RuleSchemeGroup(
                name: "AI 服务",
                kind: .select,
                members: [.reference("日本节点"), .reference("DIRECT")]
            )
        )

        let migrated = try XCTUnwrap(entry.migratedLegacyCustomization(legacy, for: scheme))

        XCTAssertEqual(migrated.policyName, "🤖 OpenAI")
        XCTAssertEqual(migrated.generatedPolicyGroup?.name, "🤖 OpenAI")
        XCTAssertEqual(
            migrated.generatedPolicyGroup?.members,
            [.reference("日本节点"), .reference("DIRECT")]
        )
    }

    func testChineseNetflixPolicyUsesStreamingEmoji() {
        XCTAssertEqual(
            RulePolicyPresentation.emoji(for: "奈飞视频", kind: .select),
            "🎞️"
        )
    }

    func testProxyCatalogEntryCreatesPolicyGroupWhenSchemeDoesNotHaveOne() throws {
        let scheme = makeScheme(includeAIGroup: false)

        let flow = try makeAIEntry().makeCustomization(for: scheme)

        XCTAssertEqual(flow.policyName, "🤖 AI 服务")
        XCTAssertEqual(flow.generatedPolicyGroup?.name, "🤖 AI 服务")
        XCTAssertEqual(
            flow.generatedPolicyGroup?.members,
            [.reference("节点选择"), .reference("DIRECT")]
        )
    }

    func testDirectAndRejectEntriesCreateCustomizablePolicyGroups() throws {
        let scheme = makeScheme(includeAIGroup: false)
        let direct = RuleCatalogEntry(
            id: "lan",
            name: "局域网",
            category: .domestic,
            provider: .acl4ssr,
            sourceURLString: "https://rules.example.com/lan.list",
            defaultRoute: .direct
        )
        let reject = RuleCatalogEntry(
            id: "ads",
            name: "广告拦截",
            category: .advertising,
            provider: .acl4ssr,
            sourceURLString: "https://rules.example.com/ads.list",
            defaultRoute: .reject
        )

        let directFlow = try direct.makeCustomization(for: scheme)
        let rejectFlow = try reject.makeCustomization(for: scheme)

        XCTAssertEqual(directFlow.policyName, "🏠 局域网")
        XCTAssertEqual(directFlow.generatedPolicyGroup?.members, [.reference("DIRECT")])
        XCTAssertEqual(rejectFlow.policyName, "🛑 广告拦截")
        XCTAssertEqual(rejectFlow.generatedPolicyGroup?.members, [.reference("REJECT")])
    }

    func testUnrelatedRemoteCustomizationStaysNearFinal() throws {
        let scheme = makeScheme(includeAIGroup: false)
        let flow = try makeAIEntry().makeCustomization(for: scheme)

        let customized = scheme.customized(
            enabledRuleGroupNames: nil,
            customRuleFlows: [flow]
        )

        XCTAssertEqual(
            customized.groups.map(\.name),
            ["节点选择", "自动选择", "🤖 AI 服务", "漏网之鱼"]
        )
        XCTAssertEqual(
            customized.rulesets.map(\.resource),
            [
                .inline("DOMAIN-SUFFIX,example.com"),
                .remote(try XCTUnwrap(URL(string: "https://rules.example.com/ai.list"))),
                .inline("FINAL"),
            ]
        )
        XCTAssertEqual(customized.rulesets.map(\.groupName), ["节点选择", "🤖 AI 服务", "漏网之鱼"])
    }

    func testOldCustomRuleFlowJSONStillDecodes() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "schemeID": "scheme",
          "name": "Tailscale",
          "policyName": "DIRECT",
          "rulesText": "DOMAIN-SUFFIX,tailscale.com",
          "isEnabled": true
        }
        """

        let flow = try JSONDecoder().decode(CustomRuleFlow.self, from: Data(json.utf8))

        XCTAssertNil(flow.catalogID)
        XCTAssertNil(flow.sourceURLString)
        XCTAssertNil(flow.generatedPolicyGroup)
        XCTAssertEqual(flow.normalizedRules, ["DOMAIN-SUFFIX,tailscale.com"])
    }

    private func makeAIEntry() -> RuleCatalogEntry {
        RuleCatalogEntry(
            id: "acl4ssr-ai",
            name: "AI 服务",
            aliases: ["OpenAI", "ChatGPT"],
            category: .ai,
            provider: .acl4ssr,
            sourceURLString: "https://rules.example.com/ai.list",
            defaultRoute: .proxy,
            suggestedPolicyName: "AI 服务"
        )
    }

    private func makeOpenAIEntry() -> RuleCatalogEntry {
        RuleCatalogEntry(
            id: "acl4ssr-openai",
            name: "OpenAI",
            aliases: ["ChatGPT", "GPT"],
            category: .ai,
            provider: .acl4ssr,
            sourceURLString: "https://rules.example.com/openai.list",
            defaultRoute: .proxy,
            suggestedPolicyName: "AI 服务"
        )
    }

    private func makeScheme(includeAIGroup: Bool) -> RuleScheme {
        var groups = [
            RuleSchemeGroup(
                name: "节点选择",
                kind: .select,
                members: [.reference("自动选择"), .reference("DIRECT")]
            ),
            RuleSchemeGroup(
                name: "自动选择",
                kind: .urlTest,
                members: [.nodePattern(".*")]
            ),
            RuleSchemeGroup(
                name: "漏网之鱼",
                kind: .select,
                members: [.reference("节点选择"), .reference("DIRECT")]
            ),
        ]
        if includeAIGroup {
            groups.insert(
                RuleSchemeGroup(
                    name: "AI 服务",
                    kind: .select,
                    members: [.reference("节点选择"), .reference("DIRECT")]
                ),
                at: 2
            )
        }
        return RuleScheme(
            id: "scheme",
            name: "测试方案",
            summary: "测试",
            groups: groups,
            rulesets: [
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("DOMAIN-SUFFIX,example.com")),
                RuleSchemeRuleset(groupName: "漏网之鱼", resource: .inline("FINAL")),
            ]
        )
    }
}

private final class RuleCatalogURLProtocol: URLProtocol {
    nonisolated(unsafe) static var payloads: [URL: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let payload = Self.payloads[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
