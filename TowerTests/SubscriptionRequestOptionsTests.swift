import XCTest
@testable import Tower

private actor RequestConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func entered() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func exited() {
        active -= 1
    }
}

private struct HTTPSubscriptionFixtureLoader: SubscriptionHTTPDataLoading {
    var headerFields: [String: String] = ["Content-Type": "text/plain"]

    func data(
        for request: URLRequest,
        dnsOverHTTPSURL: URL?
    ) async throws -> (Data, URLResponse) {
        let auth = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        let node = "ss://\(auth)@hk.example.com:8388#Hong%20Kong"
        let body = Data(Data(node.utf8).base64EncodedString().utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (body, response)
    }
}

final class SubscriptionRequestOptionsTests: XCTestCase {
    func testOrdinarySubscriptionHTTPRequestsAreNotGloballySerialized() async throws {
        let gate = SubscriptionRequestGate()
        let probe = RequestConcurrencyProbe()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...4 {
                group.addTask {
                    await gate.acquire(needsExclusiveAccess: false)
                    await probe.entered()
                    try await Task.sleep(for: .milliseconds(50))
                    await probe.exited()
                    await gate.release(wasExclusiveAccess: false)
                }
            }
            try await group.waitForAll()
        }

        let maximumActive = await probe.maximumActive
        XCTAssertEqual(maximumActive, 4)
    }

    func testFetcherAcceptsHTTPSubscriptionURL() async throws {
        let source = SubscriptionSource(
            name: "HTTP Airport",
            urlString: "http://http-subscription.test/sub/private-token"
        )

        let result = try await SubscriptionService(
            httpClient: HTTPSubscriptionFixtureLoader()
        ).fetch(source)

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.nodes.first?.name, "Hong Kong")
    }

    func testFetcherReadsBase64ProviderProfileTitle() async throws {
        let encoded = Data("云帆官方".utf8).base64EncodedString()
        let source = SubscriptionSource(
            name: "example",
            urlString: "https://example.com/sub"
        )

        let result = try await SubscriptionService(
            httpClient: HTTPSubscriptionFixtureLoader(
                headerFields: ["Profile-Title": "base64:\(encoded)"]
            )
        ).fetch(source)

        XCTAssertEqual(result.suggestedName, "云帆官方")
    }

    func testCustomUserAgentIsAppliedToEverySubscriptionRequest() throws {
        let source = SubscriptionSource(
            name: "Custom",
            urlString: "https://example.com/sub",
            requestOptions: SubscriptionRequestOptions(userAgent: "ClashMeta/2.0")
        )
        let url = try XCTUnwrap(URL(string: source.urlString))

        let request = try SubscriptionRequestBuilder().make(url: url, source: source, timeout: 30)

        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "ClashMeta/2.0")
    }

    func testBlankUserAgentFallsBackToTowerDefault() throws {
        let source = SubscriptionSource(
            name: "Default",
            urlString: "https://example.com/sub",
            requestOptions: SubscriptionRequestOptions(userAgent: "  ")
        )
        let url = try XCTUnwrap(URL(string: source.urlString))

        let request = try SubscriptionRequestBuilder().make(url: url, source: source, timeout: 30)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            SubscriptionRequestBuilder.defaultUserAgent
        )
    }

    func testDNSOverrideAcceptsOnlyHTTPSDoHEndpoints() throws {
        let valid = SubscriptionRequestOptions(
            dnsOverHTTPSURL: "https://1.1.1.1/dns-query"
        )
        XCTAssertEqual(
            try valid.validatedDNSOverHTTPSURL()?.absoluteString,
            "https://1.1.1.1/dns-query"
        )

        let invalid = SubscriptionRequestOptions(dnsOverHTTPSURL: "udp://1.1.1.1:53")
        XCTAssertThrowsError(try invalid.validatedDNSOverHTTPSURL()) { error in
            guard case SubscriptionError.invalidDNSURL = error else {
                return XCTFail("错误类型不正确：\(error)")
            }
        }
    }

    func testRequestOptionsSurviveSnapshotEncoding() throws {
        let source = SubscriptionSource(
            name: "Custom",
            urlString: "https://example.com/sub",
            requestOptions: SubscriptionRequestOptions(
                userAgent: "Shadowrocket/1.0",
                dnsOverHTTPSURL: "https://dns.example/dns-query"
            )
        )

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SubscriptionSource.self, from: data)

        XCTAssertEqual(decoded.requestOptions, source.requestOptions)
    }
}
