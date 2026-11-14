import XCTest
@testable import Tower

/// Surge iOS 6 TestFlight (build 4024+) adds a `vless` policy. App Store
/// Surge does not have it, so VLESS is written only for a request whose
/// User-Agent names a build that does.
final class SurgeVLESSTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let preset = RulePreset.builtIns[0]
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    private func node(_ query: String, name: String) throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("vless://\(uuid)@edge.example.com:443?\(query)#\(name)"))
    }

    private func surgeLine(for node: ProxyNode, vless: Bool = true) -> String? {
        let output = ConfigurationGenerator().generate(
            nodes: [node], preset: preset, target: .surge,
            supportedKindsOverride: vless ? SurgeClientCapabilities.vlessKinds : nil
        )
        return output.content.components(separatedBy: "\n")
            .first { $0.hasPrefix("\(node.name) = vless,") }
    }

    // MARK: - Version gate

    func testOnlySurgeIOSBuild4024AndLaterGetVLESS() {
        XCTAssertTrue(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge iOS/4024 SurgeCore/6011000"))
        XCTAssertTrue(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge iOS/4025"))
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge iOS/4022 SurgeCore/6011000"))
        // App Store 5.x and its TestFlight builds are all below 4000.
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge iOS/3875"))
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge iOS/5.14"))
        // Surge Mac 6.12.0 Beta, captured 2026-11-13; 6.11.0 is 12800.
        XCTAssertTrue(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge Mac/12820 SurgeCore/6012000"))
        XCTAssertTrue(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge Mac/12900"))
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge Mac/12800 SurgeCore/6011000"))
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Surge Mac/10661"))
        // An iOS build number is far below the Mac threshold, and vice versa
        // a Mac build never reads as an iOS one.
        XCTAssertNil(SurgeClientCapabilities.iOSBuild(userAgent: "Surge Mac/12820"))
        XCTAssertEqual(SurgeClientCapabilities.macBuild(userAgent: "Surge Mac/12820 SurgeCore/6012000"), 12820)
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: "Stash/3.1.0"))
        XCTAssertFalse(SurgeClientCapabilities.supportsVLESS(userAgent: nil))
        XCTAssertNil(SurgeClientCapabilities.supportedKinds(userAgent: "Surge iOS/4022"))
        XCTAssertEqual(SurgeClientCapabilities.supportedKinds(userAgent: "Surge iOS/4024"),
                       SurgeClientCapabilities.vlessKinds)
    }

    func testVLESSKindsKeepEverySurgeBaselineProtocol() {
        for kind in ProxyKind.allCases where ClientTarget.surge.supports(kind) {
            XCTAssertTrue(SurgeClientCapabilities.vlessKinds.contains(kind), kind.rawValue)
        }
        XCTAssertFalse(ClientTarget.surge.supports(.vless), "Exported files keep the App Store baseline")
    }

    func testBaselineSurgeProfileStillSkipsVLESS() throws {
        let node = try node("security=tls&sni=edge.example.com", name: "V-TLS")
        let output = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: .surge)
        XCTAssertFalse(output.content.contains("= vless,"))
        // A TestFlight build does get it, so it is a note, not a skip.
        XCTAssertEqual(output.skippedNodeCount, 0)
        XCTAssertTrue(output.skippedNodes.isEmpty)
        XCTAssertEqual(output.diagnostics.count(where: { $0.contains("TestFlight 4024") }), 1)

        // A VLESS node Surge cannot carry at all is still skipped.
        let xhttp = try self.node("security=tls&type=xhttp&path=%2Fx", name: "V-XHTTP")
        let mixed = ConfigurationGenerator().generate(nodes: [node, xhttp], preset: preset, target: .surge)
        XCTAssertEqual(mixed.skippedNodeCount, 1)
        XCTAssertEqual(mixed.skippedNodes.map(\.name), ["V-XHTTP"])
        XCTAssertTrue(mixed.diagnostics.contains { $0.hasPrefix("1 ") && $0.contains("TestFlight 4024") })
        // Surge Mac gets its own note naming the Mac beta.
        let mac = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: .surgeMac)
        XCTAssertEqual(mac.skippedNodeCount, 0)
        XCTAssertFalse(mac.content.contains("= vless,"))
        XCTAssertTrue(mac.diagnostics.contains { $0.contains("Surge Mac 6.12.0") })
        XCTAssertFalse(mac.diagnostics.contains { $0.contains("TestFlight") })
        let macWithVLESS = ConfigurationGenerator().generate(
            nodes: [node], preset: preset, target: .surgeMac,
            supportedKindsOverride: SurgeClientCapabilities.vlessKinds)
        XCTAssertTrue(macWithVLESS.content.contains("V-TLS = vless,"))
        XCTAssertFalse(macWithVLESS.diagnostics.contains { $0.contains("Surge Mac 6.12.0") })
        // Excluding VLESS in the protocol filter keeps it a plain skip.
        let filtered = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: .surge, excludedKinds: [.vless])
        XCTAssertEqual(filtered.skippedNodeCount, 1)
        XCTAssertFalse(filtered.diagnostics.contains { $0.contains("TestFlight") })
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

    func testCombinationsSurgeCannotCarryAreSkipped() throws {
        let pbk = "pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com"
        var encrypted = try node("security=tls&sni=edge.example.com", name: "Encrypted")
        encrypted.vlessEncryption = "mlkem768x25519plus.native.0rtt.key"
        let cases: [ProxyNode] = [
            try node("security=tls&type=xhttp&path=%2Fx", name: "XHTTP"),
            try node("security=tls&type=httpupgrade&path=%2Fx", name: "HTTPUpgrade"),
            try node("type=grpc&serviceName=mygrpc", name: "PlainGRPC"),
            try node("security=reality&type=ws&path=%2Fx&\(pbk)", name: "WSReality"),
            try node("security=tls&type=ws&path=%2Fx&flow=xtls-rprx-vision", name: "WSVision"),
            try node("security=tls&type=grpc&serviceName=g&flow=xtls-rprx-vision", name: "GRPCVision"),
            try node("flow=xtls-rprx-vision", name: "PlainVision"),
            try node("security=tls&flow=xtls-rprx-direct", name: "LegacyFlow"),
            try node("security=reality&\(pbk)&sid=0123456789abcdef01", name: "LongShortID"),
            encrypted
        ]
        let output = ConfigurationGenerator().generate(
            nodes: cases, preset: preset, target: .surge,
            supportedKindsOverride: SurgeClientCapabilities.vlessKinds
        )
        XCTAssertFalse(output.content.contains("= vless,"), output.content)
        XCTAssertEqual(output.skippedNodeCount, cases.count)
        XCTAssertEqual(output.skippedNodes.count, cases.count)
    }

    // MARK: - TrustTunnel client-random-auth-key (same beta builds)

    private let authKey = "00112233445566778899aabbccddeeff"

    private func keyedTrustTunnel(server: String = "t.example.com", sni: String? = "t.example.com") -> ProxyNode {
        ProxyNode(kind: .trustTunnel, name: "TT-Key", server: server, port: 443, password: "p",
                  username: "u", tls: true, sni: sni, rawURI: "",
                  trustTunnel: TrustTunnelOptions(quic: true, clientRandomAuthKey: authKey))
    }

    func testTrustTunnelAuthKeyIsWrittenOnlyForSurgeBetas() {
        let node = keyedTrustTunnel()
        for target in [ClientTarget.surge, .surgeMac] {
            let beta = ConfigurationGenerator().generate(
                nodes: [node], preset: preset, target: target,
                supportedKindsOverride: SurgeClientCapabilities.vlessKinds)
            let line = beta.content.components(separatedBy: "\n").first { $0.hasPrefix("TT-Key = ") }
            XCTAssertEqual(line, "TT-Key = trust-tunnel, t.example.com, 443, username=u, password=p, h3=true, "
                + "client-random-auth-key=\(authKey), sni=t.example.com", target.rawValue)

            let baseline = ConfigurationGenerator().generate(nodes: [node], preset: preset, target: target)
            XCTAssertFalse(baseline.content.contains("TT-Key"), target.rawValue)
            XCTAssertEqual(baseline.skippedNodeCount, 0, target.rawValue)
            XCTAssertTrue(baseline.diagnostics.contains { $0.contains("TrustTunnel") }, target.rawValue)
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
        let output = ConfigurationGenerator().generate(
            nodes: [ipOnly], preset: preset, target: .surge,
            supportedKindsOverride: SurgeClientCapabilities.vlessKinds)
        XCTAssertFalse(output.content.contains("192.0.2.1"))
        XCTAssertEqual(output.skippedNodeCount, 1)
        XCTAssertNotNil(ConfigurationGenerator().generate(
            nodes: [keyedTrustTunnel(server: "192.0.2.1", sni: "t.example.com")], preset: preset, target: .surge,
            supportedKindsOverride: SurgeClientCapabilities.vlessKinds).content.range(of: "client-random-auth-key="))
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

    // MARK: - Serving by User-Agent

    func testLANSubscriptionServesVLESSProfileOnlyToNewSurgeIOS() {
        func respond(userAgent: String, target: String = "auto", content: String? = nil) -> String {
            let query = "target=\(target)" + (content.map { "&content=\($0)" } ?? "")
            let response = LANSubscriptionHTTPRouter.response(
                request: "GET /sub/t?\(query) HTTP/1.1\r\nUser-Agent: \(userAgent)\r\n\r\n",
                token: "t",
                exactClientConfiguration: { client in
                    GeneratedConfiguration(target: client, content: "exact", supportedNodeCount: 0, skippedNodeCount: 0, ruleCount: 0)
                },
                nodeConfiguration: { client in
                    GeneratedConfiguration(target: client, content: "nodes-\(client.rawValue)", supportedNodeCount: 0,
                                           skippedNodeCount: 0, ruleCount: 0, contentMode: .nodesOnly)
                },
                surgeVLESSConfiguration: { client, mode in
                    GeneratedConfiguration(target: client, content: "vless-\(mode.rawValue)-\(client.rawValue)", supportedNodeCount: 1,
                                           skippedNodeCount: 0, ruleCount: 0, contentMode: mode)
                },
                formatConfiguration: { format in
                    GeneratedConfiguration(target: format.generationTarget, content: "baseline",
                                           supportedNodeCount: 0, skippedNodeCount: 0, ruleCount: 0)
                }
            )
            return String(decoding: response.body, as: UTF8.self)
        }
        XCTAssertEqual(respond(userAgent: "Surge iOS/4024 SurgeCore/6011000"), "vless-fullConfiguration-surge")
        XCTAssertEqual(respond(userAgent: "Surge iOS/4024 SurgeCore/6011000", target: "surge"), "vless-fullConfiguration-surge")
        XCTAssertEqual(respond(userAgent: "Surge iOS/4022 SurgeCore/6011000"), "baseline")
        XCTAssertEqual(respond(userAgent: "Surge Mac/12820 SurgeCore/6012000"), "vless-fullConfiguration-surge")
        XCTAssertEqual(respond(userAgent: "Surge Mac/12820 SurgeCore/6012000", target: "surge-mac"), "vless-fullConfiguration-surge-mac")
        XCTAssertEqual(respond(userAgent: "Surge Mac/12800 SurgeCore/6011000", target: "surge-mac"), "exact")
        XCTAssertEqual(respond(userAgent: "Surge Mac/12800 SurgeCore/6011000"), "baseline")
        XCTAssertEqual(respond(userAgent: "Surge iOS/4024", target: "surfboard"), "baseline")

        // Node-only policy-path lists switch the same way.
        XCTAssertEqual(respond(userAgent: "Surge iOS/4024", target: "surge", content: "nodesOnly"), "vless-nodesOnly-surge")
        XCTAssertEqual(respond(userAgent: "Surge Mac/12820", target: "surge-mac", content: "nodesOnly"), "vless-nodesOnly-surge-mac")
        XCTAssertEqual(respond(userAgent: "Surge iOS/4022", target: "surge", content: "nodesOnly"), "nodes-surge")
        XCTAssertEqual(respond(userAgent: "Surge iOS/4024", target: "clash", content: "nodesOnly"), "nodes-clash")
    }

    func testNodeOnlySurgeListWritesVLESSForBetasAndNotesItOtherwise() throws {
        let vless = try node("security=reality&flow=xtls-rprx-vision&pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4"
            + "&sid=0123456789abcdef&sni=www.microsoft.com", name: "V-REALITY")
        let xhttp = try node("security=tls&type=xhttp&path=%2Fx", name: "V-XHTTP")
        for target in [ClientTarget.surge, .surgeMac] {
            let beta = ConfigurationGenerator().generateNodeSubscription(
                nodes: [vless, xhttp], target: target, supportedKindsOverride: SurgeClientCapabilities.vlessKinds)
            XCTAssertTrue(beta.content.hasPrefix("V-REALITY = vless, edge.example.com, 443,"), beta.content)
            XCTAssertTrue(beta.content.contains("reality-public-key="))
            XCTAssertEqual(beta.supportedNodeCount, 1)
            XCTAssertEqual(beta.skippedNodes.map(\.name), ["V-XHTTP"])

            let baseline = ConfigurationGenerator().generateNodeSubscription(nodes: [vless, xhttp], target: target)
            XCTAssertFalse(baseline.content.contains("= vless,"))
            XCTAssertEqual(baseline.contentMode, .nodesOnly)
            XCTAssertEqual(baseline.skippedNodes.map(\.name), ["V-XHTTP"])
            XCTAssertEqual(baseline.diagnostics.count(where: { $0.contains("VLESS") }), 1)
        }
    }

    func testOneTapImportServesVLESSProfileOnlyToNewSurgeIOS() {
        let baseline = GeneratedConfiguration(target: .surge, content: "baseline", supportedNodeCount: 0, skippedNodeCount: 1, ruleCount: 0)
        let variant = GeneratedConfiguration(target: .surge, content: "vless", supportedNodeCount: 1, skippedNodeCount: 0, ruleCount: 0)
        let server = LocalConfigurationServer(configuration: baseline, surgeVLESSVariant: variant, token: "test-token-0123456789abcdef")
        func body(_ headers: String) -> String {
            String(decoding: server.response(forRequestHeaders: "GET /x HTTP/1.1\r\n\(headers)\r\n").body, as: UTF8.self)
        }
        XCTAssertEqual(body("User-Agent: Surge iOS/4024 SurgeCore/6011000\r\nX-Surge-Unlocked-Features: x\r\n"), "vless")
        XCTAssertEqual(body("user-agent: Surge iOS/4025\r\n"), "vless")
        XCTAssertEqual(body("User-Agent: Surge iOS/3875\r\n"), "baseline")
        XCTAssertEqual(body("User-Agent: Surge Mac/12820 SurgeCore/6012000\r\n"), "vless")
        XCTAssertEqual(body("User-Agent: Surge Mac/12800 SurgeCore/6011000\r\n"), "baseline")
        XCTAssertEqual(body(""), "baseline")
        // A Surge iOS UA in the body, not the headers, does not count.
        XCTAssertEqual(body("Accept: */*\r\n\r\nUser-Agent: Surge iOS/4024\r\n"), "baseline")

        let plain = LocalConfigurationServer(configuration: baseline, token: "test-token-0123456789abcdef")
        XCTAssertEqual(String(decoding: plain.response(forRequestHeaders: "GET /x HTTP/1.1\r\nUser-Agent: Surge iOS/4024\r\n\r\n").body,
                              as: UTF8.self), "baseline")
    }
}
