import XCTest
@testable import Tower

final class AnywhereTests: XCTestCase {
    func testNodesOnlyCapabilityAndOrder() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        XCTAssertEqual(target.name, "Anywhere")
        XCTAssertEqual(target.supportedContentModes, [.nodesOnly])
        XCTAssertTrue(target.supportsDirectImport(mode: .nodesOnly))
        XCTAssertFalse(target.supportsEmbeddedRemoteSubscriptions)
        let order = ClientTargetOrder.defaultOrder
        XCTAssertEqual(order[try XCTUnwrap(order.firstIndex(of: .clashApple)) + 1], target)
        let old = order.filter { $0 != target }
        let migrated = ClientTargetOrder.normalized(rawValues: old.map(\.rawValue))
        XCTAssertEqual(migrated, order)
    }

    func testImportPreservesInnerURLVerbatim() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let source = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/nodes.txt?token=a%26b&content=nodesOnly"))
        let url = try ClientImportURLBuilder.make(target: target, configurationURL: source, contentMode: .nodesOnly)
        let suffix = String(url.absoluteString.dropFirst("anywhere://add-proxy?link=".count))
        XCTAssertEqual(suffix.removingPercentEncoding, source.absoluteString)
        XCTAssertThrowsError(try ClientImportURLBuilder.make(target: target, configurationURL: source))
    }
    func testIPv6AndAnyTLSParameters() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let node = ProxyNode(kind: .anytls, name: "A & B", server: "2001:db8::1", port: 443,
                             password: "p@ss:word", tls: true, sni: "example.com",
                             idleSessionCheckInterval: 17, idleSessionTimeout: 21, minIdleSession: 3, rawURI: "")
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: [node], target: target)
        XCTAssertEqual(result.supportedNodeCount, 1)
        XCTAssertEqual(result.ruleCount, 0)
        XCTAssertTrue(result.content.contains("@[2001:db8::1]:443"))
        XCTAssertTrue(result.content.contains("ici=17"))
        XCTAssertTrue(result.content.contains("it=21"))
        XCTAssertTrue(result.content.contains("mis=3"))
        XCTAssertFalse(result.content.contains("idle-session"))
    }

    func testRejectsUnrepresentableNodesInsteadOfLosingSettings() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let base = ProxyNode(kind: .trojan, name: "Test", server: "example.com", port: 443, password: "secret", tls: true, rawURI: "")
        var pin = base; pin.certificateFingerprint = String(repeating: "ab", count: 32)
        var insecure = base; insecure.skipCertificateVerification = true
        var ws = base; ws.transport = "ws"
        var ss = base; ss.kind = .shadowsocks; ss.tls = false; ss.cipher = "aes-128-gcm"
        var udpOff = ss; udpOff.udpRelayEnabled = false
        var plugin = ss; plugin.plugin = "obfs-local"
        var vmess = base; vmess.kind = .vmess
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: [base, ss, pin, insecure, ws, udpOff, plugin, vmess], target: target)
        // The insecure Trojan travels in AJSON for the one-tap import.
        XCTAssertEqual(result.supportedNodeCount, 3)
        XCTAssertEqual(result.skippedNodeCount, 5)
    }

    /// Fingerprints follow Anywhere's own Clash importer, and each skip says
    /// which setting Anywhere cannot keep.
    func testFingerprintsAndSpecificSkipReasons() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        // Separate nodes: skip details are keyed by node identity.
        func node(_ name: String) -> ProxyNode {
            ProxyNode(kind: .anytls, name: name, server: "example.com", port: 443, password: "pw", tls: true, sni: "example.com", rawURI: "")
        }
        var chrome = node("chrome"); chrome.fingerprint = "chrome"
        var ios = node("ios"); ios.fingerprint = "ios"
        var random = node("random"); random.fingerprint = "random"
        var qq = node("qq"); qq.fingerprint = "qq"
        var insecure = node("insecure"); insecure.skipCertificateVerification = true
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: [chrome, ios, random, qq, insecure], target: target)
        // The insecure AnyTLS node travels in AJSON for the one-tap import.
        XCTAssertEqual(result.supportedNodeCount, 4)
        XCTAssertTrue(result.content.contains("fp=chrome_133"), result.content)
        XCTAssertTrue(result.content.contains("fp=chrome_120"), result.content)
        XCTAssertFalse(result.content.contains("fp=random"), result.content)
        let reasons = Dictionary(uniqueKeysWithValues: result.skippedNodes.map { ($0.name, $0.reason) })
        XCTAssertTrue(reasons["qq"]?.contains("qq") == true, "\(reasons)")
        XCTAssertNil(reasons["insecure"], "\(reasons)")
    }

    // MARK: - AJSON (issue #51)

    private func ajsonProxies(_ result: GeneratedConfiguration) throws -> [Any] {
        let text = try XCTUnwrap(result.anywhereAJSON)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(root["anywhere"] as? Int, 1)
        return try XCTUnwrap(root["proxies"] as? [Any])
    }

    /// Share links still skip a node that does not check certificates; the
    /// AJSON document keeps it with `insecure` and leaves the others as links.
    func testInsecureNodesTravelOnlyInAJSON() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let plain = ProxyNode(kind: .trojan, name: "Plain", server: "a.example.com", port: 443,
                              password: "secret", tls: true, rawURI: "")
        var insecure = ProxyNode(kind: .trojan, name: "Insecure", server: "b.example.com", port: 8443,
                                 password: "p@ss", tls: true, sni: "cdn.example.com", alpn: "h2,http/1.1", rawURI: "")
        insecure.skipCertificateVerification = true
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: [plain, insecure], target: target)

        // Counts follow the one-tap import; the links still leave it out.
        XCTAssertEqual(result.supportedNodeCount, 2)
        XCTAssertTrue(result.skippedNodes.isEmpty, "\(result.skippedNodes)")
        XCTAssertFalse(result.content.contains("b.example.com"), result.content)
        XCTAssertEqual(result.diagnostics.count, 1)
        XCTAssertTrue(result.diagnostics[0].contains("一键导入"), result.diagnostics[0])

        let proxies = try ajsonProxies(result)
        XCTAssertEqual(proxies.count, 2)
        XCTAssertEqual(proxies[0] as? String, AnywhereExport.link(for: plain))
        let proxy = try XCTUnwrap(proxies[1] as? [String: Any])
        XCTAssertEqual(proxy["protocol"] as? String, "trojan")
        XCTAssertEqual(proxy["name"] as? String, "Insecure")
        XCTAssertEqual(proxy["server"] as? String, "b.example.com")
        XCTAssertEqual(proxy["port"] as? Int, 8443)
        XCTAssertEqual(proxy["password"] as? String, "p@ss")
        let security = try XCTUnwrap(proxy["security"] as? [String: Any])
        XCTAssertEqual(security["type"] as? String, "tls")
        XCTAssertEqual(security["insecure"] as? Bool, true)
        XCTAssertEqual(security["sni"] as? String, "cdn.example.com")
        XCTAssertEqual(security["alpn"] as? [String], ["h2", "http/1.1"])
        // A link without `fp` is Anywhere's plain ClientHello, not Chrome.
        XCTAssertEqual(security["fingerprint"] as? String, "plain")
    }

    func testNoAJSONWithoutInsecureNodes() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let node = ProxyNode(kind: .trojan, name: "Plain", server: "a.example.com", port: 443,
                             password: "secret", tls: true, rawURI: "")
        XCTAssertNil(ConfigurationGenerator().generateNodeSubscription(nodes: [node], target: target).anywhereAJSON)
    }

    func testVLESSHTTPUpgradeAndAnyTLSKeepTheirLinkSettings() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        var vless = ProxyNode(kind: .vless, name: "V", server: "v.example.com", port: 443,
                              uuid: "b831381d-6324-4d53-ad4f-8cda48b30811", transport: "httpupgrade", tls: true,
                              sni: "sni.example.com", hostHeader: "host.example.com", path: "/ray", rawURI: "")
        vless.fingerprint = "chrome"
        vless.skipCertificateVerification = true
        var anytls = ProxyNode(kind: .anytls, name: "A", server: "a.example.com", port: 443,
                               password: "pw", tls: true, idleSessionCheckInterval: 17, rawURI: "")
        anytls.skipCertificateVerification = true
        let proxies = try ajsonProxies(ConfigurationGenerator().generateNodeSubscription(nodes: [vless, anytls], target: target))

        let v = try XCTUnwrap(proxies[0] as? [String: Any])
        XCTAssertEqual(v["protocol"] as? String, "vless")
        XCTAssertEqual(v["uuid"] as? String, "b831381d-6324-4d53-ad4f-8cda48b30811")
        let vSecurity = try XCTUnwrap(v["security"] as? [String: Any])
        XCTAssertEqual(vSecurity["fingerprint"] as? String, "chrome_133")
        XCTAssertEqual(vSecurity["sni"] as? String, "sni.example.com")
        XCTAssertEqual(vSecurity["insecure"] as? Bool, true)
        let transport = try XCTUnwrap(v["transport"] as? [String: Any])
        XCTAssertEqual(transport["type"] as? String, "httpupgrade")
        XCTAssertEqual(transport["path"] as? String, "/ray")
        XCTAssertEqual(transport["host"] as? String, "host.example.com")

        let a = try XCTUnwrap(proxies[1] as? [String: Any])
        XCTAssertEqual(a["protocol"] as? String, "anytls")
        XCTAssertEqual(a["idleCheckInterval"] as? Int, 17)
        XCTAssertEqual((a["security"] as? [String: Any])?["insecure"] as? Bool, true)
    }

    /// Anywhere rebuilds TLS for VLESS over WebSocket, gRPC and XHTTP and
    /// drops `insecure` there; a device test showed them failing as insecure.
    func testVLESSTransportsThatDropInsecureStaySkipped() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        let nodes = ["ws", "grpc", "xhttp"].map { transport in
            var node = ProxyNode(kind: .vless, name: transport, server: "v.example.com", port: 443,
                                 uuid: "b831381d-6324-4d53-ad4f-8cda48b30811", transport: transport, tls: true,
                                 sni: "sni.example.com", path: "/p", rawURI: "")
            node.skipCertificateVerification = true
            return node
        }
        for node in nodes { XCTAssertNil(AnywhereExport.ajsonProxy(for: node), node.name) }
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: nodes, target: target)
        XCTAssertNil(result.anywhereAJSON)
        XCTAssertEqual(result.supportedNodeCount, 0)
        XCTAssertEqual(result.skippedNodes.count, 3)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    /// AJSON has no `insecure` for Hysteria, so such nodes stay skipped.
    func testHysteriaWithoutCertificateCheckStaysSkipped() throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        var node = ProxyNode(kind: .hysteria2, name: "H", server: "h.example.com", port: 443,
                             password: "pw", tls: true, rawURI: "")
        node.skipCertificateVerification = true
        XCTAssertNil(AnywhereExport.ajsonProxy(for: node))
        let result = ConfigurationGenerator().generateNodeSubscription(nodes: [node], target: target)
        XCTAssertNil(result.anywhereAJSON)
        XCTAssertTrue(result.skippedNodes.first?.reason.contains("总是校验") == true)
    }

    func testLoopbackServesAJSONOnlyWhenAnywhereAsksForIt() async throws {
        let target = try XCTUnwrap(ClientTarget(rawValue: "anywhere"))
        var node = ProxyNode(kind: .trojan, name: "Insecure", server: "b.example.com", port: 443,
                             password: "pw", tls: true, rawURI: "")
        node.skipCertificateVerification = true
        let configuration = ConfigurationGenerator().generateNodeSubscription(
            nodes: [node], target: target, profileName: "Tower AJSON Test")
        let service = await DirectImportService()
        let scheme = try await service.prepare(configuration)
        defer { Task { @MainActor in service.stop() } }
        let link = String(scheme.absoluteString.dropFirst("anywhere://add-proxy?link=".count))
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(link.removingPercentEncoding)))

        let (links, _) = try await URLSession.shared.data(from: url)
        XCTAssertFalse(String(decoding: links, as: UTF8.self).hasPrefix("{"))

        var request = URLRequest(url: url)
        request.setValue("Anywhere", forHTTPHeaderField: "User-Agent")
        request.setValue("ajson/1", forHTTPHeaderField: "X-Anywhere-Format")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{"), text)
        XCTAssertTrue(text.contains("\"insecure\":true"), text)

        XCTAssertFalse(AnywhereExport.acceptsAJSON(formatHeader: "ajson/2"))
        XCTAssertTrue(AnywhereExport.acceptsAJSON(formatHeader: " AJSON/1"))
    }
}
