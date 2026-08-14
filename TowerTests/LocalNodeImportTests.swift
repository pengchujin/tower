import XCTest
@testable import Tower

final class LocalNodeImportTests: XCTestCase {
    func testBatchImportPreservesEveryNodeName() throws {
        let auth = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        let content = """
        ss://\(auth)@hk.example.com:8388#Hong%20Kong
        trojan://secret@jp.example.com:443#Japan
        """

        let result = try LocalNodeImporter().parse(content, preferredName: "Ignored for batch")

        XCTAssertEqual(result.nodes.map(\.name), ["Hong Kong", "Japan"])
        XCTAssertTrue(result.nodes.allSatisfy(\.isLocal))
    }

    func testSingleImportUsesPreferredName() throws {
        let result = try LocalNodeImporter().parse(
            "http://user:password@proxy.example.com:8080#Old",
            preferredName: "Office Proxy"
        )

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes[0].name, "Office Proxy")
        XCTAssertEqual(result.nodes[0].kind, .http)
    }

    func testManualHTTPNodeSupportsTLSAndCredentials() throws {
        let draft = ManualNodeDraft(
            kind: .http,
            name: "Office HTTPS",
            server: "proxy.example.com",
            port: "8443",
            username: "alice",
            secret: "password",
            tls: true
        )

        let node = try draft.makeNode()

        XCTAssertEqual(node.kind, .http)
        XCTAssertEqual(node.server, "proxy.example.com")
        XCTAssertEqual(node.port, 8443)
        XCTAssertEqual(node.username, "alice")
        XCTAssertEqual(node.password, "password")
        XCTAssertTrue(node.tls)
        XCTAssertTrue(node.rawURI.hasPrefix("https://"))
    }

    func testManualNodeRejectsInvalidPort() {
        let draft = ManualNodeDraft(
            kind: .trojan,
            name: "Broken",
            server: "example.com",
            port: "70000",
            secret: "password"
        )

        XCTAssertThrowsError(try draft.makeNode()) { error in
            XCTAssertEqual(error as? ManualNodeValidationError, .invalidPort)
        }
    }

    func testManualHTTPNodeRejectsAFullURLInTheServerField() {
        let draft = ManualNodeDraft(
            kind: .http,
            server: "https://proxy.example.com",
            port: "443",
            tls: true
        )

        XCTAssertThrowsError(try draft.makeNode()) { error in
            XCTAssertEqual(error as? ManualNodeValidationError, .invalidServer)
        }
    }

    func testManualVLESSRealityPreservesRequiredTransportFields() throws {
        let draft = ManualNodeDraft(
            kind: .vless,
            name: "VLESS Reality",
            server: "edge.example.com",
            port: "443",
            secret: "de305d54-75b4-431b-adb2-eb6b9e546014",
            transport: "grpc",
            tls: true,
            sni: "www.example.com",
            hostHeader: "cdn.example.com",
            path: "tower.Service",
            alpn: "h2",
            realityPublicKey: "server-public-key",
            realityShortID: "0123456789abcdef",
            fingerprint: "chrome",
            flow: "xtls-rprx-vision",
            skipCertificateVerification: true,
            security: "reality"
        )

        let node = try draft.makeNode()

        XCTAssertEqual(node.transport, "grpc")
        XCTAssertEqual(node.sni, "www.example.com")
        XCTAssertEqual(node.hostHeader, "cdn.example.com")
        XCTAssertEqual(node.path, "tower.Service")
        XCTAssertEqual(node.alpn, "h2")
        XCTAssertEqual(node.realityPublicKey, "server-public-key")
        XCTAssertEqual(node.realityShortID, "0123456789abcdef")
        XCTAssertEqual(node.fingerprint, "chrome")
        XCTAssertEqual(node.flow, "xtls-rprx-vision")
        XCTAssertTrue(node.skipCertificateVerification)
        XCTAssertTrue(node.rawURI.contains("security=reality"))
    }

    func testManualShadowsocksRAndSnellExposeProtocolSpecificFields() throws {
        let ssr = try ManualNodeDraft(
            kind: .shadowsocksR,
            server: "ssr.example.com",
            port: "8388",
            secret: "password",
            cipher: "aes-256-cfb",
            protocolName: "auth_aes128_md5",
            protocolParam: "42:user",
            obfs: "tls1.2_ticket_auth",
            obfsParam: "cdn.example.com"
        ).makeNode()
        XCTAssertEqual(ssr.protocolName, "auth_aes128_md5")
        XCTAssertEqual(ssr.protocolParam, "42:user")
        XCTAssertEqual(ssr.obfs, "tls1.2_ticket_auth")
        XCTAssertEqual(ssr.obfsParam, "cdn.example.com")

        let snell = try ManualNodeDraft(
            kind: .snell,
            server: "snell.example.com",
            port: "443",
            secret: "psk",
            obfs: "tls",
            obfsParam: "cdn.example.com",
            version: "4"
        ).makeNode()
        XCTAssertEqual(snell.password, "psk")
        XCTAssertEqual(snell.version, 4)
        XCTAssertEqual(snell.obfs, "tls")
        XCTAssertEqual(snell.obfsParam, "cdn.example.com")
        XCTAssertEqual(try LocalNodeImporter().parse(snell.rawURI).nodes.first?.kind, .snell)
    }

    func testManualHysteria2PreservesOfficialObfuscationFields() throws {
        let node = try ManualNodeDraft(
            kind: .hysteria2,
            server: "hy2.example.com",
            port: "443",
            secret: "authentication-password",
            obfs: "salamander",
            obfsParam: "obfuscation-password"
        ).makeNode()

        XCTAssertEqual(node.obfs, "salamander")
        XCTAssertEqual(node.obfsParam, "obfuscation-password")
        XCTAssertTrue(node.rawURI.contains("obfs=salamander"), node.rawURI)
        XCTAssertTrue(node.rawURI.contains("obfs-password=obfuscation-password"), node.rawURI)
    }

    func testManualAnyTLSPreservesSessionTuning() throws {
        let node = try ManualNodeDraft(
            kind: .anytls,
            server: "anytls.example.com",
            port: "443",
            secret: "password",
            idleSessionCheckInterval: "20",
            idleSessionTimeout: "45",
            minIdleSession: "3"
        ).makeNode()

        XCTAssertEqual(node.idleSessionCheckInterval, 20)
        XCTAssertEqual(node.idleSessionTimeout, 45)
        XCTAssertEqual(node.minIdleSession, 3)
    }

    func testManualRealityRejectsAnIncompatibleTransport() {
        let draft = ManualNodeDraft(
            kind: .vless,
            server: "reality.example.com",
            port: "443",
            secret: "de305d54-75b4-431b-adb2-eb6b9e546014",
            transport: "ws",
            realityPublicKey: "public-key",
            security: "reality"
        )

        XCTAssertThrowsError(try draft.makeNode()) { error in
            XCTAssertEqual(error as? ManualNodeValidationError, .incompatibleRealityTransport)
        }
    }
}
