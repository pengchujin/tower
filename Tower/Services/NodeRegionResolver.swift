import CoreLocation
import Foundation

struct NodeRegion: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let flag: String
    let latitude: Double
    let longitude: Double

    var id: String { code }
    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

struct NodeRegionCluster: Identifiable, Hashable {
    let region: NodeRegion
    let nodes: [ProxyNode]

    var id: String { region.code }
}

struct RepairedNodeName: Equatable {
    let region: NodeRegion
    let title: String
}

enum NodeRegionResolver {
    static func countryCode(for node: ProxyNode) -> String? {
        if let code = region(for: node)?.code {
            return code
        }

        let searchableText = normalizedLookupText("\(node.name) \(node.server)")
        guard !searchableText.isEmpty else { return nil }

        return isoCountryNames.first { entry in
            entry.phrases.contains { phrase in
                containsCountryPhrase(phrase, in: searchableText)
            }
        }?.code
    }

    static func region(countryCode: String) -> NodeRegion? {
        let normalizedCode = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return definitions.first(where: { $0.region.code == normalizedCode })?.region
    }

    static func region(for node: ProxyNode) -> NodeRegion? {
        let combined = "\(node.name) \(node.server)".lowercased()
        let tokens = Set(
            combined
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )

        return definitions.first { definition in
            definition.phrases.contains(where: combined.contains)
                || !tokens.isDisjoint(with: definition.tokens)
                || definition.domainSuffixes.contains(where: { node.server.lowercased().hasSuffix($0) })
        }?.region
    }

