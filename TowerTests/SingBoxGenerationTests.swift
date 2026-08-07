import XCTest
@testable import Tower

/// sing-box takes JSON, and Hiddify is a Flutter shell over hiddify-core —
/// which is sing-box — so one document serves both targets.
final class SingBoxGenerationTests: XCTestCase {
    private static let rejectTag = "REJECT"
    private let generator = ConfigurationGenerator()
    private let preset = RulePreset.builtIns[0]

    private func node(
        _ kind: ProxyKind,
        name: String = "HK 01",
        transport: String? = nil,
        tls: Bool = true,
        version: Int? = nil
    ) -> ProxyNode {
        ProxyNode(
            kind: kind, name: name, server: "hk.example.com", port: 443,
            cipher: kind == .shadowsocks ? "aes-256-gcm" : "auto",
            password: "pw", uuid: "b831381d-6324-4d53-ad4f-8cda48b30811",
            username: "user", transport: transport, tls: tls,
            sni: "hk.example.com", hostHeader: "hk.example.com",
            path: transport == "ws" ? "/ws" : nil,
            version: version, rawURI: "x://y"
        )
    }

    private func json(_ target: ClientTarget, nodes: [ProxyNode]) throws -> [String: Any] {
        let content = generator.generate(nodes: nodes, preset: preset, target: target).content
        let object = try JSONSerialization.jsonObject(with: Data(content.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - Document shape

    func testOutputIsValidJSON() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks)])

        XCTAssertNotNil(config["outbounds"])
        XCTAssertNotNil(config["route"])
        XCTAssertNotNil(config["inbounds"])
    }

    func testHiddifyIsTheOnlyTargetOnThisFormat() {
        // sing-box ships no App Store client of its own, so the format is
        // offered only under the app that actually runs it.
        XCTAssertEqual(ClientTarget.allCases.filter(\.usesSingBoxFormat), [.hiddify])
    }

    func testRejectIsARuleActionNotABlockOutbound() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks)])
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        // 1.11 deprecated the block outbound in favour of rule actions.
        XCTAssertFalse(outbounds.contains { $0["type"] as? String == "block" })
        XCTAssertTrue(rules.contains { $0["action"] as? String == "reject" }, "没有生成拒绝动作")
        // And with no outbound to point at, the blocking policies must not be
        // emitted as selector groups either.
        let tags = Set(outbounds.compactMap { $0["tag"] as? String })
        XCTAssertFalse(tags.contains(RulePolicy.foreignAds.configurationName))
        XCTAssertFalse(tags.contains(Self.rejectTag))
    }

    func testEveryGroupReferenceResolvesToSomething() throws {
        let config = try json(.hiddify, nodes: [node(.shadowsocks), node(.trojan, name: "JP 01")])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let tags = Set(outbounds.compactMap { $0["tag"] as? String })

        for outbound in outbounds {
            for member in outbound["outbounds"] as? [String] ?? [] {
                XCTAssertTrue(tags.contains(member), "出站 \(member) 没有对应定义")
            }
        }
        let route = try XCTUnwrap(config["route"] as? [String: Any])
        XCTAssertTrue(tags.contains(try XCTUnwrap(route["final"] as? String)))
    }

    func testEmptyGroupStillResolves() throws {
        // sing-box refuses to start on a dangling reference, so a group with no
        // members has to point somewhere.
        let config = try json(.hiddify, nodes: [])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        for outbound in outbounds {
            if let members = outbound["outbounds"] as? [String] {
                XCTAssertFalse(members.isEmpty, "\(outbound["tag"] ?? "?") 是空组")
            }
        }
    }

    // MARK: - Outbounds

    func testProtocolTypesMatchSingBoxNames() throws {
        let expected: [ProxyKind: String] = [
            .shadowsocks: "shadowsocks", .vmess: "vmess", .vless: "vless",
            .trojan: "trojan", .hysteria2: "hysteria2", .anytls: "anytls",
            .socks5: "socks", .http: "http"
        ]

        for (kind, type) in expected {
            let config = try json(.hiddify, nodes: [node(kind)])
            let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
            XCTAssertTrue(
                outbounds.contains { $0["type"] as? String == type },
                "\(kind.rawValue) 应写成 \(type)"
            )
        }
    }

    func testWebsocketBecomesATransportBlock() throws {
        let config = try json(.hiddify, nodes: [node(.vmess, transport: "ws")])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let vmess = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vmess" })
        let transport = try XCTUnwrap(vmess["transport"] as? [String: Any])

        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/ws")
    }

    func testTLSCarriesServerNameAndInsecureFlag() throws {
        let config = try json(.hiddify, nodes: [node(.trojan)])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let trojan = try XCTUnwrap(outbounds.first { $0["type"] as? String == "trojan" })
        let tls = try XCTUnwrap(trojan["tls"] as? [String: Any])

        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual(tls["server_name"] as? String, "hk.example.com")
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    func testVMessNeverWritesAutoAsAConcreteCipher() throws {
        let config = try json(.hiddify, nodes: [node(.vmess)])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        let vmess = try XCTUnwrap(outbounds.first { $0["type"] as? String == "vmess" })

        XCTAssertEqual(vmess["security"] as? String, "auto")
        XCTAssertEqual(vmess["alter_id"] as? Int, 0)
    }

    // MARK: - Snell

    func testSnellIsSkippedWhateverItsVersion() {
        // sing-box the project implements Snell; the core Hiddify ships does
        // not, so the version does not come into it.
        for version in [3, 4] {
            let output = generator.generate(
                nodes: [node(.snell, version: version)], preset: preset, target: .hiddify
            )

            XCTAssertEqual(output.supportedNodeCount, 0, "v\(version)")
            XCTAssertEqual(output.skippedNodeCount, 1, "v\(version)")
        }
        XCTAssertFalse(ClientTarget.hiddify.supports(.snell))
    }

    func testTheClientsThatDoSupportSnellAreUnaffected() {
        // Surge takes any version, Clash stops at v3.
        let v3 = node(.snell, version: 3)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .surge).supportedNodeCount, 1)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .clash).supportedNodeCount, 1)
        XCTAssertEqual(generator.generate(nodes: [v3], preset: preset, target: .egern).supportedNodeCount, 1)
    }

    // MARK: - Untrusted names

    func testHostileNodeNameCannotBreakTheDocument() throws {
        let hostile = node(.shadowsocks, name: "HK\n\"},{\"tag\":\"pwned\",\"type\":\"direct\"},{\"x\":\"")
        let config = try json(.hiddify, nodes: [hostile])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])

        // Serialising rather than string-building is what makes this safe.
        XCTAssertFalse(outbounds.contains { $0["tag"] as? String == "pwned" })
    }
}
