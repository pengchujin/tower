import XCTest
@testable import Tower

/// Xray accepts any VMess/VLESS id shorter than 32 bytes and derives a v5 UUID
/// from it, so airports publish ids like `abcd1234`. Clash and Stash reject a
/// non-UUID outright — `proxy 245: invalid UUID length: 8` — and refuse to load
/// the whole file, taking every other node down with it.
final class ProxyIDNormalizationTests: XCTestCase {
    private let generator = ConfigurationGenerator()

    func testRealUUIDIsUntouched() {
        let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"
        XCTAssertEqual(ProxyNode.normalizedProxyID(uuid), uuid)
    }

    func testShortIDBecomesTheUUIDXrayDerives() {
        // Xray hashes the nil namespace followed by the text with SHA-1, then
        // stamps version 5 and the RFC 4122 variant. These are the values its
        // own uuid.ParseString produces, so the server compares equal.
        XCTAssertEqual(ProxyNode.normalizedProxyID("abcd1234"), "b0421856-f473-5c64-a137-cdce51bda057")
        XCTAssertEqual(ProxyNode.normalizedProxyID("1"), "11116e73-1c03-5de6-9130-5f9925ae8ab4")
    }

    func testDerivedIDIsAValidUUIDOfTheRightVersion() throws {
        let derived = try XCTUnwrap(ProxyNode.normalizedProxyID("hello"))
        XCTAssertNotNil(UUID(uuidString: derived))
        XCTAssertEqual(derived.count, 36)
        // Version nibble, then the variant bits Clash checks.
        let fields = derived.split(separator: "-")
        XCTAssertEqual(fields[2].first, "5")
        XCTAssertTrue(["8", "9", "a", "b"].contains(String(fields[3].first!)))
    }

    func testLongNonUUIDCannotBeExpressed() {
        // 32 bytes or more is where Xray stops treating it as a name.
        XCTAssertNil(ProxyNode.normalizedProxyID(String(repeating: "z", count: 32)))
        XCTAssertNil(ProxyNode.normalizedProxyID(""))
    }

    func testClashGetsAUUIDForAnAirportsShortID() {
        let node = ProxyNode(
            kind: .vless, name: "CA 01", server: "1.2.3.4", port: 443,
            uuid: "abcd1234", tls: true, rawURI: "vless://abcd1234@1.2.3.4:443"
        )

        let output = generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clash)

        XCTAssertEqual(output.supportedNodeCount, 1)
        XCTAssertTrue(output.content.contains("b0421856-f473-5c64-a137-cdce51bda057"), output.content)
        XCTAssertFalse(output.content.contains("abcd1234"))
    }

    func testEveryTargetWritesTheSameDerivedID() {
        let node = ProxyNode(
            kind: .vmess, name: "JP 01", server: "1.2.3.4", port: 443,
            cipher: "auto", uuid: "abcd1234", tls: true, rawURI: "vmess://x"
        )

        for target in ClientTarget.allCases where target.supports(.vmess) {
            let output = generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            XCTAssertTrue(
                output.content.contains("b0421856-f473-5c64-a137-cdce51bda057"),
                "\(target.name) 没有写入映射后的 UUID"
            )
        }
    }

    func testUnexpressibleIDIsSkippedRatherThanWrittenBlank() {
        let node = ProxyNode(
            kind: .vless, name: "Broken", server: "1.2.3.4", port: 443,
            uuid: String(repeating: "z", count: 40), tls: true, rawURI: "vless://x"
        )

        let output = generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clash)

        XCTAssertEqual(output.supportedNodeCount, 0)
        XCTAssertEqual(output.skippedNodeCount, 1)
        XCTAssertFalse(output.content.contains("uuid: \"\""))
    }
}
