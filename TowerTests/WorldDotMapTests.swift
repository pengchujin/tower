import XCTest
@testable import Tower

/// The home map is a flat dot grid rather than a MapKit globe. The grid ships
/// as a text bitmap, so the parse and the projection onto it are what can break.
final class WorldDotMapTests: XCTestCase {
    // MARK: - Parsing

    func testParsesGridWithHeaderAndComments() throws {
        let text = """
        # a comment
        # another
        size 4 2
        #..#
        .##.
        """

        let grid = try XCTUnwrap(WorldDotGrid.parse(text))

        XCTAssertEqual(grid.columns, 4)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertTrue(grid.isLand(column: 0, row: 0))
        XCTAssertFalse(grid.isLand(column: 1, row: 0))
        XCTAssertTrue(grid.isLand(column: 3, row: 0))
        XCTAssertTrue(grid.isLand(column: 1, row: 1))
    }

    func testOutOfBoundsIsWaterRatherThanACrash() throws {
        let grid = try XCTUnwrap(WorldDotGrid.parse("size 2 1\n##"))

        XCTAssertFalse(grid.isLand(column: -1, row: 0))
        XCTAssertFalse(grid.isLand(column: 2, row: 0))
        XCTAssertFalse(grid.isLand(column: 0, row: 5))
    }

    func testShortRowIsPaddedInsteadOfLosingTheGrid() throws {
        let grid = try XCTUnwrap(WorldDotGrid.parse("size 4 1\n##"))

        XCTAssertTrue(grid.isLand(column: 0, row: 0))
        XCTAssertFalse(grid.isLand(column: 3, row: 0))
    }

    func testMissingHeaderIsRejected() {
        XCTAssertNil(WorldDotGrid.parse("####\n####"))
    }

    // MARK: - Projection

    func testProjectionSpansTheCroppedLongitudeBand() {
        // The Pacific is cropped off both edges, so the band no longer runs the
        // full ±180.
        let west = WorldDotGrid.unitPoint(latitude: 0, longitude: WorldDotGrid.minimumLongitude)
        XCTAssertEqual(west.x, 0, accuracy: 0.001)

        let east = WorldDotGrid.unitPoint(latitude: 0, longitude: WorldDotGrid.maximumLongitude)
        XCTAssertEqual(east.x, 1, accuracy: 0.001)

        let middle = WorldDotGrid.unitPoint(
            latitude: 0,
            longitude: (WorldDotGrid.minimumLongitude + WorldDotGrid.maximumLongitude) / 2
        )
        XCTAssertEqual(middle.x, 0.5, accuracy: 0.001)
    }

    func testLongitudeOutsideTheBandIsClamped() {
        XCTAssertEqual(WorldDotGrid.unitPoint(latitude: 0, longitude: -180).x, 0, accuracy: 0.001)
        XCTAssertEqual(WorldDotGrid.unitPoint(latitude: 0, longitude: 180).x, 1, accuracy: 0.001)
    }

    func testEveryRegionLongitudeSitsInsideTheCroppedBand() throws {
        // Cropping must not push a region Tower knows onto the edge, which is
        // where a clamped coordinate would land.
        for code in ["US", "CA", "BR", "GB", "FR", "DE", "NL", "RU", "AE", "IN",
                     "TH", "SG", "MY", "VN", "HK", "PH", "TW", "JP", "KR", "AU"] {
            let region = try XCTUnwrap(NodeRegionResolver.region(countryCode: code), code)
            XCTAssertGreaterThan(region.longitude, WorldDotGrid.minimumLongitude, code)
            XCTAssertLessThan(region.longitude, WorldDotGrid.maximumLongitude, code)
        }
    }

    func testLatitudeIsClampedToTheDrawnBand() {
        // Antarctica is not drawn, so a point below the band must not fall off
        // the canvas.
        let southPole = WorldDotGrid.unitPoint(latitude: -90, longitude: 0)
        XCTAssertEqual(southPole.y, 1, accuracy: 0.001)

        let northPole = WorldDotGrid.unitPoint(latitude: 90, longitude: 0)
        XCTAssertEqual(northPole.y, 0, accuracy: 0.001)
    }

    func testMercatorStretchesTowardThePoles() {
        // Equal latitude steps map to growing vertical steps under mercator;
        // that is what makes the map taller than an equirectangular one.
        let equator = WorldDotGrid.unitPoint(latitude: 0, longitude: 0).y
        let mid = WorldDotGrid.unitPoint(latitude: 30, longitude: 0).y
        let high = WorldDotGrid.unitPoint(latitude: 60, longitude: 0).y

        XCTAssertGreaterThan(equator - mid, 0)
        XCTAssertGreaterThan(mid - high, equator - mid)
    }

    func testGridMatchesTheProjectionAspect() throws {
        let grid = WorldDotGrid.shared
        try XCTSkipIf(grid.isEmpty)

        // Cells must be square in mercator space, or the land looks squashed.
        let horizontal = (WorldDotGrid.maximumLongitude - WorldDotGrid.minimumLongitude) * .pi / 180
        let vertical = WorldDotGrid.mercatorY(WorldDotGrid.maximumLatitude)
            - WorldDotGrid.mercatorY(WorldDotGrid.minimumLatitude)
        let expectedRows = Double(grid.columns) * vertical / horizontal

        XCTAssertEqual(Double(grid.rows), expectedRows, accuracy: 1.5)
    }

