import Foundation

enum RuleCatalogProvider: String, Codable, CaseIterable, Hashable {
    case acl4ssr
    case blackmatrix7

    var displayName: String {
        switch self {
        case .acl4ssr: "ACL4SSR"
        case .blackmatrix7: "blackmatrix7"
        }
    }
}

enum RuleCatalogCategory: String, Codable, CaseIterable, Hashable {
    case ai
    case streaming
    case social
    case gaming
    case advertising
    case domestic
    case infrastructure
    case other

    var displayName: String {
        switch self {
        case .ai: "AI"
        case .streaming: String(localized: "流媒体")
        case .social: String(localized: "社交")
        case .gaming: String(localized: "游戏")
        case .advertising: String(localized: "广告拦截")
        case .domestic: String(localized: "国内直连")
        case .infrastructure: String(localized: "基础服务")
        case .other: String(localized: "其他")
        }
    }
}

enum RuleCatalogDefaultRoute: String, Codable, Hashable {
    case proxy
    case direct
    case reject
}

struct RuleCatalogEntry: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var aliases: [String]
    var category: RuleCatalogCategory
    var provider: RuleCatalogProvider
    var sourceURLString: String
    var ruleCount: Int?
    var defaultRoute: RuleCatalogDefaultRoute
    var suggestedPolicyName: String?

    init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: RuleCatalogCategory,
        provider: RuleCatalogProvider,
        sourceURLString: String,
        ruleCount: Int? = nil,
        defaultRoute: RuleCatalogDefaultRoute,
        suggestedPolicyName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.provider = provider
        self.sourceURLString = sourceURLString
        self.ruleCount = ruleCount
        self.defaultRoute = defaultRoute
        self.suggestedPolicyName = suggestedPolicyName
    }

    /// A semantic, deterministic emoji for every catalog item. Curated names
    /// get their familiar service symbol; the category fallback guarantees the
    /// complete upstream catalog is still visually scannable.
    var emoji: String {
        if let first = name.first,
           first.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            return String(first)
        }

        let key = ([name] + aliases + [sourceURLString])
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let mappings: [(needles: [String], emoji: String)] = [
            (["openai", "chatgpt"], "🤖"),
            (["gemini", "bard"], "🔷"),
            (["youtube", "油管"], "📹"),
            (["netflix", "奈飞", "奈飞"], "🎞️"),
            (["disney"], "🧸"),
            (["primevideo", "amazonprime", "amazon video"], "🎥"),
            (["hbo", "max.list"], "🎦"),
            (["telegram"], "✈️"),
            (["twitter", "x.com"], "🕊️"),
            (["facebook", "instagram", "meta"], "♾️"),
            (["tiktok"], "🎵"),
            (["spotify"], "🟢"),
            (["apple", "icloud", "testflight"], "🍎"),
            (["microsoft", "onedrive", "office365"], "🪟"),
            (["google", "firebase", "youtube"], "🔎"),
            (["steam", "epic", "playstation", "xbox", "game"], "🎮"),
            (["advert", "adblock", "reject", "广告"], "🛑"),
            (["lan", "private", "local", "局域网"], "🏠"),
        ]
        if let match = mappings.first(where: { mapping in
            mapping.needles.contains(where: key.contains)
        }) {
            return match.emoji
        }

        switch category {
        case .ai: return "✨"
        case .streaming: return "🎬"
        case .social: return "💬"
        case .gaming: return "🎮"
        case .advertising: return "🛑"
        case .domestic: return "🎯"
        case .infrastructure: return "🌐"
        case .other: return "🧩"
        }
    }

    var displayName: String {
        guard name.first?.unicodeScalars.contains(where: { $0.properties.isEmoji }) != true else {
            return name
        }
        return "\(emoji) \(name)"
    }

    func matches(_ query: String) -> Bool {
        let needle = Self.searchKey(query)
        guard !needle.isEmpty else { return true }
        let values = [name, category.displayName, provider.displayName] + aliases
        return values.contains { Self.searchKey($0).contains(needle) }
    }

    func makeCustomization(for scheme: RuleScheme) throws -> CustomRuleFlow {
        guard let url = URL(string: sourceURLString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw RuleCatalogError.invalidSourceURL
        }

        // A catalog item is a distinct service ruleset. Its upstream policy
        // hint describes the broad group it used to share, but must not erase
        // the item's own identity (for example OpenAI -> AI 服务). Keeping
        // the catalog name here also makes the checkmark and Custom Rules row
        // describe the same thing.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desiredName = trimmedName.isEmpty ? name : trimmedName
        let policyName: String
        var generatedPolicyGroup: RuleSchemeGroup?
        if let existing = scheme.groups.first(where: {
            Self.policyKey($0.name) == Self.policyKey(desiredName)
        }) {
            policyName = existing.name
        } else {
            let decoratedName = Self.decoratedPolicyName(desiredName, emoji: emoji)
            policyName = decoratedName
            let members: [RuleSchemeGroupMember]
            switch defaultRoute {
            case .direct:
                members = [.reference("DIRECT")]
            case .reject:
                members = [.reference("REJECT")]
            case .proxy:
                let fallback = scheme.groups.first(where: {
                    let key = Self.policyKey($0.name)
                    return key.contains("节点选择") || key == "proxy" || key == "select proxy"
                })?.name
                if let fallback {
                    members = [.reference(fallback), .reference("DIRECT")]
                } else {
                    members = [.nodePattern(".*"), .reference("DIRECT")]
                }
            }
            generatedPolicyGroup = RuleSchemeGroup(
                name: decoratedName,
                kind: .select,
                members: members
            )
        }

        return CustomRuleFlow(
            schemeID: scheme.id,
            name: name,
            policyName: policyName,
            rulesText: "",
            catalogID: id,
            sourceURLString: sourceURLString,
            generatedPolicyGroup: generatedPolicyGroup
        )
    }

    /// Repairs the short-lived catalog format that routed a concrete service
    /// through its broad suggested group. That format sometimes overwrote both
    /// the ruleset name and policy name (OpenAI became `AI 服务`). The catalog
    /// identity and source URL keep this migration narrow, while unrelated or
    /// user-renamed policies remain untouched.
    func migratedLegacyCustomization(
        _ flow: CustomRuleFlow,
        for scheme: RuleScheme
    ) -> CustomRuleFlow? {
        guard flow.catalogID == id,
              let suggested = suggestedPolicyName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggested.isEmpty,
              Self.policyKey(suggested) != Self.policyKey(name),
              [Self.policyKey(name), Self.policyKey(suggested)].contains(Self.policyKey(flow.name)),
              Self.policyKey(flow.policyName) == Self.policyKey(suggested),
              flow.sourceURLString == nil || flow.sourceURLString == sourceURLString,
              var migrated = try? makeCustomization(for: scheme) else {
            return nil
        }

        migrated.id = flow.id
        migrated.rulesText = flow.rulesText
        migrated.isEnabled = flow.isEnabled
        if let legacyGroup = flow.generatedPolicyGroup {
            guard Self.policyKey(legacyGroup.name) == Self.policyKey(suggested) else {
                return nil
            }
            migrated.generatedPolicyGroup = RuleSchemeGroup(
                name: migrated.policyName,
                kind: legacyGroup.kind,
                members: legacyGroup.members,
                testURLString: legacyGroup.testURLString,
                interval: legacyGroup.interval,
                tolerance: legacyGroup.tolerance
            )
        }
        return migrated
    }

    private static func searchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func policyKey(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first,
              first.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return searchKey(result)
    }

    private static func decoratedPolicyName(_ value: String, emoji: String) -> String {
        guard value.first?.unicodeScalars.contains(where: { $0.properties.isEmoji }) != true else {
            return value
        }
        return "\(emoji) \(value)"
    }
}

