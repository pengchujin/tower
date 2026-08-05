import Foundation

enum SourceInputKind: Equatable {
    case subscription
    case node(ProxyKind)
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
                || (scheme == "http" && components.port != nil && components.path.isEmpty)
            if looksLikeProxy, let node = parser.parseURI(value) {
                return .node(node.kind)
            }

            if scheme == "https" {
                return .subscription
            }
        }

        return .unknown
    }
}
