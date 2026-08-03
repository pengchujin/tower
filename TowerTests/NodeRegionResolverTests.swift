import XCTest
@testable import Tower

final class NodeRegionResolverTests: XCTestCase {
    func testRecognizesCommonAirportNodeNames() {
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "香港 · 高速 01"))?.code, "HK")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "日本 · 流媒体"))?.code, "JP")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "自建 · 新加坡"))?.code, "SG")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "🇺🇸 Los Angeles 02"))?.code, "US")
    }

    func testRecognizesAirportCodesAndDomainSuffixes() {
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "Premium HKG"))?.code, "HK")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "Premium", server: "edge.example.jp"))?.code, "JP")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "LHR-01"))?.code, "GB")
    }

    func testUnknownNodeRemainsUnlocated() {
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "Premium 01", server: "203.0.113.8")))
    }

    func testTrafficUnitDoesNotLookLikeGreatBritain() {
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "剩余流量：129.29 GB", server: "203.0.113.8")))
    }

    func testRestoresFlagWhenSubscriptionReplacesRegionalIndicatorsWithQuestionMarks() {
        let damagedName = node(name: "?? 香港 02")

        XCTAssertEqual(NodeRegionResolver.displayName(for: damagedName), "🇭🇰 香港 02")
    }

    func testExposesRecoveredFlagSeparatelyForCustomEmojiRendering() {
        let damagedName = node(name: "?? 台湾 02")

        let repaired = NodeRegionResolver.repairedName(for: damagedName)
        XCTAssertEqual(repaired?.region.code, "TW")
        XCTAssertEqual(repaired?.title, "台湾 02")
    }

    func testPreservesQuestionMarksWhenRegionCannotBeDetermined() {
        let unknown = node(name: "?? Premium 02", server: "203.0.113.8")

        XCTAssertEqual(NodeRegionResolver.displayName(for: unknown), "?? Premium 02")
    }

    func testTitleRemovesLeadingFlagWhenLogoCarriesTheRegion() {
        XCTAssertEqual(NodeRegionResolver.title(for: node(name: "🇨🇳 TW Cafe Latte")), "TW Cafe Latte")
        XCTAssertEqual(NodeRegionResolver.title(for: node(name: "?? 台湾 02")), "台湾 02")
        XCTAssertEqual(NodeRegionResolver.title(for: node(name: "Tokyo Premium")), "Tokyo Premium")
        XCTAssertEqual(NodeRegionResolver.title(for: node(name: "🇭🇰 HK  Lungo")), "HK Lungo")
    }

    func testClustersNodesByRegion() {
        let nodes = [
            node(name: "HK 01"),
            node(name: "香港 02"),
            node(name: "Tokyo 01"),
            node(name: "Unknown", server: "203.0.113.8")
        ]

        let clusters = NodeRegionResolver.clusters(for: nodes)
        XCTAssertEqual(clusters.first(where: { $0.region.code == "HK" })?.nodes.count, 2)
        XCTAssertEqual(clusters.first(where: { $0.region.code == "JP" })?.nodes.count, 1)
        XCTAssertEqual(NodeRegionResolver.unlocatedNodes(in: nodes).count, 1)
    }

    func testIPCountryOverridesMisleadingNodeNameWhenClustering() {
        let misleading = node(name: "Tokyo Premium", server: "198.51.100.8")
        let clusters = NodeRegionResolver.clusters(
            for: [misleading],
            countryCodes: [misleading.id: "US"]
        )

        XCTAssertNil(clusters.first(where: { $0.region.code == "JP" }))
        XCTAssertEqual(clusters.first?.region.code, "US")
        XCTAssertEqual(NodeRegionResolver.region(countryCode: " us ")?.name, "美国")
    }

    func testRecognizesISORegionNamesForFlagFallback() {
        let expectedCodes = [
            "Spain": "ES",
            "Israel": "IL",
            "South Africa": "ZA",
            "Chile": "CL",
            "Türkiye": "TR",
            "Argentina": "AR",
            "Austria": "AT",
            "Macao": "MO"
        ]

        for (name, expectedCode) in expectedCodes {
            XCTAssertEqual(
                NodeRegionResolver.countryCode(for: node(name: name)),
                expectedCode,
                name
            )
        }
    }

    func testISORegionFallbackRequiresWholeCountryName() {
        XCTAssertEqual(NodeRegionResolver.countryCode(for: node(name: "Romania Premium")), "RO")
    }

    private func node(name: String, server: String = "edge.example.com") -> ProxyNode {
        ProxyNode(
            kind: .shadowsocks,
            name: name,
            server: server,
            port: 443,
            password: "test",
            rawURI: "ss://test"
        )
    }
}
