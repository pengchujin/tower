import Foundation

/// Where a policy group's emoji is drawn as an image: Microsoft Fluent Emoji
/// 3D (MIT) from its pinned commit on jsDelivr, and for flags the round
/// flag-icons PNGs Tower publishes. Data from Scripts/update_policy_group_icons.py.
struct PolicyGroupIconCatalog: Sendable {
    let fluentBase: URL?
    let fluentPaths: [String: String]
    /// Nil until the flags are published at an immutable Tower commit.
    let flagBase: URL?
    let flagCodes: Set<String>
    /// Quantumult X's own set, 144px on raw.githubusercontent.com: every Fluent
    /// image on a pale circle and the round flags (all in `FluentCircle/`).
    /// Nil until published at an immutable commit.
    var circleBase: URL? = nil
    var circleKeys: Set<String> = []

    static let bundled = PolicyGroupIconCatalog(bundle: .main)

    init(fluentBase: URL?, fluentPaths: [String: String], flagBase: URL?, flagCodes: Set<String>,
         circleBase: URL? = nil, circleKeys: Set<String> = []) {
        self.fluentBase = fluentBase
        self.fluentPaths = fluentPaths
        self.flagBase = flagBase
        self.flagCodes = flagCodes
        self.circleBase = circleBase
        self.circleKeys = circleKeys
    }

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "PolicyGroupIcons_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            self.init(fluentBase: nil, fluentPaths: [:], flagBase: nil, flagCodes: [])
            return
        }
        let fluent = manifest["fluent"] as? [String: Any]
        let flags = manifest["flags"] as? [String: Any]
        let flagBase = (flags?["base"] as? String).flatMap(URL.init(string:))
        // A staging manifest points at `main`, which can change under a profile.
        let published = flags?["artifactCommit"] is String && !(flagBase?.absoluteString.contains("@main/") ?? true)
        let circles = manifest["circles"] as? [String: Any]
        let circleBase = (circles?["base"] as? String).flatMap(URL.init(string:))
        let circlesPublished = circles?["artifactCommit"] is String && !(circleBase?.absoluteString.contains("/main/") ?? true)
        self.init(
            fluentBase: (fluent?["base"] as? String).flatMap(URL.init(string:)),
            fluentPaths: fluent?["emoji"] as? [String: String] ?? [:],
            flagBase: published ? flagBase : nil,
            flagCodes: Set((flags?["files"] as? [String: String] ?? [:]).keys),
            circleBase: circlesPublished ? circleBase : nil,
            circleKeys: Set((circles?["files"] as? [String: String] ?? [:]).keys)
        )
    }

    /// ACL4SSR and many providers write the US as 🇺🇲 (U.S. Outlying Islands,
    /// drawn as the same flag), which has no image of its own.
    static let flagAliases = ["UM": "US"]

    private static func iconEmoji(_ emoji: String) -> String {
        guard let code = countryCode(ofFlag: emoji), let alias = flagAliases[code] else { return emoji }
        return NodeRegionResolver.flagEmoji(for: alias)
    }

    func url(forEmoji emoji: String) -> URL? {
        let emoji = Self.iconEmoji(emoji)
        if let code = Self.countryCode(ofFlag: emoji) {
            guard let base = flagBase, flagCodes.contains(code) else { return nil }
            return base.appendingPathComponent("\(code.lowercased()).png")
        }
        let key = emoji.replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{FE0E}", with: "")
        guard let base = fluentBase, let path = fluentPaths[key] else { return nil }
        return path.split(separator: "/").reduce(base) { $0.appendingPathComponent(String($1)) }
    }

    /// `…/FluentCircle/1f680.png`: the emoji's scalars in hex, as the script names them.
    func circleURL(forEmoji emoji: String) -> URL? {
        let key = Self.iconEmoji(emoji).replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{FE0E}", with: "")
        guard let base = circleBase, circleKeys.contains(key) else { return nil }
        let stem = key.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        return base.appendingPathComponent("\(stem).png")
    }

    static func countryCode(ofFlag emoji: String) -> String? {
        let scalars = emoji.unicodeScalars.filter { $0.value != 0xFE0F }
        guard scalars.count == 2, scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else { return nil }
        return String(scalars.map { Character(UnicodeScalar($0.value - 0x1F1E6 + 65)!) })
    }
}

