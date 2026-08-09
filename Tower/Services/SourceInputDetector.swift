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
            if !parsed.nodes.isEmpty {
                return .nodeBatch(count: parsed.nodes.count)
            }
        }

        let lowercased = value.lowercased()
        let explicitNodeSchemes = [
            "ss://", "ssr://", "vmess://", "vless://", "trojan://",
            "hysteria2://", "hy2://", "anytls://", "socks5://", "socks://"
        ]
        if explicitNodeSchemes.contains(where: lowercased.hasPrefix),
           let node = parser.parseURI(value) {
            return .node(node.kind)
        }

        // Snell is shared as a Surge proxy line rather than a URI, so it is
        // recognised by that shape instead of by a scheme prefix.
        if lowercased.contains("=") , lowercased.contains("snell"),
           let node = parser.parseURI(value), node.kind == .snell {
            return .node(.snell)
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else {
            return .unknown
        }

        if scheme == "http" || scheme == "https" {
            let looksLikeProxy = components.user != nil
                || (components.port != nil
                    && components.path.isEmpty
                    && (scheme == "http" || components.fragment != nil))
            if looksLikeProxy, let node = parser.parseURI(value) {
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
            let looksLikeProxy = components.user != nil
                || (components.port != nil && components.path.isEmpty && components.fragment != nil)
            return looksLikeProxy ? nil : value
        }
    }
}
