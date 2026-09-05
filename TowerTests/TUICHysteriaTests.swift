import XCTest
@testable import Tower

/// TUIC and Hysteria 1 are the two protocols Mihomo carries that real airports
/// actually ship and that at least one target client can express. Everything
/// else missing from Tower's list (mieru, shadowquic, masque, trusttunnel,
/// sudoku, tailscale, openvpn, ssh) has no target support to write it into, so
/// importing it would only produce nodes that look healthy and never connect.
///
/// Each client's syntax below comes from that client's own material rather
/// than from a guess: Surge and Egern from Sub-Store's producers, Shadowrocket
/// from its manual's "编写本地节点" section, Clash from Mihomo, and Hiddify
/// from sing-box's outbound schema.
final class TUICHysteriaTests: XCTestCase {
    private let parser = SubscriptionParser()

    // TUIC v5 puts a pair in the userinfo — uuid first, password second — which
    // no other scheme Tower reads does.
    private let tuicURI = "tuic://3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47:pass-word-1234"
        + "@node.example.com:44300"
        + "?sni=cover.example.com&alpn=h3&congestion_control=bbr&udp_relay_mode=native"
        + "&allow_insecure=1#香港 01 TUIC"

    private let hysteriaURI = "hysteria://node.example.com:36712"
        + "?auth=pass-word-1234&protocol=udp&obfs=scramble&upmbps=80&downmbps=240"
        + "&peer=cover.example.com&alpn=h3&insecure=1#日本 02 Hysteria"

    // Left without a fragment so the obfs cases below can append to the query.
    private let hysteria2URI = "hysteria2://pass-word-1234@node.example.com:443"
        + "?sni=cover.example.com&alpn=h3&insecure=1"

    // MARK: - Parsing

    func testParsesTUICUserinfoAsUUIDAndPassword() throws {
        let node = try XCTUnwrap(parser.parseURI(tuicURI))

        XCTAssertEqual(node.kind, .tuic)
        XCTAssertEqual(node.server, "node.example.com")
        XCTAssertEqual(node.port, 44300)
        XCTAssertEqual(node.uuid, "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47")
        XCTAssertEqual(node.password, "pass-word-1234")
        XCTAssertEqual(node.sni, "cover.example.com")
        XCTAssertEqual(node.congestionControl, "bbr")
        XCTAssertEqual(node.udpRelayMode, "native")
        XCTAssertTrue(node.tls)
        XCTAssertTrue(node.skipCertificateVerification)
        XCTAssertEqual(node.name, "香港 01 TUIC")
    }

    func testParsesShadowrocketTUICQueryCredentialsAndIndexedALPN() throws {
        let node = try XCTUnwrap(
            parser.parseURI(
                "tuic://node.example.com:44300"
                    + "?uuid=3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47"
                    + "&password=pass-word-1234&sni=cover.example.com"
                    + "&alpn[0]=h3&insecure=1#香港 02 TUIC"
            )
        )

        XCTAssertEqual(node.kind, .tuic)
        XCTAssertEqual(node.uuid, "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47")
        XCTAssertEqual(node.password, "pass-word-1234")
        XCTAssertEqual(node.sni, "cover.example.com")
        XCTAssertEqual(node.alpn, "h3")
        XCTAssertTrue(node.skipCertificateVerification)
        XCTAssertEqual(node.name, "香港 02 TUIC")
    }

    func testNormalizesBracketedALPNFromTUICURI() throws {
        let node = try XCTUnwrap(
            parser.parseURI(
                "tuic://3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47:pass-word-1234"
                    + "@node.example.com:44300?sni=cover.example.com"
                    + "&alpn=%5Bh3%5D&congestion_control=bbr#Bracketed ALPN"
            )
        )

        XCTAssertEqual(node.alpn, "h3")
    }

