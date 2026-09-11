import XCTest
@testable import Tower

final class ACL4SSRImportTests: XCTestCase {
    private let source = "https://github.com/ACL4SSR/ACL4SSR/blob/master/Clash/config/ACL4SSR.ini"
    private let paths = [
        "LocalAreaNetwork.list", "BanAD.list", "BanProgramAD.list", "GoogleCN.list",
        "Ruleset/SteamCN.list", "Microsoft.list", "Apple.list", "ProxyMedia.list",
        "Telegram.list", "ProxyLite.list", "ChinaDomain.list", "ChinaCompanyIp.list"
    ]

    private var configuration: String {
        "[custom]\n" + paths.enumerated().map { index, path in
            "ruleset=\(index == 1 || index == 2 ? "Block" : "Proxy"),rules/ACL4SSR/Clash/\(path)"
        }.joined(separator: "\n") + """

        ruleset=Proxy,[]GEOIP,CN
        ruleset=Proxy,[]FINAL
        custom_proxy_group=Proxy`select`[]DIRECT
        custom_proxy_group=Block`select`[]REJECT
        """
    }

    func testGitHubImportDownloadsAllTwelveListsAndExportsTheirRulesToEveryClient() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RuleDownloadStore(folderURL: directory)
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [ACLImportURLProtocol.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        let rawSource = RuleSchemeImportService.rawFileURL(for: URL(string: source)!)
        let urls = paths.map { URL(string: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/\($0)")! }
        var payloads = [rawSource: Data(configuration.utf8)]
        for (index, url) in urls.enumerated() {
            payloads[url] = Data("DOMAIN-SUFFIX,acl-test-\(index).example\n".utf8)
        }
        ACLImportURLProtocol.payloads = payloads
        let result = try await RuleSchemeImportService(store: store, session: session)
            .importScheme(from: source, name: "ACL test")
        XCTAssertEqual(result.failedRulesetCount, 0)
        XCTAssertEqual(result.scheme.rulesets.count, 14)
        XCTAssertEqual(result.scheme.remoteRulesetURLs, urls)
        for (index, url) in urls.enumerated() {
            XCTAssertEqual(store.lines(for: url), ["DOMAIN-SUFFIX,acl-test-\(index).example"])
        }
        let restored = try JSONDecoder().decode(RuleScheme.self, from: JSONEncoder().encode(result.scheme))
        let repository = RuleSchemeRepository(downloadStore: RuleDownloadStore(folderURL: directory))
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let generated = ConfigurationGenerator().generate(
                nodes: [], scheme: restored, target: target, schemes: repository, preferRuleSets: false
            )
            XCTAssertFalse(generated.hasInvalidPolicyReferences, target.rawValue)
            for index in paths.indices {
                XCTAssertTrue(generated.content.contains("acl-test-\(index).example"), "\(target): missing list \(index)")
            }
        }
    }

    func testACLPathsPreserveTheSourceRevisionAndSurviveEditing() throws {
        for sourceURL in [
            "https://github.com/ACL4SSR/ACL4SSR/blob/abc123/Clash/config/ACL4SSR.ini",
            "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/abc123/Clash/config/ACL4SSR.ini"
        ] {
            let scheme = try RuleSchemeParser().parse(text: configuration, id: "acl", name: "ACL", summary: "", sourceURLString: sourceURL)
            XCTAssertEqual(scheme.rulesets.count, 14)
            XCTAssertEqual(scheme.remoteRulesetURLs.first?.absoluteString,
                           "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/abc123/Clash/LocalAreaNetwork.list")
            let edited = try RuleSchemeTextEditorService().validatedScheme(from: configuration, replacing: scheme)
            XCTAssertEqual(edited.rulesets, scheme.rulesets)
        }
    }

    func testKnownACLPathsInPastedTemplatesUseTheOfficialRepository() throws {
        let scheme = try RuleSchemeParser().parse(text: configuration, id: "acl", name: "ACL", summary: "")
        XCTAssertEqual(scheme.remoteRulesetURLs.count, 12)
        XCTAssertEqual(scheme.remoteRulesetURLs.last?.absoluteString,
                       "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/ChinaCompanyIp.list")
    }

    func testUnresolvableRulePathsFailInsteadOfProducingAPartialScheme() {
        for path in ["rules/Other/list.list", "rules/ACL4SSR/Clash/../private.list",
                     "rules/ACL4SSR/Clash/%2e%2e/private.list", "rules/ACL4SSR/Clash/a.list?url=other",
                     "file:///tmp/rules.list"] {
            let text = "ruleset=Proxy,\(path)\nruleset=Proxy,[]FINAL\ncustom_proxy_group=Proxy`select`[]DIRECT"
            XCTAssertThrowsError(try RuleSchemeParser().parse(text: text, id: "acl", name: "ACL", summary: ""), path)
        }
    }

    func testExistingOnlineAndInlineReferencesRemainUnchanged() throws {
        let text = "ruleset=Proxy,https://rules.example.com/test.list\nruleset=Proxy,[]FINAL\ncustom_proxy_group=Proxy`select`[]DIRECT"
        let scheme = try RuleSchemeParser().parse(text: text, id: "acl", name: "ACL", summary: "", sourceURLString: source)
        XCTAssertEqual(scheme.rulesets.map(\.resource), [.remote(URL(string: "https://rules.example.com/test.list")!), .inline("FINAL")])
    }
}

private final class ACLImportURLProtocol: URLProtocol {
    nonisolated(unsafe) static var payloads: [URL: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let payload = Self.payloads[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
