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
        region(for: node)?.code
    }

    static func region(countryCode: String) -> NodeRegion? {
        var normalizedCode = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        // "UK" is what everyone writes; "GB" is what ISO says.
        if normalizedCode == "UK" { normalizedCode = "GB" }

        if let curated = definitions.first(where: { $0.region.code == normalizedCode })?.region {
            return curated
        }
        guard let entry = countryTable[normalizedCode] else { return nil }
        return NodeRegion(
            code: normalizedCode,
            name: entry.chineseName,
            flag: flagEmoji(for: normalizedCode),
            latitude: entry.latitude,
            longitude: entry.longitude
        )
    }

    /// The regional-indicator pair an airport prefixed the name with, if any.
    ///
    /// This beats every other signal: the airport stated the country outright,
    /// in a form that cannot be confused with a word in the name.
    static func flaggedCountryCode(in name: String) -> String? {
        let indicators = name.unicodeScalars.filter { (0x1F1E6...0x1F1FF).contains(Int($0.value)) }
        guard indicators.count >= 2 else { return nil }
        let letters = indicators.prefix(2).map { scalar in
            Character(UnicodeScalar(scalar.value - 0x1F1E6 + 65)!)
        }
        return String(letters)
    }

    static func flagEmoji(for countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.compactMap { scalar in
            UnicodeScalar(127_397 + scalar.value).map(String.init)
        }.joined()
    }

    /// Two-letter codes that are also ordinary words. Matching them case
    /// insensitively turned "My Node" into Malaysia, "Rio de Janeiro" into
    /// Germany and "Contact us" into the United States. A wrong region is worse
    /// than none — it also files the node under the wrong region policy group —
    /// so these are only accepted when the name spells them in capitals, the way
    /// a country code is actually written.
    private static let caseSensitiveTokens: Set<String> = [
        "us", "in", "my", "de", "ca", "au", "th", "br", "fr", "ph", "ae", "it", "no"
    ]

    /// Codes that mean something else in a node name.
    ///
    /// SS is Shadowsocks far more often than South Sudan, and WS is WebSocket
    /// rather than Samoa. Every airport writes these in capitals, so the
    /// capitals rule alone does not separate them.
    private static let reservedTokens: Set<String> = [
        "SS", "SSR", "WS", "TLS", "TCP", "UDP", "QUIC", "KCP", "GRPC",
        "IPLC", "IEPL", "BGP", "CDN", "NAT", "VPN", "API", "DNS", "MUX",
        // Byte units. "129.29 GB" is a quota, not Great Britain — the United
        // Kingdom still answers to UK, GBR and its spelled-out names.
        "KB", "MB", "GB", "TB"
    ]

    /// Cities airports name nodes after instead of the country.
    ///
    /// Without these a node called "Johannesburg | 01" or "伊斯坦布尔" matches
    /// nothing at all, which is what the flag column showed.
    private static let cities: [String: String] = [
        "johannesburg": "ZA", "约翰内斯堡": "ZA", "cape town": "ZA", "开普敦": "ZA",
        "istanbul": "TR", "伊斯坦布尔": "TR", "伊斯坦堡": "TR", "ankara": "TR",
        "warsaw": "PL", "华沙": "PL", "prague": "CZ", "布拉格": "CZ",
        "vienna": "AT", "维也纳": "AT", "zurich": "CH", "苏黎世": "CH",
        "geneva": "CH", "日内瓦": "CH", "brussels": "BE", "布鲁塞尔": "BE",
        "madrid": "ES", "马德里": "ES", "barcelona": "ES", "巴塞罗那": "ES",
        "milan": "IT", "米兰": "IT", "rome": "IT", "罗马": "IT",
        "lisbon": "PT", "里斯本": "PT", "athens": "GR", "雅典": "GR",
        "stockholm": "SE", "斯德哥尔摩": "SE", "oslo": "NO", "奥斯陆": "NO",
        "helsinki": "FI", "赫尔辛基": "FI", "copenhagen": "DK", "哥本哈根": "DK",
        "dublin": "IE", "都柏林": "IE", "reykjavik": "IS", "雷克雅未克": "IS",
        "bucharest": "RO", "布加勒斯特": "RO", "sofia": "BG", "索菲亚": "BG",
        "budapest": "HU", "布达佩斯": "HU", "kyiv": "UA", "kiev": "UA", "基辅": "UA",
        "buenos aires": "AR", "布宜诺斯艾利斯": "AR", "santiago": "CL", "圣地亚哥": "CL",
        "lima": "PE", "利马": "PE", "bogota": "CO", "波哥大": "CO",
        "mexico city": "MX", "墨西哥城": "MX", "cairo": "EG", "开罗": "EG",
        "lagos": "NG", "拉各斯": "NG", "nairobi": "KE", "内罗毕": "KE",
        "casablanca": "MA", "卡萨布兰卡": "MA", "tel aviv": "IL", "特拉维夫": "IL",
        "riyadh": "SA", "利雅得": "SA", "doha": "QA", "多哈": "QA",
        "karachi": "PK", "卡拉奇": "PK", "dhaka": "BD", "达卡": "BD",
        "colombo": "LK", "科伦坡": "LK", "kathmandu": "NP", "加德满都": "NP",
        "almaty": "KZ", "阿拉木图": "KZ", "tashkent": "UZ", "塔什干": "UZ",
        "auckland": "NZ", "奥克兰": "NZ", "wellington": "NZ", "惠灵顿": "NZ",
        "jakarta": "ID", "雅加达": "ID", "phnom penh": "KH", "金边": "KH",
        "yangon": "MM", "仰光": "MM", "vientiane": "LA", "万象": "LA",
        "ulaanbaatar": "MN", "乌兰巴托": "MN"
    ]

    /// Where a node is, decided from what it is called.
    ///
    /// The name comes first because the airport wrote it and it is what the
    /// user reads; the hostname is consulted only when the name says nothing.
    /// The IP database is a further fallback still, applied by the caller.
    static func region(for node: ProxyNode) -> NodeRegion? {
        nameRegion(for: node.name) ?? serverRegion(for: node.server)
    }

    static func nameRegion(for name: String) -> NodeRegion? {
        if let code = flaggedCountryCode(in: name), let region = region(countryCode: code) {
            return region
        }
        return matchedCode(in: name).flatMap(region(countryCode:))
    }

    private static func serverRegion(for server: String) -> NodeRegion? {
        let host = server.lowercased()
        if let definition = definitions.first(where: { definition in
            definition.domainSuffixes.contains { host.hasSuffix($0) }
        }) {
            return definition.region
        }

        let tokens = Set(
            host.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        )
        if let definition = definitions.first(where: { !$0.tokens.isDisjoint(with: tokens) }) {
            return definition.region
        }
        // Hostnames are all lowercase, so the capitals rule cannot apply to
        // them; only spelled-out names are safe to read out of a hostname.
        return matchedCode(in: server, allowCodes: false).flatMap(region(countryCode:))
    }

    /// The country a piece of text names, preferring the longest match.
    ///
    /// Longest wins so "United States Minor Outlying Islands" is not read as
    /// the United States, and curated entries win ties so the twenty countries
    /// Tower knows best keep their hand-checked behaviour.
    private static func matchedCode(in text: String, allowCodes: Bool = true) -> String? {
        let lowercased = text.lowercased()
        let padded = " \(normalizedLookupText(text)) "
        let capitals = allowCodes
            ? Set(
                text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty && $0 == $0.uppercased() }
            )
            : []

        var best: (length: Int, curated: Bool, code: String)?
        for phrase in phraseIndex {
            let matches: Bool
            switch phrase.form {
            case .capitalisedCode:
                matches = capitals.contains(phrase.text)
            case .cjk:
                matches = lowercased.contains(phrase.text)
            case .words:
                matches = padded.contains(" \(phrase.text) ")
            }
            guard matches else { continue }

            let length = phrase.text.count
            if let current = best,
               length < current.length || (length == current.length && current.curated) {
                continue
            }
            best = (length, phrase.isCurated, phrase.code)
        }
        return best?.code
    }

    private enum PhraseForm {
        /// Latin text, matched on whole words.
        case words
        /// Chinese and other scripts that do not separate words.
        case cjk
        /// A country code, only trusted when the name shouts it.
        case capitalisedCode
    }

    private struct Phrase {
        let text: String
        let code: String
        let form: PhraseForm
        let isCurated: Bool
    }

    /// Everything that can name a country, flattened once at first use.
    private static let phraseIndex: [Phrase] = {
        var result: [Phrase] = []

        func add(_ text: String, code: String, form: PhraseForm, curated: Bool) {
            let cleaned = form == .capitalisedCode ? text.uppercased() : normalized(text, form: form)
            guard !cleaned.isEmpty else { return }
            result.append(Phrase(text: cleaned, code: code, form: form, isCurated: curated))
        }

        func normalized(_ text: String, form: PhraseForm) -> String {
            form == .cjk ? text.lowercased() : normalizedLookupText(text)
        }

        func form(of text: String) -> PhraseForm {
            text.unicodeScalars.contains { $0.value > 0x2FFF } ? .cjk : .words
        }

        for definition in definitions {
            for phrase in definition.phrases where !isRegionalFlagString(phrase) {
                add(phrase, code: definition.region.code, form: form(of: phrase), curated: true)
            }
            for token in definition.tokens {
                // Airport codes like HKG read fine in any case; the two-letter
                // ones are ordinary words and need the capitals.
                let form: PhraseForm = caseSensitiveTokens.contains(token) ? .capitalisedCode : .words
                add(token, code: definition.region.code, form: form, curated: true)
            }
        }

        for (code, entry) in countryTable {
            for name in entry.names {
                add(name, code: code, form: form(of: name), curated: false)
            }
            for isoCode in entry.codes where !reservedTokens.contains(isoCode) {
                add(isoCode, code: code, form: .capitalisedCode, curated: false)
            }
            if !reservedTokens.contains(code) {
                add(code, code: code, form: .capitalisedCode, curated: false)
            }
        }

        for (city, code) in cities {
            add(city, code: code, form: form(of: city), curated: false)
        }

        for entry in isoCountryNames {
            for phrase in entry.phrases {
                add(phrase, code: entry.code, form: form(of: phrase), curated: false)
            }
        }

        return result
    }()

    private static func isRegionalFlagString(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { (0x1F1E6...0x1F1FF).contains(Int($0.value)) }
            && !value.isEmpty
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

    /// The name the airport chose comes first; the IP database only answers
    /// for nodes whose name gives nothing away.
    static func resolvedRegion(for node: ProxyNode, countryCode: String?) -> NodeRegion? {
        if let region = region(for: node) { return region }
        guard let countryCode else { return nil }
        return region(countryCode: countryCode)
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
            phrases: ["韩国", "首尔", "南韩", "korea", "south korea", "seoul", "🇰🇷"],
            tokens: ["kr", "kor", "sel", "icn"],
            domainSuffixes: [".kr"]
        ),
        .init(
            region: .init(code: "US", name: "美国", flag: "🇺🇸", latitude: 37.0902, longitude: -95.7129),
            phrases: ["美国", "洛杉矶", "硅谷", "西雅图", "纽约", "united states", "united states of america", "america", "los angeles", "san jose", "new york", "🇺🇸"],
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
            phrases: ["英国", "伦敦", "英格兰", "苏格兰", "united kingdom", "great britain", "britain", "england", "scotland", "wales", "london", "🇬🇧"],
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
            // France's ISO3 code "fra" is deliberately absent: node names use it
            // far more often for Frankfurt, so it stays with Germany above.
            tokens: ["fr", "par", "cdg"],
            domainSuffixes: [".fr"]
        ),
        .init(
            region: .init(code: "NL", name: "荷兰", flag: "🇳🇱", latitude: 52.3676, longitude: 4.9041),
            phrases: ["荷兰", "阿姆斯特丹", "netherlands", "holland", "amsterdam", "🇳🇱"],
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