    func testNormalizesInlineAndBlockALPNListsFromClashYAML() throws {
        let yaml = """
        proxies:
          - name: TUIC inline list
            type: tuic
            server: tuic.example.com
            port: 443
            uuid: 3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47
            password: pass-word-1234
            alpn: [h3]
          - name: AnyTLS quoted list
            type: anytls
            server: anytls.example.com
            port: 443
            password: pass-word-1234
            alpn: ["h2", "http/1.1"]
          - name: Hysteria block list
            type: hysteria2
            server: hysteria.example.com
            port: 443
            password: pass-word-1234
            alpn:
              - h3
              - h2
        """

        let parsed = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(parsed.nodes.count, 3)
        XCTAssertEqual(parsed.nodes[0].alpn, "h3")
        XCTAssertEqual(parsed.nodes[1].alpn, "h2,http/1.1")
        XCTAssertEqual(parsed.nodes[2].alpn, "h3,h2")

        let output = ConfigurationGenerator().generate(
            nodes: parsed.nodes,
            preset: RulePreset.builtIns[0],
            target: .shadowrocket
        ).content
        XCTAssertTrue(output.contains("    alpn: [\"h3\"]"), output)
        XCTAssertTrue(output.contains("    alpn: [\"h2\", \"http/1.1\"]"), output)
        XCTAssertFalse(output.contains("[\"[h3]\"]"), output)
    }

