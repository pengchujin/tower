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

    func testLoopbackServerServesGeneratedConfiguration() async throws {
        let configuration = GeneratedConfiguration(
            target: .surge,
            content: "# Tower loopback test\n[General]\nloglevel = notify\n",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0
        )
        let server = LocalConfigurationServer(configuration: configuration)
        let url = try await server.start()
        defer { server.stop() }

        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), configuration.content)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
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
        XCTAssertFalse(ClientTarget.hiddify.supportsDirectConfigurationImport)
    }
}
