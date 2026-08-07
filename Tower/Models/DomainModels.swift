import CryptoKit
import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case subscriptions
    case rules
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptions: "订阅"
        case .rules: "规则"
        case .export: "导入"
        }
    }

    var symbol: String {
        switch self {
        case .subscriptions: "antenna.radiowaves.left.and.right"
        case .rules: "point.3.connected.trianglepath.dotted"
        case .export: "arrow.up.forward.app"
        }
    }
}

struct SubscriptionSource: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var urlString: String
    var isEnabled: Bool
    var createdAt: Date
    var lastUpdatedAt: Date?
    var lastError: String?
    /// Plan usage reported by the airport, when it reports any.
    var usage: SubscriptionUsage?

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil,
        usage: SubscriptionUsage? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
        self.usage = usage
    }

    var safeHost: String {
        URL(string: urlString)?.host ?? "私密订阅"
    }
}

/// How much of an airport's plan is left.
///
/// Airports report this three different ways and Tower reads all of them: the
/// `subscription-userinfo` response header, a `STATUS=` line at the head of the
/// node list, and plain sentences smuggled into the list as fake entries. Which
/// one arrives varies by airport and, on at least one panel, by request.
struct SubscriptionUsage: Codable, Hashable, Sendable {
    var uploadBytes: Int64?
    var downloadBytes: Int64?
    var totalBytes: Int64?
    var expiresAt: Date?
    /// Text the airport wrote into the node list, kept verbatim because it is
    /// free-form and often says more than the header does.
    var notices: [String] = []

    var isEmpty: Bool {
        totalBytes == nil && expiresAt == nil && notices.isEmpty
    }

    /// Whether the plan is known in numbers rather than only in prose.
    /// Free-form notices are worth showing but cannot drive a progress bar.
    var hasPlanDetail: Bool {
        totalBytes != nil || expiresAt != nil
    }

    /// Notices that are worth showing beside the structured summary.
    ///
    /// Airports that send the header often *also* write the same numbers into
    /// the node list, so showing both prints the plan twice — once formatted by
    /// Tower and once in the airport's own wording. A notice is dropped only
    /// when the structured data already covers that exact fact; a reset
    /// countdown survives an expiry date because they are different dates.
    var distinctNotices: [String] {
        notices.filter { notice in
            let text = notice.lowercased()
            if totalBytes != nil, Self.trafficWords.contains(where: text.contains) { return false }
            if expiresAt != nil, Self.expiryWords.contains(where: text.contains) { return false }
            return true
        }
    }

    private static let trafficWords = ["流量", "traffic", "余额", "balance", "↑:", "↓:", "tot:"]
    private static let expiryWords = ["到期", "过期", "有效期至", "expire"]

    var usedBytes: Int64? {
        guard uploadBytes != nil || downloadBytes != nil else { return nil }
        return (uploadBytes ?? 0) + (downloadBytes ?? 0)
    }

    var remainingBytes: Int64? {
        guard let totalBytes, let usedBytes else { return nil }
        return max(totalBytes - usedBytes, 0)
    }

    /// 0…1 for a progress bar, nil when the airport gave no total.
    var usedFraction: Double? {
        guard let totalBytes, totalBytes > 0, let usedBytes else { return nil }
        return min(Double(usedBytes) / Double(totalBytes), 1)
    }

