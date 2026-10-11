#if DEBUG
import Foundation

/// Richer sample data for App Store screenshots: `--demo --showcase`.
///
/// Debug only, and separate from `--demo` because UI tests depend on the
/// smaller demo set. Every server is under `example.com`/`example.net` and every
/// credential is a placeholder, so nothing here can reach a real proxy.
extension AppModel {
    static var showcaseSnapshot: AppSnapshot {
        let day: TimeInterval = 86_400
        let gb: Int64 = 1_073_741_824
        let yunfan = SubscriptionSource(
            name: "云帆机场",
            urlString: "https://example.com/sub/yunfan",
            createdAt: .now.addingTimeInterval(-90 * day),
            lastUpdatedAt: .now.addingTimeInterval(-6 * 60),
            usage: SubscriptionUsage(
                uploadBytes: 12 * gb, downloadBytes: 116 * gb,
                totalBytes: 500 * gb, expiresAt: .now.addingTimeInterval(160 * day)
            )
        )
        let xinghe = SubscriptionSource(
            name: "星河加速",
            urlString: "https://example.com/sub/xinghe",
            createdAt: .now.addingTimeInterval(-40 * day),
            lastUpdatedAt: .now.addingTimeInterval(-2 * 3600),
            usage: SubscriptionUsage(
                uploadBytes: 3 * gb, downloadBytes: 39 * gb,
                totalBytes: 200 * gb, expiresAt: .now.addingTimeInterval(45 * day)
            )
        )
        let aurora = SubscriptionSource(
            name: "极光 Cloud",
            urlString: "https://example.com/sub/aurora",
            createdAt: .now.addingTimeInterval(-20 * day),
            lastUpdatedAt: .now.addingTimeInterval(-26 * 3600),
            usage: SubscriptionUsage(
                uploadBytes: 6 * gb, downloadBytes: 81 * gb,
                totalBytes: 100 * gb, expiresAt: .now.addingTimeInterval(12 * day)
            )
        )

        var index = 0
        func node(_ source: SubscriptionSource?, _ kind: ProxyKind, _ name: String, _ host: String) -> ProxyNode {
            index += 1
            let server = "\(host).example.\(source == nil ? "net" : "com")"
            let raw = "\(kind.rawValue)://showcase-\(index)"
            switch kind {
            case .vmess:
                return ProxyNode(sourceID: source?.id, kind: kind, name: name, server: server, port: 443,
                                 uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e", transport: "ws", tls: true,
                                 sni: server, hostHeader: server, path: "/ws", alterID: 0, rawURI: raw)
            case .trojan:
                return ProxyNode(sourceID: source?.id, kind: kind, name: name, server: server, port: 443,
                                 password: "showcase-password", tls: true, sni: server, rawURI: raw)
            case .hysteria2:
                return ProxyNode(sourceID: source?.id, kind: kind, name: name, server: server, port: 8443,
                                 password: "showcase-password", tls: true, sni: server, rawURI: raw)
            case .tuic:
                return ProxyNode(sourceID: source?.id, kind: kind, name: name, server: server, port: 8443,
                                 password: "showcase-password", uuid: "0f3c8b0e-2a4d-4f1e-9a3b-6c1d2e3f4a5b",
                                 tls: true, sni: server, alpn: "h3", congestionControl: "bbr", rawURI: raw)
            default:
                return ProxyNode(sourceID: source?.id, kind: .shadowsocks, name: name, server: server, port: 8388,
                                 cipher: "aes-256-gcm", password: "showcase-password", rawURI: raw)
            }
        }

        let nodes = [
            node(yunfan, .shadowsocks, "香港 01 · IEPL", "hk1"),
            node(yunfan, .vmess, "香港 02 · IEPL", "hk2"),
            node(yunfan, .trojan, "香港 03", "hk3"),
            node(yunfan, .trojan, "日本 东京 01", "jp1"),
            node(yunfan, .hysteria2, "日本 大阪 02", "jp2"),
            node(yunfan, .shadowsocks, "新加坡 01", "sg1"),
            node(yunfan, .trojan, "新加坡 02", "sg2"),
            node(yunfan, .vmess, "美国 洛杉矶 01", "us1"),
            node(yunfan, .hysteria2, "美国 圣何塞 02", "us2"),
            node(yunfan, .shadowsocks, "马来西亚 01", "my1"),
            node(yunfan, .trojan, "韩国 首尔 01", "kr1"),
            node(yunfan, .vmess, "英国 伦敦 01", "uk1"),
            node(yunfan, .shadowsocks, "德国 法兰克福 01", "de1"),
            node(xinghe, .hysteria2, "香港 HKT 01", "hk4"),
            node(xinghe, .tuic, "香港 HKBN 02", "hk5"),
            node(xinghe, .shadowsocks, "日本 东京 03", "jp3"),
            node(xinghe, .trojan, "日本 东京 04", "jp4"),
            node(xinghe, .hysteria2, "新加坡 03", "sg3"),
            node(xinghe, .trojan, "美国 西雅图 03", "us3"),
            node(xinghe, .hysteria2, "泰国 曼谷 01", "th1"),
            node(xinghe, .shadowsocks, "韩国 首尔 02", "kr2"),
            node(xinghe, .vmess, "加拿大 多伦多 01", "ca1"),
            node(aurora, .shadowsocks, "香港 05", "hk6"),
            node(aurora, .shadowsocks, "日本 东京 05", "jp5"),
            node(aurora, .trojan, "美国 纽约 05", "us4"),
            node(aurora, .trojan, "澳大利亚 悉尼 01", "au1"),
            node(nil, .trojan, "自建 · 东京", "tokyo"),
            node(nil, .hysteria2, "自建 · 新加坡", "singapore"),
        ]
        return AppSnapshot(
            subscriptions: [yunfan, xinghe, aurora],
            nodes: nodes,
            selectedPresetID: Self.defaultRuleSchemeID,
            selectedTarget: .surge
        )
    }

    static let showcaseTailnets = [
        TailnetConnection(name: "家里", subnets: ["192.168.1.0/24"], magicDNSSuffix: "tail1234.ts.net"),
    ]

    /// Latencies in node order, so the map shows a believable spread.
    static let showcaseLatencies = [
        38, 42, 57, 66, 71, 49, 88, 165, 182, 61, 74, 212, 236,
        45, 53, 69, 81, 95, 178, 64, 83, 201,
        120, 133, 246, 289,
        58, 92,
    ]
}

/// Reports a signed-in account and never touches iCloud. Demo mode already
/// skips every sync call; this only lets the settings page read as configured.
struct ShowcaseCloudSync: CloudSnapshotSyncing {
    var isAccountAvailable: Bool { true }
    func download() async throws -> AppSnapshot? { nil }
    func upload(_ snapshot: AppSnapshot) async throws {}
    func removeRemoteSnapshot() async throws {}
    func commit(_ snapshot: AppSnapshot, replacing expected: AppSnapshot?) async throws {}
}
#endif
