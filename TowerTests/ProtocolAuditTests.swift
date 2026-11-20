import XCTest
@testable import Tower

/// Findings from the 2026-09-27 protocol audit. Each node shape here was run
/// through Tower's exports and then through mihomo 1.19.31 / sing-box 1.14.2
/// against a test server; every case below failed to connect before its fix.
final class ProtocolAuditTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let uuid = "52396e06-041a-4cc2-be5c-8525eb457809"

    private func content(_ nodes: [ProxyNode], _ target: ClientTarget) -> String {
        ConfigurationGenerator().generate(nodes: nodes, preset: RulePreset.builtIns[0], target: target).content
    }

    private func nodesOnly(_ nodes: [ProxyNode], _ target: ClientTarget) -> GeneratedConfiguration {
        ConfigurationGenerator().generateNodeSubscription(nodes: nodes, target: target, profileName: "Audit")
    }

    private func vmessLink(_ fields: [String: String]) -> String {
        var object = ["v": "2", "ps": "VMess", "add": "vm.example.com", "port": "80", "id": uuid, "aid": "0"]
        object.merge(fields) { _, new in new }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return "vmess://" + data.base64EncodedString()
    }

    // MARK: - HTTP/1.1 obfuscation and HTTP/2 in share links

    func testVLESSTypeHTTPIsTheHTTP2Transport() throws {
        // The Xray link standard names its HTTP/2 transport `http`.
        let node = try XCTUnwrap(parser.parseURI(
            "vless://\(uuid)@v.example.com:443?security=tls&sni=v.example.com&type=http&path=%2Fh2&host=v.example.com#H2"
        ))
        XCTAssertEqual(node.transport, "h2")
        let trojan = try XCTUnwrap(parser.parseURI("trojan://pw@t.example.com:443?type=http&path=%2Fh2#T"))
        XCTAssertEqual(trojan.transport, "h2")
    }

    func testVLESSHeaderTypeHTTPKeepsTheObfuscation() throws {
        let node = try XCTUnwrap(parser.parseURI(
            "vless://\(uuid)@v.example.com:80?security=none&type=tcp&headerType=http&path=%2Fobfs&host=cover.example.com#Obfs"
        ))
        XCTAssertEqual(node.transport, "http")
        XCTAssertEqual(node.path, "/obfs")
        XCTAssertEqual(node.hostHeader, "cover.example.com")
    }

    func testVMessTCPWithHTTPHeaderKeepsTheObfuscation() throws {
        let obfs = try XCTUnwrap(parser.parseURI(vmessLink(["net": "tcp", "type": "http", "path": "/obfs", "host": "cover.example.com"])))
        XCTAssertEqual(obfs.transport, "http")
        XCTAssertEqual(obfs.path, "/obfs")
        let h2 = try XCTUnwrap(parser.parseURI(vmessLink(["net": "http", "tls": "tls", "path": "/h2"])))
        XCTAssertEqual(h2.transport, "h2")
        let plain = try XCTUnwrap(parser.parseURI(vmessLink(["net": "tcp", "type": "none"])))
        XCTAssertEqual(plain.transport, "tcp")
    }

    func testShareLinksWriteHTTPObfuscationTheStandardWay() throws {
        let vmess = try XCTUnwrap(parser.parseURI(vmessLink(["net": "tcp", "type": "http", "path": "/obfs", "host": "cover.example.com"])))
        let link = ProxyNodeShareLinkGenerator().canonicalLink(for: vmess)
        let payload = try XCTUnwrap(Data(base64Encoded: String(link.dropFirst("vmess://".count))))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(json["net"] as? String, "tcp")
        XCTAssertEqual(json["type"] as? String, "http")
        // Re-reading the link must give the same transport back.
        XCTAssertEqual(parser.parseURI(link)?.transport, "http")

        let vless = try XCTUnwrap(parser.parseURI(
            "vless://\(uuid)@v.example.com:80?type=tcp&headerType=http&path=%2Fobfs#Obfs"
        ))
        let vlessLink = ProxyNodeShareLinkGenerator().canonicalLink(for: vless)
        XCTAssertTrue(vlessLink.contains("type=tcp"), vlessLink)
        XCTAssertTrue(vlessLink.contains("headerType=http"), vlessLink)
        XCTAssertEqual(parser.parseURI(vlessLink)?.transport, "http")
    }

    // MARK: - Native Shadowsocks TLS

    private var nativeTLSShadowsocks: ProxyNode {
        ProxyNode(kind: .shadowsocks, name: "SS TLS", server: "ss.example.com", port: 443,
                  cipher: "aes-128-gcm", password: "pw", tls: true, sni: "ss.example.com", rawURI: "")
    }

    func testNativeShadowsocksTLSIsNeverExportedAsPlainShadowsocks() {
        // Surge, Loon, Clash Mi, Karing and URI lists wrote it without TLS.
        for target in [ClientTarget.surge, .surgeMac, .loon, .clashMi, .karing, .clash, .egern, .singBox] {
            XCTAssertEqual(
                ConfigurationGenerator().generate(nodes: [nativeTLSShadowsocks], preset: RulePreset.builtIns[0], target: target).supportedNodeCount,
                0, "\(target.name) 不能表达原生 SS TLS"
            )
        }
        XCTAssertEqual(nodesOnly([nativeTLSShadowsocks], .v2box).supportedNodeCount, 0)
    }

    func testNativeShadowsocksTLSStaysInShadowrocketAndQuantumultX() {
        XCTAssertTrue(content([nativeTLSShadowsocks], .shadowrocket).contains("tls: true"))
        XCTAssertTrue(content([nativeTLSShadowsocks], .quanx).contains("obfs=over-tls"))
        // A plain URI cannot say TLS, so Shadowrocket's node list switches to YAML.
        let list = nodesOnly([nativeTLSShadowsocks], .shadowrocket)
        XCTAssertEqual(list.supportedNodeCount, 1)
        XCTAssertTrue(list.content.hasPrefix("proxies:"), list.content)
        XCTAssertTrue(list.content.contains("tls: true"), list.content)
    }

    // MARK: - Reality where the client has no field for it

    private func reality(_ kind: ProxyKind) -> ProxyNode {
        ProxyNode(kind: kind, name: "\(kind.rawValue) Reality", server: "r.example.com", port: 443,
                  password: "pw", username: kind == .anytls ? nil : "user", tls: true, sni: "cover.example.com",
                  realityPublicKey: "LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk", realityShortID: "abcd",
                  fingerprint: "chrome", rawURI: "")
    }

    func testClashMiSkipsRealityThatMihomoIgnores() {
        // Clash Mi users saw 07/09/10 fail; mihomo loads the YAML and then
        // connects with plain TLS to the borrowed SNI.
        for kind in [ProxyKind.anytls, .socks5, .http] {
            XCTAssertFalse(content([reality(kind)], .clashMi).contains("r.example.com"), "\(kind)")
        }
    }

    func testLoonAndKaringSkipSOCKS5AndHTTPReality() {
        for target in [ClientTarget.loon, .karing] {
            for kind in [ProxyKind.socks5, .http] {
                XCTAssertFalse(content([reality(kind)], target).contains("r.example.com"), "\(target.name) \(kind)")
            }
        }
        // Loon's Trojan and AnyTLS do take Reality.
        XCTAssertTrue(content([reality(.anytls)], .loon).contains("public-key="))
    }

    // MARK: - Loon

    private func hysteria2(obfs: String? = "salamander", hopping: String? = nil) -> ProxyNode {
        ProxyNode(kind: .hysteria2, name: "HY2", server: "hy.example.com", port: 443, password: "pw",
                  tls: true, sni: "hy.example.com", obfs: obfs, obfsParam: obfs == nil ? nil : "obfs-secret",
                  portHopping: hopping, rawURI: "")
    }

    func testLoonKeepsHysteria2SalamanderAndPortHopping() {
        let loon = content([hysteria2(hopping: "20000-20100,443")], .loon)
        XCTAssertTrue(loon.contains("salamander-password=obfs-secret,"), loon)
        XCTAssertFalse(loon.contains("salamander-password=\""), loon)
        var delimited = hysteria2()
        delimited.obfsParam = "a,b"
        XCTAssertFalse(content([delimited], .loon).contains("hy.example.com"))
        XCTAssertTrue(loon.contains("server-ports=\"20000:20100,443\""), loon)
        // Only Salamander has a Loon key; another obfuscator is skipped.
        XCTAssertFalse(content([hysteria2(obfs: "gecko")], .loon).contains("hy.example.com"))
    }

    func testLoonVMessAndVLESSRelayUDP() {
        let vless = ProxyNode(kind: .vless, name: "V", server: "v.example.com", port: 443, uuid: uuid,
                              transport: "ws", tls: true, path: "/ws", rawURI: "")
        let line = content([vless], .loon).split(separator: "\n").first { $0.contains("v.example.com") } ?? ""
        XCTAssertTrue(line.contains("udp=true"), String(line))
    }

    func testLoonTrojanOnlyWritesWebSocket() {
        // Loon reads a Trojan `transport=http` as WebSocket.
        let trojan = ProxyNode(kind: .trojan, name: "T", server: "t.example.com", port: 443, password: "pw",
                               transport: "http", tls: true, path: "/x", rawURI: "")
        XCTAssertFalse(content([trojan], .loon).contains("t.example.com"))
    }

    // MARK: - Hysteria 2 port hopping

    func testHysteria2PortListInTheAuthorityIsParsed() throws {
        let node = try XCTUnwrap(parser.parseURI("hysteria2://pw@hy.example.com:443,20000-20100/?sni=hy.example.com#HY"))
        XCTAssertEqual(node.port, 443)
        XCTAssertEqual(node.portHopping, "443,20000-20100")
        let range = try XCTUnwrap(parser.parseURI("hy2://pw@[2001:db8::1]:20000-20100?obfs=salamander&obfs-password=x#V6"))
        XCTAssertEqual(range.port, 20000)
        XCTAssertEqual(range.server, "2001:db8::1")
        XCTAssertEqual(range.portHopping, "20000-20100")
    }

    func testPortHoppingReachesEveryClientThatHasIt() throws {
        let node = hysteria2(hopping: "20000-20100,443")
        XCTAssertTrue(content([node], .surge).contains("port-hopping=\"20000-20100;443\""))
        XCTAssertTrue(content([node], .egern).contains("port_hopping: \"20000-20100,443\""))
        let singBox = content([node], .singBox)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(singBox.utf8)) as? [String: Any])
        let outbound = try XCTUnwrap((json["outbounds"] as? [[String: Any]])?.first { $0["type"] as? String == "hysteria2" })
        XCTAssertEqual(outbound["server_ports"] as? [String], ["20000:20100", "443:443"])
    }

    // MARK: - Egern transports

    /// Egern documents Reality on its `tls` and `grpc` transports (proxies
    /// page, re-read 2026-09-28); HTTP/2 stays ordinary TLS.
    func testEgernPairsRealityOnlyWithTCPAndGRPC() {
        let grpc = ProxyNode(kind: .vless, name: "Reality gRPC", server: "e.example.com", port: 443, uuid: uuid,
                             transport: "grpc", tls: true, sni: "cover.example.com", path: "svc",
                             realityPublicKey: "LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk", rawURI: "")
        XCTAssertTrue(content([grpc], .egern).contains("          reality:"))
        var h2 = grpc; h2.transport = "h2"; h2.server = "h2.example.com"
        XCTAssertFalse(content([h2], .egern).contains("h2.example.com"))
        let trojanHTTP = ProxyNode(kind: .trojan, name: "T", server: "t.example.com", port: 443, password: "pw",
                                   transport: "http", tls: true, rawURI: "")
        XCTAssertFalse(content([trojanHTTP], .egern).contains("t.example.com"))
    }

    // MARK: - WebSocket early data

    private var earlyData: ProxyNode {
        ProxyNode(kind: .vmess, name: "ED", server: "ws.example.com", port: 443, uuid: uuid, transport: "ws",
                  tls: true, sni: "ws.example.com", hostHeader: "ws.example.com", path: "/ws?ed=2048", rawURI: "")
    }

    func testSingBoxAndStashTakeEarlyDataAsSettings() throws {
        let singBox = content([earlyData], .singBox)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(singBox.utf8)) as? [String: Any])
        let outbound = try XCTUnwrap((json["outbounds"] as? [[String: Any]])?.first { $0["type"] as? String == "vmess" })
        let transport = try XCTUnwrap(outbound["transport"] as? [String: Any])
        XCTAssertEqual(transport["path"] as? String, "/ws")
        XCTAssertEqual(transport["max_early_data"] as? Int, 2048)
        XCTAssertEqual(transport["early_data_header_name"] as? String, "Sec-WebSocket-Protocol")

        let stash = content([earlyData], .clash)
        XCTAssertTrue(stash.contains("path: \"/ws\""), stash)
        XCTAssertTrue(stash.contains("max-early-data: 2048"), stash)
        // Mihomo reads `?ed=` from the path itself.
        XCTAssertTrue(content([earlyData], .clashApple).contains("path: \"/ws?ed=2048\""))
    }

    func testClientsWithoutEarlyDataGetTheBarePath() {
        XCTAssertTrue(content([earlyData], .surge).contains("ws-path=/ws,"))
        XCTAssertTrue(content([earlyData], .loon).contains("path=/ws,"))
        XCTAssertTrue(content([earlyData], .quanx).contains("obfs-uri=/ws,"))
        XCTAssertTrue(content([earlyData], .egern).contains("path: \"/ws\""))
    }

    func testEarlyDataKeepsOtherPathQueries() {
        var node = earlyData
        node.path = "/ws?token=a&ed=1024"
        XCTAssertEqual(node.webSocketEarlyData, 1024)
        XCTAssertEqual(node.exportablePathWithoutEarlyData, "/ws?token=a")
        node.path = "/plain"
        XCTAssertNil(node.webSocketEarlyData)
        XCTAssertEqual(node.exportablePathWithoutEarlyData, "/plain")
    }

    // MARK: - Trojan SNI in Clash YAML

    func testClashFamilyWritesTrojanSNIUnderItsOwnKey() {
        let trojan = ProxyNode(kind: .trojan, name: "T", server: "203.0.113.7", port: 443, password: "pw",
                               tls: true, sni: "front.example.com", alpn: "h2,http/1.1", rawURI: "")
        for target in [ClientTarget.clashApple, .clashMi, .karing, .shadowrocket, .clash] {
            let yaml = content([trojan], target)
            XCTAssertTrue(yaml.contains("    sni: \"front.example.com\""), "\(target.name)\n\(yaml)")
            XCTAssertFalse(yaml.contains("servername: \"front.example.com\""), target.name)
            XCTAssertTrue(yaml.contains("alpn: [\"h2\", \"http/1.1\"]"), "\(target.name)\n\(yaml)")
        }
    }

    func testSOCKS5TLSWithADifferentSNISkipsClientsWithoutAnSNIField() {
        let fronted = ProxyNode(kind: .socks5, name: "S", server: "203.0.113.7", port: 443, password: "pw",
                                username: "u", tls: true, sni: "front.example.com", rawURI: "")
        for target in [ClientTarget.clashApple, .clashMi, .clash] {
            XCTAssertFalse(content([fronted], target).contains("203.0.113.7"), target.name)
        }
        var direct = fronted
        direct.server = "front.example.com"
        XCTAssertTrue(content([direct], .clashApple).contains("front.example.com"))
    }

    func testTextClientsUseTheHostHeaderWhenSNIIsMissing() {
        let fronted = ProxyNode(kind: .vmess, name: "CDN", server: "203.0.113.7", port: 443, uuid: uuid,
                                transport: "ws", tls: true, hostHeader: "front.example.com", path: "/ws", rawURI: "")
        XCTAssertTrue(content([fronted], .surge).contains("sni=front.example.com"))
        XCTAssertTrue(content([fronted], .loon).contains("tls-name=front.example.com"))
        XCTAssertTrue(content([fronted], .quanx).contains("front.example.com"))
        XCTAssertTrue(content([fronted], .egern).contains("sni: \"front.example.com\""))
        // Stash timed out on this shape until servername was written out.
        XCTAssertTrue(content([fronted], .clash).contains("servername: \"front.example.com\""))
    }

    // MARK: - Karing

    func testKaringSkipsWhatFailedOnDevice() {
        for transport in ["h2", "httpupgrade"] {
            let node = ProxyNode(kind: .vmess, name: transport, server: "k.example.com", port: 443, uuid: uuid,
                                 transport: transport, tls: true, sni: "k.example.com", path: "/p", rawURI: "")
            XCTAssertFalse(content([node], .karing).contains("k.example.com"), transport)
            XCTAssertTrue(content([node], .clashMi).contains("k.example.com"), transport)
        }
        let grpc = ProxyNode(kind: .vless, name: "grpc", server: "g.example.com", port: 443, uuid: uuid,
                             transport: "grpc", tls: true, path: "svc", rawURI: "")
        XCTAssertTrue(content([grpc], .karing).contains("g.example.com"))
        XCTAssertFalse(content([reality(.trojan)], .karing).contains("r.example.com"))
        XCTAssertTrue(content([reality(.anytls)], .karing).contains("r.example.com"))
    }

    // MARK: - Hiddify, V2Box, Anywhere

    func testHiddifyHidesTheShadowTLSHelperInFullProfiles() throws {
        var node = ProxyNode(kind: .shadowsocks, name: "STLS", server: "s.example.com", port: 443,
                             cipher: "aes-128-gcm", password: "pw", plugin: "shadow-tls", rawURI: "")
        node.shadowTLS = ShadowTLSOptions(version: 3, host: "cover.example.com", password: "tls")
        let hiddify = content([node], .hiddify)
        XCTAssertTrue(hiddify.contains("§hide§tower-shadowtls"), hiddify)
        // Official sing-box lists only group members, so its tag stays plain.
        XCTAssertFalse(content([node], .singBox).contains("§hide§"))
    }

    func testV2BoxSkipsHTTP2WhichXrayRemoved() {
        let h2 = ProxyNode(kind: .vless, name: "H2", server: "h.example.com", port: 443, uuid: uuid,
                           transport: "h2", tls: true, sni: "h.example.com", path: "/h2", rawURI: "")
        XCTAssertEqual(nodesOnly([h2], .v2box).supportedNodeCount, 0)
    }

    func testShareLinksCarryTheHostAsSNI() throws {
        let fronted = ProxyNode(kind: .vless, name: "CDN", server: "203.0.113.7", port: 443, uuid: uuid,
                                transport: "ws", tls: true, hostHeader: "front.example.com", path: "/ws", rawURI: "")
        let link = ProxyNodeShareLinkGenerator().canonicalLink(for: fronted)
        XCTAssertEqual(URLComponents(string: link)?.queryItems?.first { $0.name == "sni" }?.value, "front.example.com")
        XCTAssertTrue(AnywhereExport.link(for: fronted).contains("sni=front.example.com"))
    }

    // MARK: - Stash field names

    func testStashUsesItsOwnHysteriaAndTUICFields() {
        let hy2 = hysteria2(obfs: nil)
        let stash = content([hy2], .clash)
        XCTAssertTrue(stash.contains("    auth: \"pw\""), stash)
        XCTAssertTrue(content([hy2], .clashApple).contains("    password: \"pw\""))

        let hy1 = ProxyNode(kind: .hysteria, name: "HY1", server: "h1.example.com", port: 443, password: "pw",
                            tls: true, upMbps: 20, downMbps: 80, rawURI: "")
        let stashHy1 = content([hy1], .clash)
        XCTAssertTrue(stashHy1.contains("up-speed: 20") && stashHy1.contains("down-speed: 80"), stashHy1)
        XCTAssertTrue(content([hy1], .clashApple).contains("    up: 20"))

        let tuic = ProxyNode(kind: .tuic, name: "TUIC", server: "t.example.com", port: 443, password: "pw",
                             uuid: uuid, tls: true, rawURI: "")
        XCTAssertTrue(content([tuic], .clash).contains("    version: 5"))
        // Stash's own YAML must still import back into Tower.
        let parsed = parser.parse(data: Data(stash.utf8)).nodes.first { $0.kind == .hysteria2 }
        XCTAssertEqual(parsed?.password, "pw")
    }

    // MARK: - Quantumult X UDP

    func testQuantumultXRelaysUDPForEveryProxyThatCan() {
        let trojan = ProxyNode(kind: .trojan, name: "T", server: "t.example.com", port: 443, password: "pw",
                               tls: true, rawURI: "")
        let vmess = ProxyNode(kind: .vmess, name: "V", server: "v.example.com", port: 443, uuid: uuid,
                              transport: "ws", tls: true, path: "/ws", rawURI: "")
        let text = content([trojan, vmess], .quanx)
        for host in ["t.example.com", "v.example.com"] {
            let line = text.split(separator: "\n").first { $0.contains(host) } ?? ""
            XCTAssertTrue(line.contains("udp-relay=true"), String(line))
        }
    }

    // MARK: - AmneziaWG

    func testAmneziaWireGuardIsRejectedRatherThanImportedAsWireGuard() {
        let block = """
        proxies:
          - name: AWG
            type: wireguard
            server: wg.example.com
            port: 51820
            ip: 10.0.0.2
            private-key: cHJpdmF0ZQ==
            public-key: cHVibGlj
            amnezia-wg-option:
              jc: 4
              jmin: 40
              jmax: 70
          - name: WG
            type: wireguard
            server: wg.example.com
            port: 51820
            ip: 10.0.0.2
            private-key: cHJpdmF0ZQ==
            public-key: cHVibGlj
        """
        let parsed = parser.parse(data: Data(block.utf8))
        XCTAssertEqual(parsed.nodes.map(\.name), ["WG"])
        XCTAssertEqual(parsed.rejectedLineCount, 1)

        let inline = "proxies:\n  - {name: AWG, type: wireguard, server: wg.example.com, port: 51820, ip: 10.0.0.2, private-key: cHJpdmF0ZQ==, public-key: cHVibGlj, amnezia-wg-option: {jc: 4, jmin: 40, jmax: 70}}\n"
        XCTAssertTrue(parser.parse(data: Data(inline.utf8)).nodes.isEmpty)

        XCTAssertNil(parser.parseURI("wireguard://cHJpdmF0ZQ==@wg.example.com:51820?publickey=cHVibGlj&address=10.0.0.2&jc=4&jmin=40&jmax=70#AWG"))
    }

    // MARK: - Shadowsocks ciphers

    func testShadowsocks2022ChaChaOnlyGoesWhereItIsImplemented() {
        let node = ProxyNode(kind: .shadowsocks, name: "SS2022", server: "ss.example.com", port: 443,
                             cipher: "2022-blake3-chacha20-poly1305", password: "a2V5", rawURI: "")
        // Surge's manual and Loon's docs list only the AES 2022 ciphers.
        for target in [ClientTarget.surge, .surgeMac, .loon, .quanx, .clash] {
            XCTAssertFalse(content([node], target).contains("ss.example.com"), target.name)
        }
        for target in [ClientTarget.egern, .clashApple, .singBox, .shadowrocket] {
            XCTAssertTrue(content([node], target).contains("ss.example.com"), target.name)
        }
        // Egern's AEAD list has no AES-192.
        let aes192 = ProxyNode(kind: .shadowsocks, name: "AES192", server: "a.example.com", port: 443,
                               cipher: "aes-192-gcm", password: "pw", rawURI: "")
        XCTAssertFalse(content([aes192], .egern).contains("a.example.com"))
        XCTAssertTrue(content([aes192], .surge).contains("a.example.com"))
    }

    // MARK: - VLESS encryption

    func testVLESSEncryptionIsKeptAndOnlyExportedWhereItWorks() throws {
        let key = "mlkem768x25519plus.native.0rtt.fixture-key"
        let node = try XCTUnwrap(parser.parseURI(
            "vless://\(uuid)@v.example.com:443?encryption=\(key)&security=none&type=tcp#Enc"
        ))
        XCTAssertEqual(node.vlessEncryption, key)
        XCTAssertNil(parser.parseURI("vless://\(uuid)@v.example.com:443?encryption=none#Plain")?.vlessEncryption)

        XCTAssertTrue(content([node], .clashApple).contains("encryption: \"\(key)\""))
        // Surge iOS 6.0 / Mac 6.12 have their own `encryption=` field.
        XCTAssertTrue(content([node], .surge).contains("encryption=\(key)"))
        for target in [ClientTarget.loon, .quanx, .singBox, .shadowrocket, .egern] {
            XCTAssertFalse(content([node], target).contains("v.example.com"), target.name)
        }
        let link = ProxyNodeShareLinkGenerator().canonicalLink(for: node)
        XCTAssertEqual(parser.parseURI(link)?.vlessEncryption, key)

        let yaml = """
        proxies:
          - name: Enc
            type: vless
            server: v.example.com
            port: 443
            uuid: \(uuid)
            encryption: \(key)
        """
        XCTAssertEqual(parser.parse(data: Data(yaml.utf8)).nodes.first?.vlessEncryption, key)
    }

    // MARK: - sing-box's single HTTP transport

    func testSingBoxSkipsHTTPTransportPairingsItCannotSpell() {
        let obfsOverTLS = ProxyNode(kind: .vmess, name: "H1 TLS", server: "a.example.com", port: 443, uuid: uuid,
                                    transport: "http", tls: true, rawURI: "")
        let cleartextH2 = ProxyNode(kind: .vmess, name: "H2C", server: "b.example.com", port: 80, uuid: uuid,
                                    transport: "h2", rawURI: "")
        for target in [ClientTarget.singBox, .hiddify] {
            let text = content([obfsOverTLS, cleartextH2], target)
            XCTAssertFalse(text.contains("a.example.com"), target.name)
            XCTAssertFalse(text.contains("b.example.com"), target.name)
        }
    }
}