    /// Parses `upload=1; download=2; total=3; expire=1735660800`.
    ///
    /// Every field is optional: airports omit whichever they do not track, and
    /// a header carrying only `expire` is still worth showing.
    static func parse(header: String) -> SubscriptionUsage? {
        var usage = SubscriptionUsage()
        var matched = false

        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            // Some airports send a float for byte counts.
            guard let value = Double(raw) else { continue }

            switch key {
            case "upload": usage.uploadBytes = Int64(value); matched = true
            case "download": usage.downloadBytes = Int64(value); matched = true
            case "total": usage.totalBytes = Int64(value); matched = true
            case "expire":
                // A zero expiry means "never", not 1970.
                if value > 0 { usage.expiresAt = Date(timeIntervalSince1970: value) }
                matched = true
            default: break
            }
        }
        return matched ? usage : nil
    }

    /// Parses `STATUS=🚀↑:20.02GB,↓:97.73GB,TOT:220GB💡EXPIRES:2026-08-09`.
    ///
    /// Some panels prepend this line to the node list instead of sending the
    /// header. It is human-formatted rather than specified, so parsing stays
    /// tolerant: every field is optional and unknown decoration is skipped.
    static func parse(statusLine: String) -> SubscriptionUsage? {
        let text = statusLine.hasPrefix(statusPrefix)
            ? String(statusLine.dropFirst(statusPrefix.count))
            : statusLine
        var usage = SubscriptionUsage()
        var matched = false

        if let value = bytes(after: "↑:", in: text) { usage.uploadBytes = value; matched = true }
        if let value = bytes(after: "↓:", in: text) { usage.downloadBytes = value; matched = true }
        if let value = bytes(after: "TOT:", in: text) { usage.totalBytes = value; matched = true }
        if let date = day(after: "EXPIRES:", in: text) { usage.expiresAt = date; matched = true }

        return matched ? usage : nil
    }

    static let statusPrefix = "STATUS="

    private static let unitMultipliers: [String: Double] = [
        "": 1, "b": 1,
        "k": 1024, "kb": 1024,
        "m": 1_048_576, "mb": 1_048_576,
        "g": 1_073_741_824, "gb": 1_073_741_824,
        "t": 1_099_511_627_776, "tb": 1_099_511_627_776
    ]

    /// Reads `20.02GB` out of whatever follows `marker`.
    private static func bytes(after marker: String, in text: String) -> Int64? {
        guard let range = text.range(of: marker) else { return nil }
        var digits = ""
        var unit = ""
        for character in text[range.upperBound...] {
            if character.isNumber || character == "." {
                // Digits after the unit belong to the next field.
                if !unit.isEmpty { break }
                digits.append(character)
            } else if character.isLetter {
                unit.append(character)
                if unit.count == 2 { break }
            } else {
                break
            }
        }
        guard let value = Double(digits), let multiplier = unitMultipliers[unit.lowercased()] else {
            return nil
        }
        return Int64(value * multiplier)
    }

    private static func day(after marker: String, in text: String) -> Date? {
        guard let range = text.range(of: marker) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text[range.upperBound...].prefix(10)))
    }
}

