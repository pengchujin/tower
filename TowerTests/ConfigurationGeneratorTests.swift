import XCTest
@testable import Tower

final class ConfigurationGeneratorTests: XCTestCase {
    private let nodes = [
        ProxyNode(
            kind: .shadowsocks,
            name: "Hong Kong",
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://test"
        ),
        ProxyNode(
            kind: .vmess,
            name: "Tokyo",
            server: "jp.example.com",
            port: 443,
            uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
            transport: "ws",
            tls: true,
            sni: "jp.example.com",
            hostHeader: "jp.example.com",
            path: "/gateway",
            rawURI: "vmess://test"
        )
    ]

    func testGeneratesEveryClientFormat() {
        let preset = RulePreset.builtIns[0]
        let generator = ConfigurationGenerator()

        for target in ClientTarget.allCases {
            let result = generator.generate(nodes: nodes, preset: preset, target: target)
            XCTAssertGreaterThan(result.content.count, 200, target.name)
            XCTAssertTrue(result.content.contains("Hong Kong"), target.name)
            XCTAssertTrue(result.content.contains("Generated locally by 塔台"), target.name)
            XCTAssertEqual(result.target, target)
            XCTAssertEqual(result.skippedNodeCount, 0, target.name)
        }
    }

    func testSurgeSkipsUnsupportedVLESSAndReportsIt() {
        let vless = ProxyNode(
            kind: .vless,
            name: "VLESS",
            server: "vless.example.com",
            port: 443,
            uuid: UUID().uuidString,
            tls: true,
            rawURI: "vless://test"
        )
        let result = ConfigurationGenerator().generate(
            nodes: nodes + [vless],
            preset: RulePreset.builtIns[0],
            target: .surge
        )

        XCTAssertEqual(result.supportedNodeCount, 2)
        XCTAssertEqual(result.skippedNodeCount, 1)
        XCTAssertFalse(result.content.contains("vless.example.com"))
    }

    func testClashOutputContainsLocalSelfConfigurationRules() {
        let result = ConfigurationGenerator().generate(
            nodes: nodes,
            preset: RulePreset.builtIns[0],
            target: .clash
        )

        XCTAssertGreaterThan(result.ruleCount, 1_000)
        XCTAssertTrue(result.content.contains("DOMAIN-SUFFIX"))
        XCTAssertTrue(result.content.contains("MATCH,国际流量"))
    }

    func testEveryClientAddsNativeImageFieldsToStrategyGroups() {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]
        let aiIcon = "https://fastly.jsdelivr.net/gh/Orz-3/mini@master/Color/OpenAI.png"

        let clash = generator.generate(nodes: nodes, preset: preset, target: .clash).content
        XCTAssertTrue(clash.contains("    icon: \"\(aiIcon)\""))

        for target in [ClientTarget.surge, .shadowrocket] {
            let content = generator.generate(nodes: nodes, preset: preset, target: target).content
            XCTAssertTrue(content.contains("icon-url=\(aiIcon)"), "\(target.name) 缺少策略组图标")
        }

        let loon = generator.generate(nodes: nodes, preset: preset, target: .loon).content
        XCTAssertTrue(loon.contains("img-url=\(aiIcon)"))

