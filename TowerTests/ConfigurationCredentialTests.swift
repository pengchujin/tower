import XCTest
@testable import Tower

/// Regression cover for the protocol branches that the 2026-08-04 review found
/// emitting lines the target clients cannot parse.
final class ConfigurationCredentialTests: XCTestCase {
    private let preset = RulePreset.builtIns[0]

    // MARK: - Positional credentials

    func testLoonSocks5WithoutCredentialsHasNoTrailingEmptyFields() {
        let node = ProxyNode(
            kind: .socks5,
            name: "Open SOCKS",
            server: "socks.example.com",
            port: 1080,
            rawURI: "socks5://socks.example.com:1080"
        )

        let line = proxyLine(for: node, target: .loon, containing: "socks.example.com")

        XCTAssertFalse(line.contains(",,"), "Loon 收到空的用户名/密码字段：\(line)")
        XCTAssertTrue(line.hasSuffix("udp=true"), line)
    }

    func testSurgeKeepsUsernameSlotWhenOnlyPasswordIsKnown() {
        let node = ProxyNode(
            kind: .socks5,
            name: "Password Only",
            server: "socks.example.com",
            port: 1080,
            password: "s3cret",
            rawURI: "socks5://socks.example.com:1080"
        )

        let line = proxyLine(for: node, target: .surge, containing: "socks.example.com")
        let fields = line.components(separatedBy: " = ")[1].components(separatedBy: ", ")

        // socks5, host, port, username, password — the password must not slide
        // into the username slot when no username is configured.
        XCTAssertEqual(fields[0], "socks5", line)
        XCTAssertEqual(fields[3], "", line)
        XCTAssertEqual(fields[4], "s3cret", line)
    }

    func testLoonSocks5KeepsBothFieldsWhenAuthenticated() {
        let node = ProxyNode(
            kind: .socks5,
            name: "Auth SOCKS",
            server: "socks.example.com",
            port: 1080,
            password: "pw",
            username: "user",
            rawURI: "socks5://socks.example.com:1080"
        )

        let line = proxyLine(for: node, target: .loon, containing: "socks.example.com")

        XCTAssertTrue(line.contains("\"user\",\"pw\""), line)
    }

    // MARK: - Quantumult X fidelity

    // Hysteria 2 used to be in this list. Quantumult X has no `hysteria2=`
    // server type, so those nodes are skipped there now and the certificate
    // question never comes up; every client that does support it is covered by
    // QuanXHysteria2Tests instead.
    func testQuanXKeepsSkipCertificateVerificationForTrojan() {
        for kind in [ProxyKind.trojan] {
            let node = ProxyNode(
                kind: kind,
                name: "Self Signed",
                server: "edge.example.com",
                port: 443,
                password: "pw",
                tls: true,
                sni: "edge.example.com",
                skipCertificateVerification: true,
                rawURI: "trojan://test"
            )

            let line = proxyLine(for: node, target: .quanx, containing: "edge.example.com")

            XCTAssertTrue(line.contains("tls-verification=false"), "\(kind.title)：\(line)")
        }
    }

    func testQuanXUsesNodeCipherForVMessInsteadOfAHardcodedOne() {
        let node = ProxyNode(
            kind: .vmess,
            name: "AES VMess",
            server: "vmess.example.com",
            port: 443,
            cipher: "aes-128-gcm",
            uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            rawURI: "vmess://test"
        )

        let line = proxyLine(for: node, target: .quanx, containing: "vmess.example.com")

        XCTAssertTrue(line.contains("method=aes-128-gcm"), line)
    }

    func testQuanXFallsBackToAnAcceptedCipherWhenNodeSaysAuto() {
        let node = ProxyNode(
            kind: .vmess,
            name: "Auto VMess",
            server: "vmess.example.com",
            port: 443,
            cipher: "auto",
            uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            rawURI: "vmess://test"
        )

        let line = proxyLine(for: node, target: .quanx, containing: "vmess.example.com")

        XCTAssertFalse(line.contains("method=auto"), line)
        XCTAssertTrue(line.contains("method=chacha20-ietf-poly1305"), line)
    }