struct RuleCatalog: Codable, Hashable {
    var entries: [RuleCatalogEntry]

    func search(_ query: String) -> [RuleCatalogEntry] {
        entries.filter { $0.matches(query) }
    }

    /// The complete `.list` indexes from both maintained upstream catalogs.
    /// Tower bundles metadata only. A rule payload is downloaded and cached
    /// after the user selects it, so the app neither enables nor ships all
    /// third-party rules by default.
    static let builtIn = RuleCatalog(entries: makeBuiltInEntries())

    private static let aclRevision = "06ff293e02565adceef9aa92321efa2603f68f32"

    private static func makeBuiltInEntries() -> [RuleCatalogEntry] {
        let curated = acl4ssrEntries + blackmatrix7Entries
        let curatedKeys = Set(curated.map(sourceKey))
        let generated = generatedEntries(
            paths: bundledPaths(resource: "ACL4SSR.list-index"),
            provider: .acl4ssr
        ) + generatedEntries(
            paths: bundledPaths(resource: "blackmatrix7.list-index"),
            provider: .blackmatrix7
        )

        return curated + generated.filter { !curatedKeys.contains(sourceKey($0)) }
    }

    private static func bundledPaths(resource: String) -> [String] {
        let bundles = [Bundle.main, Bundle(for: RuleCatalogResourceLocator.self)]
        let url = bundles.lazy.compactMap { bundle in
            bundle.url(forResource: resource, withExtension: "txt", subdirectory: "RuleCatalog")
                ?? bundle.url(forResource: resource, withExtension: "txt")
        }.first

        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func generatedEntries(
        paths: [String],
        provider: RuleCatalogProvider
    ) -> [RuleCatalogEntry] {
        let baseNames = paths.map { baseName(for: $0) }
        let duplicateCounts = Dictionary(grouping: baseNames, by: { $0 }).mapValues(\.count)

        return paths.map { path in
            let base = baseName(for: path)
            let name = displayName(
                for: path,
                provider: provider,
                includeParent: duplicateCounts[base, default: 0] > 1
            )
            let route = inferredRoute(for: path)
            return RuleCatalogEntry(
                id: generatedID(provider: provider, path: path),
                name: name,
                aliases: searchAliases(for: path, provider: provider),
                category: inferredCategory(for: path),
                provider: provider,
                sourceURLString: sourceURLString(provider: provider, path: path),
                defaultRoute: route,
                suggestedPolicyName: route == .proxy ? name : nil
            )
        }
    }

    private static func sourceURLString(provider: RuleCatalogProvider, path: String) -> String {
        let escapedPath = path.split(separator: "/").map { component in
            String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? String(component)
        }.joined(separator: "/")
        switch provider {
        case .acl4ssr:
            return "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/\(escapedPath)"
        case .blackmatrix7:
            return "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/\(escapedPath)"
        }
    }

    private static func generatedID(provider: RuleCatalogProvider, path: String) -> String {
        let encoded = Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(provider.rawValue)-path-\(encoded)"
    }

    private static func sourceKey(_ entry: RuleCatalogEntry) -> String {
        guard let url = URL(string: entry.sourceURLString) else {
            return "\(entry.provider.rawValue):\(entry.sourceURLString)"
        }
        let decodedPath = url.path.removingPercentEncoding ?? url.path
        let components = decodedPath.split(separator: "/").map(String.init)
        let marker = entry.provider == .acl4ssr ? "Clash" : "rule"
        guard let index = components.firstIndex(of: marker) else {
            return "\(entry.provider.rawValue):\(url.path)"
        }
        return "\(entry.provider.rawValue):\(components[index...].joined(separator: "/"))"
    }

    private static func baseName(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func catalogComponents(
        for path: String,
        provider: RuleCatalogProvider
    ) -> [String] {
        var components = path.split(separator: "/").map(String.init)
        if provider == .acl4ssr, components.first == "Clash" {
            components.removeFirst()
        } else if provider == .blackmatrix7,
                  components.starts(with: ["rule", "Clash"]) {
            components.removeFirst(2)
        }
        if let last = components.indices.last {
            components[last] = URL(fileURLWithPath: components[last])
                .deletingPathExtension().lastPathComponent
        }
        return components
    }

    private static func displayName(
        for path: String,
        provider: RuleCatalogProvider,
        includeParent: Bool
    ) -> String {
        let components = catalogComponents(for: path, provider: provider)
        guard includeParent, components.count > 1 else {
            return components.last ?? baseName(for: path)
        }
        return components.suffix(2).joined(separator: " / ")
    }

    private static func searchAliases(
        for path: String,
        provider: RuleCatalogProvider
    ) -> [String] {
        Array(Set(catalogComponents(for: path, provider: provider)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func inferredRoute(for path: String) -> RuleCatalogDefaultRoute {
        let key = path.lowercased()
        if key.contains("advertising") || key.contains("adblock")
            || key.contains("zhihuads") || key.contains("privacy") {
            return .reject
        }
        if key.contains("/direct/") || key.contains("china")
            || key.contains("localareanetwork") || key.contains("/lan/") {
            return .direct
        }
        return .proxy
    }

    private static func inferredCategory(for path: String) -> RuleCatalogCategory {
        let key = path.lowercased()
        if ["openai", "anthropic", "claude", "gemini", "bardai", "copilot", "perplexity"]
            .contains(where: key.contains) {
            return .ai
        }
        if ["netflix", "youtube", "disney", "spotify", "twitch", "hbo", "media", "tv"]
            .contains(where: key.contains) {
            return .streaming
        }
        if ["telegram", "twitter", "facebook", "instagram", "reddit", "whatsapp", "discord"]
            .contains(where: key.contains) {
            return .social
        }
        if ["steam", "playstation", "nintendo", "xbox", "game", "epic"]
            .contains(where: key.contains) {
            return .gaming
        }
        if ["advertising", "adblock", "ads", "privacy"].contains(where: key.contains) {
            return .advertising
        }
        if ["china", "localareanetwork", "/lan/", "/direct/"].contains(where: key.contains) {
            return .domestic
        }
        return .other
    }

    private static func acl(
        _ id: String,
        _ name: String,
        path: String,
        aliases: [String] = [],
        category: RuleCatalogCategory,
        route: RuleCatalogDefaultRoute,
        policy: String? = nil,
        count: Int? = nil
    ) -> RuleCatalogEntry {
        RuleCatalogEntry(
            id: "acl4ssr-\(id)",
            name: name,
            aliases: aliases,
            category: category,
            provider: .acl4ssr,
            sourceURLString: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/\(aclRevision)/Clash/\(path)",
            ruleCount: count,
            defaultRoute: route,
            suggestedPolicyName: policy
        )
    }

    private static func blackmatrix(
        _ id: String,
        _ name: String,
        folder: String,
        aliases: [String] = [],
        category: RuleCatalogCategory,
        route: RuleCatalogDefaultRoute,
        policy: String? = nil
    ) -> RuleCatalogEntry {
        RuleCatalogEntry(
            id: "blackmatrix7-\(id)",
            name: name,
            aliases: aliases,
            category: category,
            provider: .blackmatrix7,
            sourceURLString: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/\(folder)/\(folder).list",
            defaultRoute: route,
            suggestedPolicyName: policy
        )
    }

    private static let acl4ssrEntries: [RuleCatalogEntry] = [
        acl("openai", "OpenAI", path: "Ruleset/OpenAi.list", aliases: ["ChatGPT", "GPT", "人工智能"], category: .ai, route: .proxy, policy: "AI 服务", count: 17),
        acl("ai", "AI 服务", path: "Ruleset/AI.list", aliases: ["Claude", "Gemini", "Copilot", "人工智能"], category: .ai, route: .proxy, policy: "AI 服务", count: 49),
        acl("netflix", "Netflix", path: "Ruleset/Netflix.list", aliases: ["奈飞", "网飞"], category: .streaming, route: .proxy, policy: "奈飞视频", count: 40),
        acl("youtube", "YouTube", path: "Ruleset/YouTube.list", aliases: ["油管", "YouTube Music"], category: .streaming, route: .proxy, policy: "YouTube", count: 14),
        acl("bahamut", "Bahamut", path: "Ruleset/Bahamut.list", aliases: ["巴哈姆特", "动画疯"], category: .streaming, route: .proxy, policy: "巴哈姆特", count: 5),
        acl("bilibili-hmt", "Bilibili 港澳台", path: "Ruleset/BilibiliHMT.list", aliases: ["哔哩哔哩", "B站", "港澳台"], category: .streaming, route: .proxy, policy: "哔哩哔哩", count: 21),
        acl("proxy-media", "国外媒体", path: "ProxyMedia.list", aliases: ["国际流媒体", "Global Media"], category: .streaming, route: .proxy, policy: "国外媒体", count: 372),
        acl("telegram", "Telegram", path: "Telegram.list", aliases: ["电报", "TG"], category: .social, route: .proxy, policy: "Telegram", count: 13),
        acl("apple", "Apple", path: "Apple.list", aliases: ["苹果服务", "iCloud", "App Store"], category: .infrastructure, route: .proxy, policy: "苹果服务", count: 29),
        acl("microsoft", "Microsoft", path: "Microsoft.list", aliases: ["微软", "Windows", "Office"], category: .infrastructure, route: .proxy, policy: "微软服务", count: 79),
        acl("onedrive", "OneDrive", path: "OneDrive.list", aliases: ["微软云盘"], category: .infrastructure, route: .proxy, policy: "微软云盘", count: 17),
        acl("google-fcm", "Google FCM", path: "Ruleset/GoogleFCM.list", aliases: ["谷歌推送", "Firebase"], category: .infrastructure, route: .proxy, policy: "谷歌服务", count: 44),
        acl("epic", "Epic Games", path: "Ruleset/Epic.list", aliases: ["Epic 商店"], category: .gaming, route: .proxy, policy: "游戏平台", count: 6),
        acl("steam", "Steam", path: "Ruleset/Steam.list", aliases: ["蒸汽平台"], category: .gaming, route: .proxy, policy: "游戏平台", count: 18),
        acl("nintendo", "Nintendo", path: "Ruleset/Nintendo.list", aliases: ["任天堂", "Switch"], category: .gaming, route: .proxy, policy: "游戏平台", count: 15),
        acl("sony", "Sony", path: "Ruleset/Sony.list", aliases: ["索尼", "PlayStation", "PSN"], category: .gaming, route: .proxy, policy: "游戏平台", count: 5),
        acl("ban-ad", "广告拦截", path: "BanAD.list", aliases: ["广告", "AdBlock", "Advertising"], category: .advertising, route: .reject, count: 588),
        acl("ban-program-ad", "应用净化", path: "BanProgramAD.list", aliases: ["应用广告", "去广告"], category: .advertising, route: .reject, count: 1_016),
        acl("local-area-network", "局域网", path: "LocalAreaNetwork.list", aliases: ["LAN", "本地网络"], category: .domestic, route: .direct, count: 37),
        acl("china-domain", "中国域名", path: "ChinaDomain.list", aliases: ["国内直连", "China Domain"], category: .domestic, route: .direct, count: 635),
        acl("china-company-ip", "中国企业 IP", path: "ChinaCompanyIp.list", aliases: ["国内 IP", "阿里云", "腾讯云"], category: .domestic, route: .direct, count: 208),
        acl("china-media", "国内媒体", path: "ChinaMedia.list", aliases: ["中国流媒体"], category: .domestic, route: .direct, count: 38),
        acl("download", "下载服务", path: "Download.list", aliases: ["BT", "PT", "下载直连"], category: .domestic, route: .direct, count: 22),
        acl("proxy-lite", "精简代理", path: "ProxyLite.list", aliases: ["常用代理", "GFW Lite"], category: .other, route: .proxy, policy: "节点选择", count: 430),
        acl("proxy-gfwlist", "GFWList", path: "ProxyGFWlist.list", aliases: ["国外流量", "代理列表"], category: .other, route: .proxy, policy: "节点选择", count: 6_986),
    ]

    private static let blackmatrix7Entries: [RuleCatalogEntry] = [
        blackmatrix("openai", "OpenAI", folder: "OpenAI", aliases: ["ChatGPT", "GPT", "人工智能"], category: .ai, route: .proxy, policy: "AI 服务"),
        blackmatrix("copilot", "Microsoft Copilot", folder: "Copilot", aliases: ["Bing AI", "微软 AI"], category: .ai, route: .proxy, policy: "AI 服务"),
        blackmatrix("gemini", "Google Gemini", folder: "Gemini", aliases: ["Bard", "谷歌 AI"], category: .ai, route: .proxy, policy: "AI 服务"),
        blackmatrix("netflix", "Netflix", folder: "Netflix", aliases: ["奈飞", "网飞"], category: .streaming, route: .proxy, policy: "奈飞视频"),
        blackmatrix("youtube", "YouTube", folder: "YouTube", aliases: ["油管", "YouTube Video"], category: .streaming, route: .proxy, policy: "YouTube"),
        blackmatrix("disney", "Disney+", folder: "Disney", aliases: ["迪士尼", "Disney Plus"], category: .streaming, route: .proxy, policy: "Disney+"),
        blackmatrix("spotify", "Spotify", folder: "Spotify", aliases: ["声田", "音乐"], category: .streaming, route: .proxy, policy: "Spotify"),
        blackmatrix("telegram", "Telegram", folder: "Telegram", aliases: ["电报", "TG"], category: .social, route: .proxy, policy: "Telegram"),
        blackmatrix("twitter", "X / Twitter", folder: "Twitter", aliases: ["推特", "X"], category: .social, route: .proxy, policy: "社交媒体"),
        blackmatrix("instagram", "Instagram", folder: "Instagram", aliases: ["照片墙", "IG"], category: .social, route: .proxy, policy: "社交媒体"),
        blackmatrix("facebook", "Facebook", folder: "Facebook", aliases: ["脸书", "Meta"], category: .social, route: .proxy, policy: "社交媒体"),
        blackmatrix("github", "GitHub", folder: "GitHub", aliases: ["代码托管", "Git"], category: .infrastructure, route: .proxy, policy: "开发服务"),
        blackmatrix("apple", "Apple", folder: "Apple", aliases: ["苹果服务", "iCloud", "App Store"], category: .infrastructure, route: .proxy, policy: "苹果服务"),
        blackmatrix("google", "Google", folder: "Google", aliases: ["谷歌", "Google Search"], category: .infrastructure, route: .proxy, policy: "谷歌服务"),
        blackmatrix("microsoft", "Microsoft", folder: "Microsoft", aliases: ["微软", "Windows", "Office"], category: .infrastructure, route: .proxy, policy: "微软服务"),
        blackmatrix("steam", "Steam", folder: "Steam", aliases: ["游戏平台", "蒸汽平台"], category: .gaming, route: .proxy, policy: "游戏平台"),
        blackmatrix("playstation", "PlayStation", folder: "PlayStation", aliases: ["PSN", "索尼"], category: .gaming, route: .proxy, policy: "游戏平台"),
        blackmatrix("nintendo", "Nintendo", folder: "Nintendo", aliases: ["任天堂", "Switch"], category: .gaming, route: .proxy, policy: "游戏平台"),
        blackmatrix("advertising", "Advertising", folder: "Advertising", aliases: ["广告拦截", "去广告"], category: .advertising, route: .reject),
        blackmatrix("advertising-lite", "Advertising Lite", folder: "AdvertisingLite", aliases: ["轻量广告拦截"], category: .advertising, route: .reject),
        blackmatrix("china-max", "China Max", folder: "ChinaMax", aliases: ["国内直连", "中国网站", "China IP"], category: .domestic, route: .direct),
        blackmatrix("lan", "LAN", folder: "Lan", aliases: ["局域网", "本地网络"], category: .domestic, route: .direct),
    ]
}

enum RuleCatalogError: LocalizedError {
    case invalidSourceURL

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            String(localized: "规则地址无效")
        }
    }
}

private final class RuleCatalogResourceLocator: NSObject {}
