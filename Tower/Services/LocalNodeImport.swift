import Foundation

enum ManualNodeValidationError: LocalizedError, Equatable {
    case invalidServer
    case invalidPort
    case missingSecret
    case missingCipher
    case invalidVersion
    case missingRealityPublicKey
    case incompatibleRealityTransport
    case invalidSessionSettings
    case unsupportedProtocol

    var errorDescription: String? {
        switch self {
        case .invalidServer: String(localized: "请填写节点服务器地址")
        case .invalidPort: String(localized: "端口必须是 1 到 65535 之间的数字")
        case .missingSecret: String(localized: "请填写该协议需要的密码或 UUID")
        case .missingCipher: String(localized: "请填写 Shadowsocks 加密方式")
        case .invalidVersion: String(localized: "Snell 版本必须是 1 到 6 之间的数字")
        case .missingRealityPublicKey: String(localized: "REALITY 必须填写服务器公钥")
        case .incompatibleRealityTransport: String(localized: "REALITY 当前只支持 TCP 或 gRPC 传输")
        case .invalidSessionSettings: String(localized: "AnyTLS 会话参数必须是大于或等于 0 的整数")
        case .unsupportedProtocol: String(localized: "该协议请改用协议链接导入")
        }
    }
}

struct LocalNodeImporter {
    private let parser = SubscriptionParser()

    func parse(_ content: String, preferredName: String = "") throws -> ImportResult {
        let parsed = parser.parse(data: Data(content.utf8), sourceID: nil)
        guard !parsed.nodes.isEmpty else { throw SubscriptionError.noSupportedNodes }

        var nodes = parsed.nodes
        let name = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        if nodes.count == 1, !name.isEmpty {
            nodes[0].name = name
        }
        return ImportResult(
            nodes: nodes,
            rejectedLineCount: parsed.rejectedLineCount,
            usage: nil
        )
    }
}

struct ManualNodeDraft: Equatable {
    static let supportedKinds: [ProxyKind] = [
        .shadowsocks, .shadowsocksR, .vmess, .vless, .trojan,
        .hysteria2, .anytls, .snell, .socks5, .http
    ]

    var kind: ProxyKind = .shadowsocks
    var name = ""
    var server = ""
    var port = ""
    var username = ""
    /// Password, PSK or UUID depending on `kind`.
    var secret = ""
    var cipher = "aes-256-gcm"
    var transport = "tcp"
    var tls = false
    var sni = ""
    var hostHeader = ""
    var path = ""
    var alpn = ""
    var realityPublicKey = ""
    var realityShortID = ""
    var fingerprint = "chrome"
    var flow = ""
    var skipCertificateVerification = false
    var alterID = "0"
    var protocolName = "origin"
    var protocolParam = ""
    var obfs = "none"
    var obfsParam = ""
    var idleSessionCheckInterval = "30"
    var idleSessionTimeout = "30"
    var minIdleSession = "0"
    var version = "4"
    /// Used by the form. Imported callers that only set `tls` remain valid.
    var security = "none"

    mutating func applyDefaults(for selectedKind: ProxyKind) {
        kind = selectedKind
        switch selectedKind {
        case .shadowsocks:
            cipher = "aes-256-gcm"
            obfs = "none"
        case .shadowsocksR:
            cipher = "aes-256-cfb"
            protocolName = "origin"
            obfs = "plain"
        case .vmess:
            cipher = "auto"
            transport = "tcp"
            security = "none"
        case .vless:
            transport = "tcp"
            security = "tls"
            fingerprint = "chrome"
        case .trojan:
            transport = "tcp"
            security = "tls"
        case .hysteria2:
            security = "tls"
            obfs = "none"
            obfsParam = ""
        case .anytls:
            security = "tls"
            idleSessionCheckInterval = "30"
            idleSessionTimeout = "30"
            minIdleSession = "0"
        case .snell:
            version = "4"
            obfs = "none"
        case .socks5, .http:
            security = "none"
        case .unknown:
            break
        }
    }

