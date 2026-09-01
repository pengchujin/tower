import Foundation
import Testing
@testable import Tower

@Suite("VLESS WebSocket Host compatibility")
struct VLESSWebSocketHostTests {
    private let uuid = "11111111-2222-4333-8444-555555555555"

    @Test("Shadowrocket endpoint-only VLESS preserves a bare obfsParam Host")
    func legacyBareObfsParam() throws {
        let node = try #require(SubscriptionParser().parseURI(
            endpointOnlyLink(obfsParam: "cdn.example.com")
        ))

        #expect(node.transport == "ws")
        #expect(node.hostHeader == "cdn.example.com")
        #expect(node.sni == "tls.example.com")
    }

    @Test("Shadowrocket endpoint-only VLESS extracts Host from JSON obfsParam")
    func legacyJSONObfsParam() throws {
        let encodedJSON = "%7B%22hOsT%22%3A%22json-cdn.example.com%22%7D"
        let node = try #require(SubscriptionParser().parseURI(
            endpointOnlyLink(obfsParam: encodedJSON)
        ))

        #expect(node.hostHeader == "json-cdn.example.com")
    }

    @Test("Standard-authority VLESS accepts Shadowrocket obfsParam vocabulary")
    func standardAuthorityObfsParam() throws {
        let link = "vless://\(uuid)@203.0.113.10:443"
            + "?security=tls&type=ws&obfsParam=cdn.example.com"
            + "&path=%2Fws&sni=tls.example.com#Standard"
        let node = try #require(SubscriptionParser().parseURI(link))

        #expect(node.hostHeader == "cdn.example.com")
        #expect(node.exportablePath == "/ws")
    }

    @Test("Standard-authority VLESS extracts Host from JSON obfsParam")
    func standardAuthorityJSONObfsParam() throws {
        let link = "vless://\(uuid)@203.0.113.10:443"
            + "?security=tls&type=ws"
            + "&obfsParam=%7B%22headers%22%3A%7B%22HOST%22%3A%22json-cdn.example.com%22%7D%7D"
            + "&path=%2Fws&sni=tls.example.com#Standard"
        let node = try #require(SubscriptionParser().parseURI(link))

        #expect(node.hostHeader == "json-cdn.example.com")
    }

    @Test("obfsParam is WS-only and never overrides an explicit Host")
    func obfsParamPrecedenceAndTransportScope() throws {
        let explicit = try #require(SubscriptionParser().parseURI(
            "vless://\(uuid)@203.0.113.10:443"
                + "?security=tls&type=ws&host=explicit.example.com"
                + "&obfsParam=fallback.example.com"
        ))
        #expect(explicit.hostHeader == "explicit.example.com")

        let grpc = try #require(SubscriptionParser().parseURI(
            "vless://\(uuid)@203.0.113.10:443"
                + "?security=tls&type=grpc&serviceName=tower"
                + "&obfsParam=not-a-grpc-authority.example.com"
        ))
        #expect(grpc.hostHeader == nil)
    }

    @Test("Missing Clash WS Host uses a narrow IP plus SNI fallback")
    func inferredHostIsNarrowAndKeepsRawSourceEmpty() throws {
        let yaml = """
        proxies:
          - name: Missing Host
            type: vless
            server: 203.0.113.10
            port: 443
            uuid: \(uuid)
            network: ws
            tls: true
            servername: cdn.example.com
            ws-opts:
              path: /ws
        """
        let node = try #require(SubscriptionParser().parse(data: Data(yaml.utf8)).nodes.first)

        #expect(node.hostHeader == nil)
        #expect(node.exportableTransportHost == "cdn.example.com")

        var explicit = node
        explicit.hostHeader = "origin.example.com"
        #expect(explicit.exportableTransportHost == "origin.example.com")

        var domainEndpoint = node
        domainEndpoint.server = "edge.example.com"
        #expect(domainEndpoint.exportableTransportHost == nil)

        var plaintext = node
        plaintext.tls = false
        #expect(plaintext.exportableTransportHost == nil)

        var nonWebSocket = node
        nonWebSocket.transport = "grpc"
        #expect(nonWebSocket.exportableTransportHost == nil)

        var numericSNI = node
        numericSNI.sni = "198.51.100.20"
        #expect(numericSNI.exportableTransportHost == nil)

        var ipv6Endpoint = node
        ipv6Endpoint.server = "2001:db8::10"
        #expect(ipv6Endpoint.exportableTransportHost == "cdn.example.com")

        var reality = node
        reality.realityPublicKey = "TestPublicKeyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        #expect(reality.exportableTransportHost == nil)
    }

    @Test("Every affected full-configuration target receives the inferred Host")
    func fullConfigurationTargets() {
        let node = missingHostNode()
        let generator = ConfigurationGenerator()
        let preset = RulePreset.builtIns[0]

        for target in [ClientTarget.clash, .clashApple, .shadowrocket, .egern] {
            let result = generator.generate(nodes: [node], preset: preset, target: target)
            #expect(result.content.contains("Host: \"cdn.example.com\""), "Target: \(target.name)")
        }

        let loon = generator.generate(nodes: [node], preset: preset, target: .loon)
        #expect(loon.content.contains("host=cdn.example.com"))

        let quanX = generator.generate(nodes: [node], preset: preset, target: .quanx)
        #expect(quanX.content.contains("obfs-host=cdn.example.com"))

        for emptyHost in ["", "  \n"] {
            var blankExplicitHost = node
            blankExplicitHost.hostHeader = emptyHost
            let quanXWithBlankHost = generator.generate(
                nodes: [blankExplicitHost],
                preset: preset,
                target: .quanx
            )
            #expect(quanXWithBlankHost.content.contains("obfs-host=cdn.example.com"))
        }

        for target in [ClientTarget.hiddify, .singBox] {
            let result = generator.generate(nodes: [node], preset: preset, target: target)
            #expect(singBoxWebSocketHost(result.content) == "cdn.example.com", "Target: \(target.name)")
        }

        let surge = generator.generate(nodes: [node], preset: preset, target: .surge)
        #expect(surge.supportedNodeCount == 0)
        #expect(surge.skippedNodeCount == 1)
    }

    @Test("Every affected nodes-only target receives the inferred Host")
    func nodesOnlyTargets() throws {
        let node = missingHostNode()
        let generator = ConfigurationGenerator()

        let loon = generator.generateNodeSubscription(nodes: [node], target: .loon)
        #expect(loon.content.contains("host=cdn.example.com"))

        let quanX = generator.generateNodeSubscription(nodes: [node], target: .quanx)
        #expect(quanX.content.contains("obfs-host=cdn.example.com"))

        let hiddify = generator.generateNodeSubscription(nodes: [node], target: .hiddify)
        #expect(hiddify.content.contains("host=cdn.example.com"))

        for target in [ClientTarget.shadowrocket, .v2box] {
            let result = generator.generateNodeSubscription(nodes: [node], target: target)
            let decoded = try #require(Data(base64Encoded: result.content))
            let links = try #require(String(data: decoded, encoding: .utf8))
            #expect(links.contains("host=cdn.example.com"), "Target: \(target.name)")
        }
    }

    @Test("Manual node sharing rebuilds an otherwise reusable URI with inferred Host")
    func manualShareLinkUsesInferredHost() throws {
        let node = missingHostNode()
        let link = ProxyNodeShareLinkGenerator().link(for: node)
        let reparsed = try #require(SubscriptionParser().parseURI(link))

        #expect(link != node.rawURI)
        #expect(reparsed.hostHeader == "cdn.example.com")
    }

    private func endpointOnlyLink(obfsParam: String) -> String {
        let endpoint = "auto:\(uuid)@203.0.113.10:443"
        let encoded = Data(endpoint.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "vless://\(encoded)"
            + "?obfs=websocket&obfsParam=\(obfsParam)"
            + "&path=%2Fws&tls=1&peer=tls.example.com#Legacy"
    }

    private func missingHostNode() -> ProxyNode {
        ProxyNode(
            kind: .vless,
            name: "Missing Host",
            server: "203.0.113.10",
            port: 443,
            uuid: uuid,
            transport: "ws",
            tls: true,
            sni: "cdn.example.com",
            path: "/ws",
            rawURI: "vless://\(uuid)@203.0.113.10:443"
                + "?security=tls&type=ws&path=%2Fws&sni=cdn.example.com#Missing%20Host"
        )
    }

    private func singBoxWebSocketHost(_ content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = root["outbounds"] as? [[String: Any]],
              let proxy = outbounds.first(where: { $0["type"] as? String == "vless" }),
              let transport = proxy["transport"] as? [String: Any],
              let headers = transport["headers"] as? [String: Any] else {
            return nil
        }
        return headers["Host"] as? String
    }
}
