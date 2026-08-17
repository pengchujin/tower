import XCTest
@testable import Tower

/// AnyTLS arrived in a real subscription as twelve `anytls://` links that were
/// counted as unrecognised. Every target client supports the protocol, so it is
/// parsed and emitted rather than skipped.
final class AnyTLSTests: XCTestCase {
    private let parser = SubscriptionParser()

    /// The shape the subscription actually uses.
    private let uri = "anytls://pass-word-1234@node.example.com:40500"
        + "?type=tcp&insecure=1&fp=chrome&sni=cover.example.com#日本 01 AnyTLS"

    // MARK: - Parsing

    func testParsesAnyTLSURI() throws {
        let node = try XCTUnwrap(parser.parseURI(uri))

        XCTAssertEqual(node.kind, .anytls)
        XCTAssertEqual(node.server, "node.example.com")
        XCTAssertEqual(node.port, 40500)
        XCTAssertEqual(node.password, "pass-word-1234")
        XCTAssertEqual(node.sni, "cover.example.com")
        XCTAssertEqual(node.name, "日本 01 AnyTLS")
    }

    func testAnyTLSAlwaysNegotiatesTLS() throws {
        // There is no plaintext AnyTLS, so the flag does not depend on a query
        // parameter the way it does for VLESS.
        let node = try XCTUnwrap(parser.parseURI("anytls://pw@a.example.com:443#X"))

        XCTAssertTrue(node.tls)
    }

    func testInsecureFlagBecomesSkipCertificateVerification() throws {
        let node = try XCTUnwrap(parser.parseURI(uri))

        XCTAssertTrue(node.skipCertificateVerification)
    }

    func testMixedSubscriptionKeepsBothShadowsocksAndAnyTLS() {
        let list = [
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#SS",
            uri
        ].joined(separator: "\n")

        let result = parser.parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.map(\.kind), [.shadowsocks, .anytls])
        XCTAssertEqual(result.rejectedLineCount, 0)
    }

    // MARK: - Client support

    func testEveryTargetAcceptsAnyTLS() {
        for target in ClientTarget.allCases {
            XCTAssertTrue(target.supports(.anytls), "\(target.name) 应支持 AnyTLS")
        }
    }

    // MARK: - Generation

    func testEachTargetEmitsItsOwnAnyTLSSyntax() throws {
        let node = try XCTUnwrap(parser.parseURI(uri))
        let expected: [ClientTarget: [String]] = [
            .clash: ["type: anytls", "password: \"pass-word-1234\"", "sni: \"cover.example.com\""],
            .surge: ["anytls, node.example.com, 40500", "password=pass-word-1234", "sni=cover.example.com"],
            .shadowrocket: ["type: anytls", "password: \"pass-word-1234\"", "client-fingerprint: \"chrome\""],
            // Loon takes the password as a quoted positional field and names
            // the SNI tls-name.
            .loon: ["anytls,node.example.com,40500,\"pass-word-1234\"", "tls-name=cover.example.com"],
            .quanx: ["anytls=node.example.com:40500", "password=pass-word-1234", "tls-host=cover.example.com"]
        ]

        for (target, fragments) in expected {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            ).content

            for fragment in fragments {
                XCTAssertTrue(content.contains(fragment), "\(target.name) 缺少 \(fragment)")
            }
        }
    }

    func testSkipCertificateVerificationReachesEveryTarget() throws {
        let node = try XCTUnwrap(parser.parseURI(uri))
        let expected: [ClientTarget: String] = [
            .clash: "skip-cert-verify: true",
            .surge: "skip-cert-verify=true",
            .shadowrocket: "skip-cert-verify: true",
            .loon: "skip-cert-verify=true",
            .quanx: "tls-verification=false"
        ]

        for (target, fragment) in expected {
            let content = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            ).content
            XCTAssertTrue(content.contains(fragment), "\(target.name) 丢了证书校验设置")
        }
    }

    func testNoNodeIsSkippedForAnyTarget() throws {
        let node = try XCTUnwrap(parser.parseURI(uri))

        for target in ClientTarget.allCases {
            let result = ConfigurationGenerator().generate(
                nodes: [node],
                preset: RulePreset.builtIns[0],
                target: target
            )
            XCTAssertEqual(result.skippedNodeCount, 0, "\(target.name) 跳过了 AnyTLS 节点")
            XCTAssertEqual(result.supportedNodeCount, 1)
        }
    }

    func testSessionTuningReachesClash() {
        let node = ProxyNode(
            kind: .anytls,
            name: "AnyTLS tuned",
            server: "node.example.com",
            port: 443,
            password: "password",
            tls: true,
            idleSessionCheckInterval: 20,
            idleSessionTimeout: 45,
            minIdleSession: 3,
            rawURI: "anytls://node"
        )

        let content = ConfigurationGenerator().generate(
            nodes: [node], preset: RulePreset.builtIns[0], target: .clash
        ).content

        XCTAssertTrue(content.contains("idle-session-check-interval: 20"), content)
        XCTAssertTrue(content.contains("idle-session-timeout: 45"), content)
        XCTAssertTrue(content.contains("min-idle-session: 3"), content)
    }

    // MARK: - Sharing

    func testSharedLinkRoundTrips() throws {
        let node = ProxyNode(
            kind: .anytls,
            name: "HK 01",
            server: "node.example.com",
            port: 40500,
            password: "pass-word-1234",
            tls: true,
            sni: "cover.example.com",
            skipCertificateVerification: true,
            rawURI: "clash://local/test"
        )

        let link = ProxyNodeShareLinkGenerator().link(for: node)
        XCTAssertTrue(link.hasPrefix("anytls://"), link)

        let reparsed = try XCTUnwrap(parser.parseURI(link))
        XCTAssertEqual(reparsed.kind, .anytls)
        XCTAssertEqual(reparsed.password, "pass-word-1234")
        XCTAssertEqual(reparsed.sni, "cover.example.com")
        XCTAssertTrue(reparsed.skipCertificateVerification)
    }

    func testDetectorRecognisesAnyTLSPaste() {
        XCTAssertEqual(SourceInputDetector().detect(uri), .node(.anytls))
    }
}
