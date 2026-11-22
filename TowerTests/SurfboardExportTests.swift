import XCTest
@testable import Tower

/// The LAN `target=surfboard` alias reuses the Surge profile, narrowed to the
/// Surfboard manual (getsurfboard.com/docs/profile-format/proxy, checked
/// against mobile-2.36.0 on 2026-11-22).
final class SurfboardExportTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let preset = RulePreset.builtIns[0]
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    private func vmessHTTPUpgrade() throws -> ProxyNode {
        let json = """
        {"v":"2","ps":"M-HUP","add":"m.example.com","port":"443","id":"\(uuid)","aid":"0","net":"httpupgrade","host":"cdn.example.com","path":"/up","tls":"tls","sni":"cdn.example.com"}
        """
        return try XCTUnwrap(parser.parseURI("vmess://" + Data(json.utf8).base64EncodedString()))
    }

    private func trojan(_ type: String, name: String) throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("trojan://secret@t.example.com:443?security=tls&sni=t.example.com&type=\(type)&path=%2Fup&host=t.example.com#\(name)"))
    }

    private func vless(_ query: String, name: String) throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("vless://\(uuid)@edge.example.com:443?\(query)#\(name)"))
    }

    private func snell(version: Int, name: String) -> ProxyNode {
        ProxyNode(kind: .snell, name: name, server: "snell.example", port: 443,
                  password: "a-long-enough-psk", version: version, rawURI: "snell://\(name)")
    }

    private func shadowsocks(cipher: String, name: String) -> ProxyNode {
        var node = ProxyNode(kind: .shadowsocks, name: name, server: "ss.example", port: 8388, rawURI: "ss://\(name)")
        node.cipher = cipher
        node.password = "secret"
        return node
    }

    private func wireGuard(name: String, mtu: Int?, reserved: String? = nil) -> ProxyNode {
        var node = ProxyNode(kind: .wireguard, name: name, server: "wg.example", port: 51820, rawURI: "wg://\(name)")
        node.wireGuardPrivateKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        node.wireGuardPublicKey = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
        node.wireGuardIPv4 = "10.0.0.2"
        node.wireGuardAllowedIPs = "0.0.0.0/0, ::/0"
        node.wireGuardDNS = "1.1.1.1"
        node.wireGuardMTU = mtu
        node.wireGuardReserved = reserved
        return node
    }

    private func ssh() -> ProxyNode {
        var node = ProxyNode(kind: .ssh, name: "SSH", server: "ssh.example", port: 22, rawURI: "ssh://test")
        node.username = "root"
        node.password = "secret"
        return node
    }

    private func generate(_ nodes: [ProxyNode], dialect: SurgeDialect) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(
            nodes: nodes, preset: preset, target: .surge,
            supportedKindsOverride: dialect == .surfboard ? LANSubscriptionFormat.surfboard.supportedKindsOverride : nil,
            surgeDialect: dialect
        )
    }

    private func names(in output: GeneratedConfiguration) -> Set<String> {
        let proxies = output.content.components(separatedBy: "[Proxy]\n").dropFirst().first?
            .components(separatedBy: "\n[").first ?? ""
        return Set(proxies.split(separator: "\n").compactMap { line in
            line.range(of: " = ").map { String(line[..<$0.lowerBound]) }
        })
    }

    func testSurfboardFormatUsesSurfboardDialectAndKinds() throws {
        XCTAssertEqual(LANSubscriptionFormat.surfboard.surgeDialect, .surfboard)
        XCTAssertEqual(LANSubscriptionFormat.surge.surgeDialect, .surge)
        let kinds = try XCTUnwrap(LANSubscriptionFormat.surfboard.supportedKindsOverride)
        XCTAssertEqual(kinds, ConfigurationGenerator.surfboardKinds)
        XCTAssertTrue(kinds.allSatisfy { ClientTarget.surge.supports($0) })
        for kind in [ProxyKind.ssh, .trustTunnel, .masque, .shadowsocksR, .hysteria] {
            XCTAssertFalse(kinds.contains(kind), kind.rawValue)
        }
        XCTAssertNil(LANSubscriptionFormat.surge.supportedKindsOverride)
    }

    func testSurfboardSkipsWhatItsManualDoesNotDocument() throws {
        let kept = [
            try trojan("ws", name: "T-WS"),
            try vless("security=tls&sni=edge.example.com&type=httpupgrade&path=%2Fup&host=edge.example.com", name: "V-HUP"),
            snell(version: 5, name: "Snell5"),
            shadowsocks(cipher: "aes-256-gcm", name: "SS-GCM"),
            shadowsocks(cipher: "none", name: "SS-None"),
            wireGuard(name: "WG-OK", mtu: 1280)
        ]
        let skipped = [
            try vmessHTTPUpgrade(),
            try trojan("httpupgrade", name: "T-HUP"),
            snell(version: 6, name: "Snell6"),
            wireGuard(name: "WG-NoMTU", mtu: nil),
            wireGuard(name: "WG-Reserved", mtu: 1280, reserved: "1,2,3"),
            ssh()
        ]

        // Surge itself writes every one of these.
        let surge = generate(kept + skipped, dialect: .surge)
        XCTAssertEqual(surge.supportedNodeCount, kept.count + skipped.count, surge.skippedNodes.map(\.name).description)

        let surfboard = generate(kept + skipped, dialect: .surfboard)
        XCTAssertEqual(surfboard.supportedNodeCount, kept.count, surfboard.content)
        XCTAssertEqual(surfboard.skippedNodeCount, skipped.count)
        XCTAssertEqual(names(in: surfboard), Set(kept.map(\.name)))
        XCTAssertEqual(Set(surfboard.skippedNodes.map(\.name)), Set(skipped.map(\.name)))
        XCTAssertFalse(surfboard.content.contains("[WireGuard tower-\(skipped[3].id.uuidString.lowercased())]"))

        let reasons = Dictionary(uniqueKeysWithValues: surfboard.skippedNodes.map { ($0.name, $0.reason) })
        XCTAssertEqual(reasons["SSH"], String(localized: "当前客户端不支持此协议。"))
        XCTAssertEqual(reasons["T-HUP"], String(localized: "当前客户端不支持此节点的传输方式。"))
        XCTAssertEqual(reasons["M-HUP"], String(localized: "当前客户端不支持此节点的传输方式。"))
    }

    func testVLESSFollowsSurgeRulesUnderSurfboard() throws {
        let pbk = "pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com"
        let reality = try vless("security=reality&\(pbk)&flow=xtls-rprx-vision", name: "Reality")
        let xhttp = try vless("security=tls&sni=edge.example.com&type=xhttp&path=%2Fx&mode=packet-up", name: "XHTTP")
        let grpcPlain = try vless("type=grpc&serviceName=g", name: "gRPC-Plain")
        for node in [reality, xhttp] {
            XCTAssertTrue(ConfigurationGenerator.surfboardAccepts(node), node.name)
        }
        let output = generate([reality, xhttp, grpcPlain], dialect: .surfboard)
        XCTAssertEqual(names(in: output), ["Reality", "XHTTP"])
    }

    @MainActor
    func testRequestCacheSeparatesSurfboardFromSurge() {
        let model = AppModel(arguments: ["--demo"])
        let surge = model.configurationRequest(target: .surge)
        let surfboard = model.configurationRequest(
            target: .surge,
            supportedKindsOverride: LANSubscriptionFormat.surfboard.supportedKindsOverride,
            surgeDialect: .surfboard
        )
        XCTAssertNotEqual(surge.key, surfboard.key)
        XCTAssertEqual(model.configurationRequest(target: .surge).key, surge.key)
    }
}
