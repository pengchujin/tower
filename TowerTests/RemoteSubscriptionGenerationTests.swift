import XCTest
@testable import Tower

final class RemoteSubscriptionGenerationTests: XCTestCase {
    private let preset = RulePreset.builtIns[0]

    func testCapabilityMatrixOnlyIncludesEmbeddedRemoteSourceFormats() {
        let supported: Set<ClientTarget> = [
            .clash, .clashApple, .clashMi, .karing,
            .surge, .loon, .quanx, .egern,
        ]

        XCTAssertEqual(
            Set(ClientTarget.allCases.filter(\.supportsEmbeddedRemoteSubscriptions)),
            supported
        )
    }

    func testBuiltInProfilesEmbedRemoteSourceAndKeepLocalNodes() {
        let fixture = makeFixture()
        let generator = ConfigurationGenerator()

        let clash = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .clashApple,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(clash.contains("proxy-providers:"), clash)
        XCTAssertTrue(clash.contains("url: \"https://airport.example/sub?token=secret\""), clash)
        XCTAssertTrue(clash.contains("use:\n      - \"tower-subscription-1\""), clash)
        XCTAssertTrue(clash.contains("local.example.com"), clash)
        XCTAssertFalse(clash.contains("remote.example.com"), clash)

        let surge = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .surge,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(surge.contains("policy-path=https://airport.example/sub?token=secret"), surge)
        XCTAssertTrue(surge.contains("include-other-group=\"塔台订阅 1 · Airport\""), surge)
        XCTAssertTrue(surge.contains("local.example.com"), surge)
        XCTAssertFalse(surge.contains("remote.example.com"), surge)

        let loon = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .loon,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(loon.contains("[Remote Proxy]"), loon)
        XCTAssertTrue(loon.contains("塔台订阅 1 · Airport = https://airport.example/sub?token=secret"), loon)
        XCTAssertTrue(loon.contains("local.example.com"), loon)
        XCTAssertFalse(loon.contains("remote.example.com"), loon)

        let quanX = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .quanx,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(quanX.contains("[server_remote]"), quanX)
        XCTAssertTrue(quanX.contains("https://airport.example/sub?token=secret, tag=塔台订阅 1 · Airport"), quanX)
        XCTAssertTrue(quanX.contains("resource-tag-regex="), quanX)
        XCTAssertTrue(quanX.contains("local.example.com"), quanX)
        XCTAssertFalse(quanX.contains("remote.example.com"), quanX)

        let egern = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .egern,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(egern.contains("urls:\n        - \"https://airport.example/sub?token=secret\""), egern)
        XCTAssertTrue(egern.contains("update_interval: 86400"), egern)
        XCTAssertTrue(egern.contains("local.example.com"), egern)
        XCTAssertFalse(egern.contains("remote.example.com"), egern)
    }

    func testClashFamilyUsesDocumentedHeaderShapeForCustomUserAgent() {
        let fixture = makeFixture(userAgent: "Airport-UA")
        let generator = ConfigurationGenerator()

        let stash = generator.generate(
            nodes: fixture.nodes,
            preset: preset,
            target: .clash,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(stash.contains("headers:\n      User-Agent: \"Airport-UA\""), stash)

        for target in [ClientTarget.clashApple, .clashMi, .karing] {
            let content = generator.generate(
                nodes: fixture.nodes,
                preset: preset,
                target: target,
                remoteSubscriptions: [fixture.link]
            ).content
            XCTAssertTrue(
                content.contains("header:\n      User-Agent:\n        - \"Airport-UA\""),
                "\(target.name):\n\(content)"
            )
        }
    }

    func testImportedSchemePreservesDynamicRemoteNodeRegex() {
        let fixture = makeFixture()
        let scheme = RuleScheme(
            id: "remote-regex",
            name: "Remote Regex",
            summary: "",
            groups: [
                RuleSchemeGroup(
                    name: "Hong Kong",
                    kind: .urlTest,
                    members: [.nodePattern("(?i)香港|HK")]
                ),
            ],
            rulesets: [.init(groupName: "Hong Kong", resource: .inline("FINAL"))]
        )
        let generator = ConfigurationGenerator()

        let clash = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .clashApple,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(clash.contains("filter: \"(?:(?i)香港|HK)\""), clash)

        let surge = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .surge,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(surge.contains("policy-regex-filter=\"(?:(?i)香港|HK)\""), surge)

        let loon = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .loon,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(loon.contains("NameRegex,塔台订阅 1 · Airport,FilterKey = \"(?:(?i)香港|HK)\""), loon)

        let quanX = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .quanx,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(quanX.contains("server-tag-regex=(?:(?i)香港|HK)"), quanX)

        let egern = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .egern,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(egern.contains("filter: \"(?:(?i)香港|HK)\""), egern)
    }

    func testImportedSchemeKeepsExplicitRemoteNodeMembersThroughProviders() {
        let fixture = makeFixture()
        let remoteName = NodeRegionResolver.displayName(for: fixture.nodes[0])
        let escapedName = NSRegularExpression.escapedPattern(for: remoteName)
        let exactFilter = "^(?:\(escapedName))$"
        let scheme = RuleScheme(
            id: "remote-explicit-member",
            name: "Remote Explicit Member",
            summary: "",
            groups: [
                RuleSchemeGroup(
                    name: "Pinned Remote",
                    kind: .select,
                    members: [.reference(remoteName)]
                ),
            ],
            rulesets: [.init(groupName: "Pinned Remote", resource: .inline("FINAL"))]
        )
        let generator = ConfigurationGenerator()

        let clash = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .clashApple,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(clash.contains("use:\n      - \"tower-subscription-1\""), clash)
        XCTAssertTrue(clash.contains("filter: \"\(exactFilter)\""), clash)

        let surge = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .surge,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(surge.contains("policy-regex-filter=\"\(exactFilter)\""), surge)

        let loon = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .loon,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(loon.contains("NameRegex,塔台订阅 1 · Airport,FilterKey = \"\(exactFilter)\""), loon)

        let quanX = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .quanx,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(quanX.contains("server-tag-regex=\(exactFilter)"), quanX)

        let egern = generator.generate(
            nodes: fixture.nodes,
            scheme: scheme,
            target: .egern,
            remoteSubscriptions: [fixture.link]
        ).content
        XCTAssertTrue(egern.contains("filter: \"\(exactFilter)\""), egern)
    }

    func testUnsupportedProfilesNeverReceiveSubscriptionURL() {
        let fixture = makeFixture()
        let generator = ConfigurationGenerator()

        for target in [ClientTarget.shadowrocket, .hiddify, .singBox, .v2box] {
            let content = generator.generate(
                nodes: fixture.nodes,
                preset: preset,
                target: target,
                remoteSubscriptions: [fixture.link]
            ).content
            XCTAssertFalse(content.contains("airport.example/sub"), "\(target.name):\n\(content)")
        }
    }

    @MainActor
    func testPreferenceDefaultsOffAndPersistsOptIn() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-remote-subscriptions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)

