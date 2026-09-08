import XCTest
import CryptoKit
@testable import Tower

final class PolicyGroupGeneratorTests: XCTestCase {
    private let nodes = [
        ProxyNode(kind: .trojan, name: "A", server: "a.example.com", port: 443, password: "test", rawURI: ""),
        ProxyNode(kind: .trojan, name: "B", server: "b.example.com", port: 443, password: "test", rawURI: "")
    ]

    private func result(_ kind: RuleSchemeGroup.Kind, target: ClientTarget, algorithm: String? = nil,
                        parameters: [String: String]? = nil) -> GeneratedConfiguration {
        let group = RuleSchemeGroup(name: "Choice", kind: kind,
                                    members: [.nodePattern("^A$"), .nodePattern("^B$")],
                                    interval: 123, algorithm: algorithm, parameters: parameters)
        let scheme = RuleScheme(id: "matrix", name: "Matrix", summary: "", groups: [group],
                                rulesets: [.init(groupName: "Choice", resource: .inline("FINAL"))], isBundled: false)
        return ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: target)
    }

    func testFallbackPreservesFirstAvailableTypeAcrossConfirmedTargets() {
        let expected: [(ClientTarget, String)] = [(.surge, "Choice = fallback"), (.quanx, "available=Choice"),
            (.clash, "type: fallback"), (.clashMi, "type: fallback"), (.clashApple, "type: fallback"),
            (.loon, "Choice = fallback"), (.egern, "- fallback:")]
        for (target, text) in expected {
            let output = result(.fallback, target: target)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            XCTAssertTrue(output.content.contains(text), "\(target): \(output.content)")
        }
    }

    func testRoundRobinNeverBecomesHashOrLatencyTest() {
        for (target, text) in [(ClientTarget.quanx, "round-robin=Choice"), (.clash, "strategy: round-robin"),
                               (.loon, "algorithm=Round-Robin"), (.egern, "algorithm: round_robin")] {
            XCTAssertTrue(result(.loadBalance, target: target, algorithm: "round-robin").content.contains(text))
        }
        XCTAssertFalse(result(.loadBalance, target: .surge, algorithm: "round-robin").content.isEmpty)
    }

    func testDestinationHashAndRandomAreDistinctSurgeModes() {
        let hash = result(.loadBalance, target: .surge, algorithm: "dest-hash")
        XCTAssertTrue(hash.content.contains("persistent=true"))
        let random = result(.loadBalance, target: .surge, algorithm: "random")
        XCTAssertTrue(random.content.contains("Choice = load-balance"))
        XCTAssertFalse(random.content.contains("persistent=true"))
        XCTAssertFalse(result(.loadBalance, target: .quanx, algorithm: "random").hasInvalidPolicyReferences)
    }

    func testStickySessionsIsNotSilentlyMappedToAnotherHash() {
        XCTAssertTrue(result(.loadBalance, target: .clashMi, algorithm: "sticky-sessions").content.contains("strategy: sticky-sessions"))
        XCTAssertFalse(result(.loadBalance, target: .clashApple, algorithm: "sticky-sessions").content.isEmpty)
        XCTAssertFalse(result(.loadBalance, target: .egern, algorithm: "sticky-sessions").content.isEmpty)
    }

    func testSmartHasNativeEgernWrapperAndOtherTargetsDowngrade() {
        XCTAssertTrue(result(.smart, target: .egern).content.contains("- smart:"))
        for target in [ClientTarget.quanx, .singBox, .hiddify, .clash, .karing, .loon, .shadowrocket] {
            let output = result(.smart, target: target)
            XCTAssertFalse(output.content.isEmpty, target.rawValue)
            XCTAssertTrue(output.hasExportableProxies, target.rawValue)
            XCTAssertEqual(output.diagnostics.count, 1, target.rawValue)
        }
    }

    func testUnknownSemanticsAndSourceOptionsDowngradeWithoutBlocking() {
        XCTAssertFalse(result(.unsupported, target: .surge).content.isEmpty)
        XCTAssertFalse(result(.loadBalance, target: .egern, algorithm: "new-algorithm").content.isEmpty)
        XCTAssertFalse(result(.select, target: .surge, parameters: ["unknown-route-option": "true"]).content.isEmpty)
    }

    func testSingBoxOnlyExpressesSelectorAndURLTest() {
        for kind in [RuleSchemeGroup.Kind.fallback, .loadBalance, .conditional, .relay] {
            XCTAssertFalse(result(kind, target: .singBox).content.isEmpty)
        }
        XCTAssertTrue(result(.urlTest, target: .singBox).content.contains("123s"))
    }

    func testRelayIsOnlyEmittedForConfirmedStashDialect() {
        let stash = result(.relay, target: .clashApple)
        XCTAssertTrue(stash.content.contains("type: relay"))
        XCTAssertFalse(stash.content.contains("type: url-test"))
        XCTAssertFalse(result(.relay, target: .quanx).content.isEmpty)
    }

    func testNativeNetworkConditionalsRoundTripInTheirOwnDialect() throws {
        let fixtures: [(String, ClientTarget, String)] = [
            ("[Proxy Group]\nNet = subnet, default=DIRECT, SSID:Home=REJECT\n[Rule]\nFINAL,Net", .surge, "Net = subnet"),
            ("[policy]\nssid=Net,direct,reject,Home:direct\n[filter_local]\nfinal,Net", .quanx, "ssid=Net"),
            ("policy_groups:\n  - conditional:\n      name: Net\n      default_policy: DIRECT\n      rules:\n        - ssid:\n            match: Home*\n            policy: REJECT\nrules:\n  - default:\n      policy: Net", .egern, "- conditional:")
        ]
        for (source, target, expected) in fixtures {
            let scheme = try RuleSchemeParser().parse(text: source, id: "conditional", name: "Conditions", summary: "")
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: target)
            XCTAssertTrue(output.content.contains(expected), output.diagnostics.joined())
            XCTAssertFalse(ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .singBox).content.isEmpty)
        }
    }
    func testGeneratedMihomoRuntimeFixtures() throws {
        let fixtureNodes = ["A", "B"].enumerated().map { offset, name in
            ProxyNode(kind: .http, name: name, server: "127.0.0.1", port: 18080 + offset, rawURI: "")
        }
        let cases: [(String, RuleSchemeGroup.Kind, String?)] = [
            ("fallback", .fallback, nil), ("round-robin", .loadBalance, "round-robin"),
            ("consistent-hashing", .loadBalance, "consistent-hashing")
        ]
        for (name, kind, algorithm) in cases {
            let group = RuleSchemeGroup(name: "Policy", kind: kind,
                                        members: [.nodePattern("^A$"), .nodePattern("^B$")],
                                        testURLString: "http://fixture.invalid/health", interval: 1,
                                        algorithm: algorithm)
            let scheme = RuleScheme(id: "runtime", name: "Runtime", summary: "", groups: [group],
                                    rulesets: [.init(groupName: "Policy", resource: .inline("FINAL"))], isBundled: false)
            let output = ConfigurationGenerator().generate(nodes: fixtureNodes, scheme: scheme,
                                                          target: .clashMi, preferRuleSets: false)
            XCTAssertFalse(output.content.isEmpty, output.diagnostics.joined())
            XCTAssertTrue(output.content.contains("MATCH,Policy"))
            do {
                let directory = ProcessInfo.processInfo.environment["TOWER_POLICY_FIXTURES_DIR"]
                let url = directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("TowerPolicyRuntimeFixtures", isDirectory: true)
                print("TOWER_POLICY_FIXTURE: \(url.path)")
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data(output.content.utf8).write(to: url.appendingPathComponent(name + ".yaml"),
                                                    options: [.atomic, .completeFileProtection])
            }
        }
    }

    func testResourceTagsBindSelectedTowerSourcesWithoutFetchingURLs() throws {
        let a = SubscriptionSource(name: "Airport A", urlString: "https://example.com/a")
        let b = SubscriptionSource(name: "Airport B", urlString: "https://example.com/b")
        let nodes = [
            ProxyNode(sourceID: a.id, kind: .http, name: "A", server: "a.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: b.id, kind: .http, name: "B", server: "b.example.com", port: 80, rawURI: "")
        ]
        let hashes = Dictionary(uniqueKeysWithValues: [a, b].map { source in
            (source.id, SHA256.hash(data: Data(source.urlString.utf8)).map { String(format: "%02x", $0) }.joined())
        })
        let source = """
        [policy]
        static=Choice,resource-tag-regex=^Airport A$
        [server_remote]
        https://example.com/a,tag=Airport A,enabled=true
        https://example.com/b,tag=Airport B,enabled=true
        [filter_local]
        final,Choice
        """
        let scheme = try RuleSchemeParser().parse(text: source, id: "resources", name: "Resources", summary: "")
        let local = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx, sourceURLHashes: hashes)
        XCTAssertTrue(local.content.contains("static=Choice, A"), local.diagnostics.joined())
        let policy = try XCTUnwrap(local.content.components(separatedBy: "\n").first { $0.hasPrefix("static=Choice") })
        XCTAssertFalse(policy.contains(", B"), policy)
        let remote = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx,
                remoteSubscriptions: [RemoteSubscriptionLink(source: a), RemoteSubscriptionLink(source: b)], sourceURLHashes: hashes)
        let remotePolicy = try XCTUnwrap(remote.content.components(separatedBy: "\n").first { $0.hasPrefix("static=Choice") })
        XCTAssertTrue(remotePolicy.contains("Airport A"), remotePolicy)
        XCTAssertFalse(remotePolicy.contains("Airport B"), remotePolicy)
        let missing = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx)
        XCTAssertTrue(missing.content.contains("static=Choice, direct"), missing.diagnostics.joined())
        XCTAssertFalse(missing.diagnostics.isEmpty)
    }

    func testClashProviderFilterDoesNotExpandOtherSourcesOrDropExplicitNodes() throws {
        let a = SubscriptionSource(name: "A", urlString: "https://example.com/a")
        let b = SubscriptionSource(name: "B", urlString: "https://example.com/b")
        let nodes = [
            ProxyNode(sourceID: a.id, kind: .http, name: "A keep", server: "a.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: a.id, kind: .http, name: "A drop", server: "b.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: b.id, kind: .http, name: "B explicit", server: "c.example.com", port: 80, rawURI: ""),
            ProxyNode(sourceID: b.id, kind: .http, name: "B extra", server: "d.example.com", port: 80, rawURI: "")
        ]
        let hashes = Dictionary(uniqueKeysWithValues: [a, b].map { source in
            (source.id, SHA256.hash(data: Data(source.urlString.utf8)).map { String(format: "%02x", $0) }.joined())
        })
        let source = """
        proxy-providers:
          AirportA: {type: http, url: https://example.com/a}
          AirportB: {type: http, url: https://example.com/b}
        proxy-groups:
          - name: Choice
            type: fallback
            proxies: [B explicit]
            use: [AirportA]
            filter: A
            exclude-filter: drop
        rules: [MATCH,Choice]
        """
        // Quote rule strings containing commas in flow lists.
        let scheme = try RuleSchemeParser().parse(text: source.replacingOccurrences(of: "rules: [MATCH,Choice]", with: "rules: [\"MATCH,Choice\"]"),
                                                 id: "providers", name: "Providers", summary: "")
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .clashMi, sourceURLHashes: hashes)
        XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
        let groups = try XCTUnwrap(output.content.components(separatedBy: "proxy-groups:").last)
        XCTAssertTrue(groups.contains("B explicit"), groups)
        XCTAssertTrue(groups.contains("A keep"), groups)
        XCTAssertFalse(groups.contains("B extra"), groups)
        XCTAssertFalse(groups.contains("A drop"), groups)
    }

    func testLoonNativeProxyChainPreservesOrderedHopsInSeparateSection() throws {
        let source = """
        [Proxy Group]
        Main = select, Chain
        [Proxy Chain]
        Chain = A, B
        [Rule]
        FINAL,Main
        """
        let scheme = try RuleSchemeParser().parse(text: source, id: "chain", name: "Chain", summary: "")
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .loon)
        XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
        XCTAssertTrue(output.content.contains("[Proxy Chain]\nChain = A,B"), output.content)
        XCTAssertFalse(output.content.contains("Chain = url-test"))
        XCTAssertFalse(ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx).content.isEmpty)
    }

    func testINIPolicyReferencesUseTheSameSanitizedNamesAsDeclarations() {
        let name = "出口,#"
        let policy = RuleSchemeGroup(name: name, kind: .select, members: [.reference("DIRECT")])
        let scheme = RuleScheme(id: "names", name: "Names", summary: "", groups: [policy],
            rulesets: [.init(groupName: name, resource: .inline("DOMAIN,example.com")),
                       .init(groupName: name, resource: .inline("FINAL"))], isBundled: false)
        for target in [ClientTarget.surge, .loon] {
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: target)
            XCTAssertTrue(output.content.contains("出口，＃ = select"), output.content)
            XCTAssertTrue(output.content.contains("DOMAIN,example.com,出口，＃"), output.content)
            XCTAssertFalse(output.content.contains("DOMAIN,example.com,出口,#"))
        }
    }

    func testQXSSIDNormalizesPolicyReferencesButKeepsNetworkLiteral() throws {
        let name = "出口,#"
        let policy = RuleSchemeGroup(name: name, kind: .select, members: [.reference("DIRECT")])
        let fields = [name, "direct", "Home#WiFi:" + name]
        let parameters = ["ssid-members": String(data: try JSONEncoder().encode(fields), encoding: .utf8)!]
        let network = RuleSchemeGroup(name: "Network", kind: .conditional,
                members: [.reference(name), .reference("DIRECT")], sourceType: "ssid", sourceFormat: "quanx", parameters: parameters)
        let scheme = RuleScheme(id: "ssid-names", name: "SSID names", summary: "", groups: [policy, network],
                rulesets: [.init(groupName: "Network", resource: .inline("FINAL"))], isBundled: false)
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx)
        XCTAssertTrue(output.content.contains("ssid=Network, 出口，＃, direct, Home#WiFi:出口，＃"), output.content)
        XCTAssertFalse(output.content.contains("%2C"))
    }

    func testQXMissingOrDisabledResourceNeverFallsBackToAllSources() throws {
        for remoteSection in ["", "[server_remote]\nhttps://example.com/disabled,tag=Missing,enabled=false\n"] {
            let source = "[policy]\nstatic=Choice,resource-tag-regex=Missing\n" + remoteSection + "[filter_local]\nfinal,Choice"
            let scheme = try RuleSchemeParser().parse(text: source, id: "missing-resource", name: "Missing", summary: "")
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx)
            XCTAssertTrue(output.content.contains("static=Choice, direct"), output.diagnostics.joined())
            XCTAssertFalse(output.content.contains("static=Choice, A"))
            XCTAssertFalse(output.diagnostics.isEmpty)
        }
    }

    func testClashMissingProviderNeverFallsBackToAllSources() throws {
        let source = """
        proxy-groups:
          - name: Choice
            type: select
            use: [Missing]
        rules: ["MATCH,Choice"]
        """
        let scheme = try RuleSchemeParser().parse(text: source, id: "missing-provider", name: "Missing", summary: "")
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .clashMi)
        let groups = try XCTUnwrap(output.content.components(separatedBy: "proxy-groups:").last)
        XCTAssertTrue(groups.contains("DIRECT"), groups)
        XCTAssertFalse(groups.contains("- \"A\""), groups)
        XCTAssertFalse(output.diagnostics.isEmpty)
    }

    func testSurgeNumericBooleanOptionsRemainAccepted() throws {
        for boolean in ["0", "1"] {
            let source = "[Proxy Group]\nMain = select, DIRECT, no-alert=" + boolean + "\n[Rule]\nFINAL,Main"
            let scheme = try RuleSchemeParser().parse(text: source, id: "bool", name: "Bool", summary: "")
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .surge)
            XCTAssertFalse(output.hasInvalidPolicyReferences, output.diagnostics.joined())
            XCTAssertTrue(output.content.contains("no-alert="), output.content)
        }
    }

    func testNativeRegexFlagsAreNotOverriddenByLegacyCaseFolding() {
        for (pattern, shouldMatch) in [("^a$", false), ("(?i)^a$", true)] {
            let group = RuleSchemeGroup(name: "Choice", kind: .select, members: [.nodePattern(pattern)], sourceFormat: "clash")
            let scheme = RuleScheme(id: "case", name: "Case", summary: "", groups: [group],
                        rulesets: [.init(groupName: "Choice", resource: .inline("FINAL"))], isBundled: false)
            let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .clashMi)
            let groups = output.content.components(separatedBy: "proxy-groups:").last ?? ""
            XCTAssertEqual(groups.contains("- \"A\""), shouldMatch, groups)
            XCTAssertEqual(groups.contains("DIRECT"), !shouldMatch, groups)
        }
    }

    func testEgernOverlappingPriorityPatternsKeepDeclarationOrder() throws {
        let source = """
        policy_groups:
          - smart:
              name: Choice
              policies: [A, B]
              priorities:
                '^A$': 0.8
                '.*': 1.2
        rules:
          - default:
              policy: Choice
        """
        let scheme = try RuleSchemeParser().parse(text: source, id: "priority", name: "Priority", summary: "")
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .egern)
        XCTAssertFalse(output.content.isEmpty, output.diagnostics.joined())
        let specific = try XCTUnwrap(output.content.range(of: "0.8"))
        let general = try XCTUnwrap(output.content.range(of: "1.2"))
        XCTAssertLessThan(specific.lowerBound, general.lowerBound)
    }

    func testSmartAndNotificationOptionsDoNotBlockShadowrocket() throws {
        let scheme = try RuleSchemeParser().parse(text: "[Proxy Group]\nChoice = smart, include-all-proxies=true\nManual = select, Choice, no-alert=1\n[Rule]\nFINAL,Manual", id: "compat", name: "Compat", summary: "")
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .shadowrocket)
        XCTAssertTrue(output.hasExportableProxies, output.diagnostics.joined())
        XCTAssertTrue(output.content.contains("type: url-test"))
        XCTAssertEqual(output.diagnostics.count, 2)
        XCTAssertEqual(scheme.groups.first?.kind, .smart)
    }

    func testMultipleSmartGroupsProduceOneWarningAndKeepNativeSource() {
        let groups = ["One", "Two"].map { RuleSchemeGroup(name: $0, kind: .smart, members: [.nodePattern(".*")], sourceFormat: "egern", parameters: ["priorities": "{\"A\":0.5}"]) }
        let scheme = RuleScheme(id: "multi", name: "Multi", summary: "", groups: groups, rulesets: [.init(groupName: "One", resource: .inline("FINAL"))], isBundled: false)
        let converted = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .singBox)
        XCTAssertTrue(converted.hasExportableProxies)
        XCTAssertEqual(converted.diagnostics.count, 1)
        XCTAssertTrue(converted.content.contains("urltest"))
        let native = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .egern)
        XCTAssertTrue(native.content.contains("- smart:"))
        XCTAssertTrue(native.content.contains("priorities:"))
        XCTAssertTrue(native.diagnostics.isEmpty)
    }

}

