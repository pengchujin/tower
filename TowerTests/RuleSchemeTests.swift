import XCTest
@testable import Tower

/// Covers the subconverter `.ini` dialect and the generator path that
/// reproduces an imported scheme's own policy groups.
final class RuleSchemeTests: XCTestCase {
    private let parser = RuleSchemeParser()

    private let sample = """
    [custom]
    ;注释行应当被忽略
    ruleset=🎯 全球直连,https://example.com/Clash/LocalAreaNetwork.list
    ruleset=🛑 全球拦截,https://example.com/Clash/BanAD.list
    ruleset=🎯 全球直连,[]GEOIP,CN
    ruleset=🐟 漏网之鱼,[]FINAL
    custom_proxy_group=🚀 节点选择`select`[]♻️ 自动选择`[]🇭🇰 香港节点`[]DIRECT
    custom_proxy_group=♻️ 自动选择`url-test`.*`http://www.gstatic.com/generate_204`300,,50
    custom_proxy_group=🇭🇰 香港节点`url-test`(港|HK|Hong Kong)`http://www.gstatic.com/generate_204`300,,50
    custom_proxy_group=🎯 全球直连`select`[]DIRECT`[]🚀 节点选择
    custom_proxy_group=🛑 全球拦截`select`[]REJECT`[]DIRECT
    custom_proxy_group=🐟 漏网之鱼`select`[]🚀 节点选择`[]DIRECT
    """

    private let nodes = [
        ProxyNode(
            kind: .shadowsocks,
            name: "HK 香港 01",
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "pw",
            rawURI: "ss://a"
        ),
        ProxyNode(
            kind: .trojan,
            name: "JP Tokyo 02",
            server: "jp.example.com",
            port: 443,
            password: "pw",
            tls: true,
            rawURI: "trojan://b"
        )
    ]

    // MARK: - Parsing

    func testImportedSummaryUsesTheCurrentDisplayLanguageInsteadOfPersistedCopy() throws {
        let scheme = RuleScheme(
            id: "imported-old-copy",
            name: "raw.githubusercontent.com",
            summary: "从 raw.githubusercontent.com 导入",
            sourceURLString: "https://raw.githubusercontent.com/example/rules/main/config.ini",
            groups: [],
            rulesets: [],
            isBundled: false
        )
        let englishResources = try XCTUnwrap(
            Bundle.main.url(forResource: "en", withExtension: "lproj")
        )
        let englishBundle = try XCTUnwrap(Bundle(url: englishResources))

        XCTAssertEqual(
            scheme.localizedSummary(bundle: englishBundle),
            "Import from raw.githubusercontent.com"
        )
    }

    func testParsesGroupsAndRulesets() throws {
        let scheme = try parse()

        XCTAssertEqual(scheme.groups.count, 6)
        XCTAssertEqual(scheme.rulesets.count, 4)
        XCTAssertEqual(scheme.remoteRulesetURLs.count, 2)
        XCTAssertEqual(scheme.finalGroupName, "🐟 漏网之鱼")
    }

    func testReferenceMembersAreDistinguishedFromNodePatterns() throws {
        let scheme = try parse()
        let select = try XCTUnwrap(scheme.groups.first { $0.name == "🚀 节点选择" })
        let auto = try XCTUnwrap(scheme.groups.first { $0.name == "♻️ 自动选择" })

        XCTAssertEqual(
            select.members,
            [.reference("♻️ 自动选择"), .reference("🇭🇰 香港节点"), .reference("DIRECT")]
        )
        XCTAssertEqual(auto.members, [.nodePattern(".*")])
        XCTAssertEqual(auto.kind, .urlTest)
    }

    func testParsesTestURLAndTimingWithoutTreatingThemAsMembers() throws {
        let scheme = try parse()
        let region = try XCTUnwrap(scheme.groups.first { $0.name == "🇭🇰 香港节点" })

        XCTAssertEqual(region.members, [.nodePattern("(港|HK|Hong Kong)")])
        XCTAssertEqual(region.testURLString, "http://www.gstatic.com/generate_204")
        XCTAssertEqual(region.interval, 300)
        XCTAssertEqual(region.tolerance, 50)
    }

    func testInlineRuleKeepsItsOwnComma() throws {
        let scheme = try parse()
        let inline = scheme.rulesets.filter {
            if case .inline = $0.resource { return true }
            return false
        }

        XCTAssertEqual(inline.count, 2)
        XCTAssertEqual(inline.first?.resource, .inline("GEOIP,CN"))
        XCTAssertEqual(inline.first?.groupName, "🎯 全球直连")
    }

