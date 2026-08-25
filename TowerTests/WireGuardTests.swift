import XCTest
@testable import Tower

/// WireGuard is accepted only when Tower can preserve the complete single-peer
/// configuration: local address, both keys, endpoint and routes.  These tests
/// keep parsing, sharing and every advertised target in lockstep.
final class WireGuardTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let generator = ConfigurationGenerator()
    private let preset = RulePreset.builtIns[0]

    private let uri = "wireguard://cHJpdmF0ZS1rZXk%3D@wg.example.com:51820/"
        + "?publickey=cHVibGljLWtleQ%3D%3D&address=10.0.0.2%2F32%2Cfd00%3A%3A2%2F128"
        + "&allowedips=0.0.0.0%2F0%2C%3A%3A%2F0&reserved=1%2C2%2C3&mtu=1280"
        + "&keepalive=25&presharedkey=cHNr&dns=1.1.1.1#WARP%20Tokyo"

    private func node() throws -> ProxyNode {
        try XCTUnwrap(parser.parseURI(uri))
    }

    func testParsesWireGuardURIWithoutDroppingTunnelFields() throws {
        let node = try node()

        XCTAssertEqual(node.kind, .wireguard)
        XCTAssertEqual(node.server, "wg.example.com")
        XCTAssertEqual(node.port, 51820)
        XCTAssertEqual(node.name, "WARP Tokyo")
        XCTAssertEqual(node.wireGuardPrivateKey, "cHJpdmF0ZS1rZXk=")
        XCTAssertEqual(node.wireGuardPublicKey, "cHVibGljLWtleQ==")
        XCTAssertEqual(node.wireGuardIPv4, "10.0.0.2/32")
        XCTAssertEqual(node.wireGuardIPv6, "fd00::2/128")
        XCTAssertEqual(node.wireGuardAllowedIPs, "0.0.0.0/0,::/0")
        XCTAssertEqual(node.wireGuardReserved, "1,2,3")
        XCTAssertEqual(node.wireGuardMTU, 1280)
        XCTAssertEqual(node.wireGuardPersistentKeepalive, 25)
        XCTAssertEqual(node.wireGuardPreSharedKey, "cHNr")
        XCTAssertEqual(node.wireGuardDNS, "1.1.1.1")
    }

    func testParsesMihomoSinglePeerWireGuardYAML() throws {
        let yaml = """
        proxies:
          - name: WARP
            type: wireguard
            private-key: cHJpdmF0ZS1rZXk=
            ip: 10.0.0.2/32
            ipv6: fd00::2/128
            peers:
              - server: wg.example.com
                port: 51820
                public-key: cHVibGljLWtleQ==
                pre-shared-key: cHNr
                allowed-ips:
                  - 0.0.0.0/0
                  - ::/0
                reserved: [1, 2, 3]
                persistent-keepalive: 25
            mtu: 1280
            dns: [1.1.1.1, 2606:4700:4700::1111]
        """

        let result = parser.parse(data: Data(yaml.utf8))
        let node = try XCTUnwrap(result.nodes.first)

        XCTAssertEqual(result.rejectedLineCount, 0)
        XCTAssertEqual(node.kind, .wireguard)
        XCTAssertEqual(node.server, "wg.example.com")
        XCTAssertEqual(node.wireGuardPublicKey, "cHVibGljLWtleQ==")
        XCTAssertEqual(node.wireGuardAllowedIPs, "0.0.0.0/0,::/0")
        XCTAssertEqual(node.wireGuardDNS, "1.1.1.1,2606:4700:4700::1111")
    }

    func testRejectsMihomoMultiPeerWireGuardInsteadOfSilentlyCollapsingIt() {
        let yaml = """
        proxies:
          - name: Multi peer
            type: wireguard
            private-key: private
            ip: 10.0.0.2/32
            peers:
              - server: first.example.com
                port: 51820
                public-key: first-public-key
                allowed-ips: [10.0.0.0/8]
              - server: second.example.com
                port: 51821
                public-key: second-public-key
                allowed-ips: [0.0.0.0/0]
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertEqual(result.rejectedLineCount, 1)
    }

    func testWireGuardSupportMatrixMatchesFormatsThatCanCarryIt() {
        let supported: Set<ClientTarget> = [
            .surge, .shadowrocket, .clash, .clashApple, .loon, .hiddify, .egern, .v2box
        ]
        XCTAssertEqual(Set(ClientTarget.allCases.filter { $0.supports(.wireguard) }), supported)
    }

    func testEveryAdvertisedTargetWritesCompleteWireGuardConfiguration() throws {
        let node = try node()
        for target in [ClientTarget.surge, .shadowrocket, .clash, .loon, .hiddify, .egern] {
            let result = generator.generate(nodes: [node], preset: preset, target: target)
            XCTAssertEqual(result.supportedNodeCount, 1, target.name)
            XCTAssertEqual(result.skippedNodeCount, 0, target.name)
            XCTAssertTrue(result.content.contains("wg.example.com"), target.name)
            XCTAssertTrue(result.content.contains("cHJpdmF0ZS1rZXk="), target.name)
            XCTAssertTrue(result.content.contains("cHVibGljLWtleQ=="), target.name)
            XCTAssertTrue(result.content.contains("10.0.0.2"), target.name)
        }
    }

    func testWireGuardTargetSpecificShapes() throws {
        let node = try node()
        let surge = generator.generate(nodes: [node], preset: preset, target: .surge).content
        XCTAssertTrue(surge.contains("= wireguard, section-name="), surge)
        XCTAssertTrue(surge.contains("[WireGuard "), surge)
        XCTAssertTrue(surge.contains("peer = (public-key = cHVibGljLWtleQ=="), surge)

        let clash = generator.generate(nodes: [node], preset: preset, target: .clash).content
        XCTAssertTrue(clash.contains("    type: wireguard"), clash)
        XCTAssertTrue(clash.contains("    private-key: \"cHJpdmF0ZS1rZXk=\""), clash)
        XCTAssertTrue(clash.contains("    reserved: [1, 2, 3]"), clash)

        let loon = generator.generate(nodes: [node], preset: preset, target: .loon).content
        XCTAssertTrue(loon.contains("= wireguard,interface-ip=10.0.0.2/32"), loon)
        XCTAssertTrue(loon.contains("peers=[{public-key=\"cHVibGljLWtleQ==\""), loon)

        let hiddify = generator.generate(nodes: [node], preset: preset, target: .hiddify).content
        let document = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(hiddify.utf8)) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(document["outbounds"] as? [[String: Any]])
        let wireguard = try XCTUnwrap(outbounds.first { $0["type"] as? String == "wireguard" })
        XCTAssertEqual(wireguard["peer_public_key"] as? String, "cHVibGljLWtleQ==")

        let egern = generator.generate(nodes: [node], preset: preset, target: .egern).content
        XCTAssertTrue(egern.contains("  - wireguard:"), egern)
        XCTAssertTrue(egern.contains("      local_ipv4: \"10.0.0.2/32\""), egern)
    }

    func testCanonicalShareLinkRoundTripsWireGuard() throws {
        let original = try node()
        let link = ProxyNodeShareLinkGenerator().canonicalLink(for: original)
        let rebuilt = try XCTUnwrap(parser.parseURI(link))

        XCTAssertTrue(link.hasPrefix("wireguard://"), link)
        XCTAssertEqual(rebuilt.canonicalKey, original.canonicalKey)
    }

    func testIncompleteWireGuardIsSkippedInsteadOfPoisoningProfiles() {
        let incomplete = ProxyNode(
            kind: .wireguard,
            name: "Missing public key",
            server: "wg.example.com",
            port: 51820,
            wireGuardPrivateKey: "private",
            wireGuardIPv4: "10.0.0.2/32",
            rawURI: "wg://bad"
        )

        for target in [ClientTarget.surge, .shadowrocket, .clash, .loon, .hiddify, .egern] {
            let result = generator.generate(nodes: [incomplete], preset: preset, target: target)
            XCTAssertEqual(result.supportedNodeCount, 0, target.name)
            XCTAssertEqual(result.skippedNodeCount, 1, target.name)
            XCTAssertFalse(result.content.contains("wg.example.com"), target.name)
        }
        XCTAssertFalse(ClientTarget.quanx.supports(.wireguard))
    }

    func testManualDraftBuildsAndRoundTripsWireGuard() throws {
        var draft = ManualNodeDraft()
        draft.applyDefaults(for: .wireguard)
        draft.name = "WARP"
        draft.server = "wg.example.com"
        draft.port = "51820"
        draft.wireGuardPrivateKey = "private"
        draft.wireGuardPublicKey = "public"
        draft.wireGuardIPv4 = "10.0.0.2/32"
        draft.wireGuardAllowedIPs = "0.0.0.0/0,::/0"
        draft.wireGuardReserved = "1,2,3"

        let node = try draft.makeNode()
        let rebuilt = try ManualNodeDraft(node: node).makeNode()

        XCTAssertEqual(node.kind, .wireguard)
        XCTAssertEqual(rebuilt.canonicalKey, node.canonicalKey)
    }
}
