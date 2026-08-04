import Foundation

enum SubscriptionError: LocalizedError {
    case invalidURL
    case insecureURL
    case badResponse
    case httpStatus(Int)
    case emptySubscription
    case noSupportedNodes

    var errorDescription: String? {
        switch self {
        case .invalidURL: "订阅地址无效"
        case .insecureURL: "请使用 HTTPS 订阅地址，避免凭据在网络中明文传输"
        case .badResponse: "订阅服务器返回了无法识别的响应"
        case .httpStatus(let status): "订阅服务器返回 HTTP \(status)"
        case .emptySubscription: "订阅内容为空"
        case .noSupportedNodes: "没有找到可识别的节点"
        }
    }
}

struct SubscriptionService {
    var parser = SubscriptionParser()

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        guard let url = URL(string: source.urlString), url.host != nil else {
            throw SubscriptionError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw SubscriptionError.insecureURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Tower/1.0 (iOS; local subscription converter)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionError.badResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SubscriptionError.httpStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else { throw SubscriptionError.emptySubscription }

        let parsed = parser.parse(data: data, sourceID: source.id)
        guard !parsed.nodes.isEmpty else { throw SubscriptionError.noSupportedNodes }
        return ImportResult(
            nodes: parsed.nodes,
            rejectedLineCount: parsed.rejectedLineCount
        )
    }
}

struct SubscriptionParser {
    struct ParsedContent {
        let nodes: [ProxyNode]
        let rejectedLineCount: Int
    }

