import XCTest
@testable import Tower

final class LANSubscriptionServerTests: XCTestCase {
    func testProductionLANSharingKeepsAStablePort() {
        XCTAssertEqual(LANSubscriptionListenerEnvironment.fixedWiFiPort, 65_171)
    }

    func testExplicitTargetsAndDesktopAliasesResolve() throws {
        let expected: [String: ClientTarget] = [
            "clash": .clash,
            "openclash": .clash,
            "mihomo": .clash,
            "stash": .clash,
            "surge": .surge,
            "shadowrocket": .shadowrocket,
            "loon": .loon,
            "quanx": .quanx,
            "quantumult-x": .quanx,
            "sing-box": .hiddify,
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

    func testAutoTargetUsesClientUserAgent() throws {
        let expected: [(String, ClientTarget)] = [
            ("clash.meta", .clash),
            ("OpenClash/v0.46.014", .clash),
            ("Clash-Verge/2.3", .clash),
            ("Surge iOS/5.14", .surge),
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
            configuration: configuration
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
                configuration: configuration
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

    func testRouterSupportsHeadWithoutReturningConfigurationBody() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "HEAD /sub/private-token?target=surge HTTP/1.1\r\nHost: tower.local\r\n\r\n",
            token: "private-token",
            configuration: configuration
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.body.isEmpty)
        XCTAssertEqual(response.headers["Content-Length"], String("# surge".utf8.count))
    }

    func testAutomaticRouteReadsUserAgentCaseInsensitively() {
        let response = LANSubscriptionHTTPRouter.response(
            request: "GET /sub/private-token?target=auto HTTP/1.1\r\nHost: tower.local\r\nuSeR-aGeNt: clash.meta\r\n\r\n",
            token: "private-token",
            configuration: configuration
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
            configuration: configuration
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

    private func configuration(for target: ClientTarget) -> GeneratedConfiguration {
        GeneratedConfiguration(
            target: target,
            content: "# \(target.rawValue)",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0
        )
    }
}