        let model = AppModel(persistence: store, arguments: [])
        XCTAssertFalse(model.embedRemoteSubscriptionLinks)

        model.setEmbedRemoteSubscriptionLinks(true)

        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertTrue(reloaded.embedRemoteSubscriptionLinks)
    }

    @MainActor
    func testAppModelEmbedsOnlyEnabledHTTPSourceForCompatibleFullProfile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-remote-source-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let enabled = SubscriptionSource(
            name: "Enabled",
            urlString: "https://enabled.example/sub?token=private"
        )
        let disabled = SubscriptionSource(
            name: "Disabled",
            urlString: "https://disabled.example/sub?token=private",
            isEnabled: false
        )
        let unsupportedURL = SubscriptionSource(
            name: "Unsupported URL",
            urlString: "ftp://unsupported.example/sub"
        )
        let enabledNode = ProxyNode(
            sourceID: enabled.id,
            kind: .shadowsocks,
            name: "Enabled Remote",
            server: "enabled-node.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "enabled-password",
            rawURI: "ss://enabled"
        )
        let disabledNode = ProxyNode(
            sourceID: disabled.id,
            kind: .shadowsocks,
            name: "Disabled Inline",
            server: "disabled-node.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "disabled-password",
            rawURI: "ss://disabled"
        )
        let unsupportedURLNode = ProxyNode(
            sourceID: unsupportedURL.id,
            kind: .shadowsocks,
            name: "Unsupported URL Inline",
            server: "unsupported-url-node.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "unsupported-url-password",
            rawURI: "ss://unsupported-url"
        )
        let localNode = ProxyNode(
            kind: .shadowsocks,
            name: "Self Hosted",
            server: "local.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "local-password",
            rawURI: "ss://local"
        )
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [enabled, disabled, unsupportedURL],
            nodes: [enabledNode, disabledNode, unsupportedURLNode, localNode],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .clashApple
        ))
        let model = AppModel(persistence: store, arguments: [])
        model.setEmbedRemoteSubscriptionLinks(true)

        let clash = model.configuration(target: .clashApple).content
        XCTAssertTrue(clash.contains("https://enabled.example/sub?token=private"), clash)
        XCTAssertFalse(clash.contains("https://disabled.example/sub?token=private"), clash)
        XCTAssertFalse(clash.contains("enabled-node.example.com"), clash)
        XCTAssertFalse(clash.contains("disabled-node.example.com"), clash)
        XCTAssertTrue(clash.contains("unsupported-url-node.example.com"), clash)
        XCTAssertTrue(clash.contains("local.example.com"), clash)

        let singBox = model.configuration(target: .singBox).content
        XCTAssertFalse(singBox.contains("enabled.example/sub"), singBox)
        XCTAssertTrue(singBox.contains("enabled-node.example.com"), singBox)
        XCTAssertFalse(singBox.contains("disabled-node.example.com"), singBox)
        XCTAssertTrue(singBox.contains("unsupported-url-node.example.com"), singBox)
        XCTAssertTrue(singBox.contains("local.example.com"), singBox)
    }

    private func makeFixture(
        userAgent: String? = nil
    ) -> (nodes: [ProxyNode], link: RemoteSubscriptionLink) {
        let source = SubscriptionSource(
            name: "Airport",
            urlString: "https://airport.example/sub?token=secret",
            requestOptions: SubscriptionRequestOptions(userAgent: userAgent)
        )
        let remote = ProxyNode(
            sourceID: source.id,
            kind: .shadowsocks,
            name: "HK Remote",
            server: "remote.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "remote-password",
            rawURI: "ss://remote"
        )
        let local = ProxyNode(
            kind: .shadowsocks,
            name: "Local",
            server: "local.example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: "local-password",
            rawURI: "ss://local"
        )
        return ([remote, local], RemoteSubscriptionLink(source: source))
    }
}