enum ProxyKind: String, Codable, CaseIterable, Identifiable {
    case shadowsocks = "ss"
    case shadowsocksR = "ssr"
    case vmess
    case vless
    case trojan
    case hysteria2
    case anytls
    case snell
    case socks5
    case http
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shadowsocks: "Shadowsocks"
        case .shadowsocksR: "ShadowsocksR"
        case .vmess: "VMess"
        case .vless: "VLESS"
        case .trojan: "Trojan"
        case .hysteria2: "Hysteria 2"
        case .anytls: "AnyTLS"
        case .snell: "Snell"
        case .socks5: "SOCKS5"
        case .http: "HTTP"
        case .unknown: "未知协议"
        }
    }

    var symbol: String {
        switch self {
        case .shadowsocks, .shadowsocksR: "bolt.horizontal.circle.fill"
        case .vmess, .vless: "point.3.filled.connected.trianglepath.dotted"
        case .trojan: "shield.lefthalf.filled"
        case .hysteria2: "hare.fill"
        case .anytls: "lock.shield.fill"
        // Snell is Surge's own protocol, so this echoes the rounded-square app
        // icon it ships under, with an S for the name. Not Surge's actual mark:
        // that is their trademark and this repository is public and MIT.
        case .snell: "s.square.fill"
        case .socks5, .http: "network"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct ProxyNode: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceID: UUID?
    var kind: ProxyKind
    var name: String
    var server: String
    var port: Int
    var cipher: String?
    var password: String?
    var uuid: String?
    var username: String?
    var transport: String?
    var tls: Bool
    var sni: String?
    var hostHeader: String?
    var path: String?
    var alpn: String?
    var skipCertificateVerification: Bool
    var alterID: Int?
    var protocolName: String?
    var protocolParam: String?
    var obfs: String?
    var obfsParam: String?
    /// Snell's protocol version. It decides both what a client accepts and
    /// whether the node can carry UDP.
    var version: Int?
    var rawURI: String

    init(
        id: UUID = UUID(),
        sourceID: UUID? = nil,
        kind: ProxyKind,
        name: String,
        server: String,
        port: Int,
        cipher: String? = nil,
        password: String? = nil,
        uuid: String? = nil,
        username: String? = nil,
        transport: String? = nil,
        tls: Bool = false,
        sni: String? = nil,
        hostHeader: String? = nil,
        path: String? = nil,
        alpn: String? = nil,
        skipCertificateVerification: Bool = false,
        alterID: Int? = nil,
        protocolName: String? = nil,
        protocolParam: String? = nil,
        obfs: String? = nil,
        obfsParam: String? = nil,
        version: Int? = nil,
        rawURI: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.name = name
        self.server = server
        self.port = port
        self.cipher = cipher
        self.password = password
        self.uuid = uuid
        self.username = username
        self.transport = transport
        self.tls = tls
        self.sni = sni
        self.hostHeader = hostHeader
        self.path = path
        self.alpn = alpn
        self.skipCertificateVerification = skipCertificateVerification
        self.alterID = alterID
        self.protocolName = protocolName
        self.protocolParam = protocolParam
        self.obfs = obfs
        self.obfsParam = obfsParam
        self.version = version
        self.rawURI = rawURI
    }

    var endpoint: String {
        let host = server.contains(":") && !(server.hasPrefix("[") && server.hasSuffix("]"))
            ? "[\(server)]"
            : server
        return "\(host):\(port)"
    }
    var canonicalKey: String {
        let credential = uuid ?? username ?? password ?? ""
        return "\(kind.rawValue)|\(server.lowercased())|\(port)|\(credential)"
    }

    /// The VMess/VLESS id in the form every client accepts.
    ///
    /// Xray lets the id be any string shorter than 32 bytes and derives a v5
    /// UUID from it — SHA-1 over the nil namespace followed by the text — so
    /// airports do publish ids like `abcd1234`. Clash and Stash refuse anything
    /// that is not a UUID (`invalid UUID length: 8`) and will not load the file
    /// at all, so the same derivation is done here. The server compares against
    /// exactly this value, so the node still connects.
    var exportableUUID: String? {
        guard let uuid else { return nil }
        return ProxyNode.normalizedProxyID(uuid)
    }

    /// The transport path in the form a client will accept.
    ///
    /// WebSocket and HTTP/2 paths are HTTP request paths, so they have to be
    /// absolute, but airports do publish them without the leading slash. Xray's
    /// own server prepends one before matching (`GetNormalizedPath`), so doing
    /// the same here is what the node was always going to send on the wire.
    /// Clash and Shadowrocket quietly normalise it; Surge rejects the whole
    /// profile with "字段 `ws-path` 的值无效".
    var exportablePath: String? {
        guard let path, !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? path : "/" + path
    }

    static func normalizedProxyID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if UUID(uuidString: trimmed) != nil { return trimmed }
        // Xray's own bound: 32 bytes or more is treated as a malformed UUID
        // rather than a name, and there is nothing faithful to emit for it.
        guard trimmed.utf8.count < 32 else { return nil }
        return derivedUUID(from: trimmed)
    }

    private static func derivedUUID(from text: String) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data(repeating: 0, count: 16))
        hasher.update(data: Data(text.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | (5 << 4)
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString.lowercased()
    }
    var isLocal: Bool { sourceID == nil }

    var protocolSummary: String {
        var parts: [String] = [protocolDisplayName]

        if let transportDisplayName, !parts.contains(transportDisplayName) {
            parts.append(transportDisplayName)
        }

        if tls, ![.trojan, .hysteria2, .anytls, .http].contains(kind), !parts.contains("TLS") {
            parts.append("TLS")
        }

        if supportsUDP {
            parts.append("UDP")
        }
        return parts.joined(separator: " / ")
    }

    private var protocolDisplayName: String {
        switch kind {
        case .shadowsocks: "SHADOWSOCKS"
        case .shadowsocksR: "SHADOWSOCKS R"
        case .vmess: "VMESS"
        case .vless: "VLESS"
        case .trojan: "TROJAN"
        case .hysteria2: "HYSTERIA 2"
        case .anytls: "ANYTLS"
        case .snell: version.map { "SNELL V\($0)" } ?? "SNELL"
        case .socks5: "SOCKS5"
        case .http: tls ? "HTTPS" : "HTTP"
        case .unknown: "未知协议"
        }
    }

    private var transportDisplayName: String? {
        let rawTransport: String?
        if let transport, !transport.isEmpty {
            rawTransport = transport
        } else if [.shadowsocks, .shadowsocksR].contains(kind),
                  let obfs, !obfs.isEmpty, obfs.lowercased() != "plain" {
            rawTransport = obfs
        } else {
            rawTransport = nil
        }

        guard let normalized = rawTransport?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !["", "tcp", "none", "plain"].contains(normalized) else {
            return nil
        }

        return switch normalized {
        case "ws", "websocket": "WS"
        case "grpc": "GRPC"
        case "http", "http_simple": "HTTP"
        case "h2", "http2": "H2"
        case "httpupgrade": "HTTP UPGRADE"
        case "xhttp", "splithttp": "XHTTP"
        case "kcp", "mkcp": "KCP"
        case "quic": "QUIC"
        case "tls1.2_ticket_auth", "tls": "TLS"
        default: normalized.uppercased()
        }
    }

    private var supportsUDP: Bool {
        switch kind {
        case .http, .unknown: false
        // Snell only carries UDP from version 3 onwards.
        case .snell: (version ?? 4) >= 3
        default: true
        }
    }
}

