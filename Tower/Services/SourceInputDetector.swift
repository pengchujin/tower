import Foundation

enum SourceInputKind: Equatable {
    case subscription
    case subscriptionBatch(count: Int)
    case node(ProxyKind)
    case nodeBatch(count: Int)
    case unknown

    var isSupported: Bool {
        self != .unknown
    }
}

struct SourceInputDetector {
    private let parser = SubscriptionParser()

    func detect(_ rawValue: String) -> SourceInputKind {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .unknown }

        if value.hasPrefix("{") || value.hasPrefix("[") {
            let parsed = parser.parse(data: Data(value.utf8))
            if parsed.nodes.count == 1, let node = parsed.nodes.first { return .node(node.kind) }
            if parsed.nodes.count > 1 { return .nodeBatch(count: parsed.nodes.count) }
        }

        let meaningfulLines = value.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.isEmpty && !line.hasPrefix("#")
        }
        if meaningfulLines.count > 1 {
            let subscriptions = subscriptionURLs(value)
            if subscriptions.count == meaningfulLines.count {
                return .subscriptionBatch(count: subscriptions.count)
            }
            let parsed = parser.parse(data: Data(value.utf8))
            // A one-proxy `proxies:` snippet is how SSH and TrustTunnel nodes
            // are shared (they have no URI), so it reads as a single node.
            if parsed.nodes.count == 1, let node = parsed.nodes.first { return .node(node.kind) }
            if !parsed.nodes.isEmpty {
                return .nodeBatch(count: parsed.nodes.count)
            }
        }

        let lowercased = value.lowercased()
        // Share the parser's protocol support instead of maintaining another
        // scheme list that can omit supported aliases (wireguard://, wg://).
        // HTTP(S) remains ambiguous with subscription URLs and is handled below.
        if !lowercased.hasPrefix("http://"), !lowercased.hasPrefix("https://"),
           let node = parser.parseURI(value) {
            return .node(node.kind)
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            return .unknown
        }

        if scheme == "http" || scheme == "https" {
            if let node = httpProxyNode(value, components: components, scheme: scheme) {
                return .node(node.kind)
            }

            return .subscription
        }

        return .unknown
    }

    func subscriptionURLs(_ rawValue: String) -> [String] {
        rawValue.components(separatedBy: .newlines).compactMap { rawLine in
            let value = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !value.hasPrefix("#"),
                  let components = URLComponents(string: value),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host != nil else {
                return nil
            }
            return httpProxyNode(value, components: components, scheme: scheme) == nil ? value : nil
        }
    }

    /// HTTP(S) proxy links and subscription URLs share a scheme. The single
    /// and multi-line paths must classify them identically, otherwise two
    /// `http://host:8080` proxies pasted together import as subscriptions.
    private func httpProxyNode(_ value: String, components: URLComponents, scheme: String) -> ProxyNode? {
        let looksLikeProxy = components.user != nil
            || (components.port != nil
                && components.path.isEmpty
                && (scheme == "http" || components.fragment != nil))
        guard let node = parser.parseURI(value),
              looksLikeProxy || isEncodedHTTPProxy(node, originalHost: components.host) else {
            return nil
        }
        return node
    }

    private func isEncodedHTTPProxy(_ node: ProxyNode, originalHost: String?) -> Bool {
        guard node.kind == .http, let originalHost else { return false }
        return node.server.caseInsensitiveCompare(originalHost) != .orderedSame
    }
}
