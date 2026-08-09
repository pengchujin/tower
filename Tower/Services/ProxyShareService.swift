import Foundation

struct SharePayload: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let value: String
    let symbol: String
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
            symbol: node.kind.symbol
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
        case .vless, .trojan, .hysteria2, .anytls, .socks5, .http:
            standardLink(for: node) ?? original
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
            "hysteria2://", "hy2://", "anytls://", "socks5://", "socks://", "http://", "https://"
        ].contains(where: lowercased.hasPrefix)
    }

    private func shadowsocksLink(for node: ProxyNode) -> String? {
        guard let cipher = node.cipher, let password = node.password else { return nil }
        let auth = base64URL(Data("\(cipher):\(password)".utf8))
        var link = "ss://\(auth)@\(formattedHost(node.server)):\(node.port)"

        // Dropping the plugin would hand out a link that looks fine and cannot
        // connect, which is exactly what the importer refuses to accept.
        if let mode = node.obfs?.lowercased(), ["http", "tls"].contains(mode) {
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
        if let alpn = node.alpn { object["alpn"] = alpn }
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
        case .trojan, .hysteria2, .anytls:
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
        } else if node.tls && ![.trojan, .hysteria2, .anytls, .http].contains(node.kind) {
            queryItems.append(URLQueryItem(name: "security", value: "tls"))
        }
        if let sni = node.sni, !sni.isEmpty {
            queryItems.append(URLQueryItem(name: "sni", value: sni))
        }
        if let host = node.hostHeader, !host.isEmpty {
            queryItems.append(URLQueryItem(name: "host", value: host))
        }
        if let path = node.path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        if let alpn = node.alpn, !alpn.isEmpty {
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
            let name = [.hysteria2, .anytls].contains(node.kind) ? "insecure" : "allowInsecure"
            queryItems.append(URLQueryItem(name: name, value: "1"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
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