enum RulePolicy: String, Codable, Hashable {
    case direct
    case reject
    case select
    case auto
    case international
    case domestic
    case foreignAds
    case ai
    case youtube
    case media
    case telegram
    case googleFCM
    case apple
    case microsoft
    case google

    var displayName: String {
        switch self {
        case .direct: "全球直连"
        case .reject: "广告拦截"
        case .select: "节点选择"
        case .auto: "自动选择"
        case .international: "国际流量"
        case .domestic: "国内流量"
        case .foreignAds: "国外广告"
        case .ai: "AI 服务"
        case .youtube: "YouTube"
        case .media: "国外媒体"
        case .telegram: "Telegram"
        case .googleFCM: "Google FCM"
        case .apple: "苹果服务"
        case .microsoft: "微软服务"
        case .google: "谷歌服务"
        }
    }

    var configurationName: String {
        switch self {
        case .direct: "DIRECT"
        case .reject: "REJECT"
        case .select: "节点选择"
        case .auto: "自动选择"
        case .international: "国际流量"
        case .domestic: "国内流量"
        case .foreignAds: "国外广告"
        case .ai: "AI服务"
        case .youtube: "YouTube"
        case .media: "国外媒体"
        case .telegram: "Telegram"
        case .googleFCM: "Google FCM"
        case .apple: "苹果服务"
        case .microsoft: "Microsoft"
        case .google: "谷歌服务"
        }
    }
}

struct RuleAssignment: Identifiable, Codable, Hashable {
    var id: String { resourcePath }
    let resourcePath: String
    let title: String
    let policy: RulePolicy
}

