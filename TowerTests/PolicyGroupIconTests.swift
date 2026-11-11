import UIKit
import XCTest
@testable import Tower

/// One recogniser decides each policy group's emoji; exports turn that emoji
/// into the client's icon and drop it from names the client draws icons for.
final class PolicyGroupIconTests: XCTestCase {
    private let repository = RuleSchemeRepository()
    private let node = ProxyNode(kind: .shadowsocks, name: "HK 01", server: "hk.example.com", port: 443,
                                 cipher: "aes-128-gcm", password: "p", rawURI: "ss://x")

    private func fullScheme() throws -> RuleScheme {
        try XCTUnwrap(repository.bundledSchemes().first { $0.id == "acl4ssr-full" })
    }

    private func generate(_ scheme: RuleScheme, _ target: ClientTarget) -> String {
        ConfigurationGenerator().generate(nodes: [node], scheme: scheme, target: target, schemes: repository).content
    }

    // MARK: Recognition

    func testWordsSplitAtCamelCaseAndNeverMatchInsideAWord() {
        XCTAssertEqual(PolicyGroupEmoji.tokens("IPTVMainland"), ["iptv", "mainland"])
        XCTAssertEqual(PolicyGroupEmoji.tokens("AkamaiCloud"), ["akamai", "cloud"])
        XCTAssertEqual(PolicyGroupEmoji.tokens("Amazon Prime_Video"), ["amazon", "prime", "video"])
        // The old substring match gave these 🍎 and 🏠.
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "AkamaiCloud", regions: false))
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "HuaweiCloud", regions: false))
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "IPTVMainland", regions: false))
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "BlockChain", regions: false))
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "iCloud"), "🍎")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "GitHub"), "🐙")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "TikTok"), "🎵")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "OneDrive"), "Ⓜ️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "AmazonPrimeVideo"), "🎬")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Amazon"), "🛒")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Google FCM"), "📢")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Google"), "🔍")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "YouTube Music"), "📹")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "AI 平台"), "🤖")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "国内媒体"), "🌏")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "全球直连"), "🎯")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Hong Kong"), "🇭🇰")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "日本节点"), "🇯🇵")
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "我的分组"))
        // issue #47: these fell back to 🧩.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "影视节点"), "🎬")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "印亚马逊"), "🛒")
        // A service still wins over its category.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "油管视频"), "📹")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "奈飞视频"), "🎥")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "亚马逊视频"), "🎬")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Gmail"), "🔍")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "学术网站"), "🎓")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Bank"), "🏦")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "动漫"), "📺")
        XCTAssertEqual(PolicyGroupEmoji.resolved(for: "我的分组", kind: .urlTest), "⚡️")
        XCTAssertEqual(PolicyGroupEmoji.resolved(for: "🦄 我的分组", kind: .select), "🦄")
    }

    func testRegionsComeBeforeRolesAndRolesBeforeTheFallback() {
        // Spellings from public configs that used to fall back.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "故障转移"), "🔁")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "负载均衡"), "⚖️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "延迟最低"), "♻️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "其他地区"), "🗺️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "全部节点"), "🌐")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "家宽节点"), "🏡")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Emby"), "🍿")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "X"), "🐦")
        XCTAssertNil(PolicyGroupEmoji.recognized(for: "Xbox Cloud", regions: false).flatMap { $0 == "🐦" ? $0 : nil })
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Select"), "🎛️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Proxy Select"), "🚀")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "国内"), "🎯")
        // A region in the name beats what the group does.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "香港故转"), "🇭🇰")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "日本-自动"), "🇯🇵")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "加坡节点"), "🇸🇬")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "欧洲节点"), "🇪🇺")
        // A service beats a region.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "日本 Netflix"), "🎥")
        XCTAssertEqual(PolicyGroupEmoji.fallback(for: .select), "🌐")
        // Broad words never steal a more specific reading.
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "全球代理"), "🚀")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "自动测速"), "♻️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Others"), "🐟")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "微软云盘"), "Ⓜ️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "AI1"), "🤖")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Office365"), "Ⓜ️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "香港-Others"), "🇭🇰")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "香港测速"), "🇭🇰")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "网络测速"), "📶")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Google Cloud"), "☁️")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: "Google云盘"), "🔍")
    }

    func testRuleListsAndMembersSpeakForAVagueName() {
        func scheme(_ groups: [RuleSchemeGroup], _ rulesets: [RuleSchemeRuleset]) -> RuleScheme {
            RuleScheme(id: "t", name: "t", summary: "", sourceURLString: nil, groups: groups, rulesets: rulesets, isBundled: false)
        }
        func group(_ name: String, _ members: [RuleSchemeGroupMember]) -> RuleSchemeGroup {
            RuleSchemeGroup(name: name, kind: .select, members: members, testURLString: nil, interval: nil, tolerance: nil)
        }
        func list(_ group: String, _ file: String) -> RuleSchemeRuleset {
            RuleSchemeRuleset(groupName: group, resource: .remote(URL(string: "https://example.com/rules/\(file)")!))
        }
        let vague = group("我的分组", [.reference("节点选择")])
        let netflix = scheme([vague], [list("我的分组", "Netflix.list")])
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: vague, in: netflix), "🎥")
        let media = scheme([vague], [list("我的分组", "Netflix.list"), list("我的分组", "YouTube.yaml"), list("我的分组", "DisneyPlus.list")])
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: vague, in: media), "🎬", "several streaming services")
        let china = scheme([vague], [list("我的分组", "ChinaDomain.list"), RuleSchemeRuleset(groupName: "我的分组", resource: .inline("GEOIP,CN"))])
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: vague, in: china), "🎯")
        // The name still comes first.
        let named = group("油管", [.reference("节点选择")])
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: named, in: scheme([named], [list("油管", "Netflix.list")])), "📹")

        let empty = scheme([], [])
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: group("组 A", [.reference("DIRECT")]), in: empty), "🎯")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: group("组 B", [.reference("REJECT"), .reference("REJECT-DROP")]), in: empty), "🛑")
        XCTAssertEqual(PolicyGroupEmoji.recognized(for: group("组 C", [.nodePattern("(?i)港|HK|Hong Kong")]), in: empty), "🇭🇰")
        XCTAssertNil(PolicyGroupEmoji.recognized(for: group("组 D", [.nodePattern(".*")]), in: empty))
        XCTAssertNil(PolicyGroupEmoji.recognized(for: group("组 E", [.reference("DIRECT"), .reference("节点选择")]), in: empty))
        XCTAssertEqual(PolicyGroupEmoji.resolved(for: group("组 E", [.reference("节点选择")]), in: empty), "🌐")
    }

    func testEveryRecognisedEmojiAndFallbackHasAnImage() {
        let catalog = PolicyGroupIconCatalog.bundled
        let emoji = (PolicyGroupEmoji.table + PolicyGroupEmoji.roles + PolicyGroupEmoji.ruleLists).map(\.emoji)
            + [RuleSchemeGroup.Kind.select, .urlTest, .fallback, .loadBalance].map(PolicyGroupEmoji.fallback)
        for value in emoji {
            XCTAssertNotNil(catalog.url(forEmoji: value), value)
            XCTAssertNotNil(catalog.circleURL(forEmoji: value), value)
        }
        let rocket = catalog.url(forEmoji: "🚀")?.absoluteString ?? ""
        XCTAssertTrue(rocket.hasPrefix("https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@"), rocket)
        XCTAssertTrue(rocket.hasSuffix("/assets/Rocket/3D/rocket_3d.png"), rocket)
        XCTAssertTrue(catalog.url(forEmoji: "♻️")?.absoluteString.contains("Recycling%20symbol") == true)
        XCTAssertEqual(PolicyGroupIconCatalog.countryCode(ofFlag: "🇭🇰"), "HK")
        XCTAssertNil(PolicyGroupIconCatalog.countryCode(ofFlag: "🚀"))
    }

    func testCatalogItemsUseTheirNamesNotTheirURLs() {
        let items = RuleCatalog.builtIn.entries
        XCTAssertFalse(items.isEmpty)
        for name in ["AkamaiCloud", "HuaweiCloud", "IPTVMainland"] {
            if let item = items.first(where: { $0.name == name }) {
                XCTAssertNotEqual(item.emoji, "🍎", name)
                XCTAssertNotEqual(item.emoji, "🏠", name)
            }
        }
        XCTAssertTrue(items.allSatisfy { !$0.emoji.isEmpty })
    }

    // MARK: Auto-fill

    func testAutofillRenamesEveryReferenceAndLeavesUnknownNamesAlone() throws {
        var scheme = try fullScheme()
        scheme.groups = scheme.groups.map { group in
            RuleSchemeGroup(name: Self.plain(group.name), kind: group.kind,
                            members: group.members.map {
                                guard case .reference(let name) = $0 else { return $0 }
                                return .reference(Self.plain(name))
                            },
                            testURLString: group.testURLString, interval: group.interval, tolerance: group.tolerance,
                            algorithm: group.algorithm, sourceType: group.sourceType, sourceFormat: group.sourceFormat,
                            parameters: group.parameters)
        } + [RuleSchemeGroup(name: "我的分组", kind: .select, members: [.reference("节点选择")])]
        scheme.rulesets = scheme.rulesets.map {
            var ruleset = RuleSchemeRuleset(groupName: Self.plain($0.groupName), resource: $0.resource,
                                            options: $0.options, provider: $0.provider)
            ruleset.origin = .added("x")
            return ruleset
        }
        let filled = scheme.withGroupEmojis(true, autofill: true)
        let names = Set(filled.groups.map(\.name))
        XCTAssertTrue(names.contains("🚀 节点选择"))
        XCTAssertTrue(names.contains("🇭🇰 香港节点"))
        XCTAssertTrue(names.contains("我的分组"), "nothing recognises it, so its name stays")
        XCTAssertTrue(filled.rulesets.allSatisfy { names.contains($0.groupName) || RoutingBuiltinPolicies.names.contains($0.groupName) })
        XCTAssertTrue(filled.rulesets.allSatisfy { $0.origin == .added("x") }, "renaming keeps each rule's origin")
        let references = filled.groups.flatMap(\.members).compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }
        XCTAssertTrue(references.allSatisfy { names.contains($0) || ["DIRECT", "REJECT"].contains($0) }, "\(references)")
        XCTAssertEqual(scheme.withGroupEmojis(true, autofill: false).groups.map(\.name), scheme.groups.map(\.name))
    }

    private static func plain(_ name: String) -> String {
        PolicyGroupEmoji.leading(in: name).map { name.dropFirst($0.count).trimmingCharacters(in: .whitespaces) } ?? name
    }

    // MARK: Export

    func testClientsThatDrawIconsGetThemAndPlainNames() throws {
        let scheme = try fullScheme()
        let surge = generate(scheme, .surge)
        XCTAssertTrue(surge.range(of: #"\n节点选择 = select, .*icon-url=https://cdn\.jsdelivr\.net/gh/microsoft/fluentui-emoji@[0-9a-f]{40}/assets/Rocket/3D/rocket_3d\.png\n"#,
                                  options: .regularExpression) != nil, surge)
        XCTAssertFalse(surge.contains("🚀 节点选择"))
        XCTAssertTrue(surge.contains(",节点选择"), "rules follow the new name")

        let stash = generate(scheme, .clash)
        XCTAssertTrue(stash.contains("  - name: \"节点选择\""), stash)
        XCTAssertTrue(stash.contains("    icon: \"https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@"), stash)
        // Quantumult X drew no 256px Fluent image on a device: it gets Tower's
        // 144px circles from raw.githubusercontent.com (no `@`).
        let quanX = generate(scheme, .quanx)
        XCTAssertTrue(quanX.contains("static=节点选择, "), quanX)
        XCTAssertTrue(quanX.range(of: #", img-url=https://raw\.githubusercontent\.com/pengchujin/tower/[0-9a-f]{40}/Rulesets/PolicyGroupIcons/FluentCircle/1f680\.png\n"#,
                                  options: .regularExpression) != nil, quanX)
        XCTAssertFalse(quanX.contains("img-url=https://cdn.jsdelivr.net"), quanX)
        XCTAssertFalse(quanX.contains(".system"), quanX)
        XCTAssertTrue(quanX.contains("🇭🇰 香港节点"), quanX)
        XCTAssertTrue(generate(scheme, .loon).contains("img-url=https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@"))
        XCTAssertTrue(generate(scheme, .egern).contains("      icon: \"https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@"))

        // Region groups keep their flag in every client and get a round one,
        // except in Surge, which draws the name's flag in the icon slot.
        let surgeHongKong = try XCTUnwrap(surge.components(separatedBy: "\n").first { $0.hasPrefix("🇭🇰 香港节点 = ") })
        XCTAssertFalse(surgeHongKong.contains("icon-url"), surgeHongKong)
        XCTAssertTrue(stash.range(of: #"  - name: "🇭🇰 香港节点"\n(    .*\n)*?    icon: "https://cdn\.jsdelivr\.net/gh/pengchujin/tower@[0-9a-f]{40}/Rulesets/PolicyGroupIcons/[0-9a-f]{40}/hk\.png"\n"#,
                                  options: .regularExpression) != nil, stash)

        // mihomo cores other than Clash Verge may ignore the field: keep the emoji.
        let mihomo = generate(scheme, .clashMi)
        XCTAssertTrue(mihomo.contains("  - name: \"🚀 节点选择\""))
        XCTAssertTrue(mihomo.contains("    icon: \"https://"))
        XCTAssertTrue(generate(scheme, .clashVerge).contains("  - name: \"节点选择\""))
        // The Clash app draws `icon` since iOS 1.0.7 / macOS 1.0.10.
        let clashApp = generate(scheme, .clashApple)
        XCTAssertTrue(clashApp.contains("  - name: \"节点选择\""), clashApp)
        XCTAssertFalse(clashApp.contains("🚀 节点选择"), clashApp)
        XCTAssertTrue(clashApp.contains("    icon: \"https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@"), clashApp)
        XCTAssertTrue(clashApp.contains("  - name: \"🇭🇰 香港节点\""), clashApp)

        // No icon field anywhere else: names keep their emoji.
        for target in [ClientTarget.shadowrocket, .singBox, .hiddify, .karing] {
            let content = generate(scheme, target)
            XCTAssertFalse(content.contains("fluentui-emoji"), target.rawValue)
            XCTAssertTrue(content.contains("🚀 节点选择"), target.rawValue)
        }
    }

    func testEverySymbolExistsAndEveryEmojiTowerGivesHasOne() {
        let emoji = (PolicyGroupEmoji.table + PolicyGroupEmoji.roles + PolicyGroupEmoji.ruleLists).map(\.emoji)
            + [RuleSchemeGroup.Kind.urlTest, .fallback, .loadBalance, .select].map(PolicyGroupEmoji.fallback(for:))
        for value in emoji {
            XCTAssertNotNil(PolicyGroupIconSupport.systemSymbol(forEmoji: value), value)
        }
        for (value, symbol) in PolicyGroupIconSupport.symbols {
            XCTAssertNotNil(UIImage(systemName: symbol), "\(value) → \(symbol)")
        }
    }

    func testQuantumultXUsesPublishedCirclesAndSymbolsUntilThen() throws {
        let scheme = try fullScheme()
        let catalog = PolicyGroupIconCatalog(
            fluentBase: URL(string: "https://cdn.example/fluent/"), fluentPaths: [:], flagBase: nil, flagCodes: [],
            circleBase: URL(string: "https://raw.example/tower/abc/Rulesets/PolicyGroupIcons/FluentCircle/"),
            circleKeys: ["🚀", "♻"]
        )
        let icons = scheme.withPolicyGroupIcons(for: .quanx, catalog: catalog)
        let icon = { (name: String) in icons.groups.first { $0.name == name }?.parameters?[PolicyGroupIconSupport.parameterKey] }
        XCTAssertEqual(icon("节点选择"), "https://raw.example/tower/abc/Rulesets/PolicyGroupIcons/FluentCircle/1f680.png")
        XCTAssertEqual(icon("自动选择"), "https://raw.example/tower/abc/Rulesets/PolicyGroupIcons/FluentCircle/267b.png",
                       "the variation selector is not part of the file name")
        XCTAssertEqual(icon("全球直连"), "arrow.right.circle.fill.system", "not drawn yet: a symbol")

        // The bundled set covers every emoji that has a symbol, once published.
        let bundled = PolicyGroupIconCatalog.bundled
        XCTAssertEqual(bundled.circleKeys, Set(bundled.fluentPaths.keys)
                        .union(bundled.flagCodes.map { NodeRegionResolver.flagEmoji(for: $0) }), "every emoji and flag")
        XCTAssertNotNil(bundled.circleURL(forEmoji: "🚫"), "an imported scheme's emoji")
    }

    func testAGroupWithoutAnImageKeepsItsEmoji() throws {
        let scheme = try fullScheme()
        let catalog = PolicyGroupIconCatalog(fluentBase: URL(string: "https://cdn.example/fluent/"),
                                             fluentPaths: ["🚀": "assets/Rocket/3D/rocket_3d.png"],
                                             flagBase: nil, flagCodes: [])
        let icons = scheme.withPolicyGroupIcons(for: .surge, catalog: catalog)
        let rocket = try XCTUnwrap(icons.groups.first { $0.name == "节点选择" })
        XCTAssertEqual(rocket.parameters?[PolicyGroupIconSupport.parameterKey], "https://cdn.example/fluent/assets/Rocket/3D/rocket_3d.png")
        XCTAssertTrue(icons.groups.contains { $0.name == "🇭🇰 香港节点" }, "flags stay in the name")

        // Region groups get a round flag and keep the flag in the name too:
        // member lists show names only.
        let withFlags = PolicyGroupIconCatalog(fluentBase: nil, fluentPaths: [:],
                                               flagBase: URL(string: "https://cdn.example/flags/"), flagCodes: ["HK", "US"])
        let flagged = scheme.withPolicyGroupIcons(for: .clash, catalog: withFlags)
        let hongKong = try XCTUnwrap(flagged.groups.first { $0.name == "🇭🇰 香港节点" })
        XCTAssertEqual(hongKong.parameters?[PolicyGroupIconSupport.parameterKey], "https://cdn.example/flags/hk.png")
        // ACL4SSR's US group is 🇺🇲, which has no flag image of its own.
        XCTAssertEqual(withFlags.url(forEmoji: "🇺🇲")?.absoluteString, "https://cdn.example/flags/us.png")
        XCTAssertEqual(PolicyGroupIconCatalog.bundled.circleURL(forEmoji: "🇺🇲")?.lastPathComponent, "1f1fa-1f1f8.png")
        let quanXFlags = PolicyGroupIconCatalog(fluentBase: nil, fluentPaths: [:], flagBase: nil, flagCodes: [],
                                                circleBase: URL(string: "https://raw.example/circles/"), circleKeys: ["🇭🇰"])
        let quanX = scheme.withPolicyGroupIcons(for: .quanx, catalog: quanXFlags)
        let quanXHongKong = try XCTUnwrap(quanX.groups.first { $0.name == "🇭🇰 香港节点" })
        XCTAssertEqual(quanXHongKong.parameters?[PolicyGroupIconSupport.parameterKey], "https://raw.example/circles/1f1ed-1f1f0.png")
    }
}

/// A group's name as exported to `target`: clients that draw the group's icon
/// get the name without its leading emoji (see `withPolicyGroupIcons`).
func exportedGroupName(_ name: String, for target: ClientTarget) -> String {
    guard PolicyGroupIconSupport.drawsIcons.contains(target), let emoji = PolicyGroupEmoji.leading(in: name),
          PolicyGroupIconCatalog.countryCode(ofFlag: emoji) == nil else { return name }
    let stripped = name.trimmingCharacters(in: .whitespaces).dropFirst(emoji.count).trimmingCharacters(in: .whitespaces)
    return stripped.isEmpty ? name : stripped
}