    func testRepairsBracketedALPNAlreadyStoredByAnOlderBuild() throws {
        var node = try XCTUnwrap(
            parser.parseURI(
                "tuic://3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47:pass-word-1234"
                    + "@node.example.com:44300?sni=cover.example.com"
                    + "&alpn=h3&congestion_control=bbr#Stored TUIC"
            )
        )
        node.alpn = "[h3]"

        let output = ConfigurationGenerator().generate(
            nodes: [node],
            preset: RulePreset.builtIns[0],
            target: .shadowrocket
        ).content
        XCTAssertTrue(output.contains("    alpn: [\"h3\"]"), output)
        XCTAssertFalse(output.contains("[\"[h3]\"]"), output)

        let link = ProxyNodeShareLinkGenerator().canonicalLink(for: node)
        let components = try XCTUnwrap(URLComponents(string: link))
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "alpn" })?.value,
            "h3"
        )
    }

    func testHiddifyDoesNotSkipShadowrocketTUICQueryDialect() throws {
        let node = try XCTUnwrap(
            parser.parseURI(
                "tuic://node.example.com:44300"
                    + "?uuid=3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47"
                    + "&password=pass-word-1234&sni=cover.example.com"
                    + "&alpn[0]=h3&insecure=1#香港 02 TUIC"
            )
        )

        let result = ConfigurationGenerator().generateNodeSubscription(
            nodes: [node],
            target: .hiddify,
            profileName: "Tower"
        )

        XCTAssertEqual(result.supportedNodeCount, 1)
        XCTAssertEqual(result.skippedNodeCount, 0)
        XCTAssertTrue(result.content.hasPrefix("tuic://"), result.content)
    }

    func testRejectsTUICWithoutRequiredCredentials() {
        XCTAssertNil(
            parser.parseURI(
                "tuic://node.example.com:44300?sni=cover.example.com&alpn[0]=h3#Incomplete TUIC"
            )
        )
    }

    func testParsesHysteriaBandwidthAndObfs() throws {
        let node = try XCTUnwrap(parser.parseURI(hysteriaURI))

        XCTAssertEqual(node.kind, .hysteria)
        XCTAssertEqual(node.port, 36712)
        XCTAssertEqual(node.upMbps, 80)
        XCTAssertEqual(node.downMbps, 240)
        // Hysteria 1's obfs is one shared string, not Hysteria 2's method plus
        // password, so it lands in `obfs` with nothing in `obfsParam`.
        XCTAssertEqual(node.obfs, "scramble")
        XCTAssertNil(node.obfsParam)
        XCTAssertEqual(node.protocolName, "udp")
        XCTAssertEqual(node.sni, "cover.example.com")
    }

    /// `hysteria2://` must not be swallowed by the `hysteria` branch: the two
    /// protocols share no wire format at all.
    func testHysteria2StillParsesAsHysteria2() throws {
        let node = try XCTUnwrap(parser.parseURI("hysteria2://pw@a.example.com:443#H2"))

        XCTAssertEqual(node.kind, .hysteria2)
    }

    func testHysteriaBandwidthAcceptsAUnitSuffix() throws {
        let node = try XCTUnwrap(
            parser.parseURI("hysteria://a.example.com:443?auth=pw&upmbps=50%20Mbps&downmbps=200mbps#H")
        )

        XCTAssertEqual(node.upMbps, 50)
        XCTAssertEqual(node.downMbps, 200)
    }

    func testClashYAMLTUICAndHysteriaAreNoLongerRejected() {
        let yaml = """
        proxies:
          - {name: T, type: tuic, server: a.example.com, port: 443, \
        uuid: 3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47, password: pw, sni: c.example.com}
          - {name: H, type: hysteria, server: b.example.com, port: 443, \
        auth-str: pw, up: 50, down: 200}
          - {name: A, type: anytls, server: c.example.com, port: 443, password: pw}
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.map(\.kind), [.tuic, .hysteria, .anytls])
        XCTAssertEqual(result.nodes[1].password, "pw")
        XCTAssertEqual(result.nodes[1].upMbps, 50)
        XCTAssertEqual(result.rejectedLineCount, 0)
    }

    /// These values change the actual QUIC/Hysteria connection. Two entries
    /// sharing a front door and credentials are not duplicates when any one of
    /// these tuning parameters differs.
    func testCanonicalIdentityIncludesTUICAndHysteriaTuning() {
        let tuic = tuicNode()
        var changed = tuic
        changed.congestionControl = "cubic"
        XCTAssertNotEqual(changed.canonicalKey, tuic.canonicalKey)

        changed = tuic
        changed.udpRelayMode = "quic"
        XCTAssertNotEqual(changed.canonicalKey, tuic.canonicalKey)

        let hysteria = hysteriaNode()
        changed = hysteria
        changed.upMbps = 81
        XCTAssertNotEqual(changed.canonicalKey, hysteria.canonicalKey)

        changed = hysteria
        changed.downMbps = 241
        XCTAssertNotEqual(changed.canonicalKey, hysteria.canonicalKey)
    }

    /// A nested sequence used to end the node it belonged to.
    ///
    /// `http-opts: path: - /` is written by real airports, and the reader
    /// treated that `- /` as the start of a new proxy: it invented a junk
    /// entry *and* truncated the real node there, so everything after it —
    /// including `reality-opts` — was silently dropped. Those nodes imported
    /// looking healthy and could never connect.
    func testNestedSequenceDoesNotSplitTheNode() throws {
        let yaml = """
        proxies:
          - name: A
            type: vless
            server: a.example.com
            port: 443
            uuid: 3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47
            network: http
            servername: cover.example.com
            tls: true
            http-opts:
              path:
                - /
            reality-opts:
              public-key: dGVzdC1wdWJsaWMta2V5LXZhbHVlLWZvci11bml0LXRlc3Q
              short-id: 0b
            skip-cert-verify: true
          - name: B
            type: trojan
            server: b.example.com
            port: 443
            password: pw
            alpn:
              - h2
              - http/1.1
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.rejectedLineCount, 0)

        let vless = try XCTUnwrap(result.nodes.first)
        XCTAssertEqual(vless.name, "A")
        // The fields that used to land in the invented entry instead.
        XCTAssertEqual(vless.realityPublicKey, "dGVzdC1wdWJsaWMta2V5LXZhbHVlLWZvci11bml0LXRlc3Q")
        XCTAssertEqual(vless.realityShortID, "0b")
        XCTAssertTrue(vless.skipCertificateVerification)
        XCTAssertEqual(vless.path, "/")

        // A multi-value sequence keeps every element, in the comma-joined form
        // ProxyNode and the generators already use.
        XCTAssertEqual(result.nodes[1].alpn, "h2,http/1.1")
    }

    // MARK: - Client support

    func testTUICSupportMatchesWhatEachClientImplements() {
        let supported: Set<ClientTarget> = [
            .surge, .shadowrocket, .clash, .clashApple, .clashMi, .karing,
            .hiddify, .egern, .singBox
        ]
        for target in ClientTarget.allCases {
            XCTAssertEqual(
                target.supports(.tuic),
                supported.contains(target),
                "\(target.name) 的 TUIC 支持判断和客户端实际实现不一致"
            )
        }
    }

    func testHysteria1SupportMatchesWhatEachClientImplements() {
        // Surge, Loon, Quantumult X and Egern all ship Hysteria 2 but never
        // shipped Hysteria 1.
        let supported: Set<ClientTarget> = [
            .shadowrocket, .clash, .clashApple, .clashMi, .karing, .hiddify, .singBox
        ]
        for target in ClientTarget.allCases {
            XCTAssertEqual(
                target.supports(.hysteria),
                supported.contains(target),
                "\(target.name) 的 Hysteria 1 支持判断和客户端实际实现不一致"
            )
        }
    }

    /// A client that cannot express the protocol must skip the node and count
    /// it, never write it as something else.
    func testUnsupportedTargetsSkipAndCountRatherThanDowngrade() {
        let nodes = [tuicNode(), hysteriaNode()]

        for target in [ClientTarget.loon, .quanx] {
            let result = ConfigurationGenerator().generate(nodes: nodes, preset: RulePreset.builtIns[0], target: target)

            XCTAssertEqual(result.skippedNodeCount, 2, "\(target.name) 应跳过并计数")
            XCTAssertFalse(result.content.contains("node.example.com"), "\(target.name) 不应写出跳过的节点")
        }
    }

    /// Tower supports TUIC v5, whose UUID and password are both mandatory.
    /// A legacy v4 token or a half-filled v5 entry must not be emitted as a
    /// profile line that imports successfully but can never authenticate.
    func testIncompleteOrLegacyTUICIsSkippedByEverySupportingTarget() {
        let missingPassword = ProxyNode(
            kind: .tuic,
            name: "Missing password",
            server: "missing.example.com",
            port: 443,
            uuid: "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47",
            tls: true,
            rawURI: "tuic://missing"
        )
        let legacyToken = ProxyNode(
            kind: .tuic,
            name: "Legacy v4 token",
            server: "legacy.example.com",
            port: 443,
            password: "pw",
            uuid: "legacy-token",
            tls: true,
            rawURI: "tuic://legacy"
        )

        for target in [ClientTarget.surge, .shadowrocket, .clash, .clashMi, .karing, .hiddify, .egern] {
            let result = ConfigurationGenerator().generate(
                nodes: [missingPassword, legacyToken],
                preset: RulePreset.builtIns[0],
                target: target
            )

            XCTAssertEqual(result.supportedNodeCount, 0, target.name)
            XCTAssertEqual(result.skippedNodeCount, 2, target.name)
            XCTAssertFalse(result.content.contains("missing.example.com"), target.name)
            XCTAssertFalse(result.content.contains("legacy.example.com"), target.name)
        }
    }

    // MARK: - Emission

    func testSurgeWritesTUICv5() {
        let line = try! proxyLine(for: tuicNode(), target: .surge)

        XCTAssertTrue(line.contains("tuic-v5, node.example.com, 44300"), line)
        XCTAssertTrue(line.contains("uuid=3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47"), line)
        XCTAssertTrue(line.contains("password=pass-word-1234"), line)
        XCTAssertTrue(line.contains("sni=cover.example.com"), line)
    }

    func testShadowrocketClashProfileKeepsTUICFields() {
        let content = configuration(for: tuicNode(), target: .shadowrocket)

        XCTAssertTrue(content.contains("type: tuic"), content)
        XCTAssertTrue(content.contains("server: \"node.example.com\""), content)
        XCTAssertTrue(content.contains("port: 44300"), content)
        XCTAssertTrue(content.contains("password: \"pass-word-1234\""), content)
        XCTAssertTrue(content.contains("uuid: \"3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47\""), content)
        XCTAssertTrue(content.contains("udp: true"), content)
    }

    func testShadowrocketClashProfileKeepsHysteria2UDP() throws {
        let content = configuration(
            for: try XCTUnwrap(parser.parseURI(hysteria2URI + "#Hysteria 2")),
            target: .shadowrocket
        )

        XCTAssertTrue(content.contains("type: hysteria2"), content)
        XCTAssertTrue(content.contains("udp: true"), content)
    }

    func testShadowrocketWritesHysteria1WithAuthAndBandwidth() {
        let content = configuration(for: hysteriaNode(), target: .shadowrocket)

        XCTAssertTrue(content.contains("type: hysteria"), content)
        XCTAssertTrue(content.contains("auth-str: \"pass-word-1234\""), content)
        XCTAssertTrue(content.contains("obfs: \"scramble\""), content)
        XCTAssertTrue(content.contains("protocol: \"udp\""), content)
        XCTAssertTrue(content.contains("up: 80"), content)
        XCTAssertTrue(content.contains("down: 240"), content)
    }

    /// Shadowrocket's manual writes Hysteria 2 as `auth=`, the same key it
    /// gives Hysteria 1 — but the app was checked on device and takes Surge's
    /// `password=`, so both clients keep it. This pins the verified spelling
    /// against a future reader who compares the manual to the code and
    /// "corrects" it; see docs/HANDOFF.md.
    func testHysteria2KeepsThePasswordSpellingVerifiedOnDevice() throws {
        let node = try XCTUnwrap(parser.parseURI(hysteria2URI))

        let surge = try proxyLine(for: node, target: .surge)
        XCTAssertTrue(surge.contains("hysteria2, node.example.com, 443"), surge)
        XCTAssertTrue(surge.contains("password=pass-word-1234"), surge)
        XCTAssertFalse(surge.contains("auth=pass-word-1234"), surge)

        let shadowrocket = configuration(for: node, target: .shadowrocket)
        XCTAssertTrue(shadowrocket.contains("type: hysteria2"), shadowrocket)
        XCTAssertTrue(shadowrocket.contains("password: \"pass-word-1234\""), shadowrocket)
    }

    /// The Salamander password is named in the key by Surge and left unnamed by
    /// Shadowrocket. Dropping it, as both lines used to, produced a node that
    /// imports cleanly and never completes a handshake.
    func testHysteria2SalamanderPasswordSurvivesIntoBothClients() throws {
        let node = try XCTUnwrap(
            parser.parseURI(hysteria2URI + "&obfs=salamander&obfs-password=s3cret")
        )

        let shadowrocket = configuration(for: node, target: .shadowrocket)
        XCTAssertTrue(shadowrocket.contains("obfs: \"salamander\""), shadowrocket)
        XCTAssertTrue(shadowrocket.contains("obfs-password: \"s3cret\""), shadowrocket)

        let surge = try proxyLine(for: node, target: .surge)
        XCTAssertTrue(surge.contains("salamander-password=s3cret"), surge)
        XCTAssertFalse(surge.contains("obfsParam"), surge)
    }

    /// Neither client has a field for the obfuscator's name, so an unknown one
    /// cannot be written without silently claiming it is Salamander.
    func testHysteria2WithAnUnknownObfuscatorIsSkippedAndCounted() throws {
        let node = try XCTUnwrap(
            parser.parseURI(hysteria2URI + "&obfs=scramble&obfs-password=s3cret")
        )

        for target in [ClientTarget.surge, .shadowrocket] {
            let result = ConfigurationGenerator()
                .generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)

            XCTAssertEqual(result.skippedNodeCount, 1, "\(target.name) 应跳过并计数")
            XCTAssertFalse(result.content.contains("node.example.com"), "\(target.name)")
        }

        // Clash and sing-box carry the obfuscator by name, so they keep it.
        let clash = ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clash)
        XCTAssertEqual(clash.skippedNodeCount, 0)
        XCTAssertTrue(clash.content.contains("scramble"), clash.content)
    }

    func testClashWritesTUICAndHysteriaWithMihomoKeys() {
        let content = ConfigurationGenerator()
            .generate(nodes: [tuicNode(), hysteriaNode()], preset: RulePreset.builtIns[0], target: .clash)
            .content

        XCTAssertTrue(content.contains("type: tuic"), content)
        XCTAssertTrue(content.contains("congestion-controller: \"bbr\""), content)
        XCTAssertTrue(content.contains("udp-relay-mode: \"native\""), content)
        XCTAssertTrue(content.contains("type: hysteria"), content)
        XCTAssertTrue(content.contains("auth-str: \"pass-word-1234\""), content)
        XCTAssertTrue(content.contains("up: 80"), content)
        XCTAssertTrue(content.contains("down: 240"), content)
        // A comma-joined ALPN written as a scalar is read as one protocol name.
        XCTAssertTrue(content.contains("alpn: [\"h3\"]"), content)
    }

    /// Mihomo's congestion control is rate-based, so a Hysteria 1 node without
    /// a bandwidth budget crawls. An airport that omitted them still gets a
    /// working profile.
    func testClashFillsHysteriaBandwidthDefaults() {
        var node = hysteriaNode()
        node.upMbps = nil
        node.downMbps = nil

        let content = ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clash)
            .content

        XCTAssertTrue(content.contains("up: 50"), content)
        XCTAssertTrue(content.contains("down: 100"), content)
    }

    func testEgernWritesTUICWithAnALPNList() {
        let content = ConfigurationGenerator()
            .generate(nodes: [tuicNode()], preset: RulePreset.builtIns[0], target: .egern)
            .content

        XCTAssertTrue(content.contains("tuic:"), content)
        XCTAssertTrue(content.contains("uuid: \"3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47\""), content)
        XCTAssertTrue(content.contains("alpn: [\"h3\"]"), content)
        XCTAssertEqual(
            content.components(separatedBy: "skip_tls_verify: true").count - 1,
            1,
            "Egern 的 TUIC 映射只能写一次 skip_tls_verify：\(content)"
        )
    }

    func testHiddifyWritesSingBoxOutbounds() throws {
        let content = ConfigurationGenerator()
            .generate(nodes: [tuicNode(), hysteriaNode()], preset: RulePreset.builtIns[0], target: .hiddify)
            .content
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])

        let tuic = try XCTUnwrap(outbounds.first { $0["type"] as? String == "tuic" })
        XCTAssertEqual(tuic["uuid"] as? String, "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47")
        XCTAssertEqual(tuic["password"] as? String, "pass-word-1234")
        XCTAssertEqual(tuic["congestion_control"] as? String, "bbr")
        XCTAssertEqual(tuic["udp_relay_mode"] as? String, "native")
        XCTAssertNotNil(tuic["tls"])

        let hysteria = try XCTUnwrap(outbounds.first { $0["type"] as? String == "hysteria" })
        // sing-box spells it `auth_str`, not `password`.
        XCTAssertEqual(hysteria["auth_str"] as? String, "pass-word-1234")
        XCTAssertEqual(hysteria["up_mbps"] as? Int, 80)
        XCTAssertEqual(hysteria["down_mbps"] as? Int, 240)
    }

    // MARK: - Round trip

    func testShareLinksRoundTripThroughTheParser() throws {
        let service = ProxyNodeShareLinkGenerator()

        for original in [tuicNode(), hysteriaNode()] {
            var node = original
            node.rawURI = ""
            let link = service.link(for: node)
            let parsed = try XCTUnwrap(parser.parseURI(link), link)

            XCTAssertEqual(parsed.kind, node.kind, link)
            XCTAssertEqual(parsed.server, node.server, link)
            XCTAssertEqual(parsed.port, node.port, link)
            XCTAssertEqual(parsed.password, node.password, link)
            XCTAssertEqual(parsed.uuid, node.uuid, link)
            XCTAssertEqual(parsed.upMbps, node.upMbps, link)
            XCTAssertEqual(parsed.downMbps, node.downMbps, link)
            XCTAssertEqual(parsed.congestionControl, node.congestionControl, link)
        }
    }

    // MARK: - Helpers

    private func tuicNode() -> ProxyNode {
        parser.parseURI(tuicURI)!
    }

    private func hysteriaNode() -> ProxyNode {
        parser.parseURI(hysteriaURI)!
    }

    private func proxyLine(for node: ProxyNode, target: ClientTarget) throws -> String {
        let content = configuration(for: node, target: target)
        return try XCTUnwrap(
            content.split(separator: "\n").first { $0.contains(node.server) }.map(String.init),
            content
        )
    }

    private func configuration(for node: ProxyNode, target: ClientTarget) -> String {
        ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            .content
    }
}