struct RulePreset: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let tintName: String
    let assignments: [RuleAssignment]
    let includeGeoIPCN: Bool
    let finalPolicy: RulePolicy
    let isRecommended: Bool

    var policies: [RulePolicy] {
        var result: [RulePolicy] = [.select, .auto]
        for assignment in assignments where !result.contains(assignment.policy) {
            result.append(assignment.policy)
        }
        if !result.contains(finalPolicy) { result.append(finalPolicy) }
        return result
    }

    static let builtIns: [RulePreset] = [
        RulePreset(
            id: "self-configuration",
            name: "Self-Configuration",
            summary: "AI、全球流媒体、广告过滤和国内外流量精细分流。",
            symbol: "point.3.connected.trianglepath.dotted",
            tintName: "blue",
            assignments: [
                .init(resourcePath: "AdBlock", title: "AdBlock", policy: .foreignAds),
                .init(resourcePath: "HTTPDNS", title: "HTTPDNS", policy: .foreignAds),
                .init(resourcePath: "Special", title: "特殊直连", policy: .direct),
                .init(resourcePath: "AI Suite", title: "AI Suite", policy: .ai),
                .init(resourcePath: "Netflix", title: "Netflix", policy: .media),
                .init(resourcePath: "Disney Plus", title: "Disney+", policy: .media),
                .init(resourcePath: "YouTube", title: "YouTube", policy: .youtube),
                .init(resourcePath: "Max", title: "Max", policy: .media),
                .init(resourcePath: "Spotify", title: "Spotify", policy: .media),
                .init(resourcePath: "Bilibili", title: "哔哩哔哩", policy: .domestic),
                .init(resourcePath: "IQ", title: "iQI", policy: .domestic),
                .init(resourcePath: "IQIYI", title: "爱奇艺", policy: .domestic),
                .init(resourcePath: "Letv", title: "乐视", policy: .domestic),
                .init(resourcePath: "Netease Music", title: "网易云音乐", policy: .domestic),
                .init(resourcePath: "Tencent Video", title: "腾讯视频", policy: .domestic),
                .init(resourcePath: "WeTV", title: "WeTV", policy: .domestic),
                .init(resourcePath: "Youku", title: "优酷", policy: .domestic),
                .init(resourcePath: "Abema TV", title: "Abema TV", policy: .media),
                .init(resourcePath: "Bahamut", title: "巴哈姆特", policy: .media),
                .init(resourcePath: "DMM", title: "DMM", policy: .media),
                .init(resourcePath: "Fox+", title: "Fox+", policy: .media),
                .init(resourcePath: "Hulu Japan", title: "Hulu Japan", policy: .media),
                .init(resourcePath: "Japonx", title: "Japonx", policy: .media),
                .init(resourcePath: "JOOX", title: "JOOX", policy: .media),
                .init(resourcePath: "KKBOX", title: "KKBOX", policy: .media),
                .init(resourcePath: "KKTV", title: "KKTV", policy: .media),
                .init(resourcePath: "Line TV", title: "Line TV", policy: .media),
                .init(resourcePath: "myTV SUPER", title: "myTV SUPER", policy: .media),
                .init(resourcePath: "Niconico", title: "Niconico", policy: .media),
                .init(resourcePath: "ViuTV", title: "ViuTV", policy: .media),
                .init(resourcePath: "ABC", title: "ABC", policy: .media),
                .init(resourcePath: "Amazon", title: "Amazon", policy: .media),
                .init(resourcePath: "BBC iPlayer", title: "BBC iPlayer", policy: .media),
                .init(resourcePath: "DAZN", title: "DAZN", policy: .media),
                .init(resourcePath: "Discovery Plus", title: "Discovery+", policy: .media),
                .init(resourcePath: "encoreTVB", title: "encoreTVB", policy: .media),
                .init(resourcePath: "F1 TV", title: "F1 TV", policy: .media),
                .init(resourcePath: "Fox Now", title: "Fox Now", policy: .media),
                .init(resourcePath: "Hulu", title: "Hulu", policy: .media),
                .init(resourcePath: "Pandora", title: "Pandora", policy: .media),
                .init(resourcePath: "PBS", title: "PBS", policy: .media),
                .init(resourcePath: "Pornhub", title: "Pornhub", policy: .media),
                .init(resourcePath: "Soundcloud", title: "SoundCloud", policy: .media),
                .init(resourcePath: "Telegram", title: "Telegram", policy: .telegram),
                .init(resourcePath: "Crypto", title: "加密货币", policy: .international),
                .init(resourcePath: "Discord", title: "Discord", policy: .international),
                .init(resourcePath: "Google FCM", title: "Google FCM", policy: .googleFCM),
                .init(resourcePath: "Google", title: "Google", policy: .google),
                .init(resourcePath: "Google Drive", title: "Google Drive", policy: .google),
                .init(resourcePath: "YouTube Music", title: "YouTube Music", policy: .youtube),
                .init(resourcePath: "Google Search", title: "Google Search", policy: .google),
                .init(resourcePath: "Microsoft", title: "Microsoft", policy: .microsoft),
                .init(resourcePath: "PayPal", title: "PayPal", policy: .international),
                .init(resourcePath: "Scholar", title: "Google Scholar", policy: .google),
                .init(resourcePath: "Speedtest", title: "Speedtest", policy: .international),
                .init(resourcePath: "Steam", title: "Steam", policy: .international),
                .init(resourcePath: "TikTok", title: "TikTok", policy: .international),
                .init(resourcePath: "Apple Music", title: "Apple Music", policy: .apple),
                .init(resourcePath: "Apple News", title: "Apple News", policy: .apple),
                .init(resourcePath: "Apple TV", title: "Apple TV", policy: .apple),
                .init(resourcePath: "Apple", title: "Apple 服务", policy: .apple),
                .init(resourcePath: "miHoYo", title: "米哈游", policy: .domestic),
                .init(resourcePath: "PROXY", title: "国际代理", policy: .international),
                .init(resourcePath: "Domestic", title: "国内域名", policy: .domestic),
                .init(resourcePath: "Domestic IPs", title: "国内 IP", policy: .domestic),
                .init(resourcePath: "LAN", title: "局域网", policy: .direct),
                .init(resourcePath: "GeoIP CN", title: "中国大陆 GeoIP", policy: .domestic)
            ],
            includeGeoIPCN: false,
            finalPolicy: .international,
            isRecommended: true
        )
    ]
}

