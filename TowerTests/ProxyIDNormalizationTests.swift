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

/// WebSocket and HTTP/2 paths are HTTP request paths and must be absolute.
/// Airports publish them without the leading slash; Surge rejects the whole
/// profile for it, while Xray's server normalises the same way Tower now does.
final class TransportPathNormalizationTests: XCTestCase {
    private let generator = ConfigurationGenerator()

    private func node(path: String?) -> ProxyNode {
        ProxyNode(
            kind: .vmess, name: "HK 01", server: "1.2.3.4", port: 443,
            cipher: "auto", uuid: "b831381d-6324-4d53-ad4f-8cda48b30811",
            transport: "ws", tls: true, hostHeader: "example.com",
            path: path, rawURI: "vmess://x"
        )
    }

    func testAbsolutePathIsUntouched() {
        XCTAssertEqual(node(path: "/already/absolute").exportablePath, "/already/absolute")
    }

    func testMissingLeadingSlashIsAdded() {
        XCTAssertEqual(node(path: "1c503beb-vm").exportablePath, "/1c503beb-vm")
    }

    func testEmptyPathStaysUnset() {
        XCTAssertNil(node(path: "").exportablePath)
        XCTAssertNil(node(path: nil).exportablePath)
    }

    func testSurgeNeverWritesARelativeWebsocketPath() {
        let content = generator.generate(
            nodes: [node(path: "1c503beb-vm")], preset: RulePreset.builtIns[0], target: .surge
        ).content

        XCTAssertTrue(content.contains("ws-path=/1c503beb-vm"), content)
        XCTAssertFalse(content.contains("ws-path=1c503beb-vm"))
    }

    func testEveryTargetWritesAnAbsolutePath() {
        for target in ClientTarget.allCases where target.supports(.vmess) {
            let content = generator.generate(
                nodes: [node(path: "1c503beb-vm")], preset: RulePreset.builtIns[0], target: target
            ).content
            XCTAssertTrue(content.contains("/1c503beb-vm"), "\(target.name) 少了前导斜杠")
            // The bare form must not survive anywhere in the file.
            XCTAssertFalse(content.contains("=1c503beb-vm"), "\(target.name) 仍写出了相对路径")
            XCTAssertFalse(content.contains(": \"1c503beb-vm\""), "\(target.name) 仍写出了相对路径")
        }
    }
}

/// Quantumult X only accepts `tls-verification` alongside a declared TLS layer.
/// Airports do ship nodes with no TLS that still carry an insecure flag, and
/// the stray key rejects the entire profile.
final class QuanXCertificatePolicyTests: XCTestCase {
    private let generator = ConfigurationGenerator()

    private func node(tls: Bool, transport: String?) -> ProxyNode {
        ProxyNode(
            kind: .vless, name: "IR 01", server: "fn.example.com", port: 2090,
            uuid: "b831381d-6324-4d53-ad4f-8cda48b30811",
            transport: transport, tls: tls,
            path: transport == "ws" ? "/x" : nil,
            skipCertificateVerification: true, rawURI: "vless://x"
        )
    }

    private func line(_ node: ProxyNode) -> String {
        let content = generator.generate(
            nodes: [node], preset: RulePreset.builtIns[0], target: .quanx
        ).content
        return content.split(separator: "\n").first { $0.hasPrefix("vless=") }.map(String.init) ?? ""
    }

    func testPlainNodeDropsTheCertificateKeyItCannotUse() {
        let output = line(node(tls: false, transport: nil))

        XCTAssertFalse(output.contains("tls-verification"), output)
        XCTAssertFalse(output.contains("obfs="), output)
    }

    func testPlainWebsocketAlsoDropsIt() {
        let output = line(node(tls: false, transport: "ws"))

        XCTAssertTrue(output.contains("obfs=ws"), output)
        XCTAssertFalse(output.contains("tls-verification"), output)
    }

    func testSecureNodesKeepIt() {
        let overTLS = line(node(tls: true, transport: nil))
        XCTAssertTrue(overTLS.contains("obfs=over-tls"), overTLS)
        XCTAssertTrue(overTLS.contains("tls-verification=false"), overTLS)

        let secureWebsocket = line(node(tls: true, transport: "ws"))
        XCTAssertTrue(secureWebsocket.contains("obfs=wss"), secureWebsocket)
        XCTAssertTrue(secureWebsocket.contains("tls-verification=false"), secureWebsocket)
    }

    func testNoQuanXLineEverCarriesTheKeyWithoutObfs() {
        let nodes = [
            node(tls: false, transport: nil), node(tls: false, transport: "ws"),
            node(tls: true, transport: nil), node(tls: true, transport: "ws")
        ].enumerated().map { index, node in
            var renamed = node
            renamed.name = "Node \(index)"
            return renamed
        }

        let content = generator.generate(nodes: nodes, preset: RulePreset.builtIns[0], target: .quanx).content

        for line in content.split(separator: "\n") where line.contains("tls-verification") {
            XCTAssertTrue(line.contains("obfs="), "缺少 obfs 却写了 tls-verification：\(line)")
        }
    }
}

/// Quantumult X has no `hysteria2=` server type. Its sample.conf documents
/// ss2022, REALITY, vless-flow and AnyTLS but no Hysteria at all, and writing
/// the line fails the entire import with "配置文件语法错误, line 159".
final class QuanXHysteria2Tests: XCTestCase {
    private let generator = ConfigurationGenerator()

    private var hysteria2: ProxyNode {
        ProxyNode(
            kind: .hysteria2, name: "TW 01", server: "vpn.example.com", port: 443,
            password: "pw", tls: true, sni: "vpn.example.com",
            skipCertificateVerification: true, rawURI: "hysteria2://x"
        )
    }

    func testQuanXDoesNotClaimToSupportIt() {
        XCTAssertFalse(ClientTarget.quanx.supports(.hysteria2))
    }

    func testItIsSkippedAndCountedRatherThanWritten() {
        let output = generator.generate(
            nodes: [hysteria2], preset: RulePreset.builtIns[0], target: .quanx
        )

        XCTAssertEqual(output.supportedNodeCount, 0)
        XCTAssertEqual(output.skippedNodeCount, 1)
        XCTAssertFalse(output.content.contains("hysteria2="), output.content)
    }

    func testOtherNodesStillExportAlongsideIt() {
        let trojan = ProxyNode(
            kind: .trojan, name: "HK 01", server: "hk.example.com", port: 443,
            password: "pw", tls: true, rawURI: "trojan://x"
        )

        let output = generator.generate(
            nodes: [hysteria2, trojan], preset: RulePreset.builtIns[0], target: .quanx
        )

        XCTAssertEqual(output.supportedNodeCount, 1)
        XCTAssertEqual(output.skippedNodeCount, 1)
        XCTAssertTrue(output.content.contains("trojan="), output.content)
    }

    func testTheClientsThatDoSupportItAreUnaffected() {
        for target in [ClientTarget.clash, .surge, .shadowrocket, .loon] {
            XCTAssertTrue(target.supports(.hysteria2), target.name)
            let output = generator.generate(
                nodes: [hysteria2], preset: RulePreset.builtIns[0], target: target
            )
            XCTAssertEqual(output.supportedNodeCount, 1, target.name)
        }
    }

    func testQuanXStillSupportsAnyTLSWhichItsSampleDoesDocument() {
        XCTAssertTrue(ClientTarget.quanx.supports(.anytls))
    }
}