/// Two ways a single node took a whole profile down with it.
final class ProfileRejectionTests: XCTestCase {
    private let parser = SubscriptionParser()

    /// Quantumult X refuses the file for a repeated module just as readily as
    /// for a missing one: "配置文件语法错误, duplicated section, [server_remote]".
    func testQuantumultXEmitsEveryModuleExactlyOnce() throws {
        let modules = [
            "general", "dns", "policy",
            "server_remote", "filter_remote", "rewrite_remote",
            "server_local", "filter_local",
            "rewrite_local", "task_local", "http_backend", "mitm"
        ]
        let node = try XCTUnwrap(parser.parseURI("trojan://pw@a.example.com:443?sni=c.example.com#T"))

        for content in try quanXConfigurations(node: node) {
            let headings = content
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("[") && $0.hasSuffix("]") }
                .map { String($0.dropFirst().dropLast()) }

            XCTAssertEqual(headings, modules, content)
        }
    }

    /// Mihomo: "proxy 301: hysteria2 obfs: salamander requires obfs-password".
    /// One node written that way rejects every other node in the file.
    func testHysteria2ObfsIsWrittenOnlyWithItsPassword() throws {
        let complete = try XCTUnwrap(
            parser.parseURI("hysteria2://pw@a.example.com:443?obfs=salamander&obfs-password=s3cret#Full")
        )
        let halfWritten = try XCTUnwrap(
            parser.parseURI("hysteria2://pw@b.example.com:443?obfs=salamander#Bare")
        )

        XCTAssertEqual(complete.obfsParam, "s3cret")
        XCTAssertNil(halfWritten.obfsParam)

        for target in [ClientTarget.clash, .hiddify] {
            let content = ConfigurationGenerator()
                .generate(nodes: [complete, halfWritten], preset: RulePreset.builtIns[0], target: target)
                .content

            XCTAssertEqual(occurrences(of: "salamander", in: content), 1, "\(target.name)")
            XCTAssertTrue(content.contains("s3cret"), "\(target.name)")
            // Both nodes still ship; only the unusable obfs layer is dropped.
            XCTAssertTrue(content.contains("a.example.com"), "\(target.name)")
            XCTAssertTrue(content.contains("b.example.com"), "\(target.name)")
        }
    }

    /// `obfs-param` is ShadowsocksR's key; Hysteria 2 uses `obfs-password`.
    /// Reading only the former is how the half-written node above was made.
    func testClashYAMLReadsTheHysteria2ObfsPassword() throws {
        let yaml = """
        proxies:
          - {name: H, type: hysteria2, server: a.example.com, port: 443, \
        password: pw, obfs: salamander, obfs-password: s3cret}
        """

        let node = try XCTUnwrap(parser.parse(data: Data(yaml.utf8)).nodes.first)

        XCTAssertEqual(node.obfs, "salamander")
        XCTAssertEqual(node.obfsParam, "s3cret")
    }

    private func quanXConfigurations(node: ProxyNode) throws -> [String] {
        let generator = ConfigurationGenerator()
        // The imported-scheme path is a separate writer, and it was the one
        // that emitted the remote modules twice.
        let scheme = try RuleSchemeParser().parse(
            text: """
            ruleset=\u{1F41F} 漏网之鱼,[]FINAL
            custom_proxy_group=\u{1F41F} 漏网之鱼`select`[]DIRECT`[]REJECT
            """,
            id: "t",
            name: "t",
            summary: "t"
        )
        return [
            generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: .quanx).content,
            generator.generate(nodes: [node], scheme: scheme, target: .quanx).content
        ]
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

