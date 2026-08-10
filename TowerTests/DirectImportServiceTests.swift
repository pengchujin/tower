import XCTest
@testable import Tower

final class DirectImportServiceTests: XCTestCase {
    private let localURL = URL(string: "http://127.0.0.1:7788/private/tower.conf")!

    func testBuildsDocumentedClientSchemes() throws {
        let surge = try ClientImportURLBuilder.make(target: .surge, configurationURL: localURL)
        let clash = try ClientImportURLBuilder.make(target: .clash, configurationURL: localURL)
        let shadowrocket = try ClientImportURLBuilder.make(target: .shadowrocket, configurationURL: localURL)
        let loon = try ClientImportURLBuilder.make(target: .loon, configurationURL: localURL)

        XCTAssertEqual(surge.scheme, "surge")
        XCTAssertTrue(surge.absoluteString.hasPrefix("surge:///install-config?url="))
        XCTAssertTrue(clash.absoluteString.hasPrefix("clash://install-config?url="))
        XCTAssertTrue(clash.absoluteString.contains("name=%E5%A1%94%E5%8F%B0"))
        XCTAssertTrue(shadowrocket.absoluteString.hasPrefix("shadowrocket://config/add/http://127.0.0.1"))
        XCTAssertTrue(loon.absoluteString.hasPrefix("loon://import?sub=http%3A%2F%2F127.0.0.1"))
    }

    func testShadowrocketUsesDocumentedRawConfigurationURLPath() throws {
        let url = try ClientImportURLBuilder.make(
            target: .shadowrocket,
            configurationURL: localURL
        )

        XCTAssertEqual(
            url.absoluteString,
            "shadowrocket://config/add/http://127.0.0.1:7788/private/tower.conf"
        )
    }

    func testQuanXDoesNotPretendToSupportFullConfigurationScheme() {
        XCTAssertThrowsError(
            try ClientImportURLBuilder.make(target: .quanx, configurationURL: localURL)
        ) { error in
            XCTAssertEqual(error as? DirectImportError, .unsupportedTarget(.quanx))
        }
    }

    func testNodeOnlySchemesKeepExistingClientRules() throws {
        let shadowrocket = try ClientImportURLBuilder.make(
            target: .shadowrocket,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly
        )
        let loon = try ClientImportURLBuilder.make(
            target: .loon,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly
        )
        let quanx = try ClientImportURLBuilder.make(
            target: .quanx,
            configurationURL: localURL,
            displayName: "塔台节点",
            contentMode: .nodesOnly
        )
        let hiddify = try ClientImportURLBuilder.make(
            target: .hiddify,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly
        )

        XCTAssertTrue(shadowrocket.absoluteString.hasPrefix("shadowrocket://add/"))
        XCTAssertTrue(shadowrocket.absoluteString.hasSuffix("#%E5%A1%94%E5%8F%B0"))
        XCTAssertTrue(loon.absoluteString.hasPrefix("loon://import?nodelist=http%3A%2F%2F127.0.0.1"))
        XCTAssertTrue(quanx.absoluteString.hasPrefix("quantumult-x:///add-resource?remote-resource="))
        XCTAssertTrue(hiddify.absoluteString.hasPrefix("hiddify://import/http://127.0.0.1"))
        XCTAssertNil(hiddify.fragment, "Hiddify 的名称由 Profile-Title 响应头传递，URL 片段不能显示成百分号乱码")
    }

    func testLoonNodeImportUsesNamedRefreshableResourceURL() throws {
        let first = try ClientImportURLBuilder.make(
            target: .loon,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly,
            importRevision: "first"
        )
        let second = try ClientImportURLBuilder.make(
            target: .loon,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly,
            importRevision: "second"
        )

        XCTAssertNotEqual(first, second, "重复点击必须生成可重新添加的 Loon 资源地址")
        XCTAssertTrue(first.absoluteString.contains("tower-import%3Dfirst"), first.absoluteString)
    }

    func testQuanXOnlyOffersNodeResourceImportBecausePoliciesAreNotRemoteResources() throws {
        let nodes = try ClientImportURLBuilder.make(
            target: .quanx,
            configurationURL: localURL,
            displayName: "塔台",
            contentMode: .nodesOnly
        )
        let nodeJSON = try decodedQuanXResource(nodes)
        XCTAssertNotNil(nodeJSON["server_remote"])
        XCTAssertNil(nodeJSON["filter_remote"])
        XCTAssertTrue(nodeJSON["server_remote"]?.first?.contains("as-policy=static") == true)
        XCTAssertFalse(ClientTarget.quanx.supportedContentModes.contains(.rulesOnly))
        XCTAssertFalse(ClientTarget.quanx.supportsDirectImport(mode: .rulesOnly))
        XCTAssertThrowsError(
            try ClientImportURLBuilder.make(
                target: .quanx,
                configurationURL: localURL,
                contentMode: .rulesOnly
            )
        )
    }