    func testQuanXKeepsShadowsocksRObfuscationParameters() {
        let node = ProxyNode(
            kind: .shadowsocksR,
            name: "SSR",
            server: "ssr.example.com",
            port: 8388,
            cipher: "aes-256-cfb",
            password: "pw",
            protocolName: "auth_aes128_md5",
            protocolParam: "1234:abcd",
            obfs: "tls1.2_ticket_auth",
            obfsParam: "cloud.example.com",
            rawURI: "ssr://test"
        )

        let line = proxyLine(for: node, target: .quanx, containing: "ssr.example.com")

        XCTAssertTrue(line.contains("ssr-protocol-param=1234:abcd"), line)
        XCTAssertTrue(line.contains("obfs-host=cloud.example.com"), line)
    }

    func testQuanXBracketsIPv6HostBeforeAppendingPort() {
        let node = ProxyNode(
            kind: .trojan,
            name: "IPv6 Trojan",
            server: "2001:db8::1",
            port: 443,
            password: "pw",
            tls: true,
            rawURI: "trojan://test"
        )

        let line = proxyLine(for: node, target: .quanx, containing: "2001:db8::1")

        XCTAssertTrue(line.contains("trojan=[2001:db8::1]:443"), line)
        XCTAssertFalse(line.contains("trojan=2001:db8::1:443"), line)
    }

    // MARK: - Untrusted node names

    /// A hostile remark must not add a line to any format. Clash quotes the name
    /// so `#` and `=` are inert there; the INI-style formats have no quoting, so
    /// they additionally must not contain the injected comment or assignment.
    func testNodeNameCannotBreakOutOfTheProxyLine() {
        let hostileName = "HK 01\nREJECT = reject # owned"

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let hostile = generate(name: hostileName, target: target)
            let benign = generate(name: "HK 01", target: target)

            XCTAssertEqual(
                hostile.components(separatedBy: .newlines).count,
                benign.components(separatedBy: .newlines).count,
                "\(target.name) 节点名换行后多出了配置行"
            )

            // A serialised format cannot be injected by construction: the
            // escaping is the encoder's job, so the check is that no extra
            // outbound appeared rather than that the text is absent.
            guard !target.usesSingBoxFormat else {
                let object = try? JSONSerialization.jsonObject(with: Data(hostile.utf8))
                let outbounds = (object as? [String: Any])?["outbounds"] as? [[String: Any]] ?? []
                XCTAssertFalse(
                    outbounds.contains { ($0["tag"] as? String) == "REJECT = reject # owned" },
                    "\(target.name) 节点名注入出了新出站"
                )
                continue
            }
            // Both YAML formats quote the name, so the injected text survives
            // inside the scalar and only the line count proves it stayed put.
            guard target != .clash,
                  target != .clashApple,
                  target != .shadowrocket,
                  target != .egern else {
                XCTAssertTrue(
                    hostile.contains(#""HK 01 REJECT = reject # owned""#),
                    "\(target.name) 应把节点名保留为单行带引号标量"
                )
                continue
            }

            XCTAssertFalse(hostile.contains("REJECT = reject"), "\(target.name) 允许节点名注入赋值")
            XCTAssertFalse(hostile.contains("# owned"), "\(target.name) 允许节点名注入注释")
        }
    }

    private func generate(name: String, target: ClientTarget) -> String {
        let node = ProxyNode(
            kind: .shadowsocks,
            name: name,
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "pw",
            rawURI: "ss://test"
        )
        return ConfigurationGenerator().generate(nodes: [node], preset: preset, target: target).content
    }

    // MARK: - Quantumult X module list