    func parse(data: Data, sourceID: UUID? = nil) -> ParsedContent {
        guard var text = String(data: data, encoding: .utf8) else {
            return .init(nodes: [], rejectedLineCount: 1)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !containsNodeScheme(text),
           let decoded = decodeBase64String(text),
           containsNodeScheme(decoded) {
            text = decoded
        }

        if text.contains("proxies:") {
            let nodes = parseClashYAML(text, sourceID: sourceID)
            return .init(nodes: deduplicated(nodes), rejectedLineCount: nodes.isEmpty ? 1 : 0)
        }

        let candidates = text
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains(" ") && trimmed.filter({ $0 == ":" }).count > 1 {
                    return trimmed.components(separatedBy: .whitespaces).filter(containsNodeScheme)
                }
                return [trimmed]
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var nodes: [ProxyNode] = []
        var rejected = 0
        for candidate in candidates {
            if let node = parseURI(candidate, sourceID: sourceID) {
                nodes.append(node)
            } else {
                rejected += 1
            }
        }
        return .init(nodes: deduplicated(nodes), rejectedLineCount: rejected)
    }

    func parseURI(_ rawValue: String, sourceID: UUID? = nil) -> ProxyNode? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("ss://") { return parseShadowsocks(value, sourceID: sourceID) }
        if lowercased.hasPrefix("ssr://") { return parseShadowsocksR(value, sourceID: sourceID) }
        if lowercased.hasPrefix("vmess://") { return parseVMess(value, sourceID: sourceID) }
        if lowercased.hasPrefix("vless://") { return parseStandardURL(value, kind: .vless, sourceID: sourceID) }
        if lowercased.hasPrefix("trojan://") { return parseStandardURL(value, kind: .trojan, sourceID: sourceID) }
        if lowercased.hasPrefix("hysteria2://") || lowercased.hasPrefix("hy2://") {
            return parseStandardURL(value, kind: .hysteria2, sourceID: sourceID)
        }
        if lowercased.hasPrefix("socks5://") || lowercased.hasPrefix("socks://") {
            return parseStandardURL(value, kind: .socks5, sourceID: sourceID)
        }
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return parseStandardURL(value, kind: .http, sourceID: sourceID)
        }
        return nil
    }

    private func parseShadowsocks(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let fragmentSplit = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = fragmentSplit.count > 1
            ? String(fragmentSplit[1]).removingPercentEncoding ?? String(fragmentSplit[1])
            : "Shadowsocks"
        var payload = String(fragmentSplit[0]).replacingOccurrences(of: "ss://", with: "", options: [.anchored, .caseInsensitive])
        if let queryIndex = payload.firstIndex(of: "?") {
            let query = String(payload[payload.index(after: queryIndex)...])
            // A SIP003 plugin changes how the node is dialled. Importing it
            // without the plugin would produce a node that looks healthy and
            // never connects, so it is rejected and counted instead.
            if queryDictionary(query)["plugin"]?.isEmpty == false { return nil }
            payload = String(payload[..<queryIndex])
        }

        var auth: String
        var endpoint: String
        if let atIndex = payload.lastIndex(of: "@") {
            let encodedAuth = String(payload[..<atIndex])
            auth = decodeBase64String(encodedAuth) ?? encodedAuth.removingPercentEncoding ?? encodedAuth
            endpoint = String(payload[payload.index(after: atIndex)...])
        } else if let decoded = decodeBase64String(payload), let atIndex = decoded.lastIndex(of: "@") {
            auth = String(decoded[..<atIndex])
            endpoint = String(decoded[decoded.index(after: atIndex)...])
        } else {
            return nil
        }

        guard let separator = auth.firstIndex(of: ":") else { return nil }
        let method = String(auth[..<separator])
        let password = String(auth[auth.index(after: separator)...])
        guard let address = parseEndpoint(endpoint) else { return nil }

        return ProxyNode(
            sourceID: sourceID,
            kind: .shadowsocks,
            name: normalizedName(name, fallback: address.host),
            server: address.host,
            port: address.port,
            cipher: method,
            password: password,
            rawURI: raw
        )
    }

    private func parseShadowsocksR(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let encoded = String(raw.dropFirst("ssr://".count))
        guard let decoded = decodeBase64String(encoded) else { return nil }
        let sections = decoded.components(separatedBy: "/?")
        let main = sections[0].split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard main.count == 6, let port = Int(main[1]), let password = decodeBase64String(main[5]) else { return nil }

        let query = sections.count > 1 ? queryDictionary(sections[1]) : [:]
        let remarks = query["remarks"].flatMap(decodeBase64String) ?? main[0]
        return ProxyNode(
            sourceID: sourceID,
            kind: .shadowsocksR,
            name: normalizedName(remarks, fallback: main[0]),
            server: main[0],
            port: port,
            cipher: main[3],
            password: password,
            protocolName: main[2],
            protocolParam: query["protoparam"].flatMap(decodeBase64String),
            obfs: main[4],
            obfsParam: query["obfsparam"].flatMap(decodeBase64String),
            rawURI: raw
        )
    }

    private func parseVMess(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let encoded = String(raw.dropFirst("vmess://".count))
        guard let decoded = decodeBase64String(encoded),
              let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = stringValue(json["add"]),
              let port = intValue(json["port"]),
              let uuid = stringValue(json["id"]) else { return nil }

        let tlsValue = stringValue(json["tls"])?.lowercased()
        return ProxyNode(
            sourceID: sourceID,
            kind: .vmess,
            name: normalizedName(stringValue(json["ps"]), fallback: server),
            server: server,
            port: port,
            cipher: stringValue(json["scy"]) ?? "auto",
            uuid: uuid,
            transport: stringValue(json["net"]) ?? "tcp",
            tls: tlsValue == "tls" || tlsValue == "true",
            sni: stringValue(json["sni"]),
            hostHeader: stringValue(json["host"]),
            path: stringValue(json["path"]),
            alpn: stringValue(json["alpn"]),
            skipCertificateVerification: boolValue(json["allowInsecure"]),
            alterID: intValue(json["aid"]),
            rawURI: raw
        )
    }

    private func parseStandardURL(_ raw: String, kind: ProxyKind, sourceID: UUID?) -> ProxyNode? {
        var normalized = raw
        if normalized.lowercased().hasPrefix("hy2://") {
            normalized = "hysteria2://" + normalized.dropFirst("hy2://".count)
        } else if normalized.lowercased().hasPrefix("socks://") {
            normalized = "socks5://" + normalized.dropFirst("socks://".count)
        }
        guard let components = URLComponents(string: normalized),
              let rawHost = components.host,
              let port = components.port else { return nil }
        let server = normalizedHost(rawHost)

        let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }) { _, new in new }
        let fallback = "\(kind.title) · \(server)"
        let name = normalizedName(components.fragment?.removingPercentEncoding, fallback: fallback)
        let transport = query["type"] ?? query["network"] ?? (query["obfs"]?.contains("ws") == true ? "ws" : nil)
        let security = (query["security"] ?? query["tls"] ?? "").lowercased()
        let credential = components.user?.removingPercentEncoding

        return ProxyNode(
            sourceID: sourceID,
            kind: kind,
            name: name,
            server: server,
            port: port,
            password: [.trojan, .hysteria2].contains(kind) ? credential : components.password?.removingPercentEncoding,
            uuid: [.vmess, .vless].contains(kind) ? credential : nil,
            username: [.socks5, .http].contains(kind) ? credential : nil,
            transport: transport,
            tls: kind == .trojan || kind == .hysteria2 || security == "tls" || security == "reality" || security == "true" || normalized.lowercased().hasPrefix("https://"),
            sni: query["sni"] ?? query["servername"] ?? query["peer"],
            hostHeader: query["host"],
            path: query["path"],
            alpn: query["alpn"],
            skipCertificateVerification: ["1", "true"].contains(query["allowinsecure"] ?? query["insecure"] ?? ""),
            rawURI: raw
        )
    }

    private func parseClashYAML(_ text: String, sourceID: UUID?) -> [ProxyNode] {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "proxies:" }) else { return [] }

        var dictionaries: [[String: String]] = []
        var current: [String: String] = [:]
        var inside = false

        for rawLine in lines.dropFirst(start + 1) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indentation = rawLine.prefix { $0 == " " }.count
            if indentation == 0 && !trimmed.hasPrefix("-") { break }

            if trimmed.hasPrefix("-") {
                if !current.isEmpty { dictionaries.append(current) }
                current = [:]
                inside = true
                let remainder = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if remainder.hasPrefix("{") {
                    current.merge(parseInlineYAMLMap(String(remainder))) { _, new in new }
                } else if let pair = parseYAMLPair(String(remainder)) {
                    current[pair.0] = pair.1
                }
            } else if inside, let pair = parseYAMLPair(trimmed) {
                current[pair.0] = pair.1
            }
        }
        if !current.isEmpty { dictionaries.append(current) }

        return dictionaries.compactMap { dictionary in
            guard let type = dictionary["type"]?.lowercased(),
                  let kind = clashKind(type),
                  let rawServer = dictionary["server"],
                  let port = Int(dictionary["port"] ?? "") else { return nil }
            let server = normalizedHost(rawServer)
            return ProxyNode(
                sourceID: sourceID,
                kind: kind,
                name: normalizedName(dictionary["name"], fallback: server),
                server: server,
                port: port,
                cipher: dictionary["cipher"],
                password: dictionary["password"],
                uuid: dictionary["uuid"],
                username: dictionary["username"],
                transport: dictionary["network"],
                tls: boolString(dictionary["tls"]),
                sni: dictionary["servername"] ?? dictionary["sni"],
                hostHeader: dictionary["host"],
                path: dictionary["path"],
                alpn: dictionary["alpn"],
                skipCertificateVerification: boolString(dictionary["skip-cert-verify"]),
                alterID: Int(dictionary["alterid"] ?? dictionary["alter-id"] ?? ""),
                protocolName: dictionary["protocol"],
                protocolParam: dictionary["protocol-param"],
                obfs: dictionary["obfs"],
                obfsParam: dictionary["obfs-param"],
                rawURI: "clash://local/\(UUID().uuidString)"
            )
        }
    }

    private func parseInlineYAMLMap(_ value: String) -> [String: String] {
        let body = value.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
        var pieces: [String] = []
        var current = ""
        var quote: Character?
        var depth = 0
        for character in body {
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
            } else if quote == nil {
                if "[{".contains(character) { depth += 1 }
                if "]}".contains(character) { depth -= 1 }
                if character == "," && depth == 0 {
                    pieces.append(current)
                    current = ""
                    continue
                }
            }
            current.append(character)
        }
        if !current.isEmpty { pieces.append(current) }
        return Dictionary(pieces.compactMap(parseYAMLPair)) { _, new in new }
    }

    private func parseYAMLPair(_ value: String) -> (String, String)? {
        guard let separator = value.firstIndex(of: ":") else { return nil }
        let key = value[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = value[value.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return key.isEmpty ? nil : (key.lowercased(), cleaned)
    }

    private func clashKind(_ value: String) -> ProxyKind? {
        switch value {
        case "ss": .shadowsocks
        case "ssr": .shadowsocksR
        case "vmess": .vmess
        case "vless": .vless
        case "trojan": .trojan
        case "hysteria2", "hy2": .hysteria2
        case "socks5", "socks": .socks5
        case "http", "https": .http
        default: nil
        }
    }

    private func parseEndpoint(_ value: String) -> (host: String, port: Int)? {
        guard let components = URLComponents(string: "tcp://\(value)"),
              let host = components.host,
              let port = components.port else { return nil }
        return (normalizedHost(host), port)
    }

    /// `URLComponents.host` keeps the brackets around an IPv6 literal. Storing
    /// them would break `inet_pton` in the offline country database, the
    /// `getaddrinfo` latency probe, and the generated Clash `server` field, so
    /// the address is kept bare and re-bracketed only where a format needs it.
    private func normalizedHost(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    // A malformed or simply repetitive query string can repeat a key. Keeping
    // the last occurrence matches how the clients read these links; the
    // uniquing initialiser would trap instead.
    private func queryDictionary(_ query: String) -> [String: String] {
        Dictionary(
            query.split(separator: "&").compactMap { item in
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { return nil }
                return (String(pair[0]), String(pair[1]))
            },
            uniquingKeysWith: { _, new in new }
        )
    }

    private func containsNodeScheme(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return [
            "ss://", "ssr://", "vmess://", "vless://", "trojan://",
            "hysteria2://", "hy2://", "socks5://", "socks://", "http://", "https://"
        ]
            .contains(where: lowercased.contains)
    }

    private func decodeBase64String(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        let remainder = normalized.count % 4
        if remainder != 0 { normalized.append(String(repeating: "=", count: 4 - remainder)) }
        guard let data = Data(base64Encoded: normalized, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func normalizedName(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return boolString(value) }
        return false
    }

    private func boolString(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "yes", "tls"].contains(value.lowercased())
    }

    private func deduplicated(_ nodes: [ProxyNode]) -> [ProxyNode] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.canonicalKey).inserted }
    }
}
