import XCTest
@testable import Tower

/// Airports report plan usage two ways: a `subscription-userinfo` response
/// header, and plain sentences smuggled into the node list as fake entries.
final class SubscriptionUsageTests: XCTestCase {
    private let parser = SubscriptionParser()

    // MARK: - Header

    func testParsesFullHeader() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(header: "upload=100; download=200; total=1000; expire=1735660800")
        )

        XCTAssertEqual(usage.uploadBytes, 100)
        XCTAssertEqual(usage.downloadBytes, 200)
        XCTAssertEqual(usage.totalBytes, 1000)
        XCTAssertEqual(usage.usedBytes, 300)
        XCTAssertEqual(usage.remainingBytes, 700)
        XCTAssertEqual(usage.usedFraction ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(usage.expiresAt, Date(timeIntervalSince1970: 1_735_660_800))
    }

    func testPartialHeaderStillParses() throws {
        // Airports omit whatever they do not track.
        let usage = try XCTUnwrap(SubscriptionUsage.parse(header: "expire=1735660800"))

        XCTAssertNil(usage.totalBytes)
        XCTAssertNil(usage.usedBytes)
        XCTAssertNil(usage.usedFraction)
        XCTAssertNotNil(usage.expiresAt)
    }

    func testZeroExpiryMeansNeverRatherThan1970() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(header: "total=100; expire=0"))

        XCTAssertNil(usage.expiresAt)
        XCTAssertEqual(usage.totalBytes, 100)
    }

    func testFloatingPointByteCountsAreAccepted() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(header: "upload=1.0; download=2.0; total=3.0"))

        XCTAssertEqual(usage.usedBytes, 3)
    }

    func testUsedNeverExceedsTotalInTheFraction() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(header: "upload=900; download=900; total=1000"))

        XCTAssertEqual(usage.usedFraction, 1)
        XCTAssertEqual(usage.remainingBytes, 0)
    }

    func testGarbageHeaderYieldsNothing() {
        XCTAssertNil(SubscriptionUsage.parse(header: "hello world"))
        XCTAssertNil(SubscriptionUsage.parse(header: ""))
    }

    // MARK: - STATUS line

    func testParsesShadowrocketStyleStatusLine() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(
                statusLine: "STATUS=🚀↑:20.02GB,↓:97.73GB,TOT:220GB💡EXPIRES:2026-08-09"
            )
        )

        XCTAssertEqual(usage.uploadBytes, Int64(20.02 * 1_073_741_824))
        XCTAssertEqual(usage.downloadBytes, Int64(97.73 * 1_073_741_824))
        XCTAssertEqual(usage.totalBytes, 220 * 1_073_741_824)
        XCTAssertEqual(
            usage.expiresAt,
            DateComponents(calendar: .init(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                           year: 2026, month: 8, day: 9).date
        )
    }

    func testStatusLineUnitsOtherThanGigabytes() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(statusLine: "STATUS=↑:500MB,↓:1.5TB,TOT:2TB"))

        XCTAssertEqual(usage.uploadBytes, 500 * 1_048_576)
        XCTAssertEqual(usage.totalBytes, 2 * 1_099_511_627_776)
    }

    func testStatusLineWithoutExpiryStillParses() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(statusLine: "STATUS=🚀↑:1GB,↓:2GB,TOT:10GB"))

        XCTAssertNil(usage.expiresAt)
        XCTAssertEqual(usage.usedBytes, 3 * 1_073_741_824)
    }

    func testOrdinaryTextIsNotAStatusLine() {
        XCTAssertNil(SubscriptionUsage.parse(statusLine: "剩余流量：101.69 GB"))
        XCTAssertNil(SubscriptionUsage.parse(statusLine: "香港 IEPL 专线 1"))
    }

    func testStatusLineInTheNodeListIsQuotaNotAFailedNode() {
        let list = [
            "STATUS=🚀↑:20.02GB,↓:97.73GB,TOT:220GB💡EXPIRES:2026-08-09",
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#%E9%A6%99%E6%B8%AF%2001"
        ].joined(separator: "\n")

        let result = parser.parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.map(\.name), ["香港 01"])
        XCTAssertEqual(result.rejectedLineCount, 0, "STATUS 行不是解析失败")
        XCTAssertEqual(result.status?.totalBytes, 220 * 1_073_741_824)
    }

    // MARK: - Duplicate suppression

    func testNoticesRepeatingStructuredDataAreHidden() {
        let usage = SubscriptionUsage(
            totalBytes: 100,
            expiresAt: Date(timeIntervalSince1970: 1_735_660_800),
            notices: ["Traffic: 220GB", "套餐到期：2026-08-09", "官网：example.com"]
        )

        XCTAssertEqual(usage.distinctNotices, ["官网：example.com"])
    }

    func testNoticesSurviveWhenThereIsNoStructuredDataToRepeat() {
        let usage = SubscriptionUsage(notices: ["剩余流量：101.69 GB", "套餐到期：2026-08-09"])

        XCTAssertEqual(usage.distinctNotices, usage.notices)
    }

    func testResetCountdownSurvivesAnExpiryDate() {
        // The reset day and the expiry day are different facts.
        let usage = SubscriptionUsage(
            expiresAt: Date(timeIntervalSince1970: 1_735_660_800),
            notices: ["距离下次重置剩余：3 天"]
        )

        XCTAssertEqual(usage.distinctNotices, ["距离下次重置剩余：3 天"])
    }

    // MARK: - Notices in the node list

    func testAnnouncementEntriesBecomeNoticesNotNodes() {
        // The shape a real airport uses: quota rows are ss:// entries whose
        // only real content is the name.
        let list = [
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.4:8388#%E9%A6%99%E6%B8%AF%20IEPL%20%E4%B8%93%E7%BA%BF%201",
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.5:8388#%E5%89%A9%E4%BD%99%E6%B5%81%E9%87%8F%EF%BC%9A101.69%20GB",
            "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@1.2.3.6:8388#%E5%A5%97%E9%A4%90%E5%88%B0%E6%9C%9F%EF%BC%9A2026-08-09"
        ].joined(separator: "\n")

        let result = parser.parse(data: Data(list.utf8))

        XCTAssertEqual(result.nodes.map(\.name), ["香港 IEPL 专线 1"])
        XCTAssertEqual(result.notices, ["剩余流量：101.69 GB", "套餐到期：2026-08-09"])
        XCTAssertEqual(result.rejectedLineCount, 0, "公告不是解析失败")
    }

    func testOrdinaryNodeNamesAreNotMistakenForNotices() {
        for name in ["香港 IEPL 专线 1", "日本 01", "US West", "新加坡 BGP", "台湾 HiNet"] {
            XCTAssertFalse(SubscriptionParser.isNotice(name), name)
        }
    }

    func testAnnouncementNamesAreRecognised() {
        for name in [
            "剩余流量：101.69 GB",
            "距离下次重置剩余：3 天",
            "套餐到期：2026-08-09",
            "官网：example.com",
            "Traffic: 100GB"
        ] {
            XCTAssertTrue(SubscriptionParser.isNotice(name), name)
        }
    }

    func testAnnouncementsParkedOnAPublicResolverAreExcludedWhateverTheySay() {
        // One airport advertises its own client this way. The pitch matches no
        // keyword, but nothing real listens on 8.8.8.8:8.
        let yaml = """
        proxies:
          - {name: 香港 01, server: hk.example.com, port: 8388, type: ss, cipher: aes-128-gcm, password: pw}
          - {name: ！！！强烈推荐使用官方客户端！！！, server: 8.8.8.8, port: 8, type: ss, cipher: aes-128-gcm, password: pw}
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.map(\.name), ["香港 01"])
        XCTAssertEqual(result.notices, ["！！！强烈推荐使用官方客户端！！！"])
    }

    func testClashYAMLAnnouncementsAreAlsoExcluded() {
        let yaml = """
        proxies:
          - {name: 香港 01, server: hk.example.com, port: 8388, type: ss, cipher: aes-128-gcm, password: pw}
          - {name: 剩余流量：50 GB, server: 1.1.1.1, port: 1, type: ss, cipher: aes-128-gcm, password: pw}
        """

        let result = parser.parse(data: Data(yaml.utf8))

        XCTAssertEqual(result.nodes.map(\.name), ["香港 01"])
        XCTAssertEqual(result.notices, ["剩余流量：50 GB"])
    }

    // MARK: - Persistence

    func testUsageSurvivesEncoding() throws {
        let source = SubscriptionSource(
            name: "Airport",
            urlString: "https://example.com/sub",
            usage: SubscriptionUsage(
                uploadBytes: 1,
                downloadBytes: 2,
                totalBytes: 100,
                expiresAt: Date(timeIntervalSince1970: 1_735_660_800),
                notices: ["剩余流量：50 GB"]
            )
        )

        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(SubscriptionSource.self, from: data)

        XCTAssertEqual(restored.usage?.totalBytes, 100)
        XCTAssertEqual(restored.usage?.notices, ["剩余流量：50 GB"])
    }

    func testSourceSavedBeforeThisFeatureStillDecodes() throws {
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Old",
          "urlString": "https://example.com/sub",
          "isEnabled": true,
          "createdAt": 0
        }
        """

        let restored = try JSONDecoder().decode(SubscriptionSource.self, from: Data(legacy.utf8))

        XCTAssertNil(restored.usage)
    }
}
