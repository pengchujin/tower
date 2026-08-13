import XCTest
@testable import Tower

/// Transport parameters are load-bearing. A client that cannot express one
/// must skip the node instead of importing a profile that can never connect.
final class TransportGenerationTests: XCTestCase {
    private let parser = SubscriptionParser()
    private let generator = ConfigurationGenerator()
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    func testVLESSGRPCURIKeepsServiceNameAndAuthority() throws {
        let uri = "vless://\(uuid)@grpc.example.com:443?security=tls&type=grpc"
            + "&serviceName=tower.Telemetry&authority=edge.example.com#GRPC"

        let node = try XCTUnwrap(parser.parseURI(uri))

        XCTAssertEqual(node.transport, "grpc")
        XCTAssertEqual(node.path, "tower.Telemetry")
        XCTAssertEqual(node.hostHeader, "edge.example.com")
    }

    func testClashWritesEachSupportedTransportShape() {
        let grpc = generate(.clash, transport: "grpc", path: "tower.Telemetry")
        XCTAssertTrue(grpc.content.contains("network: \"grpc\""), grpc.content)
        XCTAssertTrue(grpc.content.contains("grpc-opts:"), grpc.content)
        XCTAssertTrue(grpc.content.contains("grpc-service-name: \"tower.Telemetry\""), grpc.content)

        let h2 = generate(.clash, transport: "h2", path: "/h2", host: "edge.example.com")
        XCTAssertTrue(h2.content.contains("h2-opts:"), h2.content)
        XCTAssertTrue(h2.content.contains("host: [\"edge.example.com\"]"), h2.content)

        let upgrade = generate(.clash, transport: "httpupgrade", path: "/up", host: "edge.example.com")
        XCTAssertTrue(upgrade.content.contains("network: \"ws\""), upgrade.content)
        XCTAssertTrue(upgrade.content.contains("v2ray-http-upgrade: true"), upgrade.content)

        let xhttp = generate(.clash, transport: "xhttp", path: "/split", host: "edge.example.com")
        XCTAssertTrue(xhttp.content.contains("xhttp-opts:"), xhttp.content)
    }

    func testUnsupportedGRPCIsSkippedInsteadOfDegradedToTCP() {
        for target in [ClientTarget.surge, .loon, .quanx] {
            let result = generate(target, transport: "grpc", path: "tower.Telemetry")
            XCTAssertEqual(result.supportedNodeCount, 0, "\(target.name) 不应降级 gRPC")
            XCTAssertEqual(result.skippedNodeCount, 1)
        }

        for target in [ClientTarget.clash, .shadowrocket, .hiddify, .egern] {
            let result = generate(target, transport: "grpc", path: "tower.Telemetry")
            XCTAssertEqual(result.supportedNodeCount, 1, "\(target.name) 应保留 gRPC")
        }
    }

    func testXHTTPIsOnlyWrittenWhereTheClientCanExpressIt() {
        for target in [ClientTarget.clash, .shadowrocket] {
            XCTAssertEqual(generate(target, transport: "xhttp", path: "/split").supportedNodeCount, 1)
        }
        for target in [ClientTarget.surge, .loon, .quanx, .hiddify, .egern] {
            let result = generate(target, transport: "xhttp", path: "/split")
            XCTAssertEqual(result.supportedNodeCount, 0, "\(target.name) 不应吞掉 XHTTP 参数")
            XCTAssertEqual(result.skippedNodeCount, 1)
        }
    }

    func testHiddifyWritesHTTPUpgradeTransport() {
        let result = generate(.hiddify, transport: "httpupgrade", path: "/up", host: "edge.example.com")
        XCTAssertEqual(result.supportedNodeCount, 1)
        XCTAssertTrue(result.content.contains("\"type\" : \"httpupgrade\""), result.content)
    }

    func testQuanXTrojanWebsocketKeepsItsWebsocketParameters() {
        let node = ProxyNode(
            kind: .trojan, name: "Trojan WS", server: "1.2.3.4", port: 443,
            password: "secret", transport: "ws", tls: true,
            sni: "edge.example.com", hostHeader: "edge.example.com", path: "/trojan",
            rawURI: "trojan://transport"
        )
        let result = generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: .quanx)
        XCTAssertEqual(result.supportedNodeCount, 1)
        XCTAssertTrue(result.content.contains("obfs=wss"), result.content)
        XCTAssertTrue(result.content.contains("obfs-uri=/trojan"), result.content)
    }

    func testShadowsocksV2RayWebsocketPluginIsParsedAndNotSilentlyFlattened() throws {
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388"
            + "?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dedge.example.com%3Bpath%3D%2Fss%3Btls#SS"

        let node = try XCTUnwrap(parser.parseURI(uri))
        XCTAssertEqual(node.transport, "ws")
        XCTAssertEqual(node.hostHeader, "edge.example.com")
        XCTAssertEqual(node.path, "/ss")
        XCTAssertTrue(node.tls)

        let clash = generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: .clash)
        XCTAssertTrue(clash.content.contains("plugin: v2ray-plugin"), clash.content)
    }

    private func generate(
        _ target: ClientTarget,
        transport: String,
        path: String? = nil,
        host: String? = nil
    ) -> GeneratedConfiguration {
        let node = ProxyNode(
            kind: .vless,
            name: "Transport",
            server: "1.2.3.4",
            port: 443,
            uuid: uuid,
            transport: transport,
            tls: true,
            sni: "edge.example.com",
            hostHeader: host,
            path: path,
            rawURI: "vless://transport"
        )
        return generator.generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
    }
}
