import XCTest
@testable import Tower

/// Answers like an online subconverter that lost the airport's quota header,
/// and like the airport itself when asked in Clash's dialect.
private actor ConverterQuotaFixtureLoader: SubscriptionHTTPDataLoading {
    private(set) var requestedURLs: [URL] = []

    func data(
        for request: URLRequest,
        dnsOverHTTPSURL: URL?
    ) async throws -> (Data, URLResponse) {
        let url = request.url!
        requestedURLs.append(url)
        let header: String
        let body: Data
        if url.host == "converter.example" {
            header = "upload=0; download=1; total=1;"
            let auth = Data("aes-256-gcm:secret".utf8).base64EncodedString()
            body = Data(Data("ss://\(auth)@hk.example.com:8388#Hong%20Kong".utf8).base64EncodedString().utf8)
        } else {
            header = "upload=100; download=200; total=53687091200; expire=1796610062"
            body = Data("not used".utf8)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["subscription-userinfo": header]
        )!
        return (body, response)
    }
}

final class ConverterQuotaTests: XCTestCase {
    private let converterLink = "https://converter.example/sub?target=clash&url=https%3A%2F%2Fairport.example%2Fsubscribe%3Ftoken%3Dabc&emoji=true"

    func testConverterPlaceholderHeaderIsNotAPlan() {
        XCTAssertNil(SubscriptionUsage.parse(header: "upload=0; download=1; total=1;"))
        XCTAssertNil(SubscriptionUsage.parse(header: "upload=0; download=1; total=1"))
        // A one-byte total with a real expiry still carries the expiry.
        XCTAssertNotNil(SubscriptionUsage.parse(header: "total=1; expire=1796610062"))
    }

    func testQuotaProbeTargetsTheAirportInsideAConverterLink() throws {
        let probe = try XCTUnwrap(SubscriptionService.quotaProbe(for: URL(string: converterLink)!))
        XCTAssertEqual(probe.host, "airport.example")
        let items = URLComponents(url: probe, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "token", value: "abc")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "flag", value: "clash")))
    }

    func testOrdinaryLinksAndMultiSourceConvertersKeepTheOldProbe() throws {
        let plain = try XCTUnwrap(SubscriptionService.quotaProbe(for: URL(string: "https://airport.example/sub?token=abc")!))
        XCTAssertEqual(plain.host, "airport.example")
        XCTAssertNil(SubscriptionService.convertedSubscriptionURL(in: URL(string: "https://airport.example/sub?url=https%3A%2F%2Fx.example")!))
        let multi = URL(string: "https://converter.example/sub?target=clash&url=https%3A%2F%2Fa.example%7Chttps%3A%2F%2Fb.example")!
        XCTAssertNil(SubscriptionService.convertedSubscriptionURL(in: multi))
    }

    func testConverterSubscriptionShowsTheAirportsQuota() async throws {
        let loader = ConverterQuotaFixtureLoader()
        let service = SubscriptionService(httpClient: loader)
        let result = try await service.fetch(SubscriptionSource(name: "t", urlString: converterLink))

        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.usage?.totalBytes, 53_687_091_200)
        XCTAssertEqual(result.usage?.usedBytes, 300)
        let hosts = await loader.requestedURLs.map(\.host)
        XCTAssertEqual(hosts, ["converter.example", "airport.example"])
    }
}
