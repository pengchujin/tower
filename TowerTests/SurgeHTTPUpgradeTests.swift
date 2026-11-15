import XCTest
@testable import Tower

/// Surge iOS TestFlight 4027+ / Mac 6.12.0 Beta 12860+ read
/// `ws-http-upgrade=true` with `ws=true` for VMess, Trojan and VLESS
/// (manual.nssurge.com/policies/vmess.html). Older builds would reject the
/// whole profile on the unknown parameter, so the transport is written only
/// for the `.httpUpgrade` tier.
final class SurgeHTTPUpgradeTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let preset = RulePreset.builtIns[0]
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    private func vless(_ query: String, name: String) throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("vless://\(uuid)@edge.example.com:443?\(query)#\(name)"))
    }

    private func vmess() throws -> ProxyNode {
        let json = """
        {"v":"2","ps":"M-HUP","add":"m.example.com","port":"443","id":"\(uuid)","aid":"0","net":"httpupgrade","host":"cdn.example.com","path":"/up","tls":"tls","sni":"cdn.example.com"}
        """
        return try XCTUnwrap(parser.parseURI("vmess://" + Data(json.utf8).base64EncodedString()))
    }

    private func trojan() throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI("trojan://secret@t.example.com:443?security=tls&sni=t.example.com&type=httpupgrade&path=%2Fup&host=t.example.com#T-HUP"))
    }

    private func generate(_ nodes: [ProxyNode], tier: SurgeClientCapabilities.Tier?, target: ClientTarget = .surge) -> GeneratedConfiguration {
        ConfigurationGenerator(surgeTier: tier ?? .vless).generate(
            nodes: nodes, preset: preset, target: target,
            supportedKindsOverride: tier == nil ? nil : SurgeClientCapabilities.vlessKinds)
    }

    private func line(_ name: String, in output: GeneratedConfiguration) -> String? {
        output.content.components(separatedBy: "\n").first { $0.hasPrefix("\(name) = ") }
    }

    func testBuildThresholds() {
        typealias Caps = SurgeClientCapabilities
        XCTAssertEqual(Caps.tier(userAgent: "Surge iOS/4026"), .vlessExtensions)
        XCTAssertEqual(Caps.tier(userAgent: "Surge iOS/4027 SurgeCore/6012000"), .httpUpgrade)
        XCTAssertEqual(Caps.tier(userAgent: "Surge Mac/12840"), .vlessExtensions)
        XCTAssertEqual(Caps.tier(userAgent: "Surge Mac/12860 SurgeCore/6012000"), .httpUpgrade)
    }

    func testNewestBetaWritesHTTPUpgradeForEveryKind() throws {
        let nodes = [try vmess(), try trojan(), try vless("security=tls&sni=edge.example.com&type=httpupgrade&path=%2Fup&host=edge.example.com", name: "V-HUP")]
        for target in [ClientTarget.surge, .surgeMac] {
            let output = generate(nodes, tier: .httpUpgrade, target: target)
            XCTAssertEqual(output.supportedNodeCount, 3, output.content)
            XCTAssertTrue(output.skippedNodes.isEmpty)
            for name in ["M-HUP", "T-HUP", "V-HUP"] {
                let line = try XCTUnwrap(line(name, in: output), name)
                XCTAssertTrue(line.contains("ws=true, ws-http-upgrade=true, ws-path=/up"), line)
            }
            XCTAssertTrue(try XCTUnwrap(line("M-HUP", in: output)).contains("ws-headers=Host:cdn.example.com"))
        }
    }

    func testEarlierBetasAndBaselineNeverSeeTheParameter() throws {
        let nodes = [try vmess(), try trojan(), try vless("security=tls&type=httpupgrade&path=%2Fup", name: "V-HUP")]
        for tier in [nil, SurgeClientCapabilities.Tier.vless, .vlessExtensions] {
            let output = generate(nodes, tier: tier)
            XCTAssertFalse(output.content.contains("ws-http-upgrade"), "\(String(describing: tier))")
            XCTAssertNil(line("M-HUP", in: output))
            XCTAssertNil(line("T-HUP", in: output))
        }
        // Baseline: not skipped, but a note naming the builds.
        let baseline = generate(nodes, tier: nil)
        XCTAssertEqual(baseline.surgeBetaNodeCount, 3)
        XCTAssertTrue(baseline.skippedNodes.isEmpty)
        XCTAssertTrue(baseline.diagnostics.contains { $0.contains("HTTPUpgrade") && $0.contains("4027") })
        let mac = generate(nodes, tier: nil, target: .surgeMac)
        XCTAssertTrue(mac.diagnostics.contains { $0.contains("HTTPUpgrade") && $0.contains("12860") })
    }

    func testPlainWebSocketIsUnchanged() throws {
        let ws = try vless("security=tls&type=ws&path=%2Fws", name: "V-WS")
        let line = try XCTUnwrap(line("V-WS", in: generate([ws], tier: .httpUpgrade)))
        XCTAssertTrue(line.contains("ws=true"))
        XCTAssertFalse(line.contains("ws-http-upgrade"))
    }

    func testVLESSHTTPUpgradeFollowsWebSocketSecurityRules() throws {
        let pbk = "pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com"
        let none = try vless("type=httpupgrade&path=%2Fup", name: "None")
        let reality = try vless("security=reality&type=httpupgrade&path=%2Fup&\(pbk)", name: "Reality")
        let vision = try vless("security=tls&type=httpupgrade&path=%2Fup&flow=xtls-rprx-vision", name: "Vision")
        XCTAssertTrue(ConfigurationGenerator.surgeAcceptsVLESS(none, withExtensions: true, withHTTPUpgrade: true))
        XCTAssertFalse(ConfigurationGenerator.surgeAcceptsVLESS(none, withExtensions: true, withHTTPUpgrade: false))
        XCTAssertFalse(ConfigurationGenerator.surgeAcceptsVLESS(reality, withExtensions: true, withHTTPUpgrade: true))
        XCTAssertFalse(ConfigurationGenerator.surgeAcceptsVLESS(vision, withExtensions: true, withHTTPUpgrade: true))
    }

    func testShadowrocketNeverGetsTheSurgeParameter() throws {
        let output = ConfigurationGenerator(surgeTier: .httpUpgrade).generate(
            nodes: [try vmess()], preset: preset, target: .shadowrocket)
        XCTAssertEqual(output.supportedNodeCount, 1)
        XCTAssertFalse(output.content.contains("ws-http-upgrade"))
    }

    func testOneTapImportPicksHTTPUpgradeTier() {
        let baseline = GeneratedConfiguration(target: .surge, content: "baseline", supportedNodeCount: 0, skippedNodeCount: 1, ruleCount: 0)
        let upgrade = GeneratedConfiguration(target: .surge, content: "upgrade", supportedNodeCount: 1, skippedNodeCount: 0, ruleCount: 0)
        let server = LocalConfigurationServer(configuration: baseline, surgeVLESSVariants: [.httpUpgrade: upgrade],
                                              token: "test-token-0123456789abcdef")
        func body(_ headers: String) -> String {
            String(decoding: server.response(forRequestHeaders: "GET /x HTTP/1.1\r\n\(headers)\r\n").body, as: UTF8.self)
        }
        XCTAssertEqual(body("User-Agent: Surge iOS/4027\r\n"), "upgrade")
        XCTAssertEqual(body("User-Agent: Surge iOS/4026\r\n"), "baseline")
        XCTAssertEqual(body("User-Agent: Surge Mac/12860\r\n"), "upgrade")
        XCTAssertEqual(body("User-Agent: Surge Mac/12840\r\n"), "baseline")
    }
}
