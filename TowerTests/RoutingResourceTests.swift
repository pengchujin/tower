import Foundation
import Testing
@testable import Tower

struct RoutingResourceTests {
    private let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")
    private func parse(_ body: String) throws -> RuleScheme {
        try RuleSchemeParser().parse(text: body, id: "resource", name: "Resource", summary: "")
    }
    private var clashGroup: String { "proxy-groups:\n  - name: OpenAI\n    type: select\n    proxies: [Test]\n" }
    private func provider(_ behavior: String, payload: String? = nil) -> String {
        clashGroup + "rule-providers:\n  sample:\n    behavior: \(behavior)\n" + (payload.map { "    type: inline\n    payload: \($0)\n" } ?? "    type: http\n    url: https://example.com/rules.yaml\n    interval: 947\n") + "rules:\n  - RULE-SET,sample,OpenAI,no-resolve\n  - MATCH,OpenAI\n"
    }
    private func generated(_ scheme: RuleScheme, _ target: ClientTarget, content: String? = nil, remote: Bool = false) throws -> GeneratedConfiguration {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleDownloadStore(folderURL: folder)
        for url in scheme.remoteRulesetURLs { if let content { try store.store(content, for: url) } }
        return ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, schemes: RuleSchemeRepository(downloadStore: store), preferRuleSets: remote)
    }
    @Test func inlineDomainProviderExpandsWithoutLosingDomainBoundaries() throws {
        let scheme = try parse(provider("domain", payload: "['+.example.com', 'exact.example.net']"))
        let result = try generated(scheme, .clashMi)
        #expect(result.content.contains("DOMAIN-SUFFIX,example.com,OpenAI"))
        #expect(result.content.contains("DOMAIN,exact.example.net,OpenAI"))
    }
    @Test func downloadedIPProviderPreservesRulesAndInterval() throws {
        let scheme = try parse(provider("ipcidr"))
        for remote in [false, true] {
            let result = try generated(scheme, .clashMi, content: "payload:\n  - '192.0.2.0/24'\n", remote: remote)
            #expect(result.content.contains(remote ? "interval: 947" : "IP-CIDR,192.0.2.0/24,OpenAI,no-resolve"))
            #expect(result.content.contains(remote ? "behavior: ipcidr" : "192.0.2.0/24"))
        }
        let saved = try JSONDecoder().decode(RuleScheme.self, from: JSONEncoder().encode(scheme))
        #expect(try generated(saved, .clashMi, content: "payload:\n  - '192.0.2.0/24'\n", remote: true).content.contains("interval: 947"))
    }
    @Test(arguments: ["payload: ['DOMAIN,example.com']", "payload: # comment\n  - 'DOMAIN,example.com'\n"])
    func providerYAMLFormsHaveIdenticalMeaning(_ content: String) throws {
        let scheme = try parse(provider("classical"))
        #expect(try generated(scheme, .surge, content: content).content.contains("DOMAIN,example.com,OpenAI"))
    }
    @Test func referenceOptionsSurviveCacheExpansionAndNativeOutput() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nRULE-SET,https://example.com/a.list,OpenAI,extended-matching,update-interval=947\nFINAL,OpenAI,dns-failed")
        let content = "DOMAIN,example.com"
        #expect(try generated(scheme, .surge, content: content, remote: true).content.contains("OpenAI,extended-matching,update-interval=947"))
        #expect(try generated(scheme, .surge, content: content).content.contains("DOMAIN,example.com,OpenAI,extended-matching"))
        var noSource = scheme; noSource.rawConfigurationText = nil
        let edited = try RuleSchemeTextEditorService().validatedScheme(from: RuleSchemeTextEditorService().editableText(for: noSource), replacing: noSource)
        #expect(edited.rulesets == noSource.rulesets)
    }
    @Test func nativeStashURLRuleIsRetained() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nURL-REGEX,^https://example.com/path,OpenAI\nFINAL,OpenAI")
        #expect(try generated(scheme, .clash).content.contains("URL-REGEX,^https://example.com/path,OpenAI"))
    }
    @Test func quantumultResourceDomainAliasesConvertAcrossTargets() throws {
        let scheme = try parse(provider("classical"))
        let content = "HOST-SUFFIX,example.com,Other\nHOST,exact.example.net,Other"
        for target in [ClientTarget.clashMi, .surge] {
            let result = try generated(scheme, target, content: content)
            #expect(result.content.contains("DOMAIN-SUFFIX,example.com,OpenAI"))
            #expect(result.content.contains("DOMAIN,exact.example.net,OpenAI"))
            #expect(!result.content.contains(",Other"))
        }
    }
    @Test func singBoxReceivesUDP443ConjunctionWithoutBlockingTCP() throws {
        let scheme = try parse(clashGroup + "rules:\n  - AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT\n  - DOMAIN-SUFFIX,openai.com,OpenAI\n  - MATCH,OpenAI\n")
        let result = try generated(scheme, .singBox)
        let json = try #require(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let route = try #require(json["route"] as? [String: Any])
        let rules = try #require(route["rules"] as? [[String: Any]])
        let reject = try #require(rules.first { $0["action"] as? String == "reject" })
        #expect(reject["mode"] as? String == "and")
        #expect((reject["rules"] as? [[String: Any]])?.count == 3)
        #expect(rules.contains { $0["outbound"] as? String == "OpenAI" })
    }
    @Test func surgePortComparisonConvertsToMihomoRange() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nDEST-PORT,>=443,OpenAI\nFINAL,OpenAI")
        #expect(try generated(scheme, .clashMi).content.contains("DST-PORT,443-65535,OpenAI"))
    }
    @Test func unsupportedRejectDoesNotProduceAnApparentlyUsableConfig() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nAND,((PROTOCOL,QUIC),(DOMAIN-SUFFIX,openai.com)),REJECT\nFINAL,OpenAI")
        let result = try generated(scheme, .clashMi)
        #expect(result.content.isEmpty)
        #expect(!result.diagnostics.isEmpty)
    }
    @Test func loonRemoteRuleCanBeImportedAgain() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nFINAL,OpenAI\n[Remote Rule]\nhttps://example.com/rules.list,policy=OpenAI,enabled=true")
        #expect(scheme.remoteRulesetURLs.count == 1)
    }

    @Test func unsupportedProviderAuthenticationIsNotSilentlyDiscarded() {
        let text = provider("classical").replacingOccurrences(of: "    interval: 947", with: "    interval: 947\n    header:\n      Authorization: ['example']")
        #expect(throws: RuleSchemeParseError.self) { try parse(text) }
    }
    @Test func crossClientReferenceIntervalHasNoDanglingComma() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nRULE-SET,https://example.com/a.list,OpenAI,update-interval=947\nFINAL,OpenAI")
        let result = try generated(scheme, .clashMi, content: "DOMAIN,example.com", remote: true)
        #expect(result.content.contains("interval: 947"))
        #expect(!result.content.contains("OpenAI,\n"))
    }
    @Test func unsupportedFinalFlagIsReportedInsteadOfChangingFallback() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nFINAL,OpenAI,dns-failed")
        let result = try generated(scheme, .clashMi)
        #expect(result.content.isEmpty)
        #expect(!result.diagnostics.isEmpty)
    }
    @Test func warningCountExcludesRulesThatCannotBeEmitted() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nURL-REGEX,^https://example.com,OpenAI\nFINAL,OpenAI")
        let result = try generated(scheme, .clashMi)
        #expect(result.ruleCount == 1)
        #expect(!result.diagnostics.isEmpty)
    }

    @Test func expandedDomainSetRetainsMatchingOptions() throws {
        let scheme = try parse("[Proxy Group]\nOpenAI=select,Test\n[Rule]\nDOMAIN-SET,https://example.com/domains.txt,OpenAI,extended-matching\nFINAL,OpenAI")
        let result = try generated(scheme, .surge, content: ".example.com")
        #expect(result.content.contains("DOMAIN-SUFFIX,example.com,OpenAI,extended-matching"))
    }
}