    func testQuanXConfigurationDeclaresEveryRequiredModule() {
        let node = ProxyNode(
            kind: .shadowsocks,
            name: "HK 01",
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "pw",
            rawURI: "ss://test"
        )
        let content = ConfigurationGenerator().generate(
            nodes: [node],
            preset: preset,
            target: .quanx
        ).content

        // Quantumult X refuses a complete configuration that omits any module,
        // reporting 配置文件缺少模块 [server_remote].
        for module in [
            "general", "dns", "policy", "server_local", "server_remote",
            "filter_local", "filter_remote", "rewrite_local", "rewrite_remote",
            "task_local", "http_backend", "mitm"
        ] {
            XCTAssertTrue(content.contains("[\(module)]"), "QuanX 配置缺少模块 [\(module)]")
        }
    }

    // MARK: - Rule types

    func testGeoSiteRulesAreKeptOnlyForClashTargets() {
        let scheme = RuleScheme(
            id: "geosite-target-matrix",
            name: "GEOSITE",
            summary: "Target rule compatibility",
            groups: [
                RuleSchemeGroup(
                    name: "Proxy",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(groupName: "DIRECT", resource: .inline("GEOSITE,CN")),
                RuleSchemeRuleset(groupName: "Proxy", resource: .inline("FINAL"))
            ]
        )

        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = ConfigurationGenerator().generate(
                nodes: [],
                scheme: scheme,
                target: target
            ).content

            XCTAssertEqual(
                content.contains("GEOSITE,CN,DIRECT"),
                [.clash, .clashApple].contains(target),
                "\(target.name) 的 GEOSITE 支持矩阵不正确：\(content)"
            )
        }
    }

    func testProcessNameRulesSurviveForSurgeFamilyButNotQuanX() {
        let scheme = RuleScheme(
            id: "process-name-test",
            name: "Process rule",
            summary: "Rule dialect regression",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "节点选择",
                    resource: .inline("PROCESS-NAME,example")
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL"))
            ]
        )
        let generator = ConfigurationGenerator()
        let surge = generator.generate(nodes: [], scheme: scheme, target: .surge).content
        let quanX = generator.generate(nodes: [], scheme: scheme, target: .quanx).content

        XCTAssertTrue(surge.contains("PROCESS-NAME"), "Surge 丢掉了 PROCESS-NAME 规则")
        XCTAssertFalse(quanX.contains("PROCESS-NAME"), "Quantumult X 不支持 PROCESS-NAME")
    }

    func testURLRegexRulesAreDroppedForClashButPreservedForSurge() {
        let scheme = RuleScheme(
            id: "url-regex-test",
            name: "URL regex rule",
            summary: "Clash portability regression",
            groups: [
                RuleSchemeGroup(
                    name: "节点选择",
                    kind: .select,
                    members: [.reference("DIRECT")]
                )
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "节点选择",
                    resource: .inline(#"URL-REGEX,^https?:\/\/www\.amazon\.com\/(Amazon-Video|gp\/video)\/"#)
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL"))
            ]
        )
        let generator = ConfigurationGenerator()

        let clash = generator.generate(nodes: [], scheme: scheme, target: .clash).content
        let surge = generator.generate(nodes: [], scheme: scheme, target: .surge).content

        XCTAssertFalse(clash.contains("URL-REGEX"), "Clash Mi 不支持 URL-REGEX，写出后整份配置无法启动")
        XCTAssertTrue(surge.contains("URL-REGEX"), "Surge 支持 URL-REGEX，不应为了 Clash 兼容而全局删除")
    }

    // MARK: - Helpers

    private func proxyLine(
        for node: ProxyNode,
        target: ClientTarget,
        containing needle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let content = ConfigurationGenerator().generate(
            nodes: [node],
            preset: preset,
            target: target
        ).content

        guard let match = content
            .components(separatedBy: .newlines)
            .first(where: { $0.contains(needle) })
        else {
            XCTFail("\(target.name) 配置里找不到 \(needle)", file: file, line: line)
            return ""
        }
        return match
    }
}

