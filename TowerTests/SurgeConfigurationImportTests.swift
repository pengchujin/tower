import XCTest
@testable import Tower

/// A complete Surge `.conf` carries its policy groups and rules in
/// `[Proxy Group]` and `[Rule]`, which is the same information a subconverter
/// `.ini` puts in `custom_proxy_group=` and `ruleset=`.
final class SurgeConfigurationImportTests: XCTestCase {
    private let parser = RuleSchemeParser()

    private let conf = """
    [General]
    loglevel = notify

    [Rule]
    # 注释行应当忽略
    PROCESS-NAME,ss-local,DIRECT
    DOMAIN,www.example.com,YouTube
    RULE-SET,https://rules.example.com/YouTube.list,YouTube,update-interval=86400
    RULE-SET,https://rules.example.com/Direct.list,DIRECT,update-interval=86400
    IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
    AND,((PROTOCOL,UDP),(DEST-PORT,443)),REJECT-NO-DROP
    GEOIP,CN,DIRECT
    FINAL,Proxies

    [Proxy]
    HK 01 = ss, hk.example.com, 8388, encrypt-method=aes-128-gcm, password=pw

    [Proxy Group]
    Proxies = select,HK,DIRECT,HK 01
    YouTube = select,Proxies,HK
    HK = url-test,HK 01,url=http://www.gstatic.com/generate_204,interval=300,tolerance=50
    """

    private func parse() throws -> RuleScheme {
        try parser.parse(text: conf, id: "surge", name: "Surge 配置", summary: "测试")
    }

    // MARK: - Groups

    func testReadsProxyGroupsFromSurgeConfiguration() throws {
        let scheme = try parse()

        XCTAssertEqual(scheme.groups.map(\.name), ["Proxies", "YouTube", "HK"])
        XCTAssertEqual(scheme.groups.first { $0.name == "HK" }?.kind, .urlTest)
    }

    func testSiblingGroupsAndBuiltinsBecomeReferences() throws {
        let group = try XCTUnwrap(parse().groups.first { $0.name == "Proxies" })

        XCTAssertEqual(group.members[0], .reference("HK"))
        XCTAssertEqual(group.members[1], .reference("DIRECT"))
    }

    func testLiteralNodeNameBecomesAnAnchoredPattern() throws {
        let group = try XCTUnwrap(parse().groups.first { $0.name == "Proxies" })

        // "HK 01" is a node, not a group, so it must match that node exactly
        // rather than being emitted as a name the client would not resolve.
        // A space needs no escaping; metacharacters in a node name do.
        XCTAssertEqual(group.members[2], .nodePattern("^HK 01$"))
    }

    func testRegexMetacharactersInNodeNamesAreEscaped() throws {
        let scheme = try parser.parse(
            text: """
            [Rule]
            FINAL,Proxies

            [Proxy Group]
            Proxies = select,Rate 2.0x (IEPL)
            """,
            id: "x",
            name: "x",
            summary: "x"
        )
        let group = try XCTUnwrap(scheme.groups.first)

        XCTAssertEqual(group.members, [.nodePattern("^Rate 2\\.0x \\(IEPL\\)$")])
    }

    func testURLTestParametersAreNotTreatedAsMembers() throws {
        let group = try XCTUnwrap(parse().groups.first { $0.name == "HK" })

        XCTAssertEqual(group.members.count, 1)
        XCTAssertEqual(group.testURLString, "http://www.gstatic.com/generate_204")
        XCTAssertEqual(group.interval, 300)
        XCTAssertEqual(group.tolerance, 50)
    }

    // MARK: - Rules

    func testRuleSetLinesBecomeRemoteRulesets() throws {
        let scheme = try parse()

        XCTAssertEqual(scheme.remoteRulesetURLs.map(\.absoluteString), [
            "https://rules.example.com/YouTube.list",
            "https://rules.example.com/Direct.list"
        ])
    }

    func testRuleSetPolicyIsTakenFromTheThirdField() throws {
        let scheme = try parse()
        let youtube = try XCTUnwrap(scheme.rulesets.first {
            if case .remote(let url) = $0.resource { return url.absoluteString.hasSuffix("YouTube.list") }
            return false
        })

        // update-interval= trails the policy and must not be mistaken for it.
        XCTAssertEqual(youtube.groupName, "YouTube")
    }

    func testInlineRulesKeepTheirPolicyAndFlags() throws {
        let scheme = try parse()
        let inline = scheme.rulesets.compactMap { ruleset -> (String, String)? in
            guard case .inline(let rule) = ruleset.resource else { return nil }
            return (rule, ruleset.groupName)
        }

        XCTAssertTrue(inline.contains { $0 == ("DOMAIN,www.example.com", "YouTube") })
        XCTAssertTrue(inline.contains { $0 == ("IP-CIDR,10.0.0.0/8,no-resolve", "DIRECT") })
        XCTAssertTrue(inline.contains { $0 == ("FINAL", "Proxies") })
    }

    func testLogicalRulesAreSkipped() throws {
        let scheme = try parse()

        // AND nests comma-separated conditions in parentheses, so splitting on
        // commas would corrupt it, and no other client understands the form.
        XCTAssertFalse(scheme.rulesets.contains { ruleset in
            if case .inline(let rule) = ruleset.resource { return rule.hasPrefix("AND") }
            return false
        })
    }

    // MARK: - Round trip

    func testGeneratesForEveryTargetWithTheImportedGroups() throws {
        let scheme = try parse()
        let node = ProxyNode(
            kind: .shadowsocks,
            name: "HK 01",
            server: "hk.example.com",
            port: 8388,
            cipher: "aes-128-gcm",
            password: "pw",
            rawURI: "ss://x"
        )

        for target in ClientTarget.allCases {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                scheme: scheme,
                target: target
            ).content

            for group in scheme.groups {
                XCTAssertTrue(content.contains(group.name), "\(target.name) 缺少组 \(group.name)")
            }
        }
    }

    func testAnchoredNodePatternSelectsThatNode() throws {
        let scheme = try parse()
        let nodes = [
            ProxyNode(kind: .shadowsocks, name: "HK 01", server: "a.example.com", port: 8388, cipher: "aes-128-gcm", password: "pw", rawURI: "ss://a"),
            ProxyNode(kind: .shadowsocks, name: "HK 011", server: "b.example.com", port: 8388, cipher: "aes-128-gcm", password: "pw", rawURI: "ss://b")
        ]

        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            scheme: scheme,
            target: .surge
        ).content
        let line = try XCTUnwrap(
            content.components(separatedBy: .newlines).first { $0.hasPrefix("HK = ") }
        )

        // Anchoring keeps "HK 011" out of a group that asked for "HK 01".
        XCTAssertTrue(line.contains("HK 01"), line)
        XCTAssertFalse(line.contains("HK 011"), line)
    }
}
