import Foundation
import Network

enum SubscriptionError: LocalizedError {
    case invalidURL
    case invalidDNSURL
    case badResponse
    case httpStatus(Int)
    case emptySubscription
    case noSupportedNodes

    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "订阅地址无效")
        case .invalidDNSURL: String(localized: "自定义 DNS 必须是 HTTPS 的 DNS-over-HTTPS 地址")
        case .badResponse: String(localized: "订阅服务器返回了无法识别的响应")
        case .httpStatus(let status): String(localized: "订阅服务器返回 HTTP \(status)")
        case .emptySubscription: String(localized: "订阅内容为空")
        case .noSupportedNodes: String(localized: "没有找到可识别的节点")
        }
    }
}

protocol SubscriptionFetching {
    func fetch(_ source: SubscriptionSource) async throws -> ImportResult
}

struct SubscriptionService: SubscriptionFetching {
    var parser: SubscriptionParser
    private let requestBuilder: SubscriptionRequestBuilder
    private let httpClient: any SubscriptionHTTPDataLoading

    init(
        parser: SubscriptionParser = SubscriptionParser(),
        requestBuilder: SubscriptionRequestBuilder = SubscriptionRequestBuilder(),
        httpClient: any SubscriptionHTTPDataLoading = SubscriptionHTTPClient()
    ) {
        self.parser = parser
        self.requestBuilder = requestBuilder
        self.httpClient = httpClient
    }

    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        guard let url = URL(string: source.urlString), url.host != nil else {
            throw SubscriptionError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw SubscriptionError.invalidURL
        }

        async let fallbackUsage: SubscriptionUsage? = {
            guard let probe = Self.quotaProbe(for: url) else { return nil }
            return try? await quota(at: probe, source: source)
        }()
        var result = try await load(url, source: source)