    func makeNode() throws -> ProxyNode {
        guard Self.supportedKinds.contains(kind) else {
            throw ManualNodeValidationError.unsupportedProtocol
        }
        let normalizedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !normalizedServer.isEmpty else { throw ManualNodeValidationError.invalidServer }
        guard let parsedPort = Int(port), (1 ... 65_535).contains(parsedPort) else {
            throw ManualNodeValidationError.invalidPort
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCipher = cipher.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTransport = transport.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHostHeader = hostHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedALPN = alpn.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRealityKey = realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRealityShortID = realityShortID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFingerprint = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFlow = flow.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocolName = protocolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProtocolParam = protocolParam.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObfs = obfs.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedObfsParam = obfsParam.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecurity = security.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usesReality = normalizedSecurity == "reality"

        if [.shadowsocks, .shadowsocksR, .vmess, .vless, .trojan, .hysteria2, .anytls, .snell].contains(kind),
           normalizedSecret.isEmpty {
            throw ManualNodeValidationError.missingSecret
        }
        if [.shadowsocks, .shadowsocksR].contains(kind), normalizedCipher.isEmpty {
            throw ManualNodeValidationError.missingCipher
        }
        if usesReality, normalizedRealityKey.isEmpty {
            throw ManualNodeValidationError.missingRealityPublicKey
        }
        if usesReality, !["tcp", "grpc"].contains(normalizedTransport.lowercased()) {
            throw ManualNodeValidationError.incompatibleRealityTransport
        }
        let parsedIdleSessionCheckInterval: Int?
        let parsedIdleSessionTimeout: Int?
        let parsedMinIdleSession: Int?
        if kind == .anytls {
            guard let checkInterval = Int(idleSessionCheckInterval), checkInterval >= 0,
                  let timeout = Int(idleSessionTimeout), timeout >= 0,
                  let minimum = Int(minIdleSession), minimum >= 0 else {
                throw ManualNodeValidationError.invalidSessionSettings
            }
            parsedIdleSessionCheckInterval = checkInterval
            parsedIdleSessionTimeout = timeout
            parsedMinIdleSession = minimum
        } else {
            parsedIdleSessionCheckInterval = nil
            parsedIdleSessionTimeout = nil
            parsedMinIdleSession = nil
        }
        let parsedVersion: Int?
        if kind == .snell {
            guard let value = Int(version), (1 ... 6).contains(value) else {
                throw ManualNodeValidationError.invalidVersion
            }
            parsedVersion = value
        } else {
            parsedVersion = nil
        }
        let parsedAlterID = kind == .vmess ? max(Int(alterID) ?? 0, 0) : nil
        let requiresTLS = [.trojan, .hysteria2, .anytls].contains(kind)
        let enablesTLS = requiresTLS || tls || ["tls", "reality"].contains(normalizedSecurity) || usesReality

        var node = ProxyNode(
            kind: kind,
            name: normalizedName.isEmpty ? "\(kind.title) · \(normalizedServer)" : normalizedName,
            server: normalizedServer,
            port: parsedPort,
            cipher: [.shadowsocks, .shadowsocksR].contains(kind)
                ? normalizedCipher
                : (kind == .vmess ? (normalizedCipher.isEmpty ? "auto" : normalizedCipher) : nil),
            password: [.shadowsocks, .shadowsocksR, .trojan, .hysteria2, .anytls, .snell, .socks5, .http].contains(kind)
                ? (normalizedSecret.isEmpty ? nil : normalizedSecret)
                : nil,
            uuid: [.vmess, .vless].contains(kind) ? normalizedSecret : nil,
            username: [.socks5, .http].contains(kind) && !normalizedUsername.isEmpty
                ? normalizedUsername
                : nil,
            transport: [.vmess, .vless, .trojan].contains(kind) && !normalizedTransport.isEmpty
                ? normalizedTransport
                : nil,
            tls: enablesTLS,
            sni: normalizedSNI.isEmpty ? nil : normalizedSNI,
            hostHeader: normalizedHostHeader.isEmpty ? nil : normalizedHostHeader,
            path: normalizedPath.isEmpty ? nil : normalizedPath,
            alpn: normalizedALPN.isEmpty ? nil : normalizedALPN,
            realityPublicKey: usesReality ? normalizedRealityKey : nil,
            realityShortID: usesReality && !normalizedRealityShortID.isEmpty ? normalizedRealityShortID : nil,
            fingerprint: usesReality && !normalizedFingerprint.isEmpty ? normalizedFingerprint : nil,
            flow: !normalizedFlow.isEmpty ? normalizedFlow : nil,
            skipCertificateVerification: skipCertificateVerification,
            alterID: parsedAlterID,
            protocolName: kind == .shadowsocksR
                ? (normalizedProtocolName.isEmpty ? "origin" : normalizedProtocolName)
                : nil,
            protocolParam: kind == .shadowsocksR && !normalizedProtocolParam.isEmpty
                ? normalizedProtocolParam
                : nil,
            obfs: [.shadowsocks, .shadowsocksR, .hysteria2, .snell].contains(kind) && !normalizedObfs.isEmpty
                ? normalizedObfs
                : nil,
            obfsParam: [.shadowsocks, .shadowsocksR, .hysteria2, .snell].contains(kind) && !normalizedObfsParam.isEmpty
                ? normalizedObfsParam
                : nil,
            idleSessionCheckInterval: parsedIdleSessionCheckInterval,
            idleSessionTimeout: parsedIdleSessionTimeout,
            minIdleSession: parsedMinIdleSession,
            version: parsedVersion,
            rawURI: ""
        )
        node.rawURI = ProxyNodeShareLinkGenerator().link(for: node)
        return node
    }
}