enum ClientTarget: String, CaseIterable, Identifiable, Codable {
    case surge
    case clash
    case shadowrocket
    case loon
    case quanx
    case singbox
    case hiddify
    case egern

    var id: String { rawValue }

    var name: String {
        switch self {
        case .surge: "Surge"
        case .clash: "Stash"
        case .shadowrocket: "Shadowrocket"
        case .loon: "Loon"
        case .quanx: "QuanX"
        case .singbox: "sing-box"
        case .hiddify: "Hiddify"
        case .egern: "Egern"
        }
    }

    var subtitle: String {
        switch self {
        case .surge: "完整配置"
        case .clash: "Clash YAML"
        case .shadowrocket: "本地配置"
        case .loon: "完整配置"
        case .quanx: "Quantumult X"
        case .singbox: "sing-box JSON"
        case .hiddify: "sing-box 内核"
        case .egern: "Egern YAML"
        }
    }

    var symbol: String {
        switch self {
        case .surge: "wave.3.right.circle.fill"
        case .clash: "square.3.layers.3d.top.filled"
        case .shadowrocket: "paperplane.circle.fill"
        case .loon: "moon.stars.circle.fill"
        case .quanx: "q.circle.fill"
        case .singbox: "shippingbox.circle.fill"
        case .hiddify: "eye.slash.circle.fill"
        case .egern: "e.circle.fill"
        }
    }

    /// `nil` when no artwork is bundled, so the picker falls back to `symbol`
    /// rather than drawing the blank that a missing asset renders as.
    var appIconAssetName: String? {
        switch self {
        case .surge: "ClientSurge"
        case .clash: "ClientStash"
        case .shadowrocket: "ClientShadowrocket"
        case .loon: "ClientLoon"
        case .quanx: "ClientQuantumultX"
        case .singbox, .hiddify, .egern: nil
        }
    }

