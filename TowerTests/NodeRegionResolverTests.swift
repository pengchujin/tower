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

    func testMapPresentationBuildsClustersAndUnlocatedCountTogether() {
        let anonymous = node(name: "Premium", server: "198.51.100.8")
        let unknown = node(name: "Unknown", server: "203.0.113.8")
        let nodes = [node(name: "香港 01"), anonymous, unknown]

        let presentation = NodeMapPresentation(
            nodes: nodes,
            countryCodes: [anonymous.id: "US"]
        )

        XCTAssertEqual(Set(presentation.clusters.map(\.region.code)), ["HK", "US"])
        XCTAssertEqual(presentation.unlocatedCount, 1)
    }

    func testNodeNameOutranksTheIPDatabaseWhenClustering() {
        // The airport named the node; that is what the user reads and what the
        // policy group should agree with, even when the exit IP is elsewhere.
        let named = node(name: "Tokyo Premium", server: "198.51.100.8")
        let clusters = NodeRegionResolver.clusters(
            for: [named],
            countryCodes: [named.id: "US"]
        )

        XCTAssertEqual(clusters.first?.region.code, "JP")
        XCTAssertEqual(NodeRegionResolver.region(countryCode: " us ")?.name, "美国")
    }

    func testIPDatabaseAnswersForNamesThatSayNothing() {
        let anonymous = node(name: "Premium 07", server: "198.51.100.8")
        let clusters = NodeRegionResolver.clusters(
            for: [anonymous],
            countryCodes: [anonymous.id: "US"]
        )

        XCTAssertEqual(clusters.first?.region.code, "US")
    }

    func testCountriesOutsideTheCuratedListStillResolveAndCanBePlaced() {
        // Every country in the table carries a label point, so a Turkey node is
        // not just named — it can be drawn on the map like any other.
        for (name, expected) in ["Turkey | 01": "TR", "Johannesburg | 01": "ZA", "Poland 02": "PL"] {
            let region = NodeRegionResolver.region(for: node(name: name))
            XCTAssertEqual(region?.code, expected, name)
            XCTAssertNotNil(region?.coordinate, name)
        }
    }

    func testCountriesOutsideTheCuratedListAreIncludedInMapClusters() {
        let nodes = [
            node(name: "Spain"),
            node(name: "Austria"),
            node(name: "Türkiye")
        ]

        let clusterCodes = Set(NodeRegionResolver.clusters(for: nodes).map(\.region.code))

        XCTAssertTrue(clusterCodes.isSuperset(of: ["ES", "AT", "TR"]))
    }

    func testProtocolAbbreviationsAreNotReadAsCountries() {
        // SS is Shadowsocks, WS is WebSocket, GB is gigabytes.
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "SS 中转", server: "203.0.113.8")))
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "WS TLS 01", server: "203.0.113.8")))
        XCTAssertNil(NodeRegionResolver.region(for: node(name: "100 GB 套餐", server: "203.0.113.8")))
    }

    func testFlagPrefixDecidesTheCountryOutright() {
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "🇹🇷 01"))?.code, "TR")
        XCTAssertEqual(NodeRegionResolver.region(for: node(name: "🇿🇦 Node"))?.code, "ZA")
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
