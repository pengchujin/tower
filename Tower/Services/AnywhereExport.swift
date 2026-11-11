import Foundation

/// Anywhere's node-URI dialect, verified against upstream 9ae49a73a0cf.
/// This client imports subscriptions, not Tower's policy groups and rules.
enum AnywhereExport {
    /// Clash's `client-fingerprint` names mapped exactly as Anywhere's own
    /// Clash importer maps them (ClashProxyParser.mapFingerprint, upstream
    /// 124ec879a313). `random` becomes Anywhere's default, so the parameter
    /// is left out rather than written.
    private static let fingerprints: [String: String?] = [
        "chrome": "chrome_133", "firefox": "firefox_148", "safari": "safari_26",
        "ios": "chrome_120", "edge": "edge_106", "random": nil, "randomized": nil
    ]
    private static let nativeFingerprints: Set<String> = [
        "chrome_133", "chrome_120", "chrome_106", "firefox_148", "firefox_120",
        "safari_26", "edge_106", "non_browser"
    ]

    /// - Parameter allowingInsecure: true for the AJSON document, whose TLS
    ///   layer has a per-proxy `insecure` field that share links lack.
    static func supports(_ node: ProxyNode, allowingInsecure: Bool = false) -> Bool {
        unsupportedReason(node, allowingInsecure: allowingInsecure) == nil
    }

    /// Why a node cannot be written for Anywhere, or nil when it can.
    static func unsupportedReason(_ node: ProxyNode, allowingInsecure: Bool = false) -> String? {
        if node.kind == .vless, UUID(uuidString: node.uuid ?? "") == nil {
            return String(localized: "节点认证信息无效或不完整。")
        }
        // Anywhere's share links have no field for these; never silently
        // weaken a pin or drop a requirement. Dropping skip-cert-verify would
        // make the node fail its handshake: it would look fine and not connect.
        if node.skipCertificateVerification, !(allowingInsecure && ajsonProxy(for: node) != nil) {
            return String(localized: "Anywhere 总是校验服务器证书，无法保留此节点的“跳过证书校验”，导出后会连接失败。")
        }
        if !(node.certificateFingerprint ?? "").isEmpty {
            return String(localized: "Anywhere 不支持证书指纹固定。")
        }
        if node.udpRelayEnabled == false {
            return String(localized: "Anywhere 无法关闭此节点的 UDP 转发。")
        }
        if let fp = node.fingerprint, !fp.isEmpty,
           fingerprints[fp.lowercased()] == nil, !nativeFingerprints.contains(fp) {
            return String(localized: "Anywhere 不支持 TLS 指纹 \(fp)。")
        }
        if !(node.portHopping ?? "").isEmpty || !(node.plugin ?? "").isEmpty {
            return String(localized: "Anywhere 不支持此节点的端口跳跃或插件。")
        }
        let transport = node.transport?.lowercased() ?? "tcp"
        if (node.usesReality && node.kind != .vless) || (node.kind != .vless && !["", "tcp"].contains(transport)) {
            return String(localized: "Anywhere 只有 VLESS 支持 Reality 和 TCP 以外的传输方式。")
        }
        let supported: Bool
        switch node.kind {
        case .shadowsocks:
            supported = !node.tls && (node.obfs ?? "none") == "none"
                && ["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "chacha20-poly1305",
                    "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
                    "2022-blake3-chacha20-poly1305", "none"].contains(node.cipher ?? "")
                && node.password != nil
        case .socks5:
            supported = !node.tls
        case .hysteria2:
            supported = (node.alpn ?? "").isEmpty
                && ["", "none", "salamander", "gecko"].contains(node.obfs?.lowercased() ?? "")
        default:
            supported = true
        }
        return supported ? nil : String(localized: "此节点的协议参数无法在当前客户端完整保留。")
    }

    static func link(for node: ProxyNode) -> String {
        let canonical = ProxyNodeShareLinkGenerator().canonicalLink(for: node)
        guard node.kind != .shadowsocks,
              var url = URLComponents(string: canonical) else { return canonical }
        var items = url.queryItems ?? []
        let aliases = ["idle-session-check-interval": "ici", "idle-session-timeout": "it", "min-idle-session": "mis"]
        items = items.map { item in
            if node.kind == .vless, node.transport == "grpc", item.name == "host" {
                return URLQueryItem(name: "authority", value: item.value)
            }
            if let alias = aliases[item.name] { return URLQueryItem(name: alias, value: item.value) }
            if item.name == "fp", let value = item.value, let mapped = fingerprints[value.lowercased()] {
                return URLQueryItem(name: "fp", value: mapped)
            }
            return item
        }.filter { !($0.name == "fp" && $0.value == nil) }
        // SOCKS5's parser expects host:port with no URI query suffix.
        if node.kind == .socks5 { items = [] }
        if node.kind == .vless, let flow = node.flow, !flow.isEmpty,
           !items.contains(where: { $0.name == "flow" }) {
            items.append(URLQueryItem(name: "flow", value: flow))
        }
        if node.kind == .hysteria2 {
            if let up = node.upMbps { items.append(URLQueryItem(name: "upmbps", value: String(up))) }
            if let down = node.downMbps { items.append(URLQueryItem(name: "downmbps", value: String(down))) }
        }
        url.queryItems = items.isEmpty ? nil : items
        return url.string ?? canonical
    }