extension PolicyGroupGeneratorTests {
    func testUnsupportedPoliciesDowngradeAcrossConfigurationTargets() {
        for target in ClientTarget.allCases where target != .v2box {
            for kind in [RuleSchemeGroup.Kind.fallback, .loadBalance, .relay, .unsupported] {
                let output = result(kind, target: target, algorithm: "unknown-algorithm",
                                    parameters: ["unknown-option": "true"])
                XCTAssertFalse(output.content.isEmpty, "\(target) \(kind): \(output.diagnostics)")
                XCTAssertFalse(output.hasInvalidPolicyReferences)
            }
        }
    }

    func testSurgeConditionalDowngradeKeepsDefaultNotFirstNetwork() {
        let group = RuleSchemeGroup(name: "Network", kind: .conditional,
            members: [.reference("A"), .reference("B")], sourceFormat: "surge",
            parameters: ["subnet-fields": "[\"SSID:Home=A\",\"default=B\"]"])
        let scheme = RuleScheme(id: "network", name: "Network", summary: "", groups: [group],
            rulesets: [.init(groupName: "Network", resource: .inline("FINAL"))])
        let output = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .quanx)
        XCTAssertTrue(output.content.contains("static=Network, B"))
        XCTAssertFalse(output.hasInvalidPolicyReferences)
        XCTAssertEqual(scheme.groups[0].kind, .conditional)
    }
}

extension PolicyGroupGeneratorTests {
    func testQuanXFilteredLatencyGroupsListConcreteCandidates() throws {
        let output = result(.urlTest, target: .quanx)
        let line = try XCTUnwrap(output.content.split(separator: "\n").first { $0.hasPrefix("url-latency-benchmark=Choice") })
        XCTAssertTrue(line.contains("Choice, A, B,"))
        XCTAssertFalse(line.contains("server-tag-regex="))
        XCTAssertFalse(line.contains("direct"))
    }
}