        let quanX = generator.generate(nodes: nodes, preset: preset, target: .quanx).content
        XCTAssertTrue(quanX.contains("img-url=\(aiIcon)"))
    }

    func testNestedStrategyChoicesUseEmojiAndChineseDirectLabel() {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]
        let expectations: [ClientTarget: String] = [
            .clash: "  - name: \"AI服务\"\n    type: select\n    proxies:\n      - \"🚀 节点选择\"\n      - \"♻️ 自动选择\"\n      - \"🎛️ 手动切换\"",
            .surge: "AI服务 = select, 🚀 节点选择, ♻️ 自动选择, 🎛️ 手动切换",
            .shadowrocket: "AI服务 = select, 🚀 节点选择, ♻️ 自动选择, 🎛️ 手动切换",
            .loon: "AI服务 = select,🚀 节点选择,♻️ 自动选择,🎛️ 手动切换",
            .quanx: "static=AI服务, 🚀 节点选择, ♻️ 自动选择, 🎛️ 手动切换"
        ]

        for target in ClientTarget.allCases {
            let content = generator.generate(nodes: nodes, preset: preset, target: target).content
            XCTAssertTrue(content.contains(expectations[target, default: "missing"]), "\(target.name) 嵌套策略缺少匹配 Emoji")
            XCTAssertTrue(content.contains("🎯 直接连接"), "\(target.name) 未将 DIRECT 显示为中文")
        }
    }

    func testClashKeepsEmojiAliasesHiddenWhileVisibleCardsStayPlain() throws {
        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            preset: RulePreset.builtIns[0],
            target: .clash
        ).content

        let visibleBlock = try XCTUnwrap(clashGroupBlock(named: "节点选择", in: content))
        XCTAssertFalse(visibleBlock.contains("hidden: true"))

        let nestedBlock = try XCTUnwrap(clashGroupBlock(named: "🚀 节点选择", in: content))
        XCTAssertTrue(nestedBlock.contains("hidden: true"))
    }

    func testRegionGroupsFollowServicePolicies() throws {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]
        let countryCodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.server.hasPrefix("hk") ? "HK" : "JP") })
        let expectations: [(ClientTarget, String, String)] = [
            (.clash, "  - name: \"AI服务\"", "  - name: \"🇭🇰 香港\"\n    type: select"),
            (.surge, "AI服务 = select", "🇭🇰 香港 = select"),
            (.shadowrocket, "AI服务 = select", "🇭🇰 香港 = select"),
            (.loon, "AI服务 = select", "🇭🇰 香港 = select"),
            (.quanx, "static=AI服务", "static=🇭🇰 香港")
        ]

        for (target, serviceDeclaration, regionDeclaration) in expectations {
            let content = generator.generate(
                nodes: nodes,
                preset: preset,
                target: target,
                countryCodes: countryCodes
            ).content
            let serviceRange = try XCTUnwrap(content.range(of: serviceDeclaration), "\(target.name) 缺少 AI 策略组")
            let regionRange = try XCTUnwrap(content.range(of: regionDeclaration), "\(target.name) 地区组不是自动优选")
            XCTAssertLessThan(serviceRange.lowerBound, regionRange.lowerBound, "\(target.name) 地区组应排在业务策略组之后")
        }
    }

    func testRegionGroupsDefaultToLatencySelectionAndAllowManualNodeOverride() {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]
        let countryCodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.server.hasPrefix("hk") ? "HK" : "JP") })
        let expectedDeclarations: [ClientTarget: [String]] = [
            .clash: [
                "  - name: \"🇭🇰 香港\"\n    type: select\n    proxies:\n      - \"🇭🇰 香港 · 延迟优选\"\n      - \"Hong Kong\"",
                "  - name: \"🇭🇰 香港 · 延迟优选\"\n    type: url-test"
            ],
            .surge: [
                "🇭🇰 香港 = select, 🇭🇰 香港 · 延迟优选, Hong Kong",
                "🇭🇰 香港 · 延迟优选 = url-test, Hong Kong, url="
            ],
            .shadowrocket: [
                "🇭🇰 香港 = select, 🇭🇰 香港 · 延迟优选, Hong Kong",
                "🇭🇰 香港 · 延迟优选 = url-test, Hong Kong, url="
            ],
            .loon: [
                "🇭🇰 香港 = select,🇭🇰 香港 · 延迟优选,Hong Kong",
                "🇭🇰 香港 · 延迟优选 = url-test,Hong Kong,url="
            ],
            .quanx: [
                "static=🇭🇰 香港, 🇭🇰 香港 · 延迟优选, Hong Kong",
                "url-latency-benchmark=🇭🇰 香港 · 延迟优选, server-tag-regex=^(?:Hong Kong)$, check-interval="
            ]
        ]

        for target in ClientTarget.allCases {
            let content = generator.generate(
                nodes: nodes,
                preset: preset,
                target: target,
                countryCodes: countryCodes
            ).content
            for declaration in expectedDeclarations[target, default: []] {
                XCTAssertTrue(content.contains(declaration), "\(target.name) 地区组未同时支持默认延迟优选和手动节点")
            }
        }
    }

    func testQuanXLatencyPoliciesSelectExactNodeTagsWithServerTagRegex() throws {
        let korea = ProxyNode(
            kind: .shadowsocks,
            name: "🇰🇷 South Korea (Premium)+",
            server: "kr.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://korea"
        )
        let content = ConfigurationGenerator().generate(
            nodes: [korea],
            preset: RulePreset.builtIns[0],
            target: .quanx,
            countryCodes: [korea.id: "KR"]
        ).content

        let latencyLines = content
            .split(separator: "\n")
            .filter { $0.hasPrefix("url-latency-benchmark=") }

        XCTAssertFalse(latencyLines.isEmpty)
        for line in latencyLines {
            XCTAssertTrue(line.contains(", server-tag-regex="), String(line))
            XCTAssertFalse(line.contains(", 🇰🇷 South Korea (Premium)+,"), String(line))
        }

        let koreaLine = try XCTUnwrap(
            latencyLines.first { $0.hasPrefix("url-latency-benchmark=🇰🇷 韩国 · 延迟优选,") }
        )
        XCTAssertTrue(
            koreaLine.contains("server-tag-regex=^(?:🇰🇷 South Korea \\(Premium\\)\\+)$"),
            String(koreaLine)
        )
    }

    func testRegionGroupNamesUseChineseFlagLabels() {
        let expectedNames = [
            "🇭🇰 香港", "🇯🇵 日本", "🇺🇸 美国", "🇸🇬 新加坡", "🇹🇼 台湾",
            "🇰🇷 韩国", "🇬🇧 英国", "🇩🇪 德国", "🇫🇷 法国", "🌍 其他地区"
        ]
        let countryCodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.server.hasPrefix("hk") ? "HK" : "JP") })
        let extraCodes = ["US", "SG", "TW", "KR", "GB", "DE", "FR", "BR"]
        let extraNodes = extraCodes.enumerated().map { index, code in
            ProxyNode(
                kind: .shadowsocks,
                name: "Region \(index)",
                server: "region-\(index).example.com",
                port: 8388,
                cipher: "chacha20-ietf-poly1305",
                password: "secret",
                rawURI: "ss://region-\(code)"
            )
        }
        let allCountryCodes = countryCodes.merging(
            Dictionary(uniqueKeysWithValues: zip(extraNodes, extraCodes).map { node, code in (node.id, code) }),
            uniquingKeysWith: { current, _ in current }
        )

        for target in ClientTarget.allCases {
            let content = ConfigurationGenerator().generate(
                nodes: nodes + extraNodes,
                preset: RulePreset.builtIns[0],
                target: target,
                countryCodes: allCountryCodes
            ).content
            for name in expectedNames {
                XCTAssertTrue(content.contains(name), "\(target.name) 缺少中文国旗地区组：\(name)")
            }
        }
    }

    func testEmojiRegionGroupsDoNotAlsoAttachRemoteFlagIcons() throws {
        let preset = RulePreset.builtIns[0]
        let countryCodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.server.hasPrefix("hk") ? "HK" : "JP") })
        let generator = ConfigurationGenerator()
        let clash = generator.generate(
            nodes: nodes,
            preset: preset,
            target: .clash,
            countryCodes: countryCodes
        ).content
        let clashMarker = "  - name: \"🇭🇰 香港\"\n"
        let clashStart = try XCTUnwrap(clash.range(of: clashMarker)?.lowerBound)
        let clashTail = clash[clashStart...]
        let nextGroup = try XCTUnwrap(clashTail.dropFirst(clashMarker.count).range(of: "\n  - name:")?.lowerBound)
        let clashBlock = clashTail[..<nextGroup]
        XCTAssertFalse(clashBlock.contains("\n    icon:"), "Clash 地区组不应同时显示远程国旗和 Emoji 国旗")

        for target in [ClientTarget.surge, .shadowrocket, .loon, .quanx] {
            let content = generator.generate(
                nodes: nodes,
                preset: preset,
                target: target,
                countryCodes: countryCodes
            ).content
            let marker = target == .quanx ? "static=🇭🇰 香港," : "🇭🇰 香港 ="
            let line = try XCTUnwrap(content.split(separator: "\n").first { $0.contains(marker) })
            XCTAssertFalse(line.contains("icon-url="), "\(target.name) 地区组重复挂载远程国旗")
            XCTAssertFalse(line.contains("img-url="), "\(target.name) 地区组重复挂载远程国旗")
        }
    }

    func testSelfConfigurationUsesSafeDefaultPolicyOrder() {
        let content = ConfigurationGenerator().generate(
            nodes: nodes,
            preset: RulePreset.builtIns[0],
            target: .clash
        ).content

        XCTAssertTrue(
            content.contains(
                "  - name: \"国外广告\"\n    type: select\n    proxies:\n      - \"REJECT\"\n      - \"🎯 直接连接\""
            )
        )
        XCTAssertTrue(
            content.contains(
                "  - name: \"国内流量\"\n    type: select\n    proxies:\n      - \"🎯 直接连接\""
            )
        )
    }

    func testEveryClientIncludesIPResolvedRegionStrategyGroups() {
        let germany = ProxyNode(
            kind: .shadowsocks,
            name: "Mystery One",
            server: "de.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://germany"
        )
        let brazil = ProxyNode(
            kind: .shadowsocks,
            name: "Mystery Two",
            server: "br.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://brazil"
        )
        let countryCodes = [germany.id: "DE", brazil.id: "BR"]
        let expectedGroups = [
            "🇭🇰 香港",
            "🇯🇵 日本",
            "🇩🇪 德国",
            "🌍 其他地区"
        ]

        for target in ClientTarget.allCases {
            let content = ConfigurationGenerator().generate(
                nodes: nodes + [germany, brazil],
                preset: RulePreset.builtIns[0],
                target: target,
                countryCodes: countryCodes
            ).content

            for group in expectedGroups {
                XCTAssertGreaterThanOrEqual(
                    content.components(separatedBy: group).count - 1,
                    2,
                    "\(target.name) 缺少可选择的地区策略组：\(group)"
                )
            }
        }
    }

    func testRegionGroupNamesCannotCollideWithNodeNames() {
        let regionNames = [
            ("🇫🇷 法国", "FR"),
            ("🇬🇧 英国", "GB"),
            ("🇩🇪 德国", "DE")
        ]
        let collidingNodes = regionNames.map { name, _ in
            ProxyNode(
                kind: .shadowsocks,
                name: name,
                server: "node.example.com",
                port: 8388,
                cipher: "chacha20-ietf-poly1305",
                password: "secret",
                rawURI: "ss://collision"
            )
        }
        let countryCodes = Dictionary(
            uniqueKeysWithValues: zip(collidingNodes, regionNames).map { node, region in
                (node.id, region.1)
            }
        )

        for target in ClientTarget.allCases {
            let content = ConfigurationGenerator().generate(
                nodes: collidingNodes,
                preset: RulePreset.builtIns[0],
                target: target,
                countryCodes: countryCodes
            ).content

            for (groupName, _) in regionNames {
                XCTAssertTrue(content.contains(groupName), "\(target.name) 缺少地区策略组")
                XCTAssertTrue(
                    content.contains("\(groupName) · 节点"),
                    "\(target.name) 未隔离同名节点与策略组：\(groupName)"
                )
            }
        }
    }

    func testSelfConfigurationResourcesSurviveBundleFlattening() {
        let assignments = RulePreset.builtIns[0].assignments
        let aiSuite = assignments.first { $0.resourcePath == "AI Suite" }!
        let domesticIPs = assignments.first { $0.resourcePath == "Domestic IPs" }!

        XCTAssertGreaterThan(RuleRepository().count(for: aiSuite), 50)
        XCTAssertGreaterThan(RuleRepository().count(for: domesticIPs), 1_000)
    }

    func testSectionHeadersEndBeforeFirstNode() {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]

        XCTAssertTrue(generator.generate(nodes: nodes, preset: preset, target: .clash).content.contains("proxies:\n  - name"))
        XCTAssertTrue(generator.generate(nodes: nodes, preset: preset, target: .surge).content.contains("[Proxy]\nHong Kong"))
        XCTAssertTrue(generator.generate(nodes: nodes, preset: preset, target: .loon).content.contains("[Proxy]\nHong Kong"))
        XCTAssertTrue(generator.generate(nodes: nodes, preset: preset, target: .quanx).content.contains("[server_local]\nshadowsocks="))
    }

    func testRestoredRegionFlagIsUsedByEveryExportFormat() {
        let damagedNode = ProxyNode(
            kind: .shadowsocks,
            name: "?? 香港 02",
            server: "hk.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "secret",
            rawURI: "ss://test"
        )
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]

        for target in ClientTarget.allCases {
            let content = generator.generate(nodes: [damagedNode], preset: preset, target: target).content
            XCTAssertTrue(content.contains("🇭🇰 香港 02"), target.name)
            XCTAssertFalse(content.contains("?? 香港 02"), target.name)
        }
    }

    func testLoonUsesDocumentedEqualsSyntaxForModernProtocols() {
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]
        let vmess = nodes[1]
        let vless = ProxyNode(
            kind: .vless,
            name: "Singapore VLESS",
            server: "sg.example.com",
            port: 443,
            uuid: "11111111-2222-3333-4444-555555555555",
            transport: "ws",
            tls: true,
            sni: "sg.example.com",
            hostHeader: "cdn.example.com",
            path: "/vless",
            skipCertificateVerification: true,
            rawURI: "vless://test"
        )

        let content = generator.generate(nodes: [vmess, vless], preset: preset, target: .loon).content

        XCTAssertTrue(content.contains("transport=ws"))
        XCTAssertTrue(content.contains("alterId=0"))
        XCTAssertTrue(content.contains("path=/gateway"))
        XCTAssertTrue(content.contains("host=jp.example.com"))
        XCTAssertTrue(content.contains("over-tls=true"))
        XCTAssertTrue(content.contains("tls-name=sg.example.com"))
        XCTAssertTrue(content.contains("skip-cert-verify=true"))
        XCTAssertFalse(content.contains("transport:"))
        XCTAssertFalse(content.contains("over-tls:"))
        XCTAssertFalse(content.contains("ws-path:"))
    }

    func testSurgeDoesNotEmitTLSFlagForIntrinsicallyTLSProtocols() {
        let preset = RulePreset.builtIns[0]
        let trojan = ProxyNode(
            kind: .trojan,
            name: "Trojan",
            server: "trojan.example.com",
            port: 443,
            password: "secret",
            transport: "ws",
            tls: true,
            sni: "trojan.example.com",
            path: "/gateway",
            rawURI: "trojan://test"
        )

        let content = ConfigurationGenerator().generate(nodes: [trojan], preset: preset, target: .surge).content

        XCTAssertTrue(content.contains("Trojan = trojan, trojan.example.com, 443, password=secret"))
        XCTAssertTrue(content.contains("ws=true"))
        XCTAssertTrue(content.contains("sni=trojan.example.com"))
        XCTAssertFalse(content.contains("tls=true"))
    }

    private func clashGroupBlock(named name: String, in content: String) -> Substring? {
        let marker = "  - name: \"\(name)\""
        guard let start = content.range(of: marker) else { return nil }
        let remainder = content[start.lowerBound...]
        guard let next = remainder.dropFirst(marker.count).range(of: "\n  - name: \"") else {
            return remainder
        }
        return content[start.lowerBound..<next.lowerBound]
    }
}