/// Panels that serialise their YAML rather than write it by hand escape every
/// non-ASCII character. Stripping the quotes without decoding leaves the escape
/// text itself as the node name — in the list, and in every generated file.
final class YAMLScalarEscapeTests: XCTestCase {
    private let parser = SubscriptionParser()

    func testDecodesEscapedNamesInDoubleQuotedScalars() throws {
        let yaml = """
        proxies:
        - name: "\\U0001F1ED\\U0001F1F0 香港 01"
          type: anytls
          server: a.example.com
          port: 27002
          password: pw
        - name: "\\uD83C\\uDDFA\\uD83C\\uDDF8 美国 01"
          type: trojan
          server: b.example.com
          port: 443
          password: pw
        """

        let nodes = parser.parse(data: Data(yaml.utf8)).nodes

        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].name, "🇭🇰 香港 01")
        // The same flag written as a UTF-16 surrogate pair.
        XCTAssertEqual(nodes[1].name, "🇺🇸 美国 01")
    }

    /// A single-quoted scalar has no escapes at all: a backslash there is a
    /// backslash, and decoding one would corrupt a name rather than fix it.
    func testSingleQuotedScalarsAreLeftAlone() throws {
        let yaml = """
        proxies:
        - {name: 'a\\Ub', type: trojan, server: a.example.com, port: 443, password: pw}
        """

        let node = try XCTUnwrap(parser.parse(data: Data(yaml.utf8)).nodes.first)

        XCTAssertEqual(node.name, "a\\Ub")
    }

    /// A decoded flag has to reach the region resolver, not just the label:
    /// the name is what decides the country before the offline IP database is
    /// ever consulted.
    func testDecodedFlagDrivesTheRegion() throws {
        let yaml = """
        proxies:
        - name: "\\U0001F1EF\\U0001F1F5 Tokyo"
          type: trojan
          server: a.example.com
          port: 443
          password: pw
        """

        let node = try XCTUnwrap(parser.parse(data: Data(yaml.utf8)).nodes.first)

        XCTAssertEqual(NodeRegionResolver.countryCode(for: node), "JP")
    }
}

