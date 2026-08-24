import Foundation

struct SharePayload: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let value: String
    let symbol: String
    let protocolKind: ProxyKind?

    init(
        title: String,
        detail: String,
        value: String,
        symbol: String,
        protocolKind: ProxyKind? = nil
    ) {
        self.title = title
        self.detail = detail
        self.value = value
        self.symbol = symbol
        self.protocolKind = protocolKind
    }
}

enum SharePayloadFactory {
    static func subscription(_ source: SubscriptionSource) -> SharePayload {
        SharePayload(
            title: source.name,
            detail: String(localized: "订阅链接"),
            value: source.urlString,
            symbol: "link.circle.fill"
        )
    }

    static func node(_ node: ProxyNode) -> SharePayload {
        SharePayload(
            title: NodeRegionResolver.title(for: node),
            detail: node.protocolSummary,
            value: ProxyNodeShareLinkGenerator().link(for: node),
            symbol: node.kind.symbol,
            protocolKind: node.kind
        )
    }
}

struct ProxyNodeShareLinkGenerator {
    func link(for node: ProxyNode) -> String {
        let original = node.rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if isReusable(original) {
            return original
        }

        return canonicalLink(for: node)
    }

    /// Subscription payloads need a normalized URI even when the provider's
    /// original link is otherwise reusable. In particular, percent-encoding
    /// the fragment keeps flag emoji and non-ASCII names intact after a client
    /// decodes the outer base64 subscription.
    func canonicalLink(for node: ProxyNode) -> String {
        let original = node.rawURI.trimmingCharacters(in: .whitespacesAndNewlines)

        return switch node.kind {
        case .shadowsocks: shadowsocksLink(for: node) ?? original
        case .shadowsocksR: shadowsocksRLink(for: node) ?? original
        case .vmess: vmessLink(for: node) ?? original
        case .vless, .trojan, .hysteria, .hysteria2, .tuic, .anytls, .socks5, .http:
            standardLink(for: node) ?? original
        case .wireguard: wireGuardLink(for: node) ?? original
        // Snell has no URI form, so share its portable Surge proxy line.
        case .snell: original.isEmpty ? snellLine(for: node) : original
        case .unknown: original
        }
    }

    private func isReusable(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("clash://local/") else { return false }
        return [
            "ss://", "ssr://", "vmess://", "vless://", "trojan://",
            "hysteria2://", "hy2://", "hysteria://", "tuic://", "wireguard://", "wg://",
            "anytls://", "socks5://", "socks://", "http://", "https://"
        ].contains(where: lowercased.hasPrefix)
    }

