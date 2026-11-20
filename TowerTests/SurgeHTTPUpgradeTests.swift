import XCTest
@testable import Tower

/// Surge iOS 6.0 / Mac 6.12 read `ws-http-upgrade=true` with `ws=true` for
/// VMess, Trojan and VLESS (manual.nssurge.com/policies/vmess.html).
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

    private func generate(_ nodes: [ProxyNode], target: ClientTarget = .surge) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(nodes: nodes, preset: preset, target: target)
    }

    private func line(_ name: String, in output: GeneratedConfiguration) -> String? {
        output.content.components(separatedBy: "\n").first { $0.hasPrefix("\(name) = ") }
    }

    func testWritesHTTPUpgradeForEveryKind() throws {
        let nodes = [try vmess(), try trojan(), try vless("security=tls&sni=edge.example.com&type=httpupgrade&path=%2Fup&host=edge.example.com", name: "V-HUP")]
        for target in [ClientTarget.surge, .surgeMac] {
            let output = generate(nodes, target: target)
            XCTAssertEqual(output.supportedNodeCount, 3, output.content)
            XCTAssertTrue(output.skippedNodes.isEmpty)
            for name in ["M-HUP", "T-HUP", "V-HUP"] {
                let line = try XCTUnwrap(line(name, in: output), name)
                XCTAssertTrue(line.contains("ws=true, ws-http-upgrade=true, ws-path=/up"), line)
            }
            XCTAssertTrue(try XCTUnwrap(line("M-HUP", in: output)).contains("ws-headers=Host:cdn.example.com"))
        }
    }

    func testPlainWebSocketIsUnchanged() throws {
        let ws = try vless("security=tls&type=ws&path=%2Fws", name: "V-WS")
        let line = try XCTUnwrap(line("V-WS", in: generate([ws])))
        XCTAssertTrue(line.contains("ws=true"))
        XCTAssertFalse(line.contains("ws-http-upgrade"))
    }

    func testVLESSHTTPUpgradeFollowsWebSocketSecurityRules() throws {
        let pbk = "pbk=dwrjY6KiAMPxKdlF7T4AWFXXBtsxeHCXtBQYeCOdZV4&sni=www.microsoft.com"
        let none = try vless("type=httpupgrade&path=%2Fup", name: "None")
        let reality = try vless("security=reality&type=httpupgrade&path=%2Fup&\(pbk)", name: "Reality")
        let vision = try vless("security=tls&type=httpupgrade&path=%2Fup&flow=xtls-rprx-vision", name: "Vision")
        XCTAssertTrue(ConfigurationGenerator.surgeAcceptsVLESS(none))
        XCTAssertFalse(ConfigurationGenerator.surgeAcceptsVLESS(reality))
        XCTAssertFalse(ConfigurationGenerator.surgeAcceptsVLESS(vision))
    }

    func testShadowrocketNeverGetsTheSurgeParameter() throws {
        let output = ConfigurationGenerator().generate(
            nodes: [try vmess()], preset: preset, target: .shadowrocket)
        XCTAssertEqual(output.supportedNodeCount, 1)
        XCTAssertFalse(output.content.contains("ws-http-upgrade"))
    }
}