/// The manual-add form, which is the only path into Tower that does not start
/// from a link someone else wrote.
final class ManualNodeDraftTests: XCTestCase {
    func testEveryProtocolAtLeastOneClientCanWriteIsOffered() {
        let expressible = ProxyKind.allCases.filter { kind in
            kind != .unknown && ClientTarget.allCases.contains { $0.supports(kind) }
        }

        XCTAssertEqual(
            Set(ManualNodeDraft.supportedKinds),
            Set(expressible),
            "手动添加的协议列表和客户端实际支持的协议不一致"
        )
    }

    func testBuildsTUICWithBothHalvesOfItsCredential() throws {
        var draft = ManualNodeDraft()
        draft.applyDefaults(for: .tuic)
        draft.server = "a.example.com"
        draft.port = "44300"
        draft.secret = "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47"
        draft.password = "pw"
        draft.congestionControl = "bbr"
        draft.udpRelayMode = "native"

        let node = try draft.makeNode()

        XCTAssertEqual(node.kind, .tuic)
        XCTAssertEqual(node.uuid, "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47")
        XCTAssertEqual(node.password, "pw")
        XCTAssertEqual(node.congestionControl, "bbr")
        XCTAssertEqual(node.udpRelayMode, "native")
        XCTAssertTrue(node.tls)
    }