    /// sing-box and Hiddify share a generator: Hiddify is a Flutter shell over
    /// hiddify-core, which is sing-box, so it reads the same document.
    var usesSingBoxFormat: Bool {
        self == .singbox || self == .hiddify
    }

    var fileExtension: String {
        switch self {
        case .clash, .egern: "yaml"
        case .singbox, .hiddify: "json"
        default: "conf"
        }
    }

    var supportsDirectConfigurationImport: Bool {
        // Quantumult X has no import scheme, and neither sing-box nor Hiddify
        // documents one, so those go through the system share sheet.
        switch self {
        case .quanx, .singbox, .hiddify, .egern: false
        default: true
        }
    }

    var primaryImportTitle: String {
        supportsDirectConfigurationImport
            ? "一键导入到 \(name)"
            : "用文件导入到 \(name)"
    }

    func supports(_ kind: ProxyKind) -> Bool {
        switch self {
        case .clash:
            kind != .unknown
        case .surge:
            [.shadowsocks, .vmess, .trojan, .hysteria2, .anytls, .snell, .socks5, .http].contains(kind)
        case .shadowrocket:
            kind != .unknown
        case .loon:
            [.shadowsocks, .shadowsocksR, .vmess, .vless, .trojan, .hysteria2, .anytls, .socks5, .http].contains(kind)
        case .quanx:
            // No Hysteria 2: Quantumult X has no `hysteria2=` server type, and
            // writing one fails the whole import with "配置文件语法错误". Its
            // sample.conf documents ss2022, REALITY, vless-flow and AnyTLS but
            // no Hysteria at all.
            [.shadowsocks, .shadowsocksR, .vmess, .vless, .trojan, .anytls, .socks5, .http].contains(kind)
        case .singbox, .hiddify:
            // Snell is accepted here but only from v4 up, which is the inverse
            // of Clash's ceiling of v3; writes(_:to:excluding:) applies that.
            kind != .unknown
        case .egern:
            [.shadowsocks, .vmess, .vless, .trojan, .hysteria2, .anytls, .snell, .socks5, .http].contains(kind)
        }
    }
}

struct AppSnapshot: Codable {
    var subscriptions: [SubscriptionSource]
    var nodes: [ProxyNode]
    var selectedPresetID: String
    var selectedTarget: ClientTarget
    /// Optional so snapshots written before rule import still decode. The
    /// synthesised decoder does not fall back to default values for missing
    /// keys, so this must stay optional rather than default to an empty array.
    var importedSchemes: [RuleScheme]?
    /// Protocols the user chose not to write, keyed by client raw value. Stored
    /// as plain strings because a dictionary with a non-String key encodes as a
    /// flat array, which is awkward to read in state.json.
    var excludedKinds: [String: [String]]?

    init(
        subscriptions: [SubscriptionSource],
        nodes: [ProxyNode],
        selectedPresetID: String,
        selectedTarget: ClientTarget,
        importedSchemes: [RuleScheme]? = nil,
        excludedKinds: [String: [String]]? = nil
    ) {
        self.subscriptions = subscriptions
        self.nodes = nodes
        self.selectedPresetID = selectedPresetID
        self.selectedTarget = selectedTarget
        self.importedSchemes = importedSchemes
        self.excludedKinds = excludedKinds
    }
}

/// Deliberately carries no HTTP response metadata. The subscription response
/// headers usually include `subscription-userinfo` and session cookies, and
/// nothing in the app consumed them.
struct ImportResult: Sendable {
    let nodes: [ProxyNode]
    let rejectedLineCount: Int
    var usage: SubscriptionUsage?
}

struct GeneratedConfiguration {
    let target: ClientTarget
    let content: String
    let supportedNodeCount: Int
    let skippedNodeCount: Int
    let ruleCount: Int

    var fileName: String {
        "塔台-\(target.name)-\(Self.timestamp).\(target.fileExtension)"
    }

    private static var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: .now)
    }
}