    private func shadowsocksLink(for node: ProxyNode) -> String? {
        guard let cipher = node.cipher, let password = node.password else { return nil }
        let auth = base64URL(Data("\(cipher):\(password)".utf8))
        var link = "ss://\(auth)@\(formattedHost(node.server)):\(node.port)"

        // Dropping the plugin would hand out a link that looks fine and cannot
        // connect, which is exactly what the importer refuses to accept.
        if node.plugin == "v2ray-plugin" {
            var plugin = "v2ray-plugin;mode=websocket"
            if node.tls { plugin += ";tls" }
            if let host = node.hostHeader, !host.isEmpty { plugin += ";host=\(host)" }
            if let path = node.exportablePath { plugin += ";path=\(path)" }
            let encoded = plugin.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            ) ?? plugin
            link += "?plugin=\(encoded)"
        } else if let mode = node.obfs?.lowercased(), ["http", "tls"].contains(mode) {
            var plugin = "obfs-local;obfs=\(mode)"
            if let host = node.obfsParam, !host.isEmpty { plugin += ";obfs-host=\(host)" }
            let encoded = plugin.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            ) ?? plugin
            link += "?plugin=\(encoded)"
        }
        return link + "#\(fragment(node.name))"
    }

    private func shadowsocksRLink(for node: ProxyNode) -> String? {
        guard let cipher = node.cipher,
              let password = node.password,
              let protocolName = node.protocolName,
              let obfs = node.obfs else { return nil }

        let encodedPassword = base64URL(Data(password.utf8))
        var queryItems = ["remarks=\(base64URL(Data(node.name.utf8)))"]
        if let protocolParam = node.protocolParam, !protocolParam.isEmpty {
            queryItems.append("protoparam=\(base64URL(Data(protocolParam.utf8)))")
        }
        if let obfsParam = node.obfsParam, !obfsParam.isEmpty {
            queryItems.append("obfsparam=\(base64URL(Data(obfsParam.utf8)))")
        }
        let payload = "\(node.server):\(node.port):\(protocolName):\(cipher):\(obfs):\(encodedPassword)/?\(queryItems.joined(separator: "&"))"
        return "ssr://\(base64URL(Data(payload.utf8)))"
    }

    private func vmessLink(for node: ProxyNode) -> String? {
        guard let uuid = node.uuid else { return nil }
        var object: [String: Any] = [
            "v": "2",
            "ps": node.name,
            "add": node.server,
            "port": String(node.port),
            "id": uuid,
            "aid": String(node.alterID ?? 0),
            "scy": node.cipher ?? "auto",
            "net": node.transport ?? "tcp",
            "type": "none",
            "tls": node.tls ? "tls" : ""
        ]
        if let sni = node.sni { object["sni"] = sni }
        if let host = node.hostHeader { object["host"] = host }
        if let path = node.path { object["path"] = path }
        if let alpn = ALPNList.normalized(node.alpn) { object["alpn"] = alpn }
        if node.skipCertificateVerification { object["allowInsecure"] = true }

        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return "vmess://\(data.base64EncodedString())"
    }

    private func standardLink(for node: ProxyNode) -> String? {
        var components = URLComponents()
        components.scheme = switch node.kind {
        case .vless: "vless"
        case .trojan: "trojan"
        case .hysteria2: "hysteria2"
        case .hysteria: "hysteria"
        case .tuic: "tuic"
        case .anytls: "anytls"
        case .socks5: "socks5"
        case .http: node.tls ? "https" : "http"
        default: nil
        }
        components.host = node.server
        components.port = node.port
        components.fragment = node.name

        switch node.kind {
        case .vless:
            components.user = node.uuid
        // TUIC v5 is the one scheme here that puts a pair in the userinfo.
        case .tuic:
            components.user = node.uuid
            components.password = node.password
        case .trojan, .hysteria, .hysteria2, .anytls:
            components.user = node.password
        case .socks5, .http:
            components.user = node.username
            components.password = node.password
        default:
            break
        }

        var queryItems: [URLQueryItem] = []
        if let transport = node.transport, !transport.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: transport))
        }
        if node.transport == "xhttp", let mode = node.transportMode, !mode.isEmpty {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        if node.usesReality {
            queryItems.append(URLQueryItem(name: "security", value: "reality"))
            queryItems.append(URLQueryItem(name: "pbk", value: node.realityPublicKey))
            if let shortID = node.realityShortID, !shortID.isEmpty {
                queryItems.append(URLQueryItem(name: "sid", value: shortID))
            }
            if let fingerprint = node.fingerprint, !fingerprint.isEmpty {
                queryItems.append(URLQueryItem(name: "fp", value: fingerprint))
            }
            if let flow = node.flow, !flow.isEmpty {
                queryItems.append(URLQueryItem(name: "flow", value: flow))
            }
        } else if node.tls && ![.trojan, .hysteria, .hysteria2, .tuic, .anytls, .http].contains(node.kind) {
            queryItems.append(URLQueryItem(name: "security", value: "tls"))
        }
        // URI producers (including Sub-Store) use `fp` for ordinary
        // VLESS/Trojan/AnyTLS uTLS fingerprints too, not only REALITY.
        if !node.usesReality,
           [.vless, .trojan, .anytls].contains(node.kind),
           let fingerprint = node.fingerprint,
           !fingerprint.isEmpty {
            queryItems.append(URLQueryItem(name: "fp", value: fingerprint))
        }
        // Shadowrocket/Sub-Store's VLESS URI dialect keeps the server
        // certificate pin in `pcs`, independently from the uTLS `fp` value.
        if node.kind == .vless,
           let fingerprint = node.certificateFingerprint,
           !fingerprint.isEmpty {
            queryItems.append(URLQueryItem(name: "pcs", value: fingerprint))
        }
        if let sni = node.sni, !sni.isEmpty {
            queryItems.append(URLQueryItem(name: "sni", value: sni))
        }
        if let host = node.hostHeader, !host.isEmpty {
            queryItems.append(URLQueryItem(name: "host", value: host))
        }
        if let path = node.path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: node.transport == "grpc" ? "serviceName" : "path", value: path))
        }
        if let alpn = ALPNList.normalized(node.alpn) {
            queryItems.append(URLQueryItem(name: "alpn", value: alpn))
        }
        if node.kind == .hysteria2,
           let obfs = node.obfs,
           !obfs.isEmpty,
           obfs.lowercased() != "none" {
            queryItems.append(URLQueryItem(name: "obfs", value: obfs))
            if let password = node.obfsParam, !password.isEmpty {
                queryItems.append(URLQueryItem(name: "obfs-password", value: password))
            }
        }
        if node.kind == .hysteria2,
           let ports = node.portHopping,
           !ports.isEmpty {
            queryItems.append(URLQueryItem(name: "mport", value: ports))
        }
        if node.kind == .hysteria2,
           let fingerprint = node.certificateFingerprint,
           !fingerprint.isEmpty {
            // Hysteria 2 URI producers use pinSHA256 for the certificate pin.
            queryItems.append(URLQueryItem(name: "pinSHA256", value: fingerprint))
        }
        if node.kind == .hysteria {
            if let protocolName = node.protocolName, !protocolName.isEmpty {
                queryItems.append(URLQueryItem(name: "protocol", value: protocolName))
            }
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                queryItems.append(URLQueryItem(name: "obfs", value: obfs))
            }
            if let value = node.upMbps { queryItems.append(URLQueryItem(name: "upmbps", value: String(value))) }
            if let value = node.downMbps {
                queryItems.append(URLQueryItem(name: "downmbps", value: String(value)))
            }
        }
        if node.kind == .tuic {
            if let value = node.congestionControl, !value.isEmpty {
                queryItems.append(URLQueryItem(name: "congestion_control", value: value))
            }
            if let value = node.udpRelayMode, !value.isEmpty {
                queryItems.append(URLQueryItem(name: "udp_relay_mode", value: value))
            }
            if let fingerprint = node.fingerprint, !fingerprint.isEmpty {
                queryItems.append(URLQueryItem(name: "client_fingerprint", value: fingerprint))
            }
            if let ports = node.portHopping, !ports.isEmpty {
                queryItems.append(URLQueryItem(name: "ports", value: ports))
            }
        }
        if node.kind == .anytls {
            if let value = node.idleSessionCheckInterval {
                queryItems.append(URLQueryItem(name: "idle-session-check-interval", value: String(value)))
            }
            if let value = node.idleSessionTimeout {
                queryItems.append(URLQueryItem(name: "idle-session-timeout", value: String(value)))
            }
            if let value = node.minIdleSession {
                queryItems.append(URLQueryItem(name: "min-idle-session", value: String(value)))
            }
        }
        if node.skipCertificateVerification {
            let name = [.hysteria, .hysteria2, .anytls].contains(node.kind)
                ? "insecure"
                : (node.kind == .tuic ? "allow_insecure" : "allowInsecure")
            queryItems.append(URLQueryItem(name: name, value: "1"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.string
    }

    private func wireGuardLink(for node: ProxyNode) -> String? {
        guard let privateKey = node.wireGuardPrivateKey, !privateKey.isEmpty,
              let publicKey = node.wireGuardPublicKey, !publicKey.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "wireguard"
        components.user = privateKey
        components.host = node.server
        components.port = node.port
        components.fragment = node.name
        var addresses: [String] = []
        if let ipv4 = node.wireGuardIPv4, !ipv4.isEmpty { addresses.append(ipv4) }
        if let ipv6 = node.wireGuardIPv6, !ipv6.isEmpty { addresses.append(ipv6) }
        var items = [
            URLQueryItem(name: "publickey", value: publicKey),
            URLQueryItem(name: "address", value: addresses.joined(separator: ",")),
            URLQueryItem(name: "allowedips", value: node.wireGuardAllowedIPs ?? "0.0.0.0/0,::/0")
        ]
        if let value = node.wireGuardReserved, !value.isEmpty {
            items.append(URLQueryItem(name: "reserved", value: value))
        }
        if let value = node.wireGuardMTU { items.append(URLQueryItem(name: "mtu", value: String(value))) }
        if let value = node.wireGuardPersistentKeepalive {
            items.append(URLQueryItem(name: "keepalive", value: String(value)))
        }
        if let value = node.wireGuardPreSharedKey, !value.isEmpty {
            items.append(URLQueryItem(name: "presharedkey", value: value))
        }
        if let value = node.wireGuardDNS, !value.isEmpty {
            items.append(URLQueryItem(name: "dns", value: value))
        }
        components.queryItems = items
        return components.string
    }

    private func snellLine(for node: ProxyNode) -> String {
        var parts = [
            "\(node.name) = snell",
            node.server,
            String(node.port),
            "psk=\(node.password ?? "")",
            "version=\(node.version ?? 4)"
        ]
        if let mode = node.obfs, !mode.isEmpty, mode.lowercased() != "none" {
            parts.append("obfs=\(mode)")
            if let host = node.obfsParam, !host.isEmpty {
                parts.append("obfs-host=\(host)")
            }
        }
        return parts.joined(separator: ", ")
    }

    private func formattedHost(_ host: String) -> String {
        host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }

    private func fragment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? value
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