/// Clients that take an icon for a policy group, and those of them that are
/// known to draw it, so the group's name can drop its emoji (CLAUDE.md #6).
/// Surge: `icon-url` (Mac 6.5+, also parsed by iOS 5.17); Stash: `icon`; the
/// Clash app: `icon`, drawn in its editor and proxy page since iOS 1.0.7 /
/// macOS 1.0.10 (release notes; name truncation with icons fixed in 1.0.14);
/// mihomo: `icon`, drawn by Clash Verge Rev, unconfirmed in the others, which
/// keep the emoji; Quantumult X and Loon: `img-url`; Egern: `icon`.
/// Quantumult X drew none of the 256px Fluent images on a device, from jsDelivr
/// or raw.githubusercontent.com, so it gets its own 144px set on pale circles
/// (`PolicyGroupIconCatalog.circleURL`), and SF Symbols (`img-url=<name>.system`)
/// until that set is published.
enum PolicyGroupIconSupport {
    static let writesIcons: Set<ClientTarget> = [
        .surge, .surgeMac, .clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi,
        .quanx, .loon, .egern
    ]
    static let drawsIcons: Set<ClientTarget> = [.surge, .surgeMac, .clash, .clashApple, .clashVerge, .quanx, .loon, .egern]
    static let parameterKey = "tower-icon"
    static let circleIcons: Set<ClientTarget> = [.quanx]
    /// Surge already draws the flag a region group's name starts with in the
    /// icon slot, so a flag icon would add nothing (user, 2026-10-19).
    static let regionIconsFromName: Set<ClientTarget> = [.surge, .surgeMac]

    /// The SF Symbol for each emoji Tower gives a group: everything in
    /// `PolicyGroupEmoji.table`, its kind fallbacks, ACL4SSR's and the legacy
    /// catalog's. Quantumult X falls back to these until its circles are
    /// published; an emoji not listed here then gets no symbol and stays in the name.
    /// All exist in SF Symbols 4 (iOS 16).
    static let symbols: [String: String] = [
        "🎛": "hand.point.up.left.fill", "♻": "speedometer", "🍃": "leaf.fill",
        "🛑": "hand.raised.fill", "🐟": "fish.fill", "🌏": "globe.asia.australia.fill",
        "🌍": "globe.europe.africa.fill", "🏠": "house.fill", "🌐": "network",
        "📢": "bell.badge.fill", "📹": "play.rectangle.fill", "🎥": "film.fill",
        "🎞": "film.fill", "🧸": "sparkles", "🎬": "film.stack.fill", "🎦": "film.stack.fill",
        "📺": "tv.fill", "🎵": "music.note", "🎧": "headphones", "🟢": "headphones",
        "🎶": "music.note.list", "📲": "paperplane.fill", "✈": "paperplane.fill",
        "💬": "bubble.left.and.bubble.right.fill", "🤖": "brain.head.profile", "🔷": "sparkle", "✨": "sparkle",
        "🐦": "bird.fill", "🕊": "bird.fill", "♾": "infinity",
        "🎙": "bubble.left.and.bubble.right.fill", "🐙": "chevron.left.forwardslash.chevron.right",
        "☁": "cloud.fill", "💳": "creditcard.fill", "🪙": "bitcoinsign.circle.fill",
        "📦": "cart.fill", "Ⓜ": "square.grid.2x2.fill", "🪟": "square.grid.2x2.fill",
        "🍎": "apple.logo", "🔍": "magnifyingglass", "🔎": "magnifyingglass",
        "🎮": "gamecontroller.fill", "🎯": "arrow.right.circle.fill", "🚀": "airplane",
        "⚡": "bolt.fill", "🔁": "arrow.triangle.2.circlepath", "⚖": "scalemass.fill",
        "🧩": "square.stack.3d.up.fill", "🎓": "graduationcap.fill", "📰": "newspaper.fill",
        "📧": "envelope.fill", "🏦": "building.columns.fill", "⚽": "soccerball", "👥": "person.2.fill",
        "📥": "arrow.down.circle.fill", "🛡": "lock.shield.fill", "📶": "speedometer", "🍿": "play.tv.fill",
        "👽": "person.3.fill", "📕": "book.closed.fill", "📞": "phone.fill", "🐳": "shippingbox.fill",
        "🎨": "paintpalette.fill", "🛒": "cart.fill", "🏡": "house.fill", "💰": "dollarsign.circle.fill",
        "⭐": "star.fill", "🛠": "wrench.and.screwdriver.fill", "🗺": "map.fill", "🔀": "arrow.triangle.branch",
        "📣": "megaphone.fill", "📝": "note.text", "📱": "iphone", "🔞": "eye.slash.fill",
    ]

