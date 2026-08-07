import XCTest
@testable import Tower

/// A VLESS node carrying `pbk` is a REALITY node. Dropping those parameters
/// leaves plain TLS aimed at a borrowed SNI — it looks right in every client
/// and never connects.
final class RealityTests: XCTestCase {
    private let generator = ConfigurationGenerator()
    private let preset = RulePreset.builtIns[0]
    private let parser = SubscriptionParser()

    private let link = """
    vless://b831381d-6324-4d53-ad4f-8cda48b30811@edge.example.com:11001?mode=multi\
    &security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision\
    &pbk=TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef\
    &sni=k0g1h.example.com&servername=k0g1h.example.com&spx=/&fp=chrome#HK 01
    """

    private func node() throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI(link))
    }

    // MARK: - Parsing

    func testRealityParametersSurviveParsing() throws {
        let node = try node()

        XCTAssertTrue(node.usesReality)
        XCTAssertEqual(node.realityPublicKey, "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(node.realityShortID, "0123456789abcdef")
        XCTAssertEqual(node.fingerprint, "chrome")
        XCTAssertEqual(node.flow, "xtls-rprx-vision")
        XCTAssertEqual(node.sni, "k0g1h.example.com")
    }

    func testPlainTLSNodeIsNotMistakenForReality() throws {
        let plain = try XCTUnwrap(parser.parseURI(
            "vless://id@edge.example.com:443?security=tls&type=tcp&sni=a.example.com#Plain"
        ))

        XCTAssertFalse(plain.usesReality)
        XCTAssertNil(plain.realityPublicKey)
    }

    // MARK: - Emission

    func testClashCarriesRealityOptions() throws {
        let content = generator.generate(nodes: [try node()], preset: preset, target: .clash).content

        XCTAssertTrue(content.contains("    reality-opts:"), content)
        XCTAssertTrue(content.contains("      public-key: \"TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""))
        XCTAssertTrue(content.contains("      short-id: \"0123456789abcdef\""))
        XCTAssertTrue(content.contains("    client-fingerprint: \"chrome\""))
        XCTAssertTrue(content.contains("    flow: \"xtls-rprx-vision\""))
    }

    func testHiddifyNestsRealityUnderTLS() throws {
        let content = generator.generate(nodes: [try node()], preset: preset, target: .hiddify).content
        let config = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let vless = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vless" })
        let tls = try XCTUnwrap(vless["tls"] as? [String: Any])
        let reality = try XCTUnwrap(tls["reality"] as? [String: Any])

        XCTAssertEqual(reality["enabled"] as? Bool, true)
        XCTAssertEqual(reality["public_key"] as? String, "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(reality["short_id"] as? String, "0123456789abcdef")
        // sing-box rejects REALITY without uTLS.
        XCTAssertEqual((tls["utls"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual(vless["flow"] as? String, "xtls-rprx-vision")
    }

    func testLoonAndQuanXUseTheirOwnKeyNames() throws {
        let loon = generator.generate(nodes: [try node()], preset: preset, target: .loon).content
        XCTAssertTrue(loon.contains("public-key=\"TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""), loon)
        XCTAssertTrue(loon.contains("short-id=0123456789abcdef"), loon)

        let quanx = generator.generate(nodes: [try node()], preset: preset, target: .quanx).content
        XCTAssertTrue(quanx.contains("reality-base64-pubkey=TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"), quanx)
        XCTAssertTrue(quanx.contains("reality-hex-shortid=0123456789abcdef"), quanx)
    }

    func testEgernNestsRealityUnderTheProxy() throws {
        let content = generator.generate(nodes: [try node()], preset: preset, target: .egern).content

        XCTAssertTrue(content.contains("      reality:"), content)
        XCTAssertTrue(content.contains("        public_key: \"TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""))
        XCTAssertTrue(content.contains("        short_id: \"0123456789abcdef\""))
    }

    // MARK: - Clients that cannot express it

    /// Shadowrocket names these differently from every other client, and
    /// numbers the flow rather than spelling it.
    func testShadowrocketUsesItsOwnRealityVocabulary() throws {
        let output = generator.generate(nodes: [try node()], preset: preset, target: .shadowrocket)

        XCTAssertEqual(output.supportedNodeCount, 1)
        XCTAssertTrue(output.content.contains("pbk=TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"), output.content)
        XCTAssertTrue(output.content.contains("sid=0123456789abcdef"))
        XCTAssertTrue(output.content.contains("fingerprint=chrome"))
        XCTAssertTrue(output.content.contains("xtls=2"), "vision 应写成 xtls=2")
        // Loon's spelling must not leak into Shadowrocket's line.
        XCTAssertFalse(output.content.contains("public-key="))
        XCTAssertFalse(output.content.contains("short-id="))
    }

    func testLoonKeepsItsOwnSpelling() throws {
        let loon = generator.generate(nodes: [try node()], preset: preset, target: .loon).content

        XCTAssertTrue(loon.contains("public-key="), loon)
        XCTAssertFalse(loon.contains("xtls="))
    }

    /// Surge is the one client that genuinely cannot: its producer raises
    /// "reality is unsupported", and it takes no VLESS at all.
    func testSurgeIsTheOnlyTargetThatSkipsReality() throws {
        let node = try node()
        let skipping = ClientTarget.allCases.filter {
            generator.generate(nodes: [node], preset: preset, target: $0).supportedNodeCount == 0
        }

        XCTAssertEqual(skipping, [.surge])
    }

    func testNoTargetEverWritesARealityNodeWithoutItsPublicKey() throws {
        let node = try node()

        for target in ClientTarget.allCases {
            let output = generator.generate(nodes: [node], preset: preset, target: target)
            guard output.supportedNodeCount > 0 else { continue }
            XCTAssertTrue(
                output.content.contains("TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
                "\(target.name) 写入了节点却丢了 REALITY 公钥"
            )
        }
    }
}