    /// A UUID with no password authenticates nothing, so the form refuses it
    /// rather than producing a node that looks complete.
    func testTUICWithoutAPasswordIsRejected() {
        var draft = ManualNodeDraft()
        draft.applyDefaults(for: .tuic)
        draft.server = "a.example.com"
        draft.port = "44300"
        draft.secret = "3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47"

        XCTAssertThrowsError(try draft.makeNode()) { error in
            XCTAssertEqual(error as? ManualNodeValidationError, .missingTUICPassword)
        }
    }

    func testHysteriaRequiresABandwidthBudget() throws {
        var draft = ManualNodeDraft()
        draft.applyDefaults(for: .hysteria)
        draft.server = "a.example.com"
        draft.port = "36712"
        draft.secret = "pw"

        // The defaults are usable, so a node built straight from them works.
        let node = try draft.makeNode()
        XCTAssertEqual(node.upMbps, 50)
        XCTAssertEqual(node.downMbps, 100)
        XCTAssertEqual(node.protocolName, "udp")

        draft.upMbps = "0"
        XCTAssertThrowsError(try draft.makeNode()) { error in
            XCTAssertEqual(error as? ManualNodeValidationError, .invalidBandwidth)
        }
    }

    /// Editing an existing node has to round-trip every field the form shows,
    /// or opening and saving quietly erases what it did not carry.
    func testEditingRoundTripsTheNewFields() throws {
        let parser = SubscriptionParser()
        for uri in [
            "tuic://3d3ab7b1-4a63-4f2e-9c1d-6b0e5a2f8c47:pw@a.example.com:44300"
                + "?congestion_control=bbr&udp_relay_mode=native&sni=c.example.com#T",
            "hysteria://b.example.com:36712?auth=pw&upmbps=80&downmbps=240&protocol=udp#H"
        ] {
            let original = try XCTUnwrap(parser.parseURI(uri), uri)
            let rebuilt = try ManualNodeDraft(node: original).makeNode()

            XCTAssertEqual(rebuilt.kind, original.kind, uri)
            XCTAssertEqual(rebuilt.uuid, original.uuid, uri)
            XCTAssertEqual(rebuilt.password, original.password, uri)
            XCTAssertEqual(rebuilt.congestionControl, original.congestionControl, uri)
            XCTAssertEqual(rebuilt.udpRelayMode, original.udpRelayMode, uri)
            XCTAssertEqual(rebuilt.upMbps, original.upMbps, uri)
            XCTAssertEqual(rebuilt.downMbps, original.downMbps, uri)
        }
    }
}