    static func systemSymbol(forEmoji emoji: String) -> String? {
        let key = emoji.replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{FE0E}", with: "")
        return symbols[key].map { "\($0).system" }
    }
}

extension RuleScheme {
    /// Each group's icon, from the emoji it has, is recognised for or its kind
    /// stands for. Where the client draws icons, a group that got one drops the
    /// emoji from its name; a group without an image keeps it, and so does a
    /// region group, whose flag shows twice on its own row.
    func withPolicyGroupIcons(for target: ClientTarget, catalog: PolicyGroupIconCatalog = .bundled) -> RuleScheme {
        guard PolicyGroupIconSupport.writesIcons.contains(target) else { return self }
        let circles = PolicyGroupIconSupport.circleIcons.contains(target)
        // Conditional (subnet / SSID) and relay groups have no documented icon
        // field (Egern lists `icon` for select, auto_test, smart, fallback and
        // load_balance only); they keep their name as written. Region groups
        // get a round flag but keep the flag in the name too: clients list a
        // group's members by name alone, where `香港节点` without its flag
        // says less, and a bare icon row looked empty (user, 2026-10-19).
        var regionGroups = Set<String>()
        let icons = Dictionary(groups.compactMap { group -> (String, String)? in
            guard ![.conditional, .relay, .unsupported].contains(group.kind) else { return nil }
            let emoji = PolicyGroupEmoji.resolved(for: group, in: self)
            if PolicyGroupIconCatalog.countryCode(ofFlag: emoji) != nil {
                guard !PolicyGroupIconSupport.regionIconsFromName.contains(target) else { return nil }
                regionGroups.insert(group.name)
            }
            let icon = circles
                ? catalog.circleURL(forEmoji: emoji)?.absoluteString ?? PolicyGroupIconSupport.systemSymbol(forEmoji: emoji)
                : catalog.url(forEmoji: emoji)?.absoluteString
            return icon.map { (group.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
        guard !icons.isEmpty else { return self }
        var scheme = self
        var originalNames: [String: String] = [:]
        if PolicyGroupIconSupport.drawsIcons.contains(target) {
            let stripped = withoutGroupEmojis(only: Set(icons.keys).subtracting(regionGroups))
            scheme = stripped.scheme
            originalNames = Dictionary(stripped.renamed.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        }
        scheme.groups = scheme.groups.map { group in
            guard let icon = icons[originalNames[group.name] ?? group.name] else { return group }
            var parameters = group.parameters ?? [:]
            parameters[PolicyGroupIconSupport.parameterKey] = icon
            return RuleSchemeGroup(
                name: group.name, kind: group.kind, members: group.members,
                testURLString: group.testURLString, interval: group.interval, tolerance: group.tolerance,
                algorithm: group.algorithm, sourceType: group.sourceType, sourceFormat: group.sourceFormat,
                parameters: parameters, isCustomNodeFilter: group.isCustomNodeFilter
            )
        }
        return scheme
    }
}