    func testNorthernPointsSitAboveSouthernOnes() {
        let tokyo = WorldDotGrid.unitPoint(latitude: 35.68, longitude: 139.65)
        let singapore = WorldDotGrid.unitPoint(latitude: 1.35, longitude: 103.82)
        let sydney = WorldDotGrid.unitPoint(latitude: -33.87, longitude: 151.21)

        XCTAssertLessThan(tokyo.y, singapore.y)
        XCTAssertLessThan(singapore.y, sydney.y)
        XCTAssertLessThan(singapore.x, tokyo.x)
    }

    // MARK: - Label placement

    private func marker(
        _ id: String,
        title: String,
        latitude: Double,
        longitude: Double,
        weight: Int = 1,
        selected: Bool = false
    ) -> WorldDotMarker {
        WorldDotMarker(
            id: id,
            title: title,
            latitude: latitude,
            longitude: longitude,
            weight: weight,
            isSelected: selected
        )
    }

    private var layout: WorldDotMapView.Layout {
        WorldDotMapView.Layout(size: CGSize(width: 360, height: 160), grid: WorldDotGrid.shared)
    }

    func testWellSeparatedLabelsAreAllPlaced() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("US", title: "美国", latitude: 37, longitude: -95),
            marker("BR", title: "巴西", latitude: -23, longitude: -46),
            marker("AU", title: "澳大利亚", latitude: -33, longitude: 151)
        ]

        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: markers,
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 360, height: 160)
        )

        XCTAssertEqual(placements.count, 3)
    }

    /// The invariant that matters is that nothing overlaps — not that some
    /// particular number of labels was dropped. Fitting them all by moving one
    /// to the side is a better outcome, not a failure.
    func testCrowdedLabelsNeverOverlapEachOther() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        // East and Southeast Asia stack a dozen regions within a few degrees.
        let markers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 18),
            marker("TW", title: "台湾", latitude: 25.0, longitude: 121.6, weight: 12),
            marker("PH", title: "菲律宾", latitude: 14.6, longitude: 121.0, weight: 3),
            marker("VN", title: "越南", latitude: 10.8, longitude: 106.6, weight: 2),
            marker("MY", title: "马来西亚", latitude: 3.1, longitude: 101.7, weight: 1)
        ]

        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: markers,
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 360, height: 160)
        )

        let rects = markers.compactMap { marker -> (String, CGRect)? in
            guard let centre = placements[marker.id] else { return nil }
            let width = CGFloat(marker.title.count) * 10.5
            return (
                marker.title,
                CGRect(x: centre.x - width / 2, y: centre.y - 6.5, width: width, height: 13)
            )
        }

        for (index, first) in rects.enumerated() {
            for second in rects.dropFirst(index + 1) {
                XCTAssertFalse(
                    first.1.intersects(second.1),
                    "\(first.0) 与 \(second.0) 的标签重叠"
                )
            }
        }
        // The busiest region keeps its label whatever else is dropped.
        XCTAssertNotNil(placements["HK"])
    }

    func testSelectedMarkerAlwaysKeepsItsLabel() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 99),
            marker("TW", title: "台湾", latitude: 22.4, longitude: 114.3, weight: 1, selected: true)
        ]

        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: markers,
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 360, height: 160)
        )

        // The selection wins even against a much heavier neighbour.
        XCTAssertNotNil(placements["TW"])
    }

    // MARK: - Bundled resource

    func testBundledGridLoadsAndLooksLikeAWorld() {
        let grid = WorldDotGrid.shared

        XCTAssertFalse(grid.isEmpty, "点阵资源没有打进 bundle")
        XCTAssertGreaterThan(grid.columns, 100)
        XCTAssertGreaterThan(grid.rows, 40)

        let land = grid.land.filter { $0 }.count
        let total = grid.columns * grid.rows
        // Land covers roughly a third of the drawn band; a wildly different
        // ratio means the raster is wrong, not just different.
        XCTAssertGreaterThan(land, total / 6)
        XCTAssertLessThan(land, total / 2)
    }

    func testEveryRegionTowerKnowsFallsInsideTheGrid() throws {
        let grid = WorldDotGrid.shared
        try XCTSkipIf(grid.isEmpty)

        for code in ["HK", "JP", "US", "SG", "TW", "KR", "GB", "DE", "FR", "AU", "BR"] {
            let region = try XCTUnwrap(NodeRegionResolver.region(countryCode: code), code)
            let point = WorldDotGrid.unitPoint(
                latitude: region.latitude,
                longitude: region.longitude
            )
            XCTAssertTrue((0...1).contains(point.x), "\(code) 超出横向范围")
            XCTAssertTrue((0...1).contains(point.y), "\(code) 超出纵向范围")
        }
    }
}
