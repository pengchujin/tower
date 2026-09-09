import Network
import UIKit
import XCTest
@testable import Tower

final class LANSubscriptionServerTests: XCTestCase {
    @MainActor
    func testAggregatedSurgeURLKeepsNodeModeAndReflectsSourceChanges() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("tower-node-sub-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = SubscriptionSource(name: "One", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "Two", urlString: "https://two.example/sub")
        let nodes = [first, second].map { source in
            ProxyNode(sourceID: source.id, kind: .shadowsocks, name: source.name,
                server: "\(source.name.lowercased()).example", port: 8388,
                cipher: "aes-128-gcm", password: "test", rawURI: "ss://test")
        }
        try store.save(AppSnapshot(subscriptions: [first, second], nodes: nodes,
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge))
        let model = AppModel(persistence: store, arguments: [])
        model.setExportContentMode(.nodesOnly, for: .surge)
        model.setExportContentMode(.nodesOnly, for: .surgeMac)
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.exportContentMode(for: .surge), .nodesOnly)
        XCTAssertEqual(reloaded.exportContentMode(for: .surgeMac), .nodesOnly)
        await model.startLANSharing(listenerEnvironment: .loopback)
        defer { model.stopLANSharing() }
        for target in [ClientTarget.surge, .surgeMac] {
            let url = try XCTUnwrap(model.lanSubscriptionURL(target: target, contentMode: .nodesOnly))
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (initial, response) = try await session.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let text = String(decoding: initial, as: UTF8.self)
            XCTAssertTrue(text.contains("one.example"))
            XCTAssertTrue(text.contains("two.example"))
            XCTAssertFalse(text.contains("[Rule]"))
            model.setExportContentMode(.fullConfiguration, for: target)
            model.selectedTarget = .clash
            model.setEmbedRemoteSubscriptionLinks(true)
            model.setSubscriptions([second], enabled: false)
            let (updated, _) = try await session.data(from: url)
            let updatedText = String(decoding: updated, as: UTF8.self)
            XCTAssertTrue(updatedText.contains("one.example"))
            XCTAssertFalse(updatedText.contains("two.example"))
            XCTAssertFalse(updatedText.contains("[Rule]"))
            XCTAssertFalse(updatedText.contains("policy-path="))
            XCTAssertEqual(model.lanSubscriptionURL(target: target, contentMode: .nodesOnly), url)
            let fullURL = try XCTUnwrap(model.lanSubscriptionURL(target: target))
            let (full, _) = try await session.data(from: fullURL)
            XCTAssertTrue(String(decoding: full, as: UTF8.self).contains("[Rule]"))
            model.setNode(nodes[0], included: false)
            let (empty, _) = try await session.data(from: url)
            XCTAssertTrue(empty.isEmpty)
            model.setNode(nodes[0], included: true)
            model.setExcluded(true, kind: .shadowsocks, for: target)
            let (filtered, _) = try await session.data(from: url)
            XCTAssertTrue(filtered.isEmpty)
            model.setExcluded(false, kind: .shadowsocks, for: target)
            model.setSubscriptions([second], enabled: true)
        }
    }

    func testNodeRouteValidatesModeTargetAndTokenBeforeGenerating() {
        for query in ["target=clash&content=nodesOnly", "target=surge&content=typo", "target=surge&content=",
                      "target=surge&content=nodesOnly&content=fullConfiguration"] {
            let response = LANSubscriptionHTTPRouter.response(
                request: "GET /sub/test?\(query) HTTP/1.1\r\n\r\n", token: "test",
                nodeConfiguration: { _ in XCTFail("Invalid request"); return self.configuration(for: .surge) },
                formatConfiguration: { _ in XCTFail("Invalid mode must not serve a full profile"); return self.configuration(for: .surge) })
            XCTAssertEqual(response.statusCode, 400)
        }
        for target in [ClientTarget.surge, .surgeMac] {
            let url = try! LANSubscriptionURLBuilder.make(host: "127.0.0.1", port: 1234,
                token: "test", target: target.rawValue, contentMode: .nodesOnly)
            for method in ["GET", "HEAD"] {
                let response = LANSubscriptionHTTPRouter.response(
                    request: "\(method) \(url.path)?\(url.query!) HTTP/1.1\r\n\r\n", token: "test",
                    nodeConfiguration: { client in
                        XCTAssertEqual(client, target)
                        return GeneratedConfiguration(target: client, content: "Node = ss, example.com, 443", supportedNodeCount: 1,
                            skippedNodeCount: 0, ruleCount: 0, contentMode: .nodesOnly, fileExtensionOverride: "txt")
                    }, formatConfiguration: { _ in XCTFail("Node URL cannot return full configuration"); return self.configuration(for: .surge) })
                XCTAssertEqual(response.statusCode, 200)
                XCTAssertTrue(response.headers["Content-Disposition"]?.contains(".txt") == true)
                XCTAssertEqual(response.body.isEmpty, method == "HEAD")
            }
            let denied = LANSubscriptionHTTPRouter.response(
                request: "GET /sub/wrong?target=\(target.rawValue)&content=nodesOnly HTTP/1.1\r\n\r\n", token: "test",
                nodeConfiguration: { _ in XCTFail("Wrong token"); return self.configuration(for: .surge) },
                formatConfiguration: { _ in XCTFail("Wrong token"); return self.configuration(for: .surge) })
            XCTAssertEqual(denied.statusCode, 404)
        }
    }

    func testCopiedMacSubscriptionsKeepExactClientInsteadOfGenericDialect() {
        for target in [ClientTarget.surgeMac, .clashMac] {
            var calledTarget: ClientTarget?
            let response = LANSubscriptionHTTPRouter.response(
                request: "GET /sub/test-token?target=\(target.rawValue) HTTP/1.1\r\n\r\n",
                token: "test-token",
                exactClientConfiguration: { client in
                    calledTarget = client
                    return GeneratedConfiguration(target: client, content: "exact-client", supportedNodeCount: 1, skippedNodeCount: 0, ruleCount: 0)
                },
                formatConfiguration: { format in
                    XCTFail("Copied Mac subscriptions must retain client filters")
                    return GeneratedConfiguration(target: format.generationTarget, content: "wrong", supportedNodeCount: 0, skippedNodeCount: 0, ruleCount: 0)
                }
            )
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(calledTarget, target)
            XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "exact-client")
        }
    }

    func testProductionLANSharingKeepsAStablePort() {
        XCTAssertEqual(LANSubscriptionListenerEnvironment.fixedWiFiPort, 65_171)
    }

    /// On a phone the pin is what keeps the listener off cellular, where
    /// "local network" would mean the carrier's network rather than the room.
    func testDesktopClientAliases() throws {
        for alias in ["clash-verge", "clashverge", "clashmac"] {
            XCTAssertEqual(try LANSubscriptionTargetResolver.resolveFormat(explicitTarget: alias, userAgent: nil), .clash)
        }
        for agent in ["ClashMac/27", "Clash-Verge/2.5"] {
            XCTAssertEqual(try LANSubscriptionTargetResolver.resolveFormat(explicitTarget: nil, userAgent: agent), .clash)
        }
    }

    func testPhoneListenerStaysPinnedToWiFi() {
        let parameters = LANSubscriptionListenerEnvironment
            .networkListening(pinnedToWiFi: true)
            .parameters()
        XCTAssertEqual(parameters.requiredInterfaceType, .wifi)
    }

    /// The same binary runs on an Apple silicon Mac, which is usually on
    /// Ethernet. Pinning to Wi-Fi there matches no interface, so the listener
    /// hands out an address that nothing on the LAN can open.
    func testMacListenerAcceptsAnyLANInterface() {
        let parameters = LANSubscriptionListenerEnvironment
            .networkListening(pinnedToWiFi: false)
            .parameters()
        XCTAssertNotEqual(parameters.requiredInterfaceType, .wifi)
        XCTAssertEqual(
            parameters.requiredLocalEndpoint,
            .hostPort(
                host: NWEndpoint.Host("0.0.0.0"),
                port: NWEndpoint.Port(rawValue: LANSubscriptionListenerEnvironment.fixedWiFiPort)!
            ),
            "dropping the interface pin must not also drop the fixed LAN port"
        )
    }

    func testExplicitTargetsAndDesktopAliasesResolve() throws {
        let expected: [String: ClientTarget] = [
            "clash": .clash,
            "clash-mi": .clash,
            "clashmi": .clash,
            "karing": .clash,
            "openclash": .clash,
            "nikki": .clash,
            "mihomo": .clash,
            "stash": .clash,
            "surge": .surge,
            "surfboard": .surge,
            "shadowrocket": .shadowrocket,
            "loon": .loon,
            "quanx": .quanx,
            "quantumult-x": .quanx,
            "sing-box": .singBox,
            "hiddify": .hiddify,
            "egern": .egern
        ]

        for (value, target) in expected {
            XCTAssertEqual(
                try LANSubscriptionTargetResolver.resolve(explicitTarget: value, userAgent: nil),
                target,
                value
            )
        }
    }

    func testSurfboardIsAFirstClassLANFormatUsingItsSurgeCompatibleDialect() throws {
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "surfboard",
                userAgent: nil
            ),
            .surfboard
        )
        XCTAssertEqual(LANSubscriptionFormat.surfboard.generationTarget, .surge)
        XCTAssertEqual(LANSubscriptionFormat.surfboard.displayName, "Surfboard")
        XCTAssertTrue(LANSubscriptionFormat.allCases.contains(.surfboard))
    }

    func testSingBoxIsAFirstClassLANFormatSeparateFromHiddify() throws {
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "sing-box",
                userAgent: nil
            ),
            .singBox
        )
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "hiddify",
                userAgent: nil
            ),
            .hiddify
        )
        XCTAssertEqual(LANSubscriptionFormat.singBox.generationTarget, .singBox)
        XCTAssertTrue(LANSubscriptionFormat.allCases.contains(.singBox))
    }

    func testAutoTargetUsesClientUserAgent() throws {
        let expected: [(String, ClientTarget)] = [
            ("clash.meta", .clash),
            ("OpenClash/v0.46.014", .clash),
            ("Nikki/1.6.3", .clash),
            ("Clash-Verge/2.3", .clash),
            ("Clash Mi/1.0", .clash),
            ("Karing/1.2", .clash),
            ("Surge iOS/5.14", .surge),
            ("Surfboard/2.33.0", .surge),
            ("Shadowrocket/1997 CFNetwork", .shadowrocket),
            ("Loon/925 CFNetwork", .loon),
            ("Quantumult%20X/1.5", .quanx),
            ("HiddifyNext/2.5 sing-box", .hiddify),
            ("Egern/1.22", .egern)
        ]

        for (userAgent, target) in expected {
            XCTAssertEqual(
                try LANSubscriptionTargetResolver.resolve(explicitTarget: "auto", userAgent: userAgent),
                target,
                userAgent
            )
        }
    }

    func testAutomaticRouteKeepsSurfboardDistinctFromSurge() throws {
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "auto",
                userAgent: "Surfboard/2.33.0"
            ),
            .surfboard
        )
    }

    func testEveryLANClientUsesBundledOfficialArtwork() {
        for format in LANSubscriptionFormat.allCases {
            XCTAssertNotNil(
                UIImage(named: format.appIconAssetName),
                "\(format.displayName) 缺少官方客户端图标"
            )
        }
    }

    func testClashLANFormatNamesItsCompatibleClientsInUserFacingOrder() {
        XCTAssertEqual(
            LANSubscriptionFormat.clash.displayName,
            "Clash / Clash Verge / ClashMac / Clash Mi / Karing / OpenClash / Nikki / Stash"
        )
    }

    func testAutomaticRouteRecognizesOfficialSingBoxUserAgent() throws {
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "auto",
                userAgent: "sing-box/1.13.19"
            ),
            .singBox
        )
        XCTAssertEqual(
            try LANSubscriptionTargetResolver.resolveFormat(
                explicitTarget: "auto",
                userAgent: "HiddifyNext/2.5 sing-box"
            ),
            .hiddify,
            "Hiddify must remain distinguishable even though its UA names the sing-box core"
        )
    }

    func testUnknownAutomaticClientIsRejectedInsteadOfReceivingWrongFormat() {
        XCTAssertThrowsError(
            try LANSubscriptionTargetResolver.resolve(
                explicitTarget: "auto",
                userAgent: "Mozilla/5.0"
            )
        ) { error in
            XCTAssertEqual(error as? LANSubscriptionRoutingError, .unknownUserAgent)
        }
    }

    func testRouterRequiresExactPrivateToken() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/wrong?target=clash HTTP/1.1\r\nHost: 192.168.1.2\r\n\r\n",
            token: "private-token",
            formatConfiguration: configuration
        )

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testRouterServesClashConfigurationAndDownloadAlias() {
        for path in [
            "/sub/private-token?target=clash",
            "/download/private-token?target=openclash"
        ] {
            let response = LANSubscriptionHTTPRouter.response(
                request: "GET \(path) HTTP/1.1\r\nHost: 192.168.1.2\r\nUser-Agent: curl/8\r\n\r\n",
                token: "private-token",
                formatConfiguration: configuration
            )

            XCTAssertEqual(response.statusCode, 200, path)
            XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "# clash", path)
            XCTAssertEqual(response.headers["Content-Type"], "application/yaml; charset=utf-8")
            XCTAssertEqual(response.headers["Cache-Control"], "no-store")
            XCTAssertEqual(response.headers["Profile-Update-Interval"], "24")
            XCTAssertEqual(
                response.headers["Content-Disposition"],
                ExportFilePresentation.contentDisposition(
                    fileName: configuration(for: .clash).fileName
                ),
                path
            )
        }
    }

    func testRouterServesSingBoxJSONAsItsOwnLANClient() throws {
        var receivedFormat: LANSubscriptionFormat?
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/private-token?target=sing-box HTTP/1.1\r\nHost: tower.local\r\n\r\n",
            token: "private-token",
            formatConfiguration: { format in
                receivedFormat = format
                return GeneratedConfiguration(
                    target: format.generationTarget,
                    content: #"{"outbounds":[]}"#,
                    supportedNodeCount: 0,
                    skippedNodeCount: 0,
                    ruleCount: 0
                )
            }
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(receivedFormat, .singBox)
        XCTAssertEqual(response.headers["X-Tower-Target"], "sing-box")
        XCTAssertEqual(response.headers["Content-Type"], "application/json; charset=utf-8")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: response.body))
    }

    func testOfficialSingBoxCapabilitiesExcludeSSRButIncludeSnell() {
        let supported = LANSubscriptionFormat.singBox.supportedKindsOverride

        XCTAssertNotNil(supported)
        XCTAssertFalse(supported?.contains(.shadowsocksR) == true)
        XCTAssertTrue(supported?.contains(.snell) == true)
        XCTAssertNil(LANSubscriptionFormat.hiddify.supportedKindsOverride)
    }

    func testRouterSupportsHeadWithoutReturningConfigurationBody() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "HEAD /sub/private-token?target=surge HTTP/1.1\r\nHost: tower.local\r\n\r\n",
            token: "private-token",
            formatConfiguration: configuration
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.body.isEmpty)
        XCTAssertEqual(response.headers["Content-Length"], String("# surge".utf8.count))
    }

    func testAutomaticRouteReadsUserAgentCaseInsensitively() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/private-token?target=auto HTTP/1.1\r\nHost: tower.local\r\nuSeR-aGeNt: clash.meta\r\n\r\n",
            token: "private-token",
            formatConfiguration: configuration
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "# clash")
    }

    func testLANClashPayloadDropsUnsupportedURLRegexRules() {
        let scheme = RuleScheme(
            id: "lan-clash-url-regex",
            name: "LAN Clash",
            summary: "Compatibility regression",
            groups: [
                RuleSchemeGroup(name: "节点选择", kind: .select, members: [.reference("DIRECT")])
            ],
            rulesets: [
                RuleSchemeRuleset(
                    groupName: "节点选择",
                    resource: .inline(#"URL-REGEX,^https?:\/\/www\.amazon\.com\/video\/"#)
                ),
                RuleSchemeRuleset(groupName: "节点选择", resource: .inline("FINAL"))
            ]
        )
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/private-token?target=auto HTTP/1.1\r\nHost: tower.local\r\nUser-Agent: Clash Mi/1.0\r\n\r\n",
            token: "private-token"
        ) { target in
            ConfigurationGenerator().generate(nodes: [], scheme: scheme, target: target)
        }
        let content = String(decoding: response.body, as: UTF8.self)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["X-Tower-Target"], ClientTarget.clash.rawValue)
        XCTAssertFalse(content.contains("URL-REGEX"), content)
    }

    func testUnknownUserAgentReturnsActionableBadRequest() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/private-token?target=auto HTTP/1.1\r\nHost: tower.local\r\nUser-Agent: curl/8\r\n\r\n",
            token: "private-token",
            formatConfiguration: configuration
        )

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("target="))
    }

    func testSharedURLContainsOnlyLocalEndpointAndAccessToken() throws {
        let sourceURL = "https://airport.example/api/subscribe?token=secret-provider-token"
        let url = try LANSubscriptionURLBuilder.make(
            host: "192.168.1.88",
            port: 25500,
            token: "random-access-token",
            target: nil
        )

        XCTAssertEqual(
            url.absoluteString,
            "http://192.168.1.88:25500/sub/random-access-token?target=auto"
        )
        XCTAssertFalse(url.absoluteString.contains(sourceURL))
        XCTAssertFalse(url.absoluteString.contains("secret-provider-token"))
    }

    func testSingBoxSharedURLUsesStableExplicitTarget() throws {
        let url = try LANSubscriptionURLBuilder.make(
            host: "192.168.1.88",
            port: 65_171,
            token: "random-access-token",
            target: LANSubscriptionFormat.singBox.rawValue
        )

        XCTAssertEqual(
            url.absoluteString,
            "http://192.168.1.88:65171/sub/random-access-token?target=sing-box"
        )
    }

    func testAccessTokenPersistsUntilUserRotatesIt() throws {
        let suiteName = "LANSubscriptionServerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = LANSubscriptionAccessTokenStore.loadOrCreate(defaults: defaults)
        XCTAssertEqual(LANSubscriptionAccessTokenStore.loadOrCreate(defaults: defaults), first)
        XCTAssertGreaterThanOrEqual(first.count, 24)

        let rotated = LANSubscriptionAccessTokenStore.rotate(defaults: defaults)
        XCTAssertNotEqual(rotated, first)
        XCTAssertEqual(LANSubscriptionAccessTokenStore.loadOrCreate(defaults: defaults), rotated)
    }

    func testLoopbackListenerServesGeneratedConfigurationEndToEnd() async throws {
        let server = LANSubscriptionServer(
            token: "private-token",
            listenerEnvironment: .loopback,
            configurationProvider: configuration
        )
        let automaticURL = try await server.start()
        defer { server.stop() }

        var request = URLRequest(url: automaticURL)
        request.setValue("OpenClash/runtime-test", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Tower-Target"), ClientTarget.clash.rawValue)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "# clash")
    }

    func testListenerWaitsForFragmentedHTTPHeaders() async throws {
        let server = LANSubscriptionServer(token: "fragment-token", listenerEnvironment: .loopback,
                                           configurationProvider: configuration)
        let url = try await server.start()
        defer { server.stop() }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(url.port!))!, using: .tcp)
        defer { connection.cancel() }
        let received = expectation(description: "Complete response after second header fragment")
        let queue = DispatchQueue(label: "tower.test.fragmented-http")
        connection.start(queue: queue)
        connection.send(content: Data("GET \(url.path) HTTP/1.1\r\nHost: localhost\r\n".utf8), completion: .contentProcessed { _ in
            queue.asyncAfter(deadline: .now() + 0.1) {
                connection.send(content: Data("User-Agent: ClashMac/27\r\n\r\n".utf8), completion: .contentProcessed { _ in })
            }
        })
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            XCTAssertNil(error)
            XCTAssertTrue(String(decoding: data ?? Data(), as: UTF8.self).hasPrefix("HTTP/1.1 200 OK"))
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 5)
    }

    private func configuration(for format: LANSubscriptionFormat) -> GeneratedConfiguration {
        GeneratedConfiguration(
            target: format.generationTarget,
            content: "# \(format.rawValue)",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0
        )
    }
}
