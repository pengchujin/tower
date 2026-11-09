import XCTest
@testable import Tower

/// Node settings found missing when the same subscription was converted by
/// Tower, subconverter and Sub-Store (docs/RULE_EXPORT_AUDIT.md, 与参考转换器逐项对比).
final class NodeExportParityTests: XCTestCase {
    private func node(_ uri: String) throws -> ProxyNode {
        try XCTUnwrap(SubscriptionParser().parse(data: Data(uri.utf8)).nodes.first, uri)
    }

    private func nodes(_ node: ProxyNode, _ target: ClientTarget) -> GeneratedConfiguration {
        ConfigurationGenerator().generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
    }

    func testSingBoxKeepsTheClientFingerprintWithoutReality() throws {
        let anytls = try node("anytls://pw@a.example.com:443?sni=a.example.com&fp=random#anytls")
        let trojan = try node("trojan://pw@t.example.com:443?sni=t.example.com&fp=chrome#trojan")
        for (source, fingerprint) in [(anytls, "random"), (trojan, "chrome")] {
            let content = nodes(source, .singBox).content
            XCTAssertTrue(content.contains(#""fingerprint" : "\#(fingerprint)""#), content)
        }
        let unknown = try node("trojan://pw@t.example.com:443?sni=t.example.com&fp=unknown-browser#odd")
        XCTAssertFalse(nodes(unknown, .singBox).content.contains("utls"))
    }

    func testQuantumultXWritesVLESSHTTPObfuscation() throws {
        let vless = try node("vless://23ad6b10-8d1a-40f7-8ad0-e3e35cd32291@v.example.com:80?security=none&type=tcp&headerType=http&host=apple.com&path=%2Fresource#vless-http")
        let result = nodes(vless, .quanx)
        XCTAssertEqual(result.supportedNodeCount, 1, "\(result.skippedNodes)")
        XCTAssertTrue(result.content.contains("obfs=http, obfs-host=apple.com, obfs-uri=/resource"), result.content)
    }

    func testEgernTakesRealityOverGRPC() throws {
        let vless = try node("vless://23ad6b10-8d1a-40f7-8ad0-e3e35cd32291@r.example.com:443?security=reality&sni=www.apple.com&pbk=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk&sid=0123abcd&type=grpc&serviceName=grpc#reality-grpc")
        let result = nodes(vless, .egern)
        XCTAssertEqual(result.supportedNodeCount, 1, "\(result.skippedNodes)")
        XCTAssertTrue(result.content.contains("""
                grpc:
                  service_name: "grpc"
                  sni: "www.apple.com"
                  reality:
                    public_key: "k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk"
                    short_id: "0123abcd"
        """), result.content)
        // HTTP/2 is still ordinary TLS in Egern.
        let h2 = try node("vless://23ad6b10-8d1a-40f7-8ad0-e3e35cd32291@r.example.com:443?security=reality&sni=www.apple.com&pbk=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk&sid=0123abcd&type=http#reality-h2")
        XCTAssertEqual(nodes(h2, .egern).supportedNodeCount, 0)
    }

    func testLoonWritesTheRealityFingerprint() throws {
        let trojan = try node("trojan://pw@t.example.com:443?security=reality&sni=www.apple.com&pbk=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk&sid=0123abcd&fp=chrome#trojan-reality")
        XCTAssertTrue(nodes(trojan, .loon).content.contains("tls-profile=chrome"))
        let vless = try node("vless://23ad6b10-8d1a-40f7-8ad0-e3e35cd32291@r.example.com:443?security=reality&sni=www.apple.com&pbk=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk&sid=0123abcd&fp=safari&type=tcp#vless-reality")
        XCTAssertTrue(nodes(vless, .loon).content.contains("tls-profile=safari-ios18"))
        // Loon documents no Firefox / Edge profile, so the field is omitted.
        for fp in ["firefox", "edge", "random"] {
            let other = try node("vless://23ad6b10-8d1a-40f7-8ad0-e3e35cd32291@r.example.com:443?security=reality&sni=www.apple.com&pbk=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk&sid=0123abcd&fp=\(fp)&type=tcp#vless-\(fp)")
            let content = nodes(other, .loon).content
            XCTAssertEqual(nodes(other, .loon).supportedNodeCount, 1, fp)
            XCTAssertFalse(content.contains("tls-profile="), fp)
        }
    }
}