    // MARK: - AJSON

    /// The request header Anywhere sends when it can read an AJSON document
    /// (`Documentations/AJSON.md`, upstream 8b1ec05). Older releases do not
    /// send it and keep receiving the share-link list.
    static let ajsonFormatHeader = "x-anywhere-format"

    static func acceptsAJSON(formatHeader value: String?) -> Bool {
        guard let value else { return false }
        return value.split(separator: ",").contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "ajson/1"
        }
    }

    /// Only nodes whose share link would lose skip-cert-verify are written as
    /// structured proxies; every other node stays the exact link string that
    /// the link-list export already uses, so the document changes nothing else.
    static func ajsonDocument(nodes: [ProxyNode], name: String) -> String? {
        var proxies: [Any] = []
        for node in nodes {
            if node.skipCertificateVerification {
                guard let proxy = ajsonProxy(for: node) else { return nil }
                proxies.append(proxy)
            } else {
                proxies.append(link(for: node))
            }
        }
        let document: [String: Any] = ["anywhere": 1, "name": name, "proxies": proxies]
        guard let data = try? JSONSerialization.data(
            withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(data: data, encoding: .utf8).map { $0 + "\n" }
    }

    /// The node as an AJSON proxy with `insecure: true`, or nil when AJSON
    /// cannot carry it. Built from the same Anywhere link and read the way
    /// Anywhere's link parser reads it (ProxyConfiguration+URLParsing), so
    /// the only difference from the link is the certificate check.
    /// Hysteria has no `insecure` field and Reality has no certificate check
    /// to skip, so neither qualifies.
    static func ajsonProxy(for node: ProxyNode) -> [String: Any]? {
        guard [.vless, .trojan, .anytls].contains(node.kind), !node.usesReality,
              let components = URLComponents(string: link(for: node)) else { return nil }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] where parameters[item.name] == nil {
            parameters[item.name] = item.value ?? ""
        }
        func value(_ key: String) -> String? {
            parameters[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        // ECH needs Anywhere's own validation; an invalid inline value would
        // drop the whole proxy, so leave such nodes to the skip list.
        guard value("ech") == nil else { return nil }

        var tls: [String: Any] = ["type": "tls", "insecure": true]
        // A link without `fp` means Anywhere's plain ClientHello, while an
        // AJSON proxy without `fingerprint` means Chrome; keep the link's.
        tls["fingerprint"] = value("fp") ?? "plain"
        if let alpn = value("alpn") {
            tls["alpn"] = alpn.split(separator: ",").map(String.init)
        }
        var proxy: [String: Any] = [
            "name": node.name,
            "server": node.server,
            "port": node.port
        ]
        switch node.kind {
        case .vless:
            guard parameters["security"] == "tls", let uuid = node.uuid else { return nil }
            proxy["protocol"] = "vless"
            proxy["uuid"] = uuid
            if let encryption = value("encryption") { proxy["encryption"] = encryption }
            if let flow = value("flow") { proxy["flow"] = flow }
            if let sni = value("sni") { tls["sni"] = sni }
            for key in ["minVersion", "maxVersion"] {
                if let version = value(key) {
                    guard ["1.0", "1.1", "1.2", "1.3"].contains(version) else { return nil }
                    tls[key] = version
                }
            }
            guard let transport = ajsonTransport(parameters) else { return nil }
            if let transport { proxy["transport"] = transport }
        case .trojan, .anytls:
            guard node.password?.isEmpty == false else { return nil }
            proxy["protocol"] = node.kind == .trojan ? "trojan" : "anytls"
            proxy["password"] = node.password
            if let sni = value("sni") ?? value("peer") { tls["sni"] = sni }
            if node.kind == .anytls {
                for (link, key) in [("ici", "idleCheckInterval"), ("it", "idleTimeout"), ("mis", "minIdleSession")] {
                    if let number = value(link).flatMap(Int.init) { proxy[key] = number }
                }
            }
        default:
            return nil
        }
        proxy["security"] = tls
        return proxy
    }

    /// The VLESS transport layer the link describes: `.some(nil)` is raw,
    /// `nil` means Anywhere cannot keep the certificate check off over it.
    private static func ajsonTransport(_ parameters: [String: String]) -> [String: Any]?? {
        func value(_ key: String) -> String? {
            parameters[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        // `type=tcp&headerType=http` is HTTP/1.1 header obfuscation, which
        // Anywhere does not implement.
        guard parameters["headerType"] == nil else { return nil }
        var transport: [String: Any]
        switch parameters["type"] ?? "tcp" {
        case "tcp", "raw":
            return .some(nil)
        case "httpupgrade":
            transport = ["type": "httpupgrade"]
        // WebSocket, gRPC and XHTTP rebuild the TLS configuration without
        // `insecureSkipVerify` (ProxyClient+VLESSTransport.swift and
        // ProxyClient+XHTTP.swift, upstream 8b1ec05), so the node would still
        // fail its certificate check. Confirmed on a device: "insecure".
        default:
            return nil
        }
        if let host = value("host") { transport["host"] = host }
        if let path = value("path") { transport["path"] = path }
        return transport
    }
}
