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
    case missingTUICPassword
    case invalidBandwidth
    case incompleteWireGuard
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
        case .missingTUICPassword: String(localized: "TUIC 需要同时填写 UUID 和密码")
        case .invalidBandwidth: String(localized: "Hysteria 上下行带宽必须是大于 0 的整数")
        case .incompleteWireGuard: String(localized: "WireGuard 需要私钥、公钥、本机地址和允许的网段")
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
        .hysteria, .hysteria2, .tuic, .wireguard, .anytls, .snell, .socks5, .http
    ]

    var kind: ProxyKind = .shadowsocks
    var name = ""
    var server = ""
    var port = ""
    var username = ""
    /// The protocol's identity: its UUID where it has one, its password or PSK
    /// where it does not.
    var secret = ""
    /// TUIC is the only protocol here that authenticates with a UUID *and* a
    /// password, so it is the only one that fills this in.
    var password = ""
    /// Hysteria 1's bandwidth budget. Not a hint — its congestion control is
    /// rate-based, so a node without one either fails to load or crawls.
    var upMbps = "50"
    var downMbps = "100"
    var wireGuardPrivateKey = ""
    var wireGuardPublicKey = ""
    var wireGuardPreSharedKey = ""
    var wireGuardIPv4 = ""
    var wireGuardIPv6 = ""
    var wireGuardAllowedIPs = "0.0.0.0/0,::/0"
    var wireGuardReserved = ""
    var wireGuardMTU = "1280"
    var wireGuardPersistentKeepalive = "25"
    var wireGuardDNS = ""
    /// TUIC's QUIC tuning. Empty means "let the client decide"; both are
    /// per-server choices, so guessing them costs UDP or throughput.
    var congestionControl = ""
    var udpRelayMode = ""
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

    init(
        kind: ProxyKind = .shadowsocks,
        name: String = "",
        server: String = "",
        port: String = "",
        username: String = "",
        secret: String = "",
        password: String = "",
        upMbps: String = "50",
        downMbps: String = "100",
        wireGuardPrivateKey: String = "",
        wireGuardPublicKey: String = "",
        wireGuardPreSharedKey: String = "",
        wireGuardIPv4: String = "",
        wireGuardIPv6: String = "",
        wireGuardAllowedIPs: String = "0.0.0.0/0,::/0",
        wireGuardReserved: String = "",
        wireGuardMTU: String = "1280",
        wireGuardPersistentKeepalive: String = "25",
        wireGuardDNS: String = "",
        congestionControl: String = "",
        udpRelayMode: String = "",
        cipher: String = "aes-256-gcm",
        transport: String = "tcp",
        tls: Bool = false,
        sni: String = "",
        hostHeader: String = "",
        path: String = "",
        alpn: String = "",
        realityPublicKey: String = "",
        realityShortID: String = "",
        fingerprint: String = "chrome",
        flow: String = "",
        skipCertificateVerification: Bool = false,
        alterID: String = "0",
        protocolName: String = "origin",
        protocolParam: String = "",
        obfs: String = "none",
        obfsParam: String = "",
        idleSessionCheckInterval: String = "30",
        idleSessionTimeout: String = "30",
        minIdleSession: String = "0",
        version: String = "4",
        security: String = "none"
    ) {
        self.kind = kind
        self.name = name
        self.server = server
        self.port = port
        self.username = username
        self.secret = secret
        self.password = password
        self.upMbps = upMbps
        self.downMbps = downMbps
        self.wireGuardPrivateKey = wireGuardPrivateKey
        self.wireGuardPublicKey = wireGuardPublicKey
        self.wireGuardPreSharedKey = wireGuardPreSharedKey
        self.wireGuardIPv4 = wireGuardIPv4
        self.wireGuardIPv6 = wireGuardIPv6
        self.wireGuardAllowedIPs = wireGuardAllowedIPs
        self.wireGuardReserved = wireGuardReserved
        self.wireGuardMTU = wireGuardMTU
        self.wireGuardPersistentKeepalive = wireGuardPersistentKeepalive
        self.wireGuardDNS = wireGuardDNS
        self.congestionControl = congestionControl
        self.udpRelayMode = udpRelayMode
        self.cipher = cipher
        self.transport = transport
        self.tls = tls
        self.sni = sni
        self.hostHeader = hostHeader
        self.path = path
        self.alpn = alpn
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
        self.fingerprint = fingerprint
        self.flow = flow
        self.skipCertificateVerification = skipCertificateVerification
        self.alterID = alterID
        self.protocolName = protocolName
        self.protocolParam = protocolParam
        self.obfs = obfs
        self.obfsParam = obfsParam
        self.idleSessionCheckInterval = idleSessionCheckInterval
        self.idleSessionTimeout = idleSessionTimeout
        self.minIdleSession = minIdleSession
        self.version = version
        self.security = security
    }

    init(node: ProxyNode) {
        kind = node.kind
        name = node.name
        server = node.server
        port = String(node.port)
        username = node.username ?? ""
        secret = [.vmess, .vless, .tuic].contains(node.kind)
            ? (node.uuid ?? "")
            : (node.password ?? "")
        password = node.kind == .tuic ? (node.password ?? "") : ""
        upMbps = String(node.upMbps ?? 50)
        downMbps = String(node.downMbps ?? 100)
        wireGuardPrivateKey = node.wireGuardPrivateKey ?? ""
        wireGuardPublicKey = node.wireGuardPublicKey ?? ""
        wireGuardPreSharedKey = node.wireGuardPreSharedKey ?? ""
        wireGuardIPv4 = node.wireGuardIPv4 ?? ""
        wireGuardIPv6 = node.wireGuardIPv6 ?? ""
        wireGuardAllowedIPs = node.wireGuardAllowedIPs ?? "0.0.0.0/0,::/0"
        wireGuardReserved = node.wireGuardReserved ?? ""
        wireGuardMTU = node.wireGuardMTU.map(String.init) ?? "1280"
        wireGuardPersistentKeepalive = node.wireGuardPersistentKeepalive.map(String.init) ?? "25"
        wireGuardDNS = node.wireGuardDNS ?? ""
        congestionControl = node.congestionControl ?? ""
        udpRelayMode = node.udpRelayMode ?? ""
        cipher = node.cipher ?? (node.kind == .vmess ? "auto" : "aes-256-gcm")
        transport = node.transport ?? "tcp"
        tls = node.tls
        sni = node.sni ?? ""
        hostHeader = node.hostHeader ?? ""
        path = node.path ?? ""
        alpn = node.alpn ?? ""
        realityPublicKey = node.realityPublicKey ?? ""
        realityShortID = node.realityShortID ?? ""
        fingerprint = node.fingerprint ?? "chrome"
        flow = node.flow ?? ""
        skipCertificateVerification = node.skipCertificateVerification
        alterID = String(node.alterID ?? 0)
        protocolName = node.protocolName ?? "origin"
        protocolParam = node.protocolParam ?? ""
        obfs = node.obfs ?? "none"
        obfsParam = node.obfsParam ?? ""
        idleSessionCheckInterval = String(node.idleSessionCheckInterval ?? 30)
        idleSessionTimeout = String(node.idleSessionTimeout ?? 30)
        minIdleSession = String(node.minIdleSession ?? 0)
        version = String(node.version ?? 4)
        security = node.realityPublicKey == nil ? (node.tls ? "tls" : "none") : "reality"
    }

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
        case .tuic:
            security = "tls"
            alpn = "h3"
        case .wireguard:
            security = "none"
            wireGuardAllowedIPs = "0.0.0.0/0,::/0"
            wireGuardMTU = "1280"
            wireGuardPersistentKeepalive = "25"
        case .hysteria:
            security = "tls"
            obfs = ""
            protocolName = "udp"
            upMbps = "50"
            downMbps = "100"
        case .socks5, .http:
            security = "none"
        case .unknown:
            break
        }
    }

    func makeNode(id: UUID = UUID(), sourceID: UUID? = nil) throws -> ProxyNode {
        guard Self.supportedKinds.contains(kind) else {
            throw ManualNodeValidationError.unsupportedProtocol
        }
        let normalizedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !normalizedServer.isEmpty else { throw ManualNodeValidationError.invalidServer }
        // This field is a hostname/IP, not a share URL. Accepting a complete
        // `https://...` value stores it verbatim and later makes DNS resolve the
        // scheme as part of the hostname.
        let invalidServerCharacters = ["://", "/", "?", "#", "@"]
        guard !invalidServerCharacters.contains(where: normalizedServer.contains) else {
            throw ManualNodeValidationError.invalidServer
        }
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

        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if [
            .shadowsocks, .shadowsocksR, .vmess, .vless, .trojan,
            .hysteria, .hysteria2, .tuic, .anytls, .snell
        ].contains(kind), normalizedSecret.isEmpty {
            throw ManualNodeValidationError.missingSecret
        }
        // TUIC needs both halves; a UUID on its own authenticates nothing.
        if kind == .tuic, normalizedPassword.isEmpty {
            throw ManualNodeValidationError.missingTUICPassword
        }
        let trimmedWGPrivateKey = wireGuardPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWGPublicKey = wireGuardPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWGIPv4 = wireGuardIPv4.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWGIPv6 = wireGuardIPv6.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWGAllowedIPs = wireGuardAllowedIPs.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .wireguard,
           trimmedWGPrivateKey.isEmpty || trimmedWGPublicKey.isEmpty
            || (trimmedWGIPv4.isEmpty && trimmedWGIPv6.isEmpty) || trimmedWGAllowedIPs.isEmpty {
            throw ManualNodeValidationError.incompleteWireGuard
        }
        let parsedUpMbps: Int?
        let parsedDownMbps: Int?
        if kind == .hysteria {
            guard let up = Int(upMbps), up > 0, let down = Int(downMbps), down > 0 else {
                throw ManualNodeValidationError.invalidBandwidth
            }
            parsedUpMbps = up
            parsedDownMbps = down
        } else {
            parsedUpMbps = nil
            parsedDownMbps = nil
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
        let requiresTLS = [.trojan, .hysteria, .hysteria2, .tuic, .anytls].contains(kind)
        let enablesTLS = requiresTLS || tls || ["tls", "reality"].contains(normalizedSecurity) || usesReality

        var node = ProxyNode(
            id: id,
            sourceID: sourceID,
            kind: kind,
            name: normalizedName.isEmpty ? "\(kind.title) · \(normalizedServer)" : normalizedName,
            server: normalizedServer,
            port: parsedPort,
            cipher: [.shadowsocks, .shadowsocksR].contains(kind)
                ? normalizedCipher
                : (kind == .vmess ? (normalizedCipher.isEmpty ? "auto" : normalizedCipher) : nil),
            // TUIC is the one protocol whose identity and secret are separate
            // fields; everywhere else `secret` is whichever one the protocol has.
            password: kind == .tuic
                ? normalizedPassword
                : ([
                    .shadowsocks, .shadowsocksR, .trojan,
                    .hysteria, .hysteria2, .anytls, .snell, .socks5, .http
                ].contains(kind)
                    ? (normalizedSecret.isEmpty ? nil : normalizedSecret)
                    : nil),
            uuid: [.vmess, .vless, .tuic].contains(kind) ? normalizedSecret : nil,
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
                : (kind == .hysteria && !normalizedProtocolName.isEmpty ? normalizedProtocolName : nil),
            protocolParam: kind == .shadowsocksR && !normalizedProtocolParam.isEmpty
                ? normalizedProtocolParam
                : nil,
            // Hysteria 1's obfs is one shared string rather than Hysteria 2's
            // method-plus-password pair, so it uses `obfs` alone.
            obfs: [.shadowsocks, .shadowsocksR, .hysteria, .hysteria2, .snell].contains(kind)
                && !normalizedObfs.isEmpty
                ? normalizedObfs
                : nil,
            obfsParam: [.shadowsocks, .shadowsocksR, .hysteria2, .snell].contains(kind) && !normalizedObfsParam.isEmpty
                ? normalizedObfsParam
                : nil,
            idleSessionCheckInterval: parsedIdleSessionCheckInterval,
            idleSessionTimeout: parsedIdleSessionTimeout,
            minIdleSession: parsedMinIdleSession,
            version: parsedVersion,
            congestionControl: kind == .tuic && !congestionControl.isEmpty ? congestionControl : nil,
            udpRelayMode: kind == .tuic && !udpRelayMode.isEmpty ? udpRelayMode : nil,
            upMbps: parsedUpMbps,
            downMbps: parsedDownMbps,
            wireGuardPrivateKey: kind == .wireguard ? trimmedWGPrivateKey : nil,
            wireGuardPublicKey: kind == .wireguard ? trimmedWGPublicKey : nil,
            wireGuardPreSharedKey: kind == .wireguard ? wireGuardPreSharedKey.nilIfBlank : nil,
            wireGuardIPv4: kind == .wireguard ? trimmedWGIPv4.nilIfBlank : nil,
            wireGuardIPv6: kind == .wireguard ? trimmedWGIPv6.nilIfBlank : nil,
            wireGuardAllowedIPs: kind == .wireguard ? trimmedWGAllowedIPs : nil,
            wireGuardReserved: kind == .wireguard ? wireGuardReserved.nilIfBlank : nil,
            wireGuardMTU: kind == .wireguard ? Int(wireGuardMTU) : nil,
            wireGuardPersistentKeepalive: kind == .wireguard ? Int(wireGuardPersistentKeepalive) : nil,
            wireGuardDNS: kind == .wireguard ? wireGuardDNS.nilIfBlank : nil,
            rawURI: ""
        )
        node.rawURI = ProxyNodeShareLinkGenerator().link(for: node)
        return node
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
