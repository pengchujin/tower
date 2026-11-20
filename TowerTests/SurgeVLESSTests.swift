import XCTest
@testable import Tower

/// Surge iOS 6.0 / Mac 6.12 (App Store and Sparkle, 2026-11-17/19) ship the
/// `vless` policy with Encryption, XHTTP and HTTPUpgrade, and TrustTunnel's
/// `client-random-auth-key` (https://nssurge.com/surge-ios-6/release-notes).
final class SurgeVLESSTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let preset = RulePreset.builtIns[0]
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    private func node(_ query: String, name: String) throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("vless://\(uuid)@edge.example.com:443?\(query)#\(name)"))
    }

    private func surgeLine(for node: ProxyNode) -> String? {
        let output = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: .surge)
        return output.content.components(separatedBy: "\n")
            .first { $0.hasPrefix("\(node.name) = vless,") }
    }

    // MARK: - Whitelist

    func testSurgeExportsVLESSInEveryForm() throws {
        XCTAssertTrue(ClientTarget.surge.supports(.vless))
        XCTAssertTrue(ClientTarget.surgeMac.supports(.vless))
        let tls = try node("security=tls&sni=edge.example.com", name: "V-TLS")
        let xhttp = try node("security=tls&type=xhttp&path=%2Fx", name: "V-XHTTP")
        let plainGRPC = try node("type=grpc&serviceName=g", name: "V-GRPC")
        for target in [ClientTarget.surge, .surgeMac] {
            let output = ConfigurationGenerator().generate(nodes: [tls, xhttp, plainGRPC], preset: preset, target: target)
            XCTAssertTrue(output.content.contains("V-TLS = vless,"), target.rawValue)
            XCTAssertTrue(output.content.contains("V-XHTTP = vless,"), target.rawValue)
            XCTAssertEqual(output.supportedNodeCount, 2, target.rawValue)
            XCTAssertTrue(output.hasExportableProxies)
            // gRPC without TLS has no Surge form: still skipped and counted.
            XCTAssertEqual(output.skippedNodes.map(\.name), ["V-GRPC"], target.rawValue)
            XCTAssertFalse(output.diagnostics.contains { $0.contains("TestFlight") || $0.contains("Beta") })
        }
        // The protocol filter still wins.
        let filtered = ConfigurationGenerator().generate(nodes: [tls], preset: preset, target: .surge, excludedKinds: [.vless])
        XCTAssertEqual(filtered.skippedNodeCount, 1)
        XCTAssertFalse(filtered.hasExportableProxies)
    }

    // MARK: - Proxy lines (manual.nssurge.com/policies/vless.html)

    func testRealityVisionLine() throws {
        let node = try node(
            "security=reality&type=tcp&flow=xtls-rprx-vision&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4"
                + "&sid=0123456789abcdef&sni=www.microsoft.com&fp=chrome",
            name: "V-REALITY"
        )
        XCTAssertEqual(
            surgeLine(for: node),
            "V-REALITY = vless, edge.example.com, 443, username=\(uuid), flow=xtls-rprx-vision, sni=www.microsoft.com, "
                + "reality-public-key=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4, reality-short-id=0123456789abcdef"
        )
    }

    func testTLSVisionLine() throws {
        let node = try node("security=tls&flow=xtls-rprx-vision&sni=edge.example.com", name: "V-TLS")
        XCTAssertEqual(
            surgeLine(for: node),
            "V-TLS = vless, edge.example.com, 443, username=\(uuid), flow=xtls-rprx-vision, tls=true, sni=edge.example.com"
        )
    }

    func testWebSocketLines() throws {
        let tls = try node("security=tls&type=ws&path=%2Fvless&host=cdn.example.com&sni=cdn.example.com", name: "V-WSS")
        XCTAssertEqual(
            surgeLine(for: tls),
            "V-WSS = vless, edge.example.com, 443, username=\(uuid), tls=true, sni=cdn.example.com, "
                + "ws=true, ws-path=/vless, ws-headers=Host:cdn.example.com"
        )
        let plain = try node("type=ws&path=%2Fvless&host=cdn.example.com", name: "V-WS")
        let line = try XCTUnwrap(surgeLine(for: plain))
        XCTAssertFalse(line.contains("tls=true"))
        XCTAssertTrue(line.contains("ws=true, ws-path=/vless"))
    }

    func testGRPCLine() throws {
        let node = try node("security=tls&type=grpc&serviceName=mygrpc&sni=edge.example.com", name: "V-GRPC")
        XCTAssertEqual(
            surgeLine(for: node),
            "V-GRPC = vless, edge.example.com, 443, username=\(uuid), tls=true, sni=edge.example.com, "
                + "grpc=true, grpc-service-name=mygrpc"
        )
        let reality = try self.node(
            "security=reality&type=grpc&serviceName=mygrpc&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com",
            name: "V-GRPC-R"
        )
        XCTAssertNotNil(surgeLine(for: reality))
    }

    private let encryption = "mlkem768x25519plus.native.0rtt.vbS7cJA-Lc9lQ_abc.QzR4m1="

    func testEncryptionLines() throws {
        var raw = try node("flow=xtls-rprx-vision", name: "V-ENC")
        raw.vlessEncryption = encryption
        XCTAssertEqual(
            surgeLine(for: raw),
            "V-ENC = vless, edge.example.com, 443, username=\(uuid), flow=xtls-rprx-vision, encryption=\(encryption)"
        )
        // With Encryption, Vision needs no TLS and runs over WebSocket too.
        var ws = try node("type=ws&path=%2Fvless&flow=xtls-rprx-vision", name: "V-ENC-WS")
        ws.vlessEncryption = "mlkem768x25519plus.random.1rtt.100-111-1111.75-0-111.key1.key2"
        let line = try XCTUnwrap(surgeLine(for: ws))
        XCTAssertTrue(line.contains("flow=xtls-rprx-vision, encryption=mlkem768x25519plus.random.1rtt.100-111-1111.75-0-111.key1.key2"), line)
        XCTAssertTrue(line.contains("ws=true, ws-path=/vless"))
        // Encryption on top of REALITY keeps both.
        var reality = try node("security=reality&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com",
                               name: "V-ENC-R")
        reality.vlessEncryption = encryption
        let realityLine = try XCTUnwrap(surgeLine(for: reality))
        XCTAssertTrue(realityLine.contains("encryption=\(encryption)"))
        XCTAssertTrue(realityLine.contains("reality-public-key="))
    }

    func testXHTTPLines() throws {
        let reality = try node(
            "security=reality&type=xhttp&path=%2Fxhttp&mode=stream-one&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4"
                + "&sni=www.microsoft.com",
            name: "V-XHTTP"
        )
        XCTAssertEqual(
            surgeLine(for: reality),
            "V-XHTTP = vless, edge.example.com, 443, username=\(uuid), sni=www.microsoft.com, "
                + "reality-public-key=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4, xhttp=true, xhttp-path=/xhttp, xhttp-mode=stream-one"
        )
        let cdn = try node("security=tls&type=xhttp&path=%2Fxhttp%3Fed%3D1&host=cdn.example.com&mode=packet-up"
                               + "&sni=cdn.example.com&alpn=h3",
                           name: "V-XHTTP-CDN")
        XCTAssertEqual(
            surgeLine(for: cdn),
            "V-XHTTP-CDN = vless, edge.example.com, 443, username=\(uuid), tls=true, sni=cdn.example.com, alpn=h3, "
                + "xhttp=true, xhttp-path=/xhttp?ed=1, xhttp-host=cdn.example.com, xhttp-mode=packet-up"
        )
        // `auto` is Surge's default and is left out; plain XHTTP has no TLS.
        let plain = try node("type=xhttp&mode=auto", name: "V-XHTTP-PLAIN")
        XCTAssertEqual(surgeLine(for: plain), "V-XHTTP-PLAIN = vless, edge.example.com, 443, username=\(uuid), xhttp=true")
        // Vision over XHTTP needs Encryption.
        var vision = try node("security=tls&type=xhttp&path=%2Fx&flow=xtls-rprx-vision&sni=edge.example.com", name: "V-XHTTP-ENC")
        vision.vlessEncryption = encryption
        XCTAssertNotNil(surgeLine(for: vision))
    }

    func testCombinationsSurgeCannotCarryAreSkipped() throws {
        let pbk = "pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com"
        var badEncryption = try node("security=tls&sni=edge.example.com", name: "BadEncryption")
        badEncryption.vlessEncryption = "mlkem768x25519plus.native.2rtt.key"
        var unknownMethod = try node("security=tls&sni=edge.example.com", name: "UnknownMethod")
        unknownMethod.vlessEncryption = "futurekem.native.0rtt.key"
        var noKey = try node("security=tls&sni=edge.example.com", name: "NoKey")
        noKey.vlessEncryption = "mlkem768x25519plus.native.0rtt"
        var encryptedGRPCVision = try node("security=tls&type=grpc&serviceName=g&flow=xtls-rprx-vision", name: "EncGRPCVision")
        encryptedGRPCVision.vlessEncryption = encryption
        let cases: [ProxyNode] = [
            try node("security=reality&type=httpupgrade&path=%2Fx&\(pbk)", name: "HTTPUpgradeReality"),
            try node("security=tls&type=xhttp&path=%2Fx&mode=stream-two", name: "XHTTPUnknownMode"),
            try node("security=tls&type=xhttp&path=%2Fx&flow=xtls-rprx-vision", name: "XHTTPVision"),
            try node("type=grpc&serviceName=mygrpc", name: "PlainGRPC"),
            try node("security=reality&type=ws&path=%2Fx&\(pbk)", name: "WSReality"),
            try node("security=tls&type=ws&path=%2Fx&flow=xtls-rprx-vision", name: "WSVision"),
            try node("security=tls&type=grpc&serviceName=g&flow=xtls-rprx-vision", name: "GRPCVision"),
            try node("flow=xtls-rprx-vision", name: "PlainVision"),
            try node("security=tls&flow=xtls-rprx-direct", name: "LegacyFlow"),
            try node("security=reality&\(pbk)&sid=0123456789abcdef01", name: "LongShortID"),
            badEncryption, unknownMethod, noKey, encryptedGRPCVision
        ]
        let output = ConfigurationGenerator().generate(nodes: cases, preset: preset, target: .surge)
        XCTAssertFalse(output.content.contains("= vless,"), output.content)
        XCTAssertEqual(output.skippedNodeCount, cases.count)
        XCTAssertEqual(output.skippedNodes.count, cases.count)
    }

    // MARK: - TrustTunnel client-random-auth-key

    private let authKey = "00112233445566778899aabbccddeeff"

    private func keyedTrustTunnel(server: String = "t.example.com", sni: String? = "t.example.com") -> ProxyNode {
        ProxyNode(kind: .trustTunnel, name: "TT-Key", server: server, port: 443, password: "p",
                  username: "u", tls: true, sni: sni, rawURI: "",
                  trustTunnel: TrustTunnelOptions(quic: true, clientRandomAuthKey: authKey))
    }

    func testTrustTunnelAuthKeyIsWrittenForSurge() {
        let node = keyedTrustTunnel()
        for target in [ClientTarget.surge, .surgeMac] {
            let output = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: target)
            let line = output.content.components(separatedBy: "\n").first { $0.hasPrefix("TT-Key = ") }
            XCTAssertEqual(line, "TT-Key = trust-tunnel, t.example.com, 443, username=u, password=p, h3=true, "
                + "client-random-auth-key=\(authKey), sni=t.example.com", target.rawValue)
            XCTAssertEqual(output.skippedNodeCount, 0, target.rawValue)
        }
    }

    func testTrustTunnelAuthKeyNodeIsSkippedEverywhereElse() {
        let node = keyedTrustTunnel()
        for target in ClientTarget.allCases where ![.surge, .surgeMac].contains(target) && target.supports(.trustTunnel) {
            let output = target.supportsFullConfigurationExport
                ? ConfigurationGenerator().generate(nodes: [node], preset: preset, target: target,
                                                    supportedKindsOverride: Set(ProxyKind.allCases))
                : ConfigurationGenerator().generateNodeSubscription(nodes: [node], target: target)
            XCTAssertFalse(output.content.contains("t.example.com"), target.rawValue)
            XCTAssertEqual(output.skippedNodeCount, 1, target.rawValue)
        }
        // The same node without the key still goes to Stash over HTTP/3.
        var plain = node
        plain.trustTunnel?.clientRandomAuthKey = nil
        XCTAssertTrue(ConfigurationGenerator().generate(nodes: [plain], preset: preset, target: .clash)
            .content.contains("t.example.com"))
    }

    func testTrustTunnelAuthKeyNeedsAnSNI() {
        // A bare IP with no sni cannot derive the key; Surge rejects it.
        let ipOnly = keyedTrustTunnel(server: "192.0.2.1", sni: nil)
        let output = ConfigurationGenerator().generate(nodes: [ipOnly], preset: preset, target: .surge)
        XCTAssertFalse(output.content.contains("192.0.2.1"))
        XCTAssertEqual(output.skippedNodeCount, 1)
        XCTAssertNotNil(ConfigurationGenerator().generate(
            nodes: [keyedTrustTunnel(server: "192.0.2.1", sni: "t.example.com")], preset: preset, target: .surge).content.range(of: "client-random-auth-key="))
    }

    func testManualFormValidatesTrustTunnelAuthKey() throws {
        var draft = ManualNodeDraft()
        draft.applyDefaults(for: .trustTunnel)
        draft.server = "t.example.com"
        draft.port = "443"
        draft.username = "u"
        draft.secret = "p"
        draft.trustTunnelAuthKey = "xyz"
        XCTAssertThrowsError(try draft.makeNode()) {
            XCTAssertEqual($0 as? ManualNodeValidationError, .invalidTrustTunnelAuthKey)
        }
        draft.trustTunnelAuthKey = "abc"
        XCTAssertThrowsError(try draft.makeNode())
        draft.trustTunnelAuthKey = " 00112233445566778899AABBCCDDEEFF "
        let node = try draft.makeNode()
        XCTAssertEqual(node.trustTunnel?.clientRandomAuthKey, authKey)
        XCTAssertEqual(ManualNodeDraft(node: node).trustTunnelAuthKey, authKey)

        draft.server = "192.0.2.1"
        draft.sni = ""
        XCTAssertThrowsError(try draft.makeNode()) {
            XCTAssertEqual($0 as? ManualNodeValidationError, .trustTunnelAuthKeyNeedsSNI)
        }
        draft.sni = "t.example.com"
        XCTAssertNoThrow(try draft.makeNode())

        draft.trustTunnelAuthKey = ""
        draft.sni = ""
        XCTAssertNil(try draft.makeNode().trustTunnel?.clientRandomAuthKey)
    }

    func testTrustTunnelAuthKeySharesAsSurgeLineAndChangesIdentity() {
        let node = keyedTrustTunnel()
        XCTAssertTrue(ProxyNodeShareLinkGenerator().canonicalLink(for: node).contains("client-random-auth-key=\(authKey)"))
        var plain = node
        plain.trustTunnel?.clientRandomAuthKey = nil
        XCTAssertNotEqual(node.canonicalKey, plain.canonicalKey)
    }

    // MARK: - Node-only lists

    func testNodeOnlySurgeListWritesVLESS() throws {
        let vless = try node("security=reality&flow=xtls-rprx-vision&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4"
            + "&sid=0123456789abcdef&sni=www.microsoft.com", name: "V-REALITY")
        let upgrade = try node("security=tls&type=httpupgrade&path=%2Fx", name: "V-HUP")
        for target in [ClientTarget.surge, .surgeMac] {
            let output = ConfigurationGenerator().generateNodeSubscription(nodes: [vless, upgrade], target: target)
            XCTAssertTrue(output.content.hasPrefix("V-REALITY = vless, edge.example.com, 443,"), output.content)
            XCTAssertTrue(output.content.contains("reality-public-key="))
            XCTAssertTrue(output.content.contains("V-HUP = vless,"))
            XCTAssertTrue(output.content.contains("ws-http-upgrade=true"))
            XCTAssertEqual(output.contentMode, .nodesOnly)
            XCTAssertEqual(output.supportedNodeCount, 2)
            XCTAssertTrue(output.skippedNodes.isEmpty)
        }
    }
}