        // The node list is authoritative for nodes; only the quota may be
        // missing from it. Airports that answer `flag=clash` send a
        // `subscription-userinfo` header, so a second request fills the gap —
        // but its body is not used, because the panel's Clash converter drops
        // whatever it cannot express. One real airport returns 43 of its 55
        // nodes that way, silently losing every AnyTLS entry.
        if result.usage?.hasPlanDetail != true {
            if let usage = await fallbackUsage {
                var merged = usage
                merged.notices = result.usage?.notices ?? []
                result.usage = merged
            }
        } else {
            _ = await fallbackUsage
        }
        return result
    }

    /// The same subscription asked for in Clash's dialect, purely to read the
    /// quota header. `nil` when the caller already pinned a flag themselves.
    private static func quotaProbe(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let existing = components.queryItems ?? []
        guard !existing.contains(where: { $0.name.lowercased() == "flag" }) else { return nil }
        components.queryItems = existing + [URLQueryItem(name: "flag", value: "clash")]
        return components.url
    }

    private func quota(at url: URL, source: SubscriptionSource) async throws -> SubscriptionUsage {
        let request = try requestBuilder.make(url: url, source: source, timeout: 15)
        let dnsURL = try source.requestOptions?.validatedDNSOverHTTPSURL()
        let (_, response) = try await httpClient.data(for: request, dnsOverHTTPSURL: dnsURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let header = httpResponse.value(forHTTPHeaderField: "subscription-userinfo"),
              let usage = SubscriptionUsage.parse(header: header) else {
            throw SubscriptionError.badResponse
        }
        return usage
    }

    private func load(_ url: URL, source: SubscriptionSource) async throws -> ImportResult {
        let dnsURL = try source.requestOptions?.validatedDNSOverHTTPSURL()
        let customUserAgent = source.requestOptions?.userAgent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowsCompatibilityFallback = customUserAgent?.isEmpty != false
        let fallbackUserAgents = allowsCompatibilityFallback
            ? SubscriptionRequestBuilder.compatibilityUserAgents
            : []
        let userAgentAttempts: [String?] = [nil] + fallbackUserAgents.map(Optional.some)

        for (index, fallbackUserAgent) in userAgentAttempts.enumerated() {
            let request = try requestBuilder.make(
                url: url,
                source: source,
                timeout: 30,
                overridingUserAgent: fallbackUserAgent
            )
            let (data, response) = try await httpClient.data(
                for: request,
                dnsOverHTTPSURL: dnsURL
            )
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SubscriptionError.badResponse
            }
            let hasAnotherAttempt = index < userAgentAttempts.count - 1
            guard (200..<300).contains(httpResponse.statusCode) else {
                if hasAnotherAttempt, Self.isClientGatingResponse(response) {
                    continue
                }
                throw SubscriptionError.httpStatus(httpResponse.statusCode)
            }
            guard !data.isEmpty else {
                if hasAnotherAttempt { continue }
                throw SubscriptionError.emptySubscription
            }

            let parsed = parser.parse(data: data, sourceID: source.id)
            guard !parsed.nodes.isEmpty else {
                if hasAnotherAttempt { continue }
                throw SubscriptionError.noSupportedNodes
            }

            // Only this one header is read. Keeping the whole response would drag
            // cookies and other session state into app state for no reason.
            let header = httpResponse.value(forHTTPHeaderField: "subscription-userinfo")
                .flatMap(SubscriptionUsage.parse(header:))
            var usage = header ?? parsed.status ?? SubscriptionUsage()
            usage.notices = parsed.notices

            return ImportResult(
                nodes: parsed.nodes,
                rejectedLineCount: parsed.rejectedLineCount,
                usage: usage.isEmpty ? nil : usage,
                suggestedName: Self.providerTitle(from: httpResponse)
            )
        }

        throw SubscriptionError.noSupportedNodes
    }

    private static func isClientGatingResponse(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return SubscriptionRequestBuilder.clientGatingStatusCodes.contains(httpResponse.statusCode)
    }

    /// Reads the same profile naming hints used by modern subscription apps.
    /// Hiddify documents `Profile-Title` as the first-priority value and allows
    /// a base64 UTF-8 form for names containing emoji.
    static func providerTitle(from response: HTTPURLResponse) -> String? {
        for header in ["Profile-Title", "Subscription-Title"] {
            if let value = response.value(forHTTPHeaderField: header),
               let decoded = decodedProfileTitle(value) {
                return decoded
            }
        }

        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }
        let pattern = #"filename\*?=(?:UTF-8''|\")?([^\";]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: disposition,
                range: NSRange(disposition.startIndex..., in: disposition)
              ),
              let range = Range(match.range(at: 1), in: disposition) else { return nil }
        let fileName = String(disposition[range]).removingPercentEncoding ?? String(disposition[range])
        let stem = (fileName as NSString).deletingPathExtension
        return decodedProfileTitle(stem)
    }

    private static func decodedProfileTitle(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
        let decoded: String
        if trimmed.lowercased().hasPrefix("base64:"),
           let data = Data(base64Encoded: String(trimmed.dropFirst("base64:".count))),
           let value = String(data: data, encoding: .utf8) {
            decoded = value
        } else {
            decoded = trimmed.removingPercentEncoding ?? trimmed
        }
        let result = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

struct SubscriptionRequestBuilder {
    static let shadowrocketCompatibilityUserAgent =
        "Shadowrocket/3378 CFNetwork/3892.100.1 Darwin/27.0.0"
    static let defaultUserAgent = shadowrocketCompatibilityUserAgent
    static let clientGatingStatusCodes: Set<Int> = [403, 406, 421, 426]
    static let clashMetaCompatibilityUserAgent = "clash.meta"
    static let compatibilityUserAgents = [clashMetaCompatibilityUserAgent]

    func make(
        url: URL,
        source: SubscriptionSource,
        timeout: TimeInterval,
        overridingUserAgent: String? = nil
    ) throws -> URLRequest {
        _ = try source.requestOptions?.validatedDNSOverHTTPSURL()
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let custom = source.requestOptions?.userAgent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue(
            overridingUserAgent ?? (custom?.isEmpty == false ? custom : Self.defaultUserAgent),
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }
}

/// Allows ordinary subscription requests to run together while reserving
/// exclusive access for a request that temporarily changes Network.framework's
/// process-wide encrypted resolver.
actor SubscriptionRequestGate {
    private struct Waiter {
        let needsExclusiveAccess: Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private var activeReaders = 0
    private var hasActiveWriter = false
    private var waiters: [Waiter] = []

    func acquire(needsExclusiveAccess: Bool) async {
        if needsExclusiveAccess {
            if !hasActiveWriter, activeReaders == 0 {
                hasActiveWriter = true
                return
            }
        } else if !hasActiveWriter,
                  !waiters.contains(where: \.needsExclusiveAccess) {
            activeReaders += 1
            return
        }
        await withCheckedContinuation {
            waiters.append(Waiter(needsExclusiveAccess: needsExclusiveAccess, continuation: $0))
        }
    }

    func release(wasExclusiveAccess: Bool) {
        if wasExclusiveAccess {
            hasActiveWriter = false
        } else {
            activeReaders -= 1
        }
        resumeEligibleWaiters()
    }

    private func resumeEligibleWaiters() {
        guard !hasActiveWriter, activeReaders == 0, !waiters.isEmpty else { return }
        if waiters[0].needsExclusiveAccess {
            hasActiveWriter = true
            waiters.removeFirst().continuation.resume()
            return
        }

        while !waiters.isEmpty, !waiters[0].needsExclusiveAccess {
            activeReaders += 1
            waiters.removeFirst().continuation.resume()
        }
    }
}

protocol SubscriptionHTTPDataLoading {
    func data(
        for request: URLRequest,
        dnsOverHTTPSURL: URL?
    ) async throws -> (Data, URLResponse)
}

struct SubscriptionHTTPClient: SubscriptionHTTPDataLoading {
    private static let gate = SubscriptionRequestGate()

    func data(
        for request: URLRequest,
        dnsOverHTTPSURL: URL?
    ) async throws -> (Data, URLResponse) {
        let needsExclusiveAccess = dnsOverHTTPSURL != nil
        await Self.gate.acquire(needsExclusiveAccess: needsExclusiveAccess)
        if let dnsOverHTTPSURL { applyDNSOverHTTPS(dnsOverHTTPSURL) }

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            let result = try await session.data(for: request)
            session.finishTasksAndInvalidate()
            if dnsOverHTTPSURL != nil { resetDNS() }
            await Self.gate.release(wasExclusiveAccess: needsExclusiveAccess)
            return result
        } catch {
            if dnsOverHTTPSURL != nil { resetDNS() }
            await Self.gate.release(wasExclusiveAccess: needsExclusiveAccess)
            throw error
        }
    }

    private func applyDNSOverHTTPS(_ url: URL) {
        let context = NWParameters.PrivacyContext.default
        context.requireEncryptedNameResolution(
            true,
            fallbackResolver: .https(url, serverAddresses: [])
        )
        context.flushCache()
    }

    private func resetDNS() {
        let context = NWParameters.PrivacyContext.default
        context.requireEncryptedNameResolution(
            false,
            fallbackResolver: nil
        )
        context.flushCache()
    }
}

struct SubscriptionParser {
    struct ParsedContent {
        let nodes: [ProxyNode]
        let rejectedLineCount: Int
        /// Airport announcements smuggled into the node list — remaining
        /// traffic, expiry and the like.
        var notices: [String] = []
        /// Quota read from a `STATUS=` line at the head of the list, for the
        /// panels that put it there instead of in the response header.
        var status: SubscriptionUsage?
    }

    /// Names that are an announcement rather than a node.
    ///
    /// Several airports publish quota and expiry as extra entries whose only
    /// real content is the name. Importing them yields nodes that cannot
    /// connect and inflates the node count, so they become subscription
    /// metadata instead. The list is deliberately narrow: a real node is not
    /// called 剩余流量 or 套餐到期, but it may well be called 香港 IEPL 专线.
    private static let noticeKeywords = [
        "剩余流量", "已用流量", "总流量", "流量重置", "距离下次重置", "重置剩余",
        "套餐到期", "到期时间", "过期时间", "有效期至", "账户余额",
        "官网", "续费", "客服", "邮箱", "订阅地址", "机场地址",
        "expire", "expires", "traffic", "remaining", "reset"
    ]

    /// Hosts an airport parks its announcement entries on so they look like
    /// nodes. No real proxy runs on a public resolver.
    private static let placeholderHosts: Set<String> = [
        "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1", "223.5.5.5",
        "127.0.0.1", "0.0.0.0", "localhost", "example.com"
    ]

    static func isNotice(_ name: String) -> Bool {
        let text = name.lowercased()
        return noticeKeywords.contains { text.contains($0.lowercased()) }
    }

    /// Announcements the keyword list misses still give themselves away by
    /// where they point: one airport advertises its client this way, with the
    /// pitch as the name and `8.8.8.8:8` as the endpoint.
    static func isNotice(_ node: ProxyNode) -> Bool {
        isNotice(node.name) || placeholderHosts.contains(node.server.lowercased())
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
            let parsed = parseClashYAML(text, sourceID: sourceID)
            let marked = parsed.nodes.map(markingSubscriptionMetadata)
            let notices = marked.filter { $0.isSubscriptionMetadata == true }.map(\.name)
            return .init(
                nodes: deduplicated(marked),
                rejectedLineCount: parsed.rejectedLineCount,
                notices: notices,
                status: notices.lazy.compactMap(SubscriptionUsage.parse(statusLine:)).first
            )
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
        var status: SubscriptionUsage?
        for candidate in candidates {
            // Not a node and not a failure: some panels lead with the quota.
            if candidate.hasPrefix(SubscriptionUsage.statusPrefix) {
                status = status ?? SubscriptionUsage.parse(statusLine: candidate)
                continue
            }
            if let node = parseURI(candidate, sourceID: sourceID) {
                nodes.append(node)
            } else {
                rejected += 1
            }
        }
        let marked = nodes.map(markingSubscriptionMetadata)
        let notices = marked.filter { $0.isSubscriptionMetadata == true }.map(\.name)
        return .init(
            nodes: deduplicated(marked),
            rejectedLineCount: rejected,
            notices: notices,
            // Other panels write the same line in as a node remark.
            status: status ?? notices.lazy.compactMap(SubscriptionUsage.parse(statusLine:)).first
        )
    }

    func parseURI(_ rawValue: String, sourceID: UUID? = nil) -> ProxyNode? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = value.lowercased()
        // Snell has no URI form at all. It is shared as the Surge proxy line it
        // is written as, so that line is what Tower accepts.
        if let snell = parseSnellLine(value, sourceID: sourceID) { return snell }
        if lowercased.hasPrefix("ss://") { return parseShadowsocks(value, sourceID: sourceID) }
        if lowercased.hasPrefix("ssr://") { return parseShadowsocksR(value, sourceID: sourceID) }
        if lowercased.hasPrefix("vmess://") { return parseVMess(value, sourceID: sourceID) }
        if lowercased.hasPrefix("vless://") {
            return parseStandardURL(value, kind: .vless, sourceID: sourceID)
                ?? parseLegacyVLESS(value, sourceID: sourceID)
        }
        if lowercased.hasPrefix("trojan://") { return parseStandardURL(value, kind: .trojan, sourceID: sourceID) }
        if lowercased.hasPrefix("anytls://") { return parseStandardURL(value, kind: .anytls, sourceID: sourceID) }
        if lowercased.hasPrefix("hysteria2://") || lowercased.hasPrefix("hy2://") {
            return parseStandardURL(value, kind: .hysteria2, sourceID: sourceID)
        }
        // Checked after hysteria2 so `hysteria2://` never falls in here.
        if lowercased.hasPrefix("hysteria://") || lowercased.hasPrefix("hy://") {
            return parseStandardURL(value, kind: .hysteria, sourceID: sourceID)
        }
        if lowercased.hasPrefix("tuic://") { return parseStandardURL(value, kind: .tuic, sourceID: sourceID) }
        if lowercased.hasPrefix("wireguard://") || lowercased.hasPrefix("wg://") {
            return parseWireGuardURL(value, sourceID: sourceID)
        }
        if lowercased.hasPrefix("socks5://") || lowercased.hasPrefix("socks://") {
            return parseStandardURL(value, kind: .socks5, sourceID: sourceID)
        }
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            // Shadowrocket also exports HTTP(S) nodes as
            // `https://base64(user:password@host:port)?remarks=...`. Try that
            // dialect before the standard URL form; otherwise the encoded
            // authority itself can be mistaken for the proxy hostname.
            return parseShadowrocketHTTPURL(value, sourceID: sourceID)
                ?? parseStandardURL(value, kind: .http, sourceID: sourceID)
        }
        return nil
    }

    /// Sub-Store's portable single-peer URI. A WireGuard endpoint is not a
    /// generic username/password proxy: the local address and allowed routes
    /// are required to make the tunnel meaningful, so every field is retained.
    private func parseWireGuardURL(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let normalized = raw.lowercased().hasPrefix("wg://")
            ? "wireguard://" + raw.dropFirst("wg://".count)
            : raw
        guard let components = URLComponents(string: normalized),
              let rawHost = components.host else { return nil }
        let query = Dictionary((components.queryItems ?? []).map {
            ($0.name.lowercased(), $0.value ?? "")
        }) { _, new in new }
        let addresses = csvValues(query["address"] ?? query["addresses"] ?? "")
        let ipv4 = addresses.first { !$0.contains(":") }
        let ipv6 = addresses.first { $0.contains(":") }
        let server = normalizedHost(rawHost)
        return ProxyNode(
            sourceID: sourceID,
            kind: .wireguard,
            name: normalizedName(components.fragment?.removingPercentEncoding, fallback: "WireGuard · \(server)"),
            server: server,
            port: components.port ?? 51_820,
            wireGuardPrivateKey: components.user?.removingPercentEncoding,
            wireGuardPublicKey: query["publickey"] ?? query["public-key"],
            wireGuardPreSharedKey: query["presharedkey"] ?? query["pre-shared-key"] ?? query["preshared-key"],
            wireGuardIPv4: ipv4,
            wireGuardIPv6: ipv6,
            wireGuardAllowedIPs: csvValues(query["allowedips"] ?? query["allowed-ips"] ?? "0.0.0.0/0,::/0").joined(separator: ","),
            wireGuardReserved: csvValues(query["reserved"] ?? "").joined(separator: ","),
            wireGuardMTU: Int(query["mtu"] ?? ""),
            wireGuardPersistentKeepalive: Int(query["keepalive"] ?? query["persistent-keepalive"] ?? ""),
            wireGuardDNS: csvValues(query["dns"] ?? query["dns-server"] ?? "").joined(separator: ","),
            rawURI: raw
        )
    }

    private func parseShadowsocks(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let fragmentSplit = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = fragmentSplit.count > 1
            ? String(fragmentSplit[1]).removingPercentEncoding ?? String(fragmentSplit[1])
            : "Shadowsocks"
        var payload = String(fragmentSplit[0]).replacingOccurrences(of: "ss://", with: "", options: [.anchored, .caseInsensitive])
        var obfsMode: String?
        var obfsHost: String?
        var sip003Plugin: String?
        var pluginTransport: String?
        var pluginPath: String?
        var pluginTLS = false
        if let queryIndex = payload.firstIndex(of: "?") {
            let query = String(payload[payload.index(after: queryIndex)...])
            // A SIP003 plugin changes how the node is dialled. simple-obfs is
            // carried over because every target format can express it; any
            // other plugin would import as a node that looks healthy and never
            // connects, so it is rejected and counted instead.
            if let plugin = queryDictionary(query)["plugin"]?.removingPercentEncoding,
               !plugin.isEmpty {
                if let options = simpleObfsOptions(from: plugin) {
                    obfsMode = options.mode
                    obfsHost = options.host
                } else if let options = v2rayPluginOptions(from: plugin) {
                    sip003Plugin = "v2ray-plugin"
                    pluginTransport = options.transport
                    obfsHost = options.host
                    pluginPath = options.path
                    pluginTLS = options.tls
                } else {
                    return nil
                }
            }
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
            transport: pluginTransport,
            plugin: sip003Plugin,
            tls: pluginTLS,
            hostHeader: obfsHost,
            path: pluginPath,
            obfs: obfsMode,
            obfsParam: sip003Plugin == nil ? obfsHost : nil,
            rawURI: raw
        )
    }

    /// Reads a SIP003 plugin string such as
    /// `obfs-local;obfs=http;obfs-host=www.example.com`.
    /// Returns nil for plugins Tower cannot reproduce faithfully.
    private func simpleObfsOptions(from plugin: String) -> (mode: String, host: String?)? {
        let parts = plugin.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let name = parts.first?.lowercased(),
              ["obfs", "obfs-local", "simple-obfs"].contains(name) else { return nil }

        var mode = "http"
        var host: String?
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            if key == "obfs" || key == "mode" {
                mode = value
            } else if key == "obfs-host" || key == "host" {
                host = value
            }
        }
        return (mode, host)
    }

    private func v2rayPluginOptions(
        from plugin: String
    ) -> (transport: String, host: String?, path: String?, tls: Bool)? {
        let parts = plugin.split(separator: ";", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.first?.lowercased() == "v2ray-plugin" else { return nil }
        var mode = "websocket"
        var host: String?
        var path: String?
        var tls = false
        for part in parts.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = pair[0].lowercased()
            if pair.count == 1 {
                if key == "tls" { tls = true }
                continue
            }
            let value = String(pair[1])
            switch key {
            case "mode", "obfs": mode = value
            case "host", "obfs-host": host = value
            case "path": path = value
            case "tls": tls = boolString(value)
            default: break
            }
        }
        guard ["websocket", "ws"].contains(mode.lowercased()) else { return nil }
        return ("ws", host, path, tls)
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
        guard let decoded = decodeBase64String(encoded.split(separator: "?", maxSplits: 1).first.map(String.init) ?? encoded),
              let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = stringValue(json["add"]),
              let port = intValue(json["port"]),
              let uuid = stringValue(json["id"]) else {
            // Not the base64-JSON form. Shadowrocket and friends instead encode
            // `method:uuid@host:port` and hang the rest off a query string.
            return parseLegacyVMess(raw, sourceID: sourceID)
        }

        let tlsValue = stringValue(json["tls"])?.lowercased()
        let rawTransport = stringValue(json["net"])
            ?? stringValue(json["network"])
            ?? stringValue(json["type"])
        return ProxyNode(
            sourceID: sourceID,
            kind: .vmess,
            name: normalizedName(stringValue(json["ps"]), fallback: server),
            server: server,
            port: port,
            cipher: stringValue(json["scy"]) ?? "auto",
            uuid: uuid,
            transport: normalizedVMessTransport(rawTransport) ?? "tcp",
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

    /// A Surge proxy line: `名称 = snell, 主机, 端口, psk=…, version=4, obfs=http`.
    ///
    /// Positional fields come first, then `key=value` options in any order.
    private func parseSnellLine(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        guard let separator = raw.firstIndex(of: "=") else { return nil }
        let name = String(raw[..<separator]).trimmingCharacters(in: .whitespaces)
        let body = String(raw[raw.index(after: separator)...])
        let fields = body.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty,
              fields.first?.lowercased() == "snell",
              fields.count >= 3,
              let port = Int(fields[2]) else { return nil }

        let server = normalizedHost(fields[1])
        guard !server.isEmpty else { return nil }

        var options: [String: String] = [:]
        for field in fields.dropFirst(3) {
            guard let equals = field.firstIndex(of: "=") else { continue }
            let key = String(field[..<equals]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(field[field.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            options[key] = value
        }
        guard let psk = options["psk"], !psk.isEmpty else { return nil }

        return ProxyNode(
            sourceID: sourceID,
            kind: .snell,
            name: name,
            server: server,
            port: port,
            password: psk,
            hostHeader: options["obfs-host"],
            obfs: options["obfs"],
            obfsParam: options["obfs-host"],
            version: Int(options["version"] ?? ""),
            rawURI: raw
        )
    }

    /// `vmess://base64(method:uuid@host:port)?remarks=…&obfs=…&tls=1`.
    ///
    /// Only the endpoint is base64; the options stay readable in the query, and
    /// the transport is named `obfs` rather than `net`.
    private func parseLegacyVMess(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        var body = String(raw.dropFirst("vmess://".count))
        if let fragment = body.firstIndex(of: "#") { body = String(body[..<fragment]) }

        let parts = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let decoded = decodeBase64String(String(parts[0])) else { return nil }
        let query = parts.count > 1
            ? Dictionary(
                queryDictionary(String(parts[1])).map { ($0.key.lowercased(), $0.value) },
                uniquingKeysWith: { _, new in new }
            )
            : [:]

        guard let atIndex = decoded.lastIndex(of: "@") else { return nil }
        let auth = String(decoded[..<atIndex])
        guard let address = parseEndpoint(String(decoded[decoded.index(after: atIndex)...])) else {
            return nil
        }

        // The credential half is `method:uuid`; a bare uuid is also accepted.
        let cipher: String
        let uuid: String
        if let separator = auth.firstIndex(of: ":") {
            cipher = String(auth[..<separator])
            uuid = String(auth[auth.index(after: separator)...])
        } else {
            cipher = "auto"
            uuid = auth
        }
        guard !uuid.isEmpty else { return nil }

        let obfs = query["obfs"]?.removingPercentEncoding
        let transport = normalizedVMessTransport(obfs)
        let name = query["remarks"]?.removingPercentEncoding
            ?? raw.split(separator: "#", maxSplits: 1).dropFirst().first
                .map(String.init)?.removingPercentEncoding

        return ProxyNode(
            sourceID: sourceID,
            kind: .vmess,
            name: normalizedName(name, fallback: address.host),
            server: address.host,
            port: address.port,
            cipher: cipher.isEmpty ? "auto" : cipher,
            uuid: uuid,
            transport: transport,
            tls: ["1", "true", "tls"].contains(query["tls"]?.lowercased() ?? ""),
            sni: query["peer"]?.removingPercentEncoding ?? query["sni"]?.removingPercentEncoding,
            hostHeader: query["obfsparam"]?.removingPercentEncoding
                ?? query["host"]?.removingPercentEncoding,
            path: query["path"]?.removingPercentEncoding,
            skipCertificateVerification: ["1", "true"].contains(
                query["allowinsecure"]?.lowercased() ?? query["tls-verification"]?.lowercased() ?? ""
            ),
            alterID: Int(query["alterid"] ?? ""),
            rawURI: raw
        )
    }

    private func normalizedVMessTransport(_ value: String?) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty else { return nil }
        return switch value {
        case "websocket", "ws": "ws"
        case "http2": "h2"
        case "http-upgrade", "httpupgrade": "httpupgrade"
        case "splithttp": "xhttp"
        case "none": nil
        default: value
        }
    }

    private func normalizedTransport(_ value: String?) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !value.isEmpty else { return nil }
        return switch value {
        case "tcp", "none": nil
        case "websocket", "ws": "ws"
        case "http2": "h2"
        case "http-upgrade", "httpupgrade": "httpupgrade"
        case "splithttp": "xhttp"
        default: value
        }
    }

    /// `vless://base64(uuid@host:port)?remarks=…&tls=1&pbk=…&xtls=2`.
    ///
    /// Shadowrocket exports this endpoint-only Base64 dialect instead of the
    /// standard VLESS URL authority form. Its REALITY option names also differ
    /// from the Xray vocabulary used by standard VLESS links.
    private func parseLegacyVLESS(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        var body = String(raw.dropFirst("vless://".count))
        let fragmentName: String?
        if let fragment = body.firstIndex(of: "#") {
            fragmentName = String(body[body.index(after: fragment)...]).removingPercentEncoding
            body = String(body[..<fragment])
        } else {
            fragmentName = nil
        }

        let parts = body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let decoded = decodeBase64String(String(parts[0])),
              let atIndex = decoded.lastIndex(of: "@") else { return nil }
        let rawUUID = String(decoded[..<atIndex])
        let uuid = rawUUID.hasPrefix(":") ? String(rawUUID.dropFirst()) : rawUUID
        guard !uuid.isEmpty,
              let address = parseEndpoint(String(decoded[decoded.index(after: atIndex)...])) else {
            return nil
        }

        let rawQuery = parts.count > 1 ? queryDictionary(String(parts[1])) : [:]
        let query = Dictionary(rawQuery.map { ($0.key.lowercased(), $0.value) }) { _, new in new }
        let realityPublicKey = query["pbk"]?.removingPercentEncoding
        let tlsValue = (query["security"] ?? query["tls"] ?? "").lowercased()
        let rawTransport = (query["type"] ?? query["network"] ?? query["obfs"])?
            .removingPercentEncoding?.lowercased()
        let transport = normalizedTransport(rawTransport)
        let flow = query["flow"]?.removingPercentEncoding
            ?? (query["xtls"] == "2" ? "xtls-rprx-vision" : nil)
        let name = query["remarks"]?.removingPercentEncoding ?? fragmentName

        return ProxyNode(
            sourceID: sourceID,
            kind: .vless,
            name: normalizedName(name, fallback: address.host),
            server: address.host,
            port: address.port,
            uuid: uuid,
            transport: transport,
            transportMode: transport == "xhttp" ? query["mode"]?.removingPercentEncoding : nil,
            tls: !((realityPublicKey ?? "").isEmpty)
                || ["1", "true", "tls", "reality"].contains(tlsValue),
            sni: (query["peer"] ?? query["sni"] ?? query["servername"])?
                .removingPercentEncoding,
            hostHeader: (query["authority"] ?? query["host"])?.removingPercentEncoding,
            path: (transport == "grpc" ? query["servicename"] ?? query["service_name"] : query["path"])?.removingPercentEncoding,
            alpn: query["alpn"]?.removingPercentEncoding,
            realityPublicKey: realityPublicKey,
            realityShortID: query["sid"]?.removingPercentEncoding,
            fingerprint: (query["fingerprint"] ?? query["fp"])?.removingPercentEncoding,
            flow: flow,
            skipCertificateVerification: ["1", "true"].contains(
                query["allowinsecure"]?.lowercased() ?? query["insecure"]?.lowercased() ?? ""
            ),
            rawURI: raw
        )
    }

    private func parseShadowrocketHTTPURL(_ raw: String, sourceID: UUID?) -> ProxyNode? {
        let lowercased = raw.lowercased()
        let scheme: String
        if lowercased.hasPrefix("https://") {
            scheme = "https"
        } else if lowercased.hasPrefix("http://") {
            scheme = "http"
        } else {
            return nil
        }

        let body = String(raw.dropFirst(scheme.count + "://".count))
        let authorityEnd = body.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? body.endIndex
        let encodedAuthority = String(body[..<authorityEnd])
        // A standard proxy already contains `@`. Requiring `@` in the decoded
        // value prevents an ordinary subscription hostname from being treated
        // as an encoded HTTP proxy by coincidence.
        guard !encodedAuthority.isEmpty,
              !encodedAuthority.contains("@"),
              let decodedAuthority = decodeBase64String(encodedAuthority),
              decodedAuthority.contains("@"),
              let components = URLComponents(string: "\(scheme)://\(decodedAuthority)"),
              let rawHost = components.host else { return nil }

        let remainder = String(body[authorityEnd...])
        let fragment: String?
        let queryText: String?
        if let fragmentIndex = remainder.firstIndex(of: "#") {
            fragment = String(remainder[remainder.index(after: fragmentIndex)...]).removingPercentEncoding
            let beforeFragment = String(remainder[..<fragmentIndex])
            queryText = beforeFragment.hasPrefix("?") ? String(beforeFragment.dropFirst()) : nil
        } else {
            fragment = nil
            queryText = remainder.hasPrefix("?") ? String(remainder.dropFirst()) : nil
        }
        let rawQuery = queryText.map(queryDictionary) ?? [:]
        let query = Dictionary(rawQuery.map { ($0.key.lowercased(), $0.value) }) { _, new in new }
        let server = normalizedHost(rawHost)
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        let remarks = query["remarks"]?.removingPercentEncoding
            ?? query["remark"]?.removingPercentEncoding

        return ProxyNode(
            sourceID: sourceID,
            kind: .http,
            name: normalizedName(remarks ?? fragment, fallback: "HTTP · \(server)"),
            server: server,
            port: port,
            password: components.password?.removingPercentEncoding,
            username: components.user?.removingPercentEncoding,
            tls: scheme == "https",
            rawURI: raw
        )
    }

    private func parseStandardURL(_ raw: String, kind: ProxyKind, sourceID: UUID?) -> ProxyNode? {
        var normalized = raw
        if normalized.lowercased().hasPrefix("hy2://") {
            normalized = "hysteria2://" + normalized.dropFirst("hy2://".count)
        } else if normalized.lowercased().hasPrefix("hy://") {
            normalized = "hysteria://" + normalized.dropFirst("hy://".count)
        } else if normalized.lowercased().hasPrefix("socks://") {
            normalized = "socks5://" + normalized.dropFirst("socks://".count)
        }
        guard let components = URLComponents(string: normalized),
              let rawHost = components.host else { return nil }
        let defaultHTTPPort: Int? = kind == .http
            ? (components.scheme?.lowercased() == "https" ? 443 : 80)
            : nil
        guard let port = components.port ?? defaultHTTPPort else { return nil }
        let server = normalizedHost(rawHost)

        let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }) { _, new in new }
        let fallback = "\(kind.title) · \(server)"
        let name = normalizedName(
            components.fragment?.removingPercentEncoding
                ?? query["remarks"]?.removingPercentEncoding
                ?? query["remark"]?.removingPercentEncoding,
            fallback: fallback
        )
        let transport = normalizedTransport(
            query["type"] ?? query["network"] ?? (query["obfs"]?.contains("ws") == true ? "ws" : nil)
        )
        let security = (query["security"] ?? query["tls"] ?? "").lowercased()
        // Shadowrocket has two VLESS URL dialects. Its Base64-authority form
        // is handled above, but it can also keep the standard UUID authority
        // while using Shadowrocket's query vocabulary (`tls=1`, `xtls=2`,
        // `fingerprint`). A public key is unambiguous evidence that this VLESS
        // node is REALITY even when `security=reality` is omitted.
        let realityPublicKey = query["pbk"]
        let carriesReality = security == "reality"
            || (kind == .vless && !((realityPublicKey ?? "").isEmpty))
        let flow = query["flow"]
            ?? (kind == .vless && query["xtls"] == "2" ? "xtls-rprx-vision" : nil)
        let credential = components.user?.removingPercentEncoding

        return ProxyNode(
            sourceID: sourceID,
            kind: kind,
            name: name,
            server: server,
            port: port,
            // TUIC v5 writes `tuic://uuid:password@host`, so unlike every
            // other scheme here both halves of the userinfo are meaningful.
            // Hysteria 1 puts its secret in the query instead of the userinfo.
            password: kind == .tuic
                ? components.password?.removingPercentEncoding
                : (kind == .hysteria
                    ? (credential ?? query["auth"] ?? query["auth_str"] ?? query["authstr"])
                    : ([.trojan, .hysteria2, .anytls].contains(kind)
                        ? credential
                        : components.password?.removingPercentEncoding)),
            uuid: [.vmess, .vless, .tuic].contains(kind) ? credential : nil,
            username: [.socks5, .http].contains(kind) ? credential : nil,
            transport: transport,
            transportMode: transport == "xhttp" ? query["mode"] : nil,
            tls: [.trojan, .hysteria, .hysteria2, .tuic, .anytls].contains(kind)
                || ["1", "true", "tls", "reality"].contains(security)
                || carriesReality
                || normalized.lowercased().hasPrefix("https://"),
            sni: query["sni"] ?? query["servername"] ?? query["peer"],
            hostHeader: query["authority"] ?? query["host"],
            path: transport == "grpc"
                ? query["servicename"] ?? query["service_name"] ?? query["path"]
                : query["path"],
            alpn: query["alpn"],
            // REALITY. `pbk` is the required server public key; `sid` is the
            // short id and may legitimately be empty. Preserve both exactly.
            realityPublicKey: carriesReality ? realityPublicKey : nil,
            realityShortID: carriesReality ? query["sid"] : nil,
            fingerprint: query["fp"] ?? query["fingerprint"],
            flow: flow,
            skipCertificateVerification: ["1", "true"].contains(
                query["allowinsecure"] ?? query["insecure"] ?? query["allow_insecure"] ?? ""
            ),
            protocolName: kind == .hysteria ? query["protocol"] : nil,
            // Hysteria 1's obfs is a single shared string, not Hysteria 2's
            // (method, password) pair, so it lives in `obfs` alone.
            // With `obfs=xplus` the shared key is in `obfsParam`; Mihomo and
            // sing-box both want that key, not the mode name.
            obfs: kind == .hysteria
                ? query["obfsparam"] ?? query["obfs"]
                : (kind == .hysteria2 ? query["obfs"] : nil),
            obfsParam: kind == .hysteria2
                ? query["obfs-password"] ?? query["obfspassword"] ?? query["obfs_password"]
                : nil,
            idleSessionCheckInterval: kind == .anytls
                ? Int(query["idle-session-check-interval"] ?? query["idlesessioncheckinterval"] ?? "")
                : nil,
            idleSessionTimeout: kind == .anytls
                ? Int(query["idle-session-timeout"] ?? query["idlesessiontimeout"] ?? "")
                : nil,
            minIdleSession: kind == .anytls
                ? Int(query["min-idle-session"] ?? query["minidlesession"] ?? "")
                : nil,
            congestionControl: kind == .tuic
                ? query["congestion_control"] ?? query["congestion-controller"]
                : nil,
            udpRelayMode: kind == .tuic ? query["udp_relay_mode"] ?? query["udp-relay-mode"] : nil,
            upMbps: kind == .hysteria ? mbps(query["upmbps"] ?? query["up"]) : nil,
            downMbps: kind == .hysteria ? mbps(query["downmbps"] ?? query["down"]) : nil,
            rawURI: raw
        )
    }

    private func parseClashYAML(_ text: String, sourceID: UUID?) -> ParsedContent {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "proxies:" }) else {
            return .init(nodes: [], rejectedLineCount: 1)
        }

        var dictionaries: [[String: String]] = []
        var current: [String: String] = [:]
        var inside = false
        // A proxy starts at the indentation of the first `-` under `proxies:`.
        // Deeper `-` lines are a nested sequence — `http-opts: path: - /` is
        // the common one — and treating those as a new proxy both invents a
        // junk entry and truncates the real node at that line, dropping
        // whatever follows. One real list loses 28 nodes' `reality-opts` that
        // way: they import looking healthy and never connect.
        var itemIndentation: Int?
        // The key a bare sequence element belongs to, for the same reason.
        var pendingSequenceKey: String?

        for rawLine in lines.dropFirst(start + 1) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indentation = rawLine.prefix { $0 == " " }.count
            if indentation == 0 && !trimmed.hasPrefix("-") { break }

            if trimmed.hasPrefix("-"), indentation <= (itemIndentation ?? indentation) {
                itemIndentation = indentation
                if !current.isEmpty { dictionaries.append(current) }
                current = [:]
                inside = true
                pendingSequenceKey = nil
                let remainder = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if remainder.hasPrefix("{") {
                    current.merge(parseInlineYAMLMap(String(remainder))) { _, new in new }
                } else if let pair = parseYAMLPair(String(remainder)) {
                    current[pair.0] = pair.1
                    if pair.1.isEmpty { pendingSequenceKey = pair.0 }
                }
            } else if inside, trimmed.hasPrefix("-") {
                // A nested element. Collected comma-joined so a multi-value
                // `alpn` survives in the one form ProxyNode and the generators
                // already use.
                let element = yamlScalar(
                    String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                )
                guard !element.isEmpty else { continue }
                // A single WireGuard peer begins with `- server: …`; that is a
                // nested map entry, not a scalar belonging to `peers`.
                if let pair = parseYAMLPair(element), !pair.1.isEmpty {
                    if pair.0 == "server",
                       current["type"]?.lowercased() == "wireguard" {
                        let peerCount = Int(current["__wireguard-peer-count"] ?? "0") ?? 0
                        current["__wireguard-peer-count"] = String(peerCount + 1)
                    }
                    current[pair.0] = pair.1
                    pendingSequenceKey = nil
                    continue
                }
                guard let key = pendingSequenceKey else { continue }
                let existing = current[key] ?? ""
                current[key] = existing.isEmpty ? element : existing + "," + element
            } else if inside, let pair = parseYAMLPair(trimmed) {
                current[pair.0] = pair.1
                pendingSequenceKey = pair.1.isEmpty ? pair.0 : nil
            }
        }
        if !current.isEmpty { dictionaries.append(current) }

        var nodes: [ProxyNode] = []
        var rejected = 0
        for dictionary in dictionaries {
            guard let type = dictionary["type"]?.lowercased(),
                  let kind = clashKind(type),
                  let rawServer = dictionary["server"],
                  let port = Int(dictionary["port"] ?? "") else {
                rejected += 1
                continue
            }
            // ProxyNode intentionally models one WireGuard endpoint. Flattening
            // multiple peers would silently keep only the final peer and can
            // route traffic to the wrong endpoint, so preserve integrity by
            // rejecting that one proxy instead.
            if kind == .wireguard,
               (Int(dictionary["__wireguard-peer-count"] ?? "0") ?? 0) > 1 {
                rejected += 1
                continue
            }

            // A SIP003 plugin changes how the node is dialled. simple-obfs is
            // expressible in all five target formats and is carried over;
            // anything else would import as a node that looks healthy and never
            // connects, so it is rejected and counted instead.
            var obfsMode = dictionary["obfs"]
            var sip003Plugin: String?
            var pluginTransport: String?
            var pluginPath: String?
            var pluginTLS = false
            // `obfs-param` is ShadowsocksR's key. Hysteria 2 spells the same
            // slot `obfs-password`, and reading only the SSR name left every
            // salamander node with a type and no password — which makes Mihomo
            // reject the whole profile, not just that node.
            var obfsHost = dictionary["obfs-param"]
                ?? dictionary["obfs-password"]
                ?? dictionary["obfs_password"]
            if kind == .shadowsocks, let plugin = dictionary["plugin"]?.lowercased(), !plugin.isEmpty {
                let options = parseInlineYAMLMap(dictionary["plugin-opts"] ?? "")
                if plugin == "obfs" || plugin == "obfs-local" || plugin == "simple-obfs" {
                    obfsMode = options["mode"] ?? "http"
                    obfsHost = options["host"]
                } else if plugin == "v2ray-plugin",
                          ["websocket", "ws"].contains((options["mode"] ?? "websocket").lowercased()) {
                    sip003Plugin = "v2ray-plugin"
                    pluginTransport = "ws"
                    pluginPath = options["path"]
                    pluginTLS = boolString(options["tls"])
                    obfsHost = options["host"]
                } else {
                    rejected += 1
                    continue
                }
            }

            let server = normalizedHost(rawServer)
            // The deliberately small YAML reader above flattens nested maps.
            // Keep the parent marker so a generic `public-key` is only treated
            // as REALITY when it actually came from `reality-opts`.
            let hasRealityOptions = dictionary.keys.contains("reality-opts")
                || dictionary["security"]?.lowercased() == "reality"
            nodes.append(ProxyNode(
                sourceID: sourceID,
                kind: kind,
                name: normalizedName(dictionary["name"], fallback: server),
                server: server,
                port: port,
                cipher: dictionary["cipher"],
                // Hysteria 1 calls it `auth-str` and Snell calls it `psk`;
                // both are the single shared secret ProxyNode stores.
                password: dictionary["password"]
                    ?? dictionary["auth-str"]
                    ?? dictionary["auth_str"]
                    ?? dictionary["auth"]
                    ?? dictionary["psk"],
                uuid: dictionary["uuid"],
                username: dictionary["username"],
                transport: pluginTransport ?? normalizedTransport(dictionary["network"]),
                transportMode: normalizedTransport(dictionary["network"]) == "xhttp"
                    ? dictionary["mode"] : nil,
                plugin: sip003Plugin,
                tls: pluginTLS || boolString(dictionary["tls"]),
                sni: dictionary["servername"] ?? dictionary["sni"],
                hostHeader: dictionary["authority"] ?? dictionary["host"],
                path: pluginPath
                    ?? (normalizedTransport(dictionary["network"]) == "grpc"
                        ? dictionary["grpc-service-name"] ?? dictionary["service-name"] ?? dictionary["path"]
                        : dictionary["path"]),
                alpn: dictionary["alpn"],
                realityPublicKey: hasRealityOptions
                    ? dictionary["public-key"] ?? dictionary["pbk"]
                    : nil,
                realityShortID: hasRealityOptions
                    ? clashYAMLScalar(dictionary["short-id"] ?? dictionary["sid"])
                    : nil,
                fingerprint: dictionary["client-fingerprint"]
                    ?? dictionary["fingerprint"]
                    ?? dictionary["fp"],
                flow: dictionary["flow"],
                skipCertificateVerification: boolString(dictionary["skip-cert-verify"]),
                alterID: Int(dictionary["alterid"] ?? dictionary["alter-id"] ?? ""),
                protocolName: dictionary["protocol"],
                protocolParam: dictionary["protocol-param"],
                obfs: obfsMode,
                obfsParam: sip003Plugin == nil ? obfsHost : nil,
                version: Int(dictionary["version"] ?? ""),
                congestionControl: dictionary["congestion-controller"]
                    ?? dictionary["congestion_control"],
                udpRelayMode: dictionary["udp-relay-mode"],
                upMbps: kind == .hysteria ? mbps(dictionary["up"] ?? dictionary["up-speed"]) : nil,
                downMbps: kind == .hysteria ? mbps(dictionary["down"] ?? dictionary["down-speed"]) : nil,
                wireGuardPrivateKey: kind == .wireguard ? dictionary["private-key"] : nil,
                wireGuardPublicKey: kind == .wireguard ? dictionary["public-key"] : nil,
                wireGuardPreSharedKey: kind == .wireguard
                    ? dictionary["pre-shared-key"] ?? dictionary["preshared-key"]
                    : nil,
                wireGuardIPv4: kind == .wireguard ? dictionary["ip"] : nil,
                wireGuardIPv6: kind == .wireguard ? dictionary["ipv6"] : nil,
                wireGuardAllowedIPs: kind == .wireguard
                    ? csvValues(dictionary["allowed-ips"] ?? "0.0.0.0/0,::/0").joined(separator: ",")
                    : nil,
                wireGuardReserved: kind == .wireguard
                    ? csvValues(dictionary["reserved"] ?? "").joined(separator: ",")
                    : nil,
                wireGuardMTU: kind == .wireguard ? Int(dictionary["mtu"] ?? "") : nil,
                wireGuardPersistentKeepalive: kind == .wireguard
                    ? Int(dictionary["persistent-keepalive"] ?? dictionary["keepalive"] ?? "")
                    : nil,
                wireGuardDNS: kind == .wireguard
                    ? csvValues(dictionary["dns"] ?? "").joined(separator: ",")
                    : nil,
                rawURI: "clash://local/\(UUID().uuidString)"
            ))
        }
        return .init(
            nodes: nodes,
            rejectedLineCount: dictionaries.isEmpty ? 1 : rejected
        )
    }

    /// Clash producers occasionally encode a single REALITY short id as a
    /// one-element YAML array. ProxyNode stores the protocol value itself.
    private func clashYAMLScalar(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
                .split(separator: ",", maxSplits: 1)
                .first
                .map(String.init) ?? ""
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
        return value.isEmpty ? nil : value
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
        return key.isEmpty ? nil : (key.lowercased(), yamlScalar(raw))
    }

    /// Unwraps a YAML scalar, decoding escapes when the quoting style has them.
    ///
    /// Panels that emit YAML from a serialiser rather than by hand write
    /// non-ASCII as escapes: one airport sends every node as
    /// `name: "\U0001F1ED\U0001F1F0 香港 01"`. Stripping the quotes without
    /// decoding leaves the escape text itself as the node name, which is what
    /// the list then displays and what every generated configuration carries.
    ///
    /// Only double quotes process escapes. In a single-quoted scalar a
    /// backslash is a literal backslash and `''` is the only escape there is,
    /// so the two styles cannot share one code path.
    private func yamlScalar(_ raw: String) -> String {
        guard raw.count >= 2 else {
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        if raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        guard raw.hasPrefix("\""), raw.hasSuffix("\"") else {
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return decodeYAMLEscapes(String(raw.dropFirst().dropLast()))
    }

    private func decodeYAMLEscapes(_ body: String) -> String {
        guard body.contains("\\") else { return body }
        var output = ""
        let scalars = Array(body.unicodeScalars)
        var index = 0
        // A `\uD83C\uDDED` pair has to be combined before it can be appended;
        // appending a lone surrogate is not representable in a Swift string.
        var pendingHighSurrogate: UInt32?

        func flushSurrogate() {
            if let high = pendingHighSurrogate, let scalar = Unicode.Scalar(high) {
                output.unicodeScalars.append(scalar)
            }
            pendingHighSurrogate = nil
        }

        func hex(_ count: Int) -> UInt32? {
            guard index + count <= scalars.count else { return nil }
            let digits = String(String.UnicodeScalarView(scalars[index ..< index + count]))
            guard digits.count == count, let value = UInt32(digits, radix: 16) else { return nil }
            index += count
            return value
        }

        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\\", index + 1 < scalars.count else {
                flushSurrogate()
                output.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            let marker = scalars[index + 1]
            index += 2

            let width: Int
            switch marker {
            case "x": width = 2
            case "u": width = 4
            case "U": width = 8
            default:
                flushSurrogate()
                switch marker {
                case "n": output.append("\n")
                case "t": output.append("\t")
                case "r": output.append("\r")
                case "0": output.append("\0")
                case "a": output.unicodeScalars.append(Unicode.Scalar(7))
                case "b": output.unicodeScalars.append(Unicode.Scalar(8))
                case "e": output.unicodeScalars.append(Unicode.Scalar(27))
                // `\/` and `\_` are YAML's, `\\` and `\"` are shared with JSON.
                default: output.unicodeScalars.append(marker)
                }
                continue
            }

            guard let value = hex(width) else {
                flushSurrogate()
                output.append("\\")
                output.unicodeScalars.append(marker)
                continue
            }
            if let high = pendingHighSurrogate {
                pendingHighSurrogate = nil
                if (0xDC00 ... 0xDFFF).contains(value) {
                    let combined = 0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00)
                    if let scalar = Unicode.Scalar(combined) { output.unicodeScalars.append(scalar) }
                    continue
                }
                if let scalar = Unicode.Scalar(high) { output.unicodeScalars.append(scalar) }
            }
            if (0xD800 ... 0xDBFF).contains(value) {
                pendingHighSurrogate = value
            } else if let decoded = Unicode.Scalar(value) {
                output.unicodeScalars.append(decoded)
            }
        }
        flushSurrogate()
        return output
    }

    private func clashKind(_ value: String) -> ProxyKind? {
        switch value {
        case "ss": .shadowsocks
        case "ssr": .shadowsocksR
        case "vmess": .vmess
        case "vless": .vless
        case "trojan": .trojan
        case "hysteria2", "hy2": .hysteria2
        case "hysteria": .hysteria
        case "tuic": .tuic
        case "wireguard", "wg": .wireguard
        case "anytls": .anytls
        case "snell": .snell
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
            "hysteria2://", "hy2://", "hysteria://", "tuic://", "wireguard://", "wg://",
            "anytls://", "socks5://", "socks://", "http://", "https://"
        ]
            .contains(where: lowercased.contains)
    }

    /// Normalises YAML/URI list scalars (`[a, b]`, `a,b`) without touching
    /// colons inside IPv6 addresses.
    private func csvValues(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n\"'"))
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'")) }
            .filter { !$0.isEmpty }
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
        // Share links encode the name form-style, so `+` is a space. Strictly a
        // URI fragment keeps `+` literal, but every airport writes it the other
        // way — this one publishes "🇭🇰+HongKong+01" and its own Shadowrocket
        // link spells the same node "🇭🇰%20HongKong%2001".
        let spaced = (value ?? "").replacingOccurrences(of: "+", with: " ")
        let trimmed = spaced.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Reads a Hysteria 1 bandwidth field.
    ///
    /// Airports write these as a bare number, as `100 Mbps`, and occasionally
    /// as `100mbps`, so the digits are taken and the unit ignored. Zero and
    /// negative values mean "unset" rather than "no bandwidth".
    private func mbps(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber }
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }

    private func deduplicated(_ nodes: [ProxyNode]) -> [ProxyNode] {
        var seen = Set<String>()
        return nodes.filter { node in
            let key = node.isSubscriptionMetadata == true
                ? "\(node.canonicalKey)|metadata|\(node.name.lowercased())"
                : node.canonicalKey
            return seen.insert(key).inserted
        }
    }

    private func markingSubscriptionMetadata(_ node: ProxyNode) -> ProxyNode {
        var marked = node
        marked.isSubscriptionMetadata = Self.isNotice(node)
        return marked
    }
}
