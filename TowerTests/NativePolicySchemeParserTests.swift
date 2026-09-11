import XCTest
@testable import Tower

final class NativePolicySchemeParserTests: XCTestCase {
    private func parse(_ text: String) throws -> RuleScheme {
        try RuleSchemeParser().parse(text: text, id: "fixture", name: "Fixture", summary: "")
    }

    func testClashStructuredFlowAndArbitraryIndentationPreserveSemantics() throws {
        let scheme = try parse("""
        proxy-groups:
            - {name: '首选,组', type: fallback, proxies: ['A,one', B], interval: 300}
            - name: Spread
              type: load-balance
              proxies:
                - '首选,组'
              strategy: sticky-sessions
        rules:
            - 'MATCH,Spread'
        """)
        XCTAssertEqual(scheme.groups.map(\.kind), [.fallback, .loadBalance])
        XCTAssertEqual(scheme.groups[0].name, "首选,组")
        XCTAssertEqual(scheme.groups[0].members.count, 2)
        XCTAssertEqual(scheme.groups[1].members, [.reference("首选,组")])
        XCTAssertEqual(scheme.groups[1].algorithm, "sticky-sessions")
    }

    func testQuantumultXNativeKindsAndParameters() throws {
        let scheme = try parse("""
        [policy]
        static = Manual, A, B
        available = Backup, A, B
        round-robin = Rotate, A, B
        dest-hash = Sticky, A, B
        url-latency-benchmark = Auto, A, B, check-interval=600, tolerance=50
        ssid = Network, Manual, Backup, Home:Auto
        [filter_local]
        host-suffix, example.com, Backup
        final, Network
        """)
        XCTAssertEqual(scheme.groups.map(\.kind), [.select, .fallback, .loadBalance, .loadBalance, .urlTest, .conditional])
        XCTAssertEqual(scheme.groups[4].interval, 600)
        XCTAssertEqual(scheme.groups[5].members, [.reference("Manual"), .reference("Backup"), .reference("Auto")])
        XCTAssertEqual(scheme.rulesets[0].resource, .inline("DOMAIN-SUFFIX,example.com"))
    }

    func testEgernNativeWrapperAndConditionalReferences() throws {
        let scheme = try parse("""
        policy_groups:
          - smart:
              name: Smart
              policies: [A, B]
              priorities: {A: 2}
          - conditional:
              name: Network
              default_policy: Smart
              rules:
                - ssid:
                    match: Home
                    policy: Smart
        rules:
          - default:
              policy: Network
        """)
        XCTAssertEqual(scheme.groups.map(\.kind), [.smart, .conditional])
        XCTAssertEqual(scheme.groups[0].parameters?["priorities"], "{\"A\":2}")
        XCTAssertEqual(scheme.groups[1].members, [.reference("Smart")])
    }

    func testSingBoxNativeDurationAndRoute() throws {
        let scheme = try parse("""
        {"outbounds":[{"type":"urltest","tag":"Auto","outbounds":["A","B"],"interval":"1m30s"}],"route":{"rules":[{"domain_suffix":["example.com"],"outbound":"Auto"}],"final":"Auto"}}
        """)
        XCTAssertEqual(scheme.groups[0].kind, .urlTest)
        XCTAssertEqual(scheme.groups[0].interval, 90)
        XCTAssertEqual(scheme.groups[0].parameters?["interval"], "1m30s")
        XCTAssertEqual(scheme.rulesets.count, 2)
        XCTAssertNil(scheme.rawConfigurationText)
    }