/// Square brackets open a section in every INI-style config, so a node named
/// like an airport's "[BETA-1] …" silently ended the `[Proxy]` section and
/// orphaned every proxy below it.
extension ConfigurationCredentialTests {
    func testBracketedNodeNameCannotStartANewSection() {
        let nodes = [
            ProxyNode(kind: .shadowsocks, name: "HK 01", server: "a.example.com",
                      port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x"),
            ProxyNode(kind: .shadowsocks, name: "[BETA-1] 🇭🇰 HongKong [0.1x]", server: "b.example.com",
                      port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x"),
            ProxyNode(kind: .shadowsocks, name: "HK 03", server: "c.example.com",
                      port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x")
        ]

        for target in [ClientTarget.surge, .shadowrocket, .loon, .quanx] {
            let content = ConfigurationGenerator()
                .generate(nodes: nodes, preset: RulePreset.builtIns[0], target: target).content
            let lines = content.split(separator: "\n").map(String.init)

            // No proxy line may begin a section.
            for line in lines where line.contains("example.com") {
                XCTAssertFalse(line.hasPrefix("["), "\(target.name) 节点行开了新段：\(line.prefix(40))")
            }
            // And all three must still be in the file.
            for host in ["a.example.com", "b.example.com", "c.example.com"] {
                XCTAssertTrue(content.contains(host), "\(target.name) 丢了 \(host)")
            }
        }
    }

    func testBracketsSurviveAsReadableTextInTheName() {
        let node = ProxyNode(kind: .shadowsocks, name: "[BETA] HK", server: "a.example.com",
                             port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x")
        let content = ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: .shadowrocket).content

        XCTAssertTrue(content.contains("name: \"[BETA] HK\""), content)
    }
}

/// Quantumult X imported Tower's rules but none of its policy groups. Its own
/// converters all emit `[policy]` before the server and filter sections;
/// Tower emitted four hundred nodes between `[dns]` and `[policy]`.
extension ConfigurationCredentialTests {
    func testQuanXDeclaresPoliciesBeforeServersAndFilters() {
        let nodes = (0..<3).map { index in
            ProxyNode(kind: .shadowsocks, name: "HK 0\(index)", server: "h\(index).example.com",
                      port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x")
        }
        let content = ConfigurationGenerator()
            .generate(nodes: nodes, preset: RulePreset.builtIns[0], target: .quanx).content

        let order = content.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("[") && $0.hasSuffix("]") }

        guard let policy = order.firstIndex(of: "[policy]"),
              let serverLocal = order.firstIndex(of: "[server_local]"),
              let filterLocal = order.firstIndex(of: "[filter_local]") else {
            return XCTFail("段落不全：\(order)")
        }

        XCTAssertLessThan(policy, serverLocal, "[policy] 必须在 [server_local] 之前：\(order)")
        XCTAssertLessThan(policy, filterLocal, "[policy] 必须在 [filter_local] 之前：\(order)")
        // Exactly one of each — an earlier attempt emitted server_local twice.
        XCTAssertEqual(order.filter { $0 == "[server_local]" }.count, 1, "\(order)")
    }

    func testQuanXStillDeclaresEverySection() {
        let node = ProxyNode(kind: .shadowsocks, name: "HK", server: "h.example.com",
                             port: 8388, cipher: "aes-256-gcm", password: "pw", rawURI: "ss://x")
        let content = ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: .quanx).content

        for section in ["[general]", "[dns]", "[policy]", "[server_remote]", "[filter_remote]",
                        "[rewrite_remote]", "[server_local]", "[filter_local]", "[rewrite_local]",
                        "[task_local]", "[http_backend]", "[mitm]"] {
            XCTAssertTrue(content.contains(section), "缺少 \(section)")
        }
        // And the nodes still land in server_local, not somewhere else.
        XCTAssertTrue(content.contains("shadowsocks=h.example.com"), content)
    }
}