    static func displayName(for node: ProxyNode) -> String {
        guard let repaired = repairedName(for: node) else {
            return node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(repaired.region.flag) \(repaired.title)"
    }

    static func title(for node: ProxyNode) -> String {
        if let repaired = repairedName(for: node) {
            return repaired.title
        }

        var title = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = title.first, isRegionalFlag(first) {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        title = normalizedWhitespace(title)
        return title.isEmpty ? (region(for: node)?.name ?? node.endpoint) : title
    }

    static func repairedName(for node: ProxyNode) -> RepairedNodeName? {
        let name = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let region = region(for: node) else { return nil }

        var suffixStart = name.startIndex
        var placeholderCount = 0
        while suffixStart < name.endIndex,
              ["?", "？", "�"].contains(String(name[suffixStart])) {
            placeholderCount += 1
            suffixStart = name.index(after: suffixStart)
        }
        guard placeholderCount >= 2 else { return nil }

        let suffix = normalizedWhitespace(name[suffixStart...].trimmingCharacters(in: .whitespacesAndNewlines))
        return RepairedNodeName(region: region, title: suffix.isEmpty ? region.name : suffix)
    }

    static func clusters(for nodes: [ProxyNode]) -> [NodeRegionCluster] {
        clusters(for: nodes, countryCodes: [:])
    }

    static func clusters(
        for nodes: [ProxyNode],
        countryCodes: [UUID: String]
    ) -> [NodeRegionCluster] {
        let grouped = Dictionary(grouping: nodes) { node in
            resolvedRegion(for: node, countryCode: countryCodes[node.id])?.code
        }
        return definitions.compactMap { definition in
            guard let nodes = grouped[definition.region.code], !nodes.isEmpty else { return nil }
            return NodeRegionCluster(region: definition.region, nodes: nodes)
        }
    }

    static func unlocatedNodes(in nodes: [ProxyNode]) -> [ProxyNode] {
        unlocatedNodes(in: nodes, countryCodes: [:])
    }

    static func unlocatedNodes(
        in nodes: [ProxyNode],
        countryCodes: [UUID: String]
    ) -> [ProxyNode] {
        nodes.filter { resolvedRegion(for: $0, countryCode: countryCodes[$0.id]) == nil }
    }

    private static func resolvedRegion(for node: ProxyNode, countryCode: String?) -> NodeRegion? {
        if let countryCode, let ipRegion = region(countryCode: countryCode) {
            return ipRegion
        }
        return region(for: node)
    }

    private static func isRegionalFlag(_ character: Character) -> Bool {
        let regionalIndicators = character.unicodeScalars.filter {
            (0x1F1E6...0x1F1FF).contains(Int($0.value))
        }
        return regionalIndicators.count == 2
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedLookupText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func containsCountryPhrase(_ phrase: String, in searchableText: String) -> Bool {
        let containsNonASCII = phrase.unicodeScalars.contains { $0.value > 127 }
        if containsNonASCII {
            return searchableText.contains(phrase)
        }
        return " \(searchableText) ".contains(" \(phrase) ")
    }

    private struct Definition {
        let region: NodeRegion
        let phrases: [String]
        let tokens: Set<String>
        let domainSuffixes: [String]
    }

    private struct ISONameEntry {
        let code: String
        let phrases: [String]
    }

    private static let isoCountryNames: [ISONameEntry] = {
        let locales = [
            Locale(identifier: "en_US_POSIX"),
            Locale(identifier: "zh_Hans"),
            Locale(identifier: "zh_Hant")
        ]

        return Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier.uppercased()
            guard code.count == 2,
                  code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
                return nil
            }

            let phrases = Set(locales.compactMap { locale in
                locale.localizedString(forRegionCode: code).map(normalizedLookupText)
            }.filter { !$0.isEmpty })
            guard !phrases.isEmpty else { return nil }
            return ISONameEntry(code: code, phrases: phrases.sorted())
        }
    }()

    private static let definitions: [Definition] = [
        .init(
            region: .init(code: "HK", name: "香港", flag: "🇭🇰", latitude: 22.3193, longitude: 114.1694),
            phrases: ["香港", "hong kong", "hongkong", "🇭🇰"],
            tokens: ["hk", "hkg"],
            domainSuffixes: [".hk"]
        ),
        .init(
            region: .init(code: "JP", name: "日本", flag: "🇯🇵", latitude: 35.6762, longitude: 139.6503),
            phrases: ["日本", "东京", "大阪", "tokyo", "osaka", "japan", "🇯🇵"],
            tokens: ["jp", "jpn", "nrt", "hnd", "kix"],
            domainSuffixes: [".jp"]
        ),
        .init(
            region: .init(code: "SG", name: "新加坡", flag: "🇸🇬", latitude: 1.3521, longitude: 103.8198),
            phrases: ["新加坡", "狮城", "singapore", "🇸🇬"],
            tokens: ["sg", "sgp", "sin"],
            domainSuffixes: [".sg"]
        ),
        .init(
            region: .init(code: "TW", name: "台湾", flag: "🇹🇼", latitude: 25.0330, longitude: 121.5654),
            phrases: ["台湾", "台北", "taiwan", "taipei", "🇹🇼"],
            tokens: ["tw", "twn", "tpe"],
            domainSuffixes: [".tw"]
        ),
        .init(
            region: .init(code: "KR", name: "韩国", flag: "🇰🇷", latitude: 37.5665, longitude: 126.9780),
            phrases: ["韩国", "首尔", "南韩", "korea", "seoul", "🇰🇷"],
            tokens: ["kr", "kor", "sel", "icn"],
            domainSuffixes: [".kr"]
        ),
        .init(
            region: .init(code: "US", name: "美国", flag: "🇺🇸", latitude: 37.0902, longitude: -95.7129),
            phrases: ["美国", "洛杉矶", "硅谷", "西雅图", "纽约", "united states", "los angeles", "san jose", "new york", "🇺🇸"],
            tokens: ["us", "usa", "lax", "sfo", "sjc", "sea", "nyc"],
            domainSuffixes: [".us"]
        ),
        .init(
            region: .init(code: "CA", name: "加拿大", flag: "🇨🇦", latitude: 43.6532, longitude: -79.3832),
            phrases: ["加拿大", "多伦多", "温哥华", "canada", "toronto", "vancouver", "🇨🇦"],
            tokens: ["ca", "can", "yyz", "yvr"],
            domainSuffixes: [".ca"]
        ),
        .init(
            region: .init(code: "GB", name: "英国", flag: "🇬🇧", latitude: 51.5074, longitude: -0.1278),
            phrases: ["英国", "伦敦", "united kingdom", "london", "🇬🇧"],
            tokens: ["uk", "gbr", "lon", "lhr"],
            domainSuffixes: [".uk"]
        ),
        .init(
            region: .init(code: "DE", name: "德国", flag: "🇩🇪", latitude: 50.1109, longitude: 8.6821),
            phrases: ["德国", "法兰克福", "柏林", "germany", "frankfurt", "berlin", "🇩🇪"],
            tokens: ["de", "deu", "fra", "ber"],
            domainSuffixes: [".de"]
        ),
        .init(
            region: .init(code: "FR", name: "法国", flag: "🇫🇷", latitude: 48.8566, longitude: 2.3522),
            phrases: ["法国", "巴黎", "france", "paris", "🇫🇷"],
            tokens: ["fr", "frr", "par", "cdg"],
            domainSuffixes: [".fr"]
        ),
        .init(
            region: .init(code: "NL", name: "荷兰", flag: "🇳🇱", latitude: 52.3676, longitude: 4.9041),
            phrases: ["荷兰", "阿姆斯特丹", "netherlands", "amsterdam", "🇳🇱"],
            tokens: ["nl", "nld", "ams"],
            domainSuffixes: [".nl"]
        ),
        .init(
            region: .init(code: "AU", name: "澳大利亚", flag: "🇦🇺", latitude: -33.8688, longitude: 151.2093),
            phrases: ["澳大利亚", "澳洲", "悉尼", "墨尔本", "australia", "sydney", "melbourne", "🇦🇺"],
            tokens: ["au", "aus", "syd", "mel"],
            domainSuffixes: [".au"]
        ),
        .init(
            region: .init(code: "MY", name: "马来西亚", flag: "🇲🇾", latitude: 3.1390, longitude: 101.6869),
            phrases: ["马来西亚", "吉隆坡", "malaysia", "kuala lumpur", "🇲🇾"],
            tokens: ["my", "mys", "kul"],
            domainSuffixes: [".my"]
        ),
        .init(
            region: .init(code: "TH", name: "泰国", flag: "🇹🇭", latitude: 13.7563, longitude: 100.5018),
            phrases: ["泰国", "曼谷", "thailand", "bangkok", "🇹🇭"],
            tokens: ["th", "tha", "bkk"],
            domainSuffixes: [".th"]
        ),
        .init(
            region: .init(code: "VN", name: "越南", flag: "🇻🇳", latitude: 10.8231, longitude: 106.6297),
            phrases: ["越南", "胡志明", "河内", "vietnam", "ho chi minh", "hanoi", "🇻🇳"],
            tokens: ["vn", "vnm", "sgn", "han"],
            domainSuffixes: [".vn"]
        ),
        .init(
            region: .init(code: "PH", name: "菲律宾", flag: "🇵🇭", latitude: 14.5995, longitude: 120.9842),
            phrases: ["菲律宾", "马尼拉", "philippines", "manila", "🇵🇭"],
            tokens: ["ph", "phl", "mnl"],
            domainSuffixes: [".ph"]
        ),
        .init(
            region: .init(code: "IN", name: "印度", flag: "🇮🇳", latitude: 19.0760, longitude: 72.8777),
            phrases: ["印度", "孟买", "班加罗尔", "india", "mumbai", "bangalore", "🇮🇳"],
            tokens: ["in", "ind", "bom", "blr"],
            domainSuffixes: [".in"]
        ),
        .init(
            region: .init(code: "AE", name: "阿联酋", flag: "🇦🇪", latitude: 25.2048, longitude: 55.2708),
            phrases: ["阿联酋", "迪拜", "uae", "dubai", "🇦🇪"],
            tokens: ["ae", "are", "dxb"],
            domainSuffixes: [".ae"]
        ),
        .init(
            region: .init(code: "RU", name: "俄罗斯", flag: "🇷🇺", latitude: 55.7558, longitude: 37.6173),
            phrases: ["俄罗斯", "莫斯科", "russia", "moscow", "🇷🇺"],
            tokens: ["ru", "rus", "mow", "svo"],
            domainSuffixes: [".ru"]
        ),
        .init(
            region: .init(code: "BR", name: "巴西", flag: "🇧🇷", latitude: -23.5505, longitude: -46.6333),
            phrases: ["巴西", "圣保罗", "brazil", "sao paulo", "são paulo", "🇧🇷"],
            tokens: ["br", "bra", "gru"],
            domainSuffixes: [".br"]
        )
    ]
}