    func testUnknownGroupPreservedAndUnsupportedRuleFails() throws {
        let scheme = try parse("""
        proxy-groups:
          - {name: Experimental, type: future-smart, proxies: [A]}
        rules: [MATCH,Experimental]
        """.replacingOccurrences(of: "rules: [MATCH,Experimental]", with: "rules: ['MATCH,Experimental']"))
        XCTAssertEqual(scheme.groups[0].kind, .unsupported)
        XCTAssertEqual(scheme.groups[0].sourceType, "future-smart")
        XCTAssertThrowsError(try parse("""
        {"outbounds":[{"type":"selector","tag":"A","outbounds":["B"]}],"route":{"rules":[{"domain":["example.com"],"port":443,"outbound":"A"}],"final":"A"}}
        """))
    }

    func testClashIncludeAllFiltersAreMarkedAsDynamicSourcePatterns() throws {
        let scheme = try parse("""
        proxy-groups:
          - {name: HK, type: url-test, include-all: true, filter: '^HK$'}
        rules: ['MATCH,HK']
        """)
        XCTAssertEqual(scheme.groups[0].parameters?["tower-source-patterns"], "[\"^HK$\"]")
        XCTAssertEqual(scheme.groups[0].members, [.nodePattern("^HK$")])
    }

    func testQuantumultResourceBindingsStoreHashesWithoutSubscriptionCredentials() throws {
        let scheme = try parse("""
        [server_remote]
        https://example.com/sub?token=private-fixture, tag=Airport, enabled=true
        https://example.com/disabled, tag=Disabled, enabled=false
        [policy]
        available = Backup, resource-tag-regex=^Airport$, server-tag-regex=HK
        [filter_local]
        final, Backup
        """)
        let group = try XCTUnwrap(scheme.groups.first)
        let bindings = try XCTUnwrap(group.parameters?["tower-source-bindings"])
        XCTAssertTrue(bindings.contains(RuleSchemeParser.sourceURLHash("https://example.com/sub?token=private-fixture")))
        XCTAssertFalse(bindings.contains("Disabled"))
        XCTAssertFalse(bindings.contains("private-fixture"))
        XCTAssertEqual(group.parameters?["tower-source-patterns"], "[\"HK\"]")
        XCTAssertNil(scheme.rawConfigurationText)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(scheme), as: UTF8.self).contains("private-fixture"))
    }

    func testEgernExternalRetainsEffectiveTypeAndHashesSourceURLs() throws {
        let scheme = try parse("""
        policy_groups:
          - external:
              name: Airport
              type: fallback
              urls: ['https://example.com/sub?token=private-fixture']
              filter: HK
        rules:
          - default: {policy: Airport}
        """)
        XCTAssertEqual(scheme.groups[0].kind, .fallback)
        XCTAssertEqual(scheme.groups[0].sourceType, "external")
        XCTAssertNil(scheme.groups[0].parameters?["urls"])
        XCTAssertNotNil(scheme.groups[0].parameters?["tower-source-tags"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(scheme), as: UTF8.self).contains("private-fixture"))
    }

    func testLegacyMigrationRecoversFallbackWithoutReplacingMetadataGroups() throws {
        let source = """
        [Proxy Group]
        Backup = fallback,A,B
        Manual = select,A,B
        [Rule]
        FINAL,Backup
        """
        var scheme = try parse(source)
        scheme.groups = [
            .init(name: "Backup", kind: .urlTest, members: [.nodePattern(".*")]),
            .init(name: "Manual", kind: .select, members: [.reference("DIRECT")], sourceType: "select", sourceFormat: "surge")
        ]
        let migrated = RuleSchemeParser().restoringLegacySmartGroups(in: scheme)
        XCTAssertEqual(migrated.groups[0].kind, .fallback)
        XCTAssertEqual(migrated.groups[1].members, [.reference("DIRECT")])
        XCTAssertEqual(migrated.id, scheme.id)
        XCTAssertEqual(migrated.updatedAt, scheme.updatedAt)
    }

    func testUndefinedYAMLAliasesAreRejectedRatherThanChangingMeaning() {
        XCTAssertThrowsError(try parse("""
        proxy-groups:
          - name: Main
            type: select
            proxies: *shared
        rules: ['MATCH,Main']
        """))
    }
}