    func testRejectsConfigWithoutGroups() {
        XCTAssertThrowsError(
            try parser.parse(text: "ruleset=A,[]FINAL", id: "x", name: "x", summary: "x")
        ) { error in
            XCTAssertEqual(error as? RuleSchemeParseError, .noGroups)
        }
    }

    func testParsesClashYAMLForManualSelfConfigurationDownload() throws {
        let yaml = """
        proxy-groups:
          - name: 🚀 节点选择
            type: select
            proxies:
              - DIRECT
              - 🇭🇰 Hong Kong
          - name: 🇭🇰 Hong Kong
            type: select
            use:
              - all-proxies
            filter: "(?i)港|HK|Hong Kong"
        rules:
          - RULE-SET,AI Suite,🚀 节点选择
          - GEOIP,CN,DIRECT
          - MATCH,🚀 节点选择
        rule-providers:
          AI Suite:
            type: http
            url: 'https://example.com/AI.yaml'
        """

        let scheme = try parser.parse(
            text: yaml,
            id: "self-configuration",
            name: "Self-Configuration",
            summary: "手动下载"
        )

        XCTAssertEqual(scheme.groups.count, 2)
        XCTAssertEqual(
            scheme.groups.last?.members,
            [.nodePattern("(?i)港|HK|Hong Kong")]
        )
        XCTAssertEqual(scheme.rulesets.count, 3)
        XCTAssertEqual(
            scheme.remoteRulesetURLs,
            [URL(string: "https://example.com/AI.yaml")!]
        )
        XCTAssertEqual(scheme.finalGroupName, "🚀 节点选择")
    }

    // MARK: - Bundled snapshots

    func testBundledACL4SSRSchemesLoadAndDifferInGroupCount() {
        let schemes = RuleSchemeRepository(bundle: .main).bundledSchemes()
        let ids = schemes.map(\.id)

        XCTAssertTrue(ids.contains("acl4ssr-default"), "缺少默认配置")
        XCTAssertTrue(ids.contains("acl4ssr-mini"), "缺少精简配置")
        XCTAssertTrue(ids.contains("acl4ssr-full"), "缺少全分组配置")

        let mini = schemes.first { $0.id == "acl4ssr-mini" }
        let full = schemes.first { $0.id == "acl4ssr-full" }
        XCTAssertNotNil(mini)
        XCTAssertNotNil(full)
        // The three presets exist precisely because their group counts differ;
        // collapsing them would defeat the point of shipping all three.
        XCTAssertGreaterThan(full?.groups.count ?? 0, mini?.groups.count ?? 0)
    }

    func testBundledRulesResolveOfflineWithoutNetwork() throws {
        let repository = RuleSchemeRepository(bundle: .main)
        let scheme = try XCTUnwrap(repository.bundledSchemes().first { $0.id == "acl4ssr-mini" })
        let total = scheme.rulesets.reduce(0) { $0 + repository.lines(for: $1.resource).count }

        XCTAssertGreaterThan(total, 100, "内置快照没有读到规则")
    }

    func testSelfConfigurationRulesAreNotInTheApplicationBundle() {
        let repository = RuleRepository(bundle: .main)
        let apple = RuleAssignment(resourcePath: "Apple", title: "Apple", policy: .apple)

        XCTAssertEqual(repository.count(for: apple), 0, "Self-Configuration 只能由用户主动下载")
        XCTAssertNil(Bundle.main.url(forResource: "SelfConfiguration-NOTICE", withExtension: "txt"))
        XCTAssertNil(Bundle.main.url(forResource: "manifest", withExtension: "json"))
    }

    // MARK: - Source URL handling

    func testGitHubPageURLIsRewrittenToTheRawFile() {
        let entered = URL(string: "https://github.com/ACL4SSR/ACL4SSR/blob/master/Clash/config/ACL4SSR_NoApple.ini")!

        XCTAssertEqual(
            RuleSchemeImportService.rawFileURL(for: entered).absoluteString,
            "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/ACL4SSR_NoApple.ini"
        )
    }

    func testGiteeAndGitLabPageURLsAreRewritten() {
        let gitee = URL(string: "https://gitee.com/owner/repo/blob/master/rule.ini")!
        let gitlab = URL(string: "https://gitlab.com/owner/repo/-/blob/main/rule.ini")!

        XCTAssertEqual(
            RuleSchemeImportService.rawFileURL(for: gitee).absoluteString,
            "https://gitee.com/owner/repo/raw/master/rule.ini"
        )
        XCTAssertEqual(
            RuleSchemeImportService.rawFileURL(for: gitlab).absoluteString,
            "https://gitlab.com/owner/repo/-/raw/main/rule.ini"
        )
    }

