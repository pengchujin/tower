import XCTest
@testable import Tower

final class NativeRoutingRuleTests: XCTestCase {
    private let node = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "test", rawURI: "")

    private func parse(_ rules: [String], surge: Bool = false) throws -> RuleScheme {
        let text = surge
            ? "[Proxy Group]\nOpenAI = select,Test\n[Rule]\n" + rules.joined(separator: "\n")
            : "proxy-groups:\n  - name: OpenAI\n    type: select\n    proxies: [Test]\nrules:\n" + rules.map { "  - " + $0 }.joined(separator: "\n")
        return try RuleSchemeParser().parse(text: text, id: "native", name: "Native", summary: "")
    }

    private func output(_ scheme: RuleScheme, _ target: ClientTarget) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, preferRuleSets: false)
    }

    func testDirectRejectSurvivesSelectionAndTextEditing() throws {
        let scheme = try parse(["DOMAIN-SUFFIX,openai.com,REJECT", "DOMAIN-SUFFIX,chatgpt.com,REJECT-DROP", "MATCH,OpenAI"])
        let selected = scheme.customized(enabledRuleGroupNames: ["OpenAI"], customRuleFlows: [])
        XCTAssertEqual(selected.rulesets, scheme.rulesets)
        for target in [ClientTarget.clashMi, .surge, .surgeMac] {
            let generated = output(selected, target)
            XCTAssertFalse(generated.hasInvalidPolicyReferences)
            XCTAssertTrue(generated.content.contains("DOMAIN-SUFFIX,openai.com,REJECT"))
            XCTAssertTrue(generated.content.contains("DOMAIN-SUFFIX,chatgpt.com,REJECT-DROP"))
        }
        XCTAssertNoThrow(try RuleSchemeTextEditorService().validatedScheme(from: XCTUnwrap(scheme.rawConfigurationText), replacing: scheme))
    }

    func testUDP443RejectConvertsToBothDialectsWithoutChangingOrder() throws {
        let rules = [
            "AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT",
            "AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,chatgpt.com)),REJECT",
            "DOMAIN-SUFFIX,openai.com,OpenAI", "DOMAIN-SUFFIX,chatgpt.com,OpenAI", "MATCH,OpenAI"
        ]
        let scheme = try parse(rules)
        for target in [ClientTarget.clashMi, .surge, .surgeMac] {
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences)
            let expected = target == .clashMi ? rules[0] : rules[0].replacingOccurrences(of: "NETWORK", with: "PROTOCOL").replacingOccurrences(of: "DST-PORT", with: "DEST-PORT")
            let first = try XCTUnwrap(result.content.range(of: expected))
            let later = try XCTUnwrap(result.content.range(of: "DOMAIN-SUFFIX,openai.com,OpenAI"))
            XCTAssertLessThan(first.lowerBound, later.lowerBound)
        }
    }

    func testNestedLogicalConditionsConvertRecursively() throws {
        let rule = "AND,((NOT,((SRC-IP,192.168.1.10))),(OR,((PROTOCOL,UDP),(DEST-PORT,80-90)))),REJECT"
        let scheme = try parse([rule, "FINAL,OpenAI"], surge: true)
        let result = output(scheme, .clashMi)
        XCTAssertTrue(result.content.contains("AND,((NOT,((SRC-IP-CIDR,192.168.1.10/32))),(OR,((NETWORK,UDP),(DST-PORT,80-90)))),REJECT"))
    }

    func testAllMihomoLeafTypesRemainInMihomoOutput() throws {
        let leaves = ["DOMAIN-REGEX,^api.*com$", "IP-SUFFIX,8.8.8.8/24", "SRC-GEOIP,CN", "SRC-IP-ASN,13335", "SRC-IP-CIDR,192.168.0.0/16", "SRC-IP-SUFFIX,192.168.1.1/8", "DST-PORT,443", "NETWORK,UDP", "IN-TYPE,SOCKS", "IN-USER,test", "IN-NAME,entry", "REMATCH-NAME,route", "PROCESS-PATH,/usr/bin/curl", "PROCESS-PATH-WILDCARD,/usr/*/curl", "PROCESS-PATH-REGEX,.*bin/curl", "PROCESS-NAME-WILDCARD,*curl*", "PROCESS-NAME-REGEX,curl$", "UID,1001", "DSCP,4"]
        let result = output(try parse(leaves.map { $0 + ",OpenAI" } + ["MATCH,OpenAI"]), .clashMi)
        for leaf in leaves { XCTAssertTrue(result.content.contains(leaf + ",OpenAI"), leaf) }
    }

    func testSurgeNativeTypesAndOptionsStayNative() throws {
        let lines = ["DEVICE-NAME,Kids,REJECT", "MAC-ADDRESS,AA:BB:CC:DD:EE:FF,REJECT", "HOSTNAME-TYPE,IPv6,REJECT", "CELLULAR-RADIO,LTE,OpenAI", "CELLULAR-CARRIER,310260,OpenAI", "DOMAIN,ad.example,REJECT,pre-matching", "DOMAIN,api.example,OpenAI,extended-matching,notification-text=Matched,notification-interval=600,always-capture=test", "FINAL,OpenAI,dns-failed,notification-interval=900"]
        let scheme = try parse(lines, surge: true)
        XCTAssertEqual(scheme.rulesets.map(\.groupName), ["REJECT", "REJECT", "REJECT", "OpenAI", "OpenAI", "REJECT", "OpenAI", "OpenAI"])
        let result = output(scheme, .surge)
        for line in lines { XCTAssertTrue(result.content.contains(line), line) }
        let restored = try JSONDecoder().decode(RuleScheme.self, from: JSONEncoder().encode(scheme))
        XCTAssertEqual(output(restored, .surge).content, result.content)
    }

    func testSourceIPFlagConvertsWithoutMatchingDestinationIP() throws {
        let scheme = try parse(["IP-CIDR,192.168.0.0/16,OpenAI,src", "MATCH,OpenAI"])
        XCTAssertTrue(output(scheme, .clashMi).content.contains("IP-CIDR,192.168.0.0/16,OpenAI,src"))
        XCTAssertTrue(output(scheme, .surge).content.contains("SRC-IP,192.168.0.0/16,OpenAI"))
    }

    func testQuotedRegexAndInlineCommentsPreserveValues() throws {
        let scheme = try parse(["URL-REGEX,'^https://example.com/a{1,3}#x',OpenAI // comment", "DOMAIN,one.example,REJECT # comment", "DOMAIN,two.example,REJECT ; comment", "FINAL,OpenAI"], surge: true)
        XCTAssertEqual(scheme.rulesets.map(\.groupName), ["OpenAI", "REJECT", "REJECT", "OpenAI"])
        XCTAssertTrue(output(scheme, .surge).content.contains("URL-REGEX,'^https://example.com/a{1,3}#x',OpenAI"))
    }

    func testUntranslatableConditionReportsLossWithoutBroadeningReject() throws {
        let scheme = try parse(["AND,((PROTOCOL,QUIC),(DOMAIN-SUFFIX,openai.com)),REJECT", "FINAL,OpenAI"], surge: true)
        let result = output(scheme, .clashMi)
        XCTAssertFalse(result.diagnostics.isEmpty)
        XCTAssertFalse(result.content.contains("DOMAIN-SUFFIX,openai.com,REJECT"))
        XCTAssertFalse(result.content.contains("NETWORK,UDP"))
        XCTAssertFalse(result.content.contains("PROTOCOL,QUIC"))
    }

    func testSurgeAndMihomoBuiltinsValidateOnlyOnCompatibleTargets() throws {
        for (policy, target) in [("PASS", ClientTarget.clashMi), ("PASS-RULE", .clashMi), ("COMPATIBLE", .clashMi), ("REJECT-NO-DROP", .surge), ("REJECT-TINYGIF", .surge), ("CELLULAR", .surge), ("CELLULAR-ONLY", .surge), ("HYBRID", .surge), ("NO-HYBRID", .surge)] {
            let scheme = try parse(["DOMAIN,example.com,\(policy)", target == .clashMi ? "MATCH,OpenAI" : "FINAL,OpenAI"], surge: target != .clashMi)
            let result = output(scheme, target)
            XCTAssertFalse(result.hasInvalidPolicyReferences, policy)
            XCTAssertTrue(result.content.contains("DOMAIN,example.com,\(policy)"), policy)
            let incompatible = output(scheme, .quanx)
            XCTAssertFalse(incompatible.diagnostics.isEmpty, policy)
        }
    }

    func testMalformedLogicalRulesAreRejected() {
        for line in ["AND,((NETWORK,UDP),(DST-PORT,443),REJECT", "NOT,((NETWORK,UDP),(DST-PORT,443)),REJECT", "AND,(),REJECT", "AND,((MATCH,OpenAI)),REJECT"] {
            XCTAssertThrowsError(try parse([line, "MATCH,OpenAI"]), line)
        }
    }
}