    func testLoopbackServerServesGeneratedConfiguration() async throws {
        let configuration = GeneratedConfiguration(
            target: .surge,
            content: "# Tower loopback test\n[General]\nloglevel = notify\n",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0,
            profileName: "塔台"
        )
        let server = LocalConfigurationServer(configuration: configuration)
        let url = try await server.start()
        defer { server.stop() }

        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), configuration.content)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Profile-Title"),
            "base64:\(Data("塔台".utf8).base64EncodedString())"
        )
        XCTAssertTrue(
            (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?
                .contains("filename*=UTF-8''") == true
        )

        var refreshComponents = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        refreshComponents.queryItems = [URLQueryItem(name: "tower-import", value: "second-import")]
        let refreshURL = try XCTUnwrap(refreshComponents.url)
        let (refreshData, refreshResponse) = try await URLSession.shared.data(from: refreshURL)
        XCTAssertEqual((refreshResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: refreshData, as: UTF8.self), configuration.content)
    }

    func testOneTapImportKeepsTheSameProtectedLocalURLAcrossExports() throws {
        let suiteName = "tower-direct-import-token-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let token = DirectImportAccessTokenStore.loadOrCreate(defaults: defaults)
        XCTAssertEqual(DirectImportAccessTokenStore.loadOrCreate(defaults: defaults), token)

        let configuration = GeneratedConfiguration(
            target: .clash,
            content: "# stable import",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0
        )
        let first = LocalConfigurationServer(configuration: configuration, token: token)
        let second = LocalConfigurationServer(configuration: configuration, token: token)

        XCTAssertEqual(first.configurationURL, second.configurationURL)
        XCTAssertEqual(first.configurationURL.host, "127.0.0.1")
        XCTAssertEqual(first.configurationURL.port, 65_172)
        XCTAssertEqual(
            first.configurationURL.path,
            "/\(configuration.profileName)/\(token)/\(configuration.fileName)"
        )
    }
}

private extension DirectImportServiceTests {
    func decodedQuanXResource(_ url: URL) throws -> [String: [String]] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let encoded = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "remote-resource" })?.value)
        let data = try XCTUnwrap(encoded.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String]])
    }
}

/// Egern documents `egern:/profiles/new?name=&url=` — one slash, so the path
/// carries no authority component.
extension DirectImportServiceTests {
    func testEgernUsesItsDocumentedProfileScheme() throws {
        let localURL = URL(string: "http://127.0.0.1:8080/token/塔台-Egern.yaml")!

        let url = try ClientImportURLBuilder.make(target: .egern, configurationURL: localURL)

        XCTAssertEqual(url.scheme, "egern")
        XCTAssertNil(url.host, "egern:/… 没有 authority 段")
        XCTAssertEqual(url.path, "/profiles/new")
        let query = try XCTUnwrap(url.query)
        XCTAssertTrue(query.contains("url="), query)
        XCTAssertFalse(query.contains("127.0.0.1:8080/token"), "配置地址必须转义")
    }

    func testEgernIsOfferedAsOneTapImport() {
        XCTAssertTrue(ClientTarget.egern.supportsDirectConfigurationImport)
    }
}

/// Hiddify's parser bails on `!uri.hasAuthority`, so its link needs the two
/// slashes Egern's must not have. Both forms are pinned so neither gets
/// "corrected" into the other.
extension DirectImportServiceTests {
    func testHiddifyUsesCurrentUnifiedImportRoute() throws {
        let localURL = URL(string: "http://127.0.0.1:8080/token/塔台-Hiddify.json")!

        let url = try ClientImportURLBuilder.make(target: .hiddify, configurationURL: localURL)

        XCTAssertEqual(url.scheme, "hiddify")
        XCTAssertEqual(url.host, "import")
        XCTAssertTrue(url.path.contains("http://127.0.0.1:8080/token"), url.absoluteString)
    }

    func testEgernAndHiddifyUseTheirDocumentedRoutes() throws {
        let localURL = URL(string: "http://127.0.0.1:8080/token/c.yaml")!

        let egern = try ClientImportURLBuilder.make(target: .egern, configurationURL: localURL)
        let hiddify = try ClientImportURLBuilder.make(target: .hiddify, configurationURL: localURL)

        XCTAssertNil(egern.host)
        XCTAssertNotNil(hiddify.host)
    }

    func testOnlyQuantumultXStillLacksAScheme() {
        let withoutScheme = ClientTarget.allCases.filter { !$0.supportsDirectConfigurationImport }
        XCTAssertEqual(withoutScheme, [.quanx])
    }
}

/// The served file has to look like what the client expects. Hiddify was being
/// handed a sing-box JSON document named `tower.conf` as text/plain.
extension DirectImportServiceTests {
    func testServedFileMatchesTheTargetFormat() {
        let expected: [ClientTarget: String] = [
            .clash: "application/yaml",
            .egern: "application/yaml",
            .hiddify: "application/json",
            .surge: "text/plain"
        ]

        for (target, type) in expected {
            let configuration = GeneratedConfiguration(
                target: target, content: "x", supportedNodeCount: 1,
                skippedNodeCount: 0, ruleCount: 0
            )
            let server = LocalConfigurationServer(configuration: configuration)

            XCTAssertEqual(server.servedFileName, configuration.fileName, target.name)
            XCTAssertTrue(server.servedContentType.hasPrefix(type), "\(target.name): \(server.servedContentType)")
        }
    }
}