    func testAlreadyRawURLIsLeftAlone() {
        let raw = URL(string: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/config/x.ini")!

        XCTAssertEqual(RuleSchemeImportService.rawFileURL(for: raw), raw)
    }

    func testHTMLPayloadIsRecognisedAsAWebPage() {
        let html = Data("<!DOCTYPE html>\n<html lang=\"en\">".utf8)
        let config = Data("[custom]\nruleset=A,[]FINAL".utf8)

        XCTAssertTrue(RuleSchemeImportService.looksLikeWebPage(html))
        XCTAssertFalse(RuleSchemeImportService.looksLikeWebPage(config))
    }

    func testDownloadedClashProviderKeepsOnlyPayloadRules() {
        let provider = """
        payload:
          - DOMAIN-SUFFIX,openai.com
          - 'DOMAIN-SUFFIX,anthropic.com'
        """

        XCTAssertEqual(
            RuleSchemeRepository.sanitizedLines(from: provider),
            ["DOMAIN-SUFFIX,openai.com", "DOMAIN-SUFFIX,anthropic.com"]
        )
    }

    // MARK: - Generation

    func testEveryTargetReproducesImportedGroups() throws {
        let scheme = try parse()

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = ConfigurationGenerator().generate(
                nodes: nodes,
                scheme: scheme,
                target: target
            ).content

            for group in scheme.groups {
                XCTAssertTrue(content.contains(group.name), "\(target.name) 缺少策略组 \(group.name)")
            }
        }
    }

    func testNodePatternSelectsOnlyMatchingNodes() throws {
        let scheme = try parse()
        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            scheme: scheme,
            target: .clash
        ).content

        let regionBlock = try XCTUnwrap(
            content.components(separatedBy: "  - name: \"🇭🇰 香港节点\"").last?
                .components(separatedBy: "  - name:").first
        )
        XCTAssertTrue(regionBlock.contains("HK 香港 01"), regionBlock)
        XCTAssertFalse(regionBlock.contains("JP Tokyo 02"), regionBlock)
    }

    func testQuanXAllNodeLatencyGroupListsOnlyProxyTags() throws {
        let scheme = try parse()
        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            scheme: scheme,
            target: .quanx
        ).content

        let line = try XCTUnwrap(
            content.components(separatedBy: .newlines).first { $0.hasPrefix("url-latency-benchmark=♻️ 自动选择") }
        )
        XCTAssertTrue(line.contains(", HK 香港 01, JP Tokyo 02,"), line)
        XCTAssertFalse(line.contains("server-tag-regex="), line)
        XCTAssertFalse(line.localizedCaseInsensitiveContains("direct"), line)
    }

    func testImportedSchemeAlsoDeclaresEveryQuanXModule() throws {
        let scheme = try parse()
        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            scheme: scheme,
            target: .quanx
        ).content

        for module in [
            "general", "dns", "policy", "server_local", "server_remote",
            "filter_local", "filter_remote", "rewrite_local", "rewrite_remote",
            "task_local", "http_backend", "mitm"
        ] {
            XCTAssertTrue(content.contains("[\(module)]"), "导入方案的 QuanX 配置缺少模块 [\(module)]")
        }
    }

    func testFinalRuleIsEmittedInEachDialect() throws {
        let scheme = try parse()
        let expected: [ClientTarget: String] = [
            .clash: "MATCH,🐟 漏网之鱼",
            .surge: "FINAL,🐟 漏网之鱼",
            .shadowrocket: "MATCH,🐟 漏网之鱼",
            .loon: "FINAL,🐟 漏网之鱼",
            .quanx: "final, 🐟 漏网之鱼"
        ]

        for (target, rule) in expected {
            let content = ConfigurationGenerator().generate(
                nodes: nodes,
                scheme: scheme,
                target: target
            ).content
            XCTAssertTrue(content.contains(rule), "\(target.name) 缺少兜底规则")
        }
    }

    func testGroupWithNoMatchingNodesFallsBackInsteadOfEmittingAnEmptyGroup() throws {
        let scheme = try parser.parse(
            text: """
            ruleset=A,[]FINAL
            custom_proxy_group=A`url-test`(完全匹配不到的名字)`http://x/y`300,,50
            """,
            id: "t",
            name: "t",
            summary: "t"
        )

        let content = ConfigurationGenerator().generate(nodes: nodes, scheme: scheme, target: .surge).content
        let line = try XCTUnwrap(
            content.components(separatedBy: .newlines).first { $0.hasPrefix("A = ") }
        )
        XCTAssertTrue(line.contains("DIRECT"), line)
    }

    private func parse() throws -> RuleScheme {
        try parser.parse(text: sample, id: "test", name: "测试方案", summary: "摘要")
    }
}
