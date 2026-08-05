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

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        lastUpdatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastError = lastError
    }

    var safeHost: String {
        URL(string: urlString)?.host ?? "私密订阅"
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

    var id: String { rawValue }

    var name: String {
        switch self {
        case .surge: "Surge"
        case .clash: "Stash"
        case .shadowrocket: "Shadowrocket"
        case .loon: "Loon"
        case .quanx: "QuanX"
        }
    }

    var subtitle: String {
        switch self {
        case .surge: "完整配置"
        case .clash: "Clash YAML"
        case .shadowrocket: "本地配置"
        case .loon: "完整配置"
        case .quanx: "Quantumult X"
        }
    }

    var symbol: String {
        switch self {
        case .surge: "wave.3.right.circle.fill"
        case .clash: "square.3.layers.3d.top.filled"
        case .shadowrocket: "paperplane.circle.fill"
        case .loon: "moon.stars.circle.fill"
        case .quanx: "q.circle.fill"
        }
    }

    var appIconAssetName: String {
        switch self {
        case .surge: "ClientSurge"
        case .clash: "ClientStash"
        case .shadowrocket: "ClientShadowrocket"
        case .loon: "ClientLoon"
        case .quanx: "ClientQuantumultX"
        }
    }

    var fileExtension: String {
        self == .clash ? "yaml" : "conf"
    }

    var supportsDirectConfigurationImport: Bool {
        self != .quanx
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
            [.shadowsocks, .vmess, .trojan, .hysteria2, .anytls, .socks5, .http].contains(kind)
        case .shadowrocket:
            kind != .unknown
        case .loon:
            [.shadowsocks, .shadowsocksR, .vmess, .vless, .trojan, .hysteria2, .anytls, .socks5, .http].contains(kind)
        case .quanx:
            [.shadowsocks, .shadowsocksR, .vmess, .vless, .trojan, .hysteria2, .anytls, .socks5, .http].contains(kind)
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

    init(
        subscriptions: [SubscriptionSource],
        nodes: [ProxyNode],
        selectedPresetID: String,
        selectedTarget: ClientTarget,
        importedSchemes: [RuleScheme]? = nil
    ) {
        self.subscriptions = subscriptions
        self.nodes = nodes
        self.selectedPresetID = selectedPresetID
        self.selectedTarget = selectedTarget
        self.importedSchemes = importedSchemes
    }
}

/// Deliberately carries no HTTP response metadata. The subscription response
/// headers usually include `subscription-userinfo` and session cookies, and
/// nothing in the app consumed them.
struct ImportResult: Sendable {
    let nodes: [ProxyNode]
    let rejectedLineCount: Int
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
