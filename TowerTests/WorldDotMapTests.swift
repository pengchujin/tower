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

    func testProjectionPlacesKnownPoints() {
        // Longitude runs the full width; latitude is clamped to the drawn band.
        let greenwich = WorldDotGrid.unitPoint(latitude: 0, longitude: 0)
        XCTAssertEqual(greenwich.x, 0.5, accuracy: 0.001)

        let dateLineWest = WorldDotGrid.unitPoint(latitude: 0, longitude: -180)
        XCTAssertEqual(dateLineWest.x, 0, accuracy: 0.001)

        let dateLineEast = WorldDotGrid.unitPoint(latitude: 0, longitude: 180)
        XCTAssertEqual(dateLineEast.x, 1, accuracy: 0.001)
    }

    func testLatitudeIsClampedToTheDrawnBand() {
        // Antarctica is not drawn, so a point below the band must not fall off
        // the canvas.
        let southPole = WorldDotGrid.unitPoint(latitude: -90, longitude: 0)
        XCTAssertEqual(southPole.y, 1, accuracy: 0.001)

        let northPole = WorldDotGrid.unitPoint(latitude: 90, longitude: 0)
        XCTAssertEqual(northPole.y, 0, accuracy: 0.001)
    }

    func testNorthernPointsSitAboveSouthernOnes() {
        let tokyo = WorldDotGrid.unitPoint(latitude: 35.68, longitude: 139.65)
        let singapore = WorldDotGrid.unitPoint(latitude: 1.35, longitude: 103.82)
        let sydney = WorldDotGrid.unitPoint(latitude: -33.87, longitude: 151.21)

        XCTAssertLessThan(tokyo.y, singapore.y)
        XCTAssertLessThan(singapore.y, sydney.y)
        XCTAssertLessThan(singapore.x, tokyo.x)
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
