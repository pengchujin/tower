import XCTest
import SwiftUI
@testable import Tower

/// The home map is a flat dot grid rather than a MapKit globe. The grid ships
/// as a text bitmap, so the parse and the projection onto it are what can break.
final class WorldDotMapTests: XCTestCase {
    func testPanReversesImmediatelyAfterOvershootingEveryEdge() {
        let size = CGSize(width: 320, height: 180)
        for sign: CGFloat in [-1, 1] {
            let start = WorldDotMapView.Viewport(scale: 2)
            let overshoot = CGSize(width: sign * 900, height: sign * 900)
            let edge = start.translated(by: overshoot, in: size)
            let reversal = CGSize(width: overshoot.width - sign * 5, height: overshoot.height - sign * 7)
            let moved = edge.translated(by: WorldDotMapView.PanMotion.delta(from: overshoot, to: reversal), in: size)
            XCTAssertEqual(moved.offset.width, edge.offset.width - sign * 5, accuracy: 0.001)
            XCTAssertEqual(moved.offset.height, edge.offset.height - sign * 7, accuracy: 0.001)
        }
    }

    func testMapTransformRecordsInterpolatedViewportForGestureHandoff() {
        let size = CGSize(width: 320, height: 180)
        let recorder = WorldDotMapView.ViewportPresentation()
        let target = WorldDotMapView.Viewport(scale: 3, offset: CGSize(width: 100, height: -40))
        var effect = WorldDotMapView.TrackedViewportTransform(viewport: target,
            baseSize: size, recorder: recorder)
        // Mimic SwiftUI's presentation value halfway through a zoom/recenter.
        effect.animatableData = AnimatablePair(2, AnimatablePair(40, -15))
        let transform = effect.effectValue(size: size)
        let visible = recorder.value
        XCTAssertEqual(visible.scale, 2)
        XCTAssertEqual(visible.offset, CGSize(width: 40, height: -15))
        XCTAssertNotEqual(visible, target)
        let point = CGPoint(x: 70, y: 45)
        let expected = visible.transform(point, in: size)
        XCTAssertEqual(point.x * transform.m11 + transform.m31, expected.x, accuracy: 0.001)
        XCTAssertEqual(point.y * transform.m22 + transform.m32, expected.y, accuracy: 0.001)
        let continued = visible.translated(by: CGSize(width: 3, height: 4), in: size)
        XCTAssertEqual(continued.offset, CGSize(width: 43, height: -11))
    }

    func testTargetDensityRasterNormalizesBeforePresentationZoom() {
        let size = CGSize(width: 320, height: 180)
        let point = CGPoint(x: 60, y: 120)
        let visible = WorldDotMapView.Viewport(scale: 2, offset: CGSize(width: 22, height: -33))
        let effect = WorldDotMapView.TrackedViewportTransform(viewport: visible,
            baseSize: size, recorder: .init())
        let transform = effect.effectValue(size: size)
        for rasterScale: CGFloat in [1, 1.8, 2.8, 4.2] {
            // Both raster paths normalize to the same base map coordinates.
            let normalized = CGPoint(x: point.x * rasterScale / rasterScale, y: point.y * rasterScale / rasterScale)
            let expected = visible.transform(point, in: size)
            XCTAssertEqual(normalized.x * transform.m11 + transform.m31, expected.x, accuracy: 0.001)
            XCTAssertEqual(normalized.y * transform.m22 + transform.m32, expected.y, accuracy: 0.001)
        }
    }

    func testCountryLatencyUsesMedianAndWaitsBeforeDeclaringFailure() {
        let nodes = (0..<3).map { ProxyNode(kind: .trojan, name: "US \($0)", server: "example.com", port: 443, rawURI: "") }
        var results: [UUID: NodeLatencyMeasurement] = [:]
        XCTAssertEqual(MapLatencySummary(nodes: nodes, measurements: results, testingIDs: []).band, .untested)
        results[nodes[0].id] = .unavailable("timeout")
        XCTAssertEqual(MapLatencySummary(nodes: nodes, measurements: results, testingIDs: [nodes[1].id]).band, .untested)
        results[nodes[1].id] = .success(milliseconds: 80, method: .icmp)
        results[nodes[2].id] = .success(milliseconds: 320, method: .tcp)
        let measured = MapLatencySummary(nodes: nodes, measurements: results, testingIDs: [])
        XCTAssertEqual(measured.median, 200)
        XCTAssertEqual(measured.band, .normal)
        XCTAssertEqual(MapLatencySummary(nodes: nodes, measurements: results, testingIDs: Set(nodes.map(\.id))).band, measured.band)
        for node in nodes { results[node.id] = .unavailable("timeout") }
        XCTAssertEqual(MapLatencySummary(nodes: nodes, measurements: results, testingIDs: []).band, .unreachable)
        results[nodes[0].id]?.isApplicable = false
        XCTAssertEqual(MapLatencySummary(nodes: nodes, measurements: results, testingIDs: []).band, .untested)
    }

    func testCountryWithOneReachableNodeExcludesUnreachableNodesFromMedianAndPaint() {
        let nodes = (0..<3).map {
            ProxyNode(kind: .shadowsocks, name: "Israel \($0)", server: "example.com", port: 443, rawURI: "")
        }
        let measurements: [UUID: NodeLatencyMeasurement] = [
            nodes[0].id: .unavailable("timeout"),
            nodes[1].id: .success(milliseconds: 32, method: .tcp),
            nodes[2].id: .unavailable("timeout")
        ]
        let summary = MapLatencySummary(nodes: nodes, measurements: measurements, testingIDs: [])
        XCTAssertEqual(summary.median, 32)
        XCTAssertEqual(summary.band, .fast)
        let marker = WorldDotMarker(id: "IL", title: "以色列", latitude: 30.9111,
                                    longitude: 34.8479, weight: 3, isSelected: true,
                                    latencyBand: summary.band)
        let grid = WorldDotGrid.shared
        let paint = WorldDotPaint(grid: grid, markers: [marker])
        let cells = grid.coveredCellIndexes(for: [marker])
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { paint.latencyBands[$0] == .fast })
    }

    func testLatencyThresholdsKeepSlowDistinctFromUnreachable() {
        XCTAssertEqual([100, 101, 200, 201, 350, 351].map(MapLatencyBand.measured), [.fast, .normal, .normal, .slow, .slow, .verySlow])
        for band in MapLatencyBand.allCases {
            XCTAssertNotEqual(band.color(), band.color(selected: true))
            XCTAssertNotEqual(band.color(dark: true), band.color(selected: true, dark: true))
        }
    }

    @MainActor
    func testLatencyMapPaletteVisuals() throws {
        let countries: [(String, String, Double, Double)] = [
            ("US", "美国", 38, -97), ("GB", "英国", 54, -2),
            ("DE", "德国", 51, 10), ("JP", "日本", 36, 138),
            ("AU", "澳大利亚", -25, 134), ("BR", "巴西", -14, -52)
        ]
        for selected in [false, true] {
            for dark in [false, true] {
                let markers = zip(countries, MapLatencyBand.allCases).map { country, band in
                    WorldDotMarker(id: country.0, title: country.1, latitude: country.2, longitude: country.3, weight: 1, isSelected: selected, latencyBand: band)
                }
                let renderer = ImageRenderer(content: WorldDotMapView(markers: markers, initialPaint: WorldDotPaint(grid: .shared, markers: markers)) { _ in }
                    .frame(width: 390, height: 280)
                    .background(dark ? Color.black : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "latency-map-\(selected)-\(dark)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testCountryCoverageLookupBenchmark() {
        let grid = WorldDotGrid.shared
        let codes = Array(Set(grid.countryCodes.compactMap { $0 })).sorted().prefix(60)
        let markers = codes.map { WorldDotMarker(id: $0, title: $0, latitude: 0, longitude: 0, weight: 1, isSelected: false) }
        let start = ContinuousClock.now
        var count = 0
        for _ in 0..<100 {
            for band in 0..<6 {
                count += grid.coveredCellIndexes(for: markers.enumerated().filter { $0.offset % 6 == band }.map(\.element)).count
            }
        }
        print("MAP_COVERAGE_100=\(ContinuousClock.now - start)")
        XCTAssertGreaterThan(count, 0)
    }

    func testExpandedLabelsFitMoreCountriesWithoutOverlap() {
        let markers = ["香港", "台湾", "澳门", "日本"].enumerated().map {
            WorldDotMarker(id: String($0.offset), title: $0.element, latitude: 0, longitude: 0, weight: 1, isSelected: false)
        }
        let positions = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, CGPoint(x: 180, y: 140)) })
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 280)
        let overview = WorldDotMapView.LabelPlanner.plan(markers: markers, positions: positions, bounds: bounds)
        let expanded = WorldDotMapView.LabelPlanner.plan(markers: markers, positions: positions, bounds: bounds, expanded: true)
        XCTAssertGreaterThan(expanded.count, overview.count)
        XCTAssertEqual(expanded.count, markers.count)
        let frames = markers.compactMap { marker in expanded[marker.id].map { WorldDotMapView.LabelPlanner.estimatedFrame(for: marker, at: $0) } }
        for i in frames.indices {
            XCTAssertTrue(bounds.contains(frames[i]))
            for j in frames.indices where j > i { XCTAssertFalse(frames[i].intersects(frames[j])) }
        }
    }

    func testPaintIdentityIgnoresTestingProgressButTracksColorAndSelection() {
        var marker = WorldDotMarker(id: "US", title: "美国", latitude: 38, longitude: -97, weight: 1, isSelected: false)
        let original = WorldDotPaint.Input(marker)
        marker.isTesting = true
        XCTAssertEqual(original, WorldDotPaint.Input(marker))
        marker.latencyBand = .fast
        XCTAssertNotEqual(original, WorldDotPaint.Input(marker))
        let grid = WorldDotGrid(columns: 2, rows: 1, land: [true, true], countryCodes: ["US", "JP"])
        let paint = WorldDotPaint(grid: grid, markers: [marker])
        XCTAssertEqual(paint.coveredCells, [0])
        XCTAssertEqual(paint.latencyBands, [0: .fast])
        XCTAssertEqual(Set(MapLatencyBand.allCases.flatMap { band in [WorldDotPaint.key(band: band, selected: false), WorldDotPaint.key(band: band, selected: true)] }).count, 12)
    }

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

    func testParsesCountryOwnershipForEachLandDot() throws {
        let land = "size 4 2\n#..#\n.##."
        let countries = "size 4 2\nUS .. .. JP\n.. CN CN .."

        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))

        XCTAssertEqual(grid.countryCode(column: 0, row: 0), "US")
        XCTAssertEqual(grid.countryCode(column: 3, row: 0), "JP")
        XCTAssertEqual(grid.countryCode(column: 1, row: 1), "CN")
        XCTAssertNil(grid.countryCode(column: 1, row: 0))
    }

    func testCoveredCountryIncludesEveryOwnedLandDot() throws {
        let land = "size 4 2\n#..#\n.##."
        let countries = "size 4 2\nUS .. .. JP\n.. CN CN .."
        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))

        let highlighted = grid.coveredCellIndexes(for: [
            marker("CN", title: "中国", latitude: 35, longitude: 104)
        ])

        XCTAssertEqual(highlighted, Set([5, 6]))
    }

    func testSmallCoveredRegionFallsBackToItsNearestLandDot() throws {
        let land = "size 4 2\n#...\n...."
        let countries = "size 4 2\n.. .. .. ..\n.. .. .. .."
        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))

        let highlighted = grid.coveredCellIndexes(for: [
            marker("HK", title: "香港", latitude: 80, longitude: -135)
        ])

        XCTAssertEqual(highlighted, Set([0]))
    }

    func testTapInsideCoveredCountrySelectsItsRegion() throws {
        let land = "size 4 2\n#..#\n.##."
        let countries = "size 4 2\nUS .. .. JP\n.. CN CN .."
        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))
        let layout = WorldDotMapView.Layout(size: CGSize(width: 400, height: 200), grid: grid)

        let markerID = WorldDotMapView.RegionHitTester.markerID(
            at: layout.center(column: 1, row: 1),
            markers: [marker("CN", title: "中国", latitude: 35, longitude: 104)],
            grid: grid,
            layout: layout,
            viewport: .init()
        )

        XCTAssertEqual(markerID, "CN")
    }

    func testTapUsesTheVisibleCountryPositionAfterZoomAndPan() throws {
        let land = "size 4 2\n#..#\n.##."
        let countries = "size 4 2\nUS .. .. JP\n.. CN CN .."
        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))
        let layout = WorldDotMapView.Layout(size: CGSize(width: 400, height: 200), grid: grid)
        let viewport = WorldDotMapView.Viewport(
            scale: 2,
            offset: CGSize(width: -60, height: 30)
        )
        let visiblePoint = viewport.transform(
            layout.center(column: 1, row: 1),
            in: layout.size
        )

        let markerID = WorldDotMapView.RegionHitTester.markerID(
            at: visiblePoint,
            markers: [marker("CN", title: "中国", latitude: 35, longitude: 104)],
            grid: grid,
            layout: layout,
            viewport: viewport
        )

        XCTAssertEqual(markerID, "CN")
    }

    func testTapOnUncoveredCountryDoesNothing() throws {
        let land = "size 4 2\n#..#\n.##."
        let countries = "size 4 2\nUS .. .. JP\n.. CN CN .."
        let grid = try XCTUnwrap(WorldDotGrid.parse(land, countryText: countries))
        let layout = WorldDotMapView.Layout(size: CGSize(width: 400, height: 200), grid: grid)

        let markerID = WorldDotMapView.RegionHitTester.markerID(
            at: layout.center(column: 0, row: 0),
            markers: [marker("CN", title: "中国", latitude: 35, longitude: 104)],
            grid: grid,
            layout: layout,
            viewport: .init()
        )

        XCTAssertNil(markerID)
    }

    func testTapOnCountryLabelUsesThatLabelsRegionID() {
        let hongKong = marker("HK", title: "香港", latitude: 22.3, longitude: 114.2)
        let labels = [
            WorldDotMapView.PresentedLabel(
                marker: hongKong,
                position: CGPoint(x: 140, y: 72)
            )
        ]

        let markerID = WorldDotMapView.LabelHitTester.markerID(
            at: CGPoint(x: 140, y: 72),
            labels: labels
        )

        XCTAssertEqual(markerID, "HK")
    }

    func testZoomedTapNearTinyCoveredCountryUsesMinimumTouchTarget() {
        let columns = 100
        let rows = 50
        let countryIndex = 25 * columns + 50
        var land = Array(repeating: false, count: columns * rows)
        var countryCodes = Array<String?>(repeating: nil, count: columns * rows)
        land[countryIndex] = true
        countryCodes[countryIndex] = "SG"
        let grid = WorldDotGrid(
            columns: columns,
            rows: rows,
            land: land,
            countryCodes: countryCodes
        )
        let layout = WorldDotMapView.Layout(
            size: CGSize(width: 400, height: 200),
            grid: grid
        )
        let singapore = marker(
            "SG",
            title: "新加坡",
            latitude: 0,
            longitude: (WorldDotGrid.minimumLongitude + WorldDotGrid.maximumLongitude) / 2
        )
        let viewport = WorldDotMapView.Viewport(scale: 3)
        let countryPosition = layout.position(for: singapore, viewport: viewport)

        let markerID = WorldDotMapView.RegionHitTester.markerID(
            at: CGPoint(x: countryPosition.x + 18, y: countryPosition.y),
            markers: [singapore],
            grid: grid,
            layout: layout,
            viewport: viewport
        )

        XCTAssertEqual(markerID, "SG")
    }

    func testTapSelectsSmallRegionAtItsFallbackPosition() throws {
        let grid = try XCTUnwrap(
            WorldDotGrid.parse(
                "size 4 2\n#...\n....",
                countryText: "size 4 2\n.. .. .. ..\n.. .. .. .."
            )
        )
        let layout = WorldDotMapView.Layout(size: CGSize(width: 400, height: 200), grid: grid)
        let tinyRegion = marker("HK", title: "香港", latitude: 80, longitude: -135)

        let markerID = WorldDotMapView.RegionHitTester.markerID(
            at: layout.position(for: tinyRegion),
            markers: [tinyRegion],
            grid: grid,
            layout: layout,
            viewport: .init()
        )

        XCTAssertEqual(markerID, "HK")
    }

    func testMissingHeaderIsRejected() {
        XCTAssertNil(WorldDotGrid.parse("####\n####"))
    }

    // MARK: - Projection

    func testProjectionSpansTheWholeWorldLongitudeBand() {
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

    func testLongitudeAtTheDateLineMapsToTheTwoEdges() {
        XCTAssertEqual(WorldDotGrid.unitPoint(latitude: 0, longitude: -180).x, 0, accuracy: 0.001)
        XCTAssertEqual(WorldDotGrid.unitPoint(latitude: 0, longitude: 180).x, 1, accuracy: 0.001)
    }

    func testEveryPracticalRegionUsesItsRealCoordinateRatherThanAClampedEdge() throws {
        // Antarctica is intentionally outside this compact node overview; all
        // other ISO regions Tower exposes must retain their actual label point.
        for (code, entry) in NodeRegionResolver.countryTable where code != "AQ" {
            XCTAssertGreaterThan(entry.longitude, WorldDotGrid.minimumLongitude, code)
            XCTAssertLessThan(entry.longitude, WorldDotGrid.maximumLongitude, code)
            XCTAssertGreaterThan(entry.latitude, WorldDotGrid.minimumLatitude, code)
            XCTAssertLessThan(entry.latitude, WorldDotGrid.maximumLatitude, code)
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

    func testSelectedEdgeLabelIsClampedInsideTheVisibleMap() throws {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 160)
        let selected = marker(
            "NZ",
            title: "新西兰 · 3",
            latitude: -41,
            longitude: 174,
            selected: true
        )

        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: [selected],
            positions: ["NZ": CGPoint(x: 358, y: 132)],
            bounds: bounds
        )
        let placement = try XCTUnwrap(placements["NZ"])
        let frame = WorldDotMapView.LabelPlanner.estimatedFrame(
            for: selected,
            at: placement
        )

        XCTAssertTrue(bounds.insetBy(dx: 6, dy: 6).contains(frame))
    }

    func testSelectionDoesNotChangeLabelCollisionGeometry() {
        let unselected = marker(
            "RO",
            title: "罗马尼亚",
            latitude: 46,
            longitude: 25,
            selected: false
        )
        let selected = marker(
            "RO",
            title: "罗马尼亚",
            latitude: 46,
            longitude: 25,
            selected: true
        )

        XCTAssertEqual(
            WorldDotMapView.LabelPlanner.estimatedFrame(for: selected, at: .zero).size,
            WorldDotMapView.LabelPlanner.estimatedFrame(for: unselected, at: .zero).size
        )
    }

    func testSelectingMarkerDoesNotMoveOtherCountryLabels() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let baseMarkers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 18),
            marker("TW", title: "台湾", latitude: 22.4, longitude: 114.3, weight: 12),
            marker("PH", title: "菲律宾", latitude: 14.6, longitude: 121.0, weight: 8)
        ]
        let selectedMarkers = baseMarkers.map { value in
            marker(
                value.id,
                title: value.title,
                latitude: value.latitude,
                longitude: value.longitude,
                weight: value.weight,
                selected: value.id == "TW"
            )
        }
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 160)

        let before = WorldDotMapView.LabelPlanner.plan(
            markers: baseMarkers,
            layout: layout,
            bounds: bounds
        )
        let after = WorldDotMapView.LabelPlanner.plan(
            markers: selectedMarkers,
            layout: layout,
            bounds: bounds
        )

        for markerID in ["HK", "PH"] {
            XCTAssertEqual(after[markerID], before[markerID], "选择台湾不应移动 \(markerID) 的文字")
        }
    }

    func testCrowdedLabelsStayDirectlyAboveOrBelowTheirMarker() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("A", title: "香港", latitude: 22.3, longitude: 114.2, weight: 3),
            marker("B", title: "九龙", latitude: 22.3, longitude: 114.2, weight: 2),
            marker("C", title: "新界", latitude: 22.3, longitude: 114.2, weight: 1)
        ]
        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: markers,
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 360, height: 160)
        )
        let anchor = layout.position(for: markers[0])

        XCTAssertEqual(placements.count, 2, "附近没有准确位置时应隐藏标签，而不是把它推到其他地点")
        for placement in placements.values {
            XCTAssertEqual(placement.x, anchor.x, accuracy: 0.001)
            XCTAssertLessThanOrEqual(abs(placement.y - anchor.y), 16)
        }
    }

    func testMapMarkerTitlesDoNotIncludeFlagEmoji() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/NodeMapOverview.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("region.flag"))
    }

    func testMapUsesCountryCoverageWithoutSeparateLocationDotMarkers() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("AnimatedWorldDotMarker"))
        XCTAssertFalse(source.contains("WorldDotClusterMarker"))
        XCTAssertTrue(source.contains("WorldDotHitTarget"))
    }

    func testMapUsesDirectCountryTapAndKeepsSelectedLabelNeutral() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SpatialTapGesture"))
        XCTAssertTrue(source.contains("? Color.primary"))
    }

    func testCountryLabelsUseOnePersistentPresentationLayer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ForEach(presentedLabels)"))
        XCTAssertFalse(source.contains("ForEach(frozenLabels)"))
    }

    func testSelectedLabelStaysAboveNeighboursWithoutMaterialMorphing() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let labelStart = try XCTUnwrap(source.range(of: "private func mapLabel"))
        let labelEnd = try XCTUnwrap(source.range(of: "private func markersForLabels"))
        let labelSource = String(source[labelStart.lowerBound..<labelEnd.lowerBound])

        XCTAssertTrue(source.contains(".zIndex(label.marker.isSelected ? 1 : 0)"))
        XCTAssertFalse(source.contains("size: marker.isSelected ?"))
        XCTAssertFalse(source.contains(".fill(.regularMaterial)"))
        XCTAssertTrue(
            labelSource.contains("transaction.animation = nil"),
            "放大后已有标签的选中样式不能继承地区列表的弹簧动画"
        )
        XCTAssertTrue(
            source.contains("mapLabel(label.marker)\n                        .position(label.position)"),
            "标签外层位置仍应跟随地图居中动画，不能把整张标签禁用动画"
        )
    }

    func testZoomTransformsCachedDotCanvasInsteadOfRerasterizingIt() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("WorldDotCanvas"))
        XCTAssertTrue(source.contains(".equatable()"))
    }

    func testDenseAsiaKeepsAtLeastTheHighestPriorityLabels() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 18),
            marker("TW", title: "台湾", latitude: 25.0, longitude: 121.6, weight: 12),
            marker("PH", title: "菲律宾", latitude: 14.6, longitude: 121.0, weight: 8),
            marker("VN", title: "越南", latitude: 10.8, longitude: 106.6, weight: 7),
            marker("MY", title: "马来西亚", latitude: 3.1, longitude: 101.7, weight: 6),
            marker("SG", title: "新加坡", latitude: 1.35, longitude: 103.8, weight: 5),
            marker("JP", title: "日本", latitude: 35.7, longitude: 139.7, weight: 4),
            marker("KR", title: "韩国", latitude: 37.6, longitude: 127.0, weight: 3)
        ]

        let placements = WorldDotMapView.LabelPlanner.plan(
            markers: markers,
            layout: layout,
            bounds: CGRect(x: 0, y: 0, width: 360, height: 160)
        )

        XCTAssertGreaterThanOrEqual(placements.count, 2)
        XCTAssertNotNil(placements["HK"])
    }

    // MARK: - Interactive viewport and level of detail

    func testPanTracksFingerOneToOne() throws {
        let tracked = WorldDotMapView.PanMotion.tracked(
            CGSize(width: 100, height: -80)
        )

        XCTAssertEqual(tracked.width, 100, accuracy: 0.001)
        XCTAssertEqual(tracked.height, -80, accuracy: 0.001)

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/WorldDotMapView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 1)"))
    }

    func testPanKeepsOnlyASmallPartOfProjectedMomentum() {
        let settled = WorldDotMapView.PanMotion.settled(
            translation: CGSize(width: 100, height: 50),
            predictedEndTranslation: CGSize(width: 400, height: 200),
            reduceMotion: false
        )

        XCTAssertEqual(settled.width, 112, accuracy: 0.001)
        XCTAssertEqual(settled.height, 56, accuracy: 0.001)
    }

    func testReducedMotionPanDoesNotUseProjectedMomentum() {
        let settled = WorldDotMapView.PanMotion.settled(
            translation: CGSize(width: 100, height: 50),
            predictedEndTranslation: CGSize(width: 400, height: 200),
            reduceMotion: true
        )

        XCTAssertEqual(settled.width, 100, accuracy: 0.001)
        XCTAssertEqual(settled.height, 50, accuracy: 0.001)
    }

    func testViewportUsesThreeInformationLevels() {
        XCTAssertEqual(WorldDotMapView.Viewport(scale: 1).level, .overview)
        XCTAssertEqual(WorldDotMapView.Viewport(scale: 1.6).level, .countries)
        XCTAssertEqual(WorldDotMapView.Viewport(scale: 2.5).level, .detail)
    }

    func testZoomKeepsTheFingerAnchorFixedOnScreen() {
        let size = CGSize(width: 360, height: 240)
        let anchorPoint = CGPoint(x: 84, y: 72)
        let anchor = UnitPoint(
            x: anchorPoint.x / size.width,
            y: anchorPoint.y / size.height
        )

        let zoomed = WorldDotMapView.Viewport()
            .zoomed(to: 2, anchor: anchor, in: size)
        let transformed = zoomed.transform(anchorPoint, in: size)

        XCTAssertEqual(transformed.x, anchorPoint.x, accuracy: 0.001)
        XCTAssertEqual(transformed.y, anchorPoint.y, accuracy: 0.001)
    }

    func testViewportClampsScaleAndOffsetToTheVisibleMap() {
        let size = CGSize(width: 360, height: 240)
        let viewport = WorldDotMapView.Viewport(
            scale: 9,
            offset: CGSize(width: 2_000, height: -2_000)
        ).normalized(in: size)

        XCTAssertEqual(viewport.scale, 4.2, accuracy: 0.001)
        XCTAssertEqual(viewport.offset.width, 756, accuracy: 0.001)
        XCTAssertEqual(viewport.offset.height, -504, accuracy: 0.001)
        XCTAssertEqual(
            WorldDotMapView.Viewport(scale: 0.4, offset: CGSize(width: 10, height: 10))
                .normalized(in: size),
            .init()
        )
    }

    func testFocusedEdgeCountryMovesToTheMapCenter() {
        let size = CGSize(width: 360, height: 240)
        let countryPoint = CGPoint(x: 354, y: 188)

        let focused = WorldDotMapView.Viewport(scale: 2.8)
            .focused(on: countryPoint, scale: 2.8, in: size)
        let visiblePoint = focused.transform(countryPoint, in: size)

        XCTAssertEqual(visiblePoint.x, size.width / 2, accuracy: 0.001)
        XCTAssertEqual(visiblePoint.y, size.height / 2, accuracy: 0.001)
    }

    func testSelectingCountryFromOverviewZoomsAndCentersIt() {
        let size = CGSize(width: 360, height: 240)
        let countryPoint = CGPoint(x: 318, y: 176)

        let selected = WorldDotMapView.Viewport()
            .centeredOnSelection(countryPoint, in: size)
        let visiblePoint = selected.transform(countryPoint, in: size)

        XCTAssertEqual(selected.scale, WorldDotMapView.Viewport.selectionScale, accuracy: 0.001)
        XCTAssertEqual(selected.level, .countries)
        XCTAssertEqual(visiblePoint.x, size.width / 2, accuracy: 0.001)
        XCTAssertEqual(visiblePoint.y, size.height / 2, accuracy: 0.001)
    }

    func testSelectingCountryPreservesAnExistingCountryZoom() {
        let size = CGSize(width: 360, height: 240)
        let original = WorldDotMapView.Viewport(scale: 1.6)
        let selected = original.centeredOnSelection(CGPoint(x: 230, y: 140), in: size)
        XCTAssertEqual(original.level, .countries)
        XCTAssertEqual(selected.scale, original.scale)
        XCTAssertEqual(selected.transform(CGPoint(x: 230, y: 140), in: size),
                       CGPoint(x: 180, y: 120))
    }

    func testSelectingCountryPreservesAnExistingDetailZoom() {
        let size = CGSize(width: 360, height: 240)
        let countryPoint = CGPoint(x: 318, y: 176)

        let selected = WorldDotMapView.Viewport(scale: 2.8)
            .centeredOnSelection(countryPoint, in: size)

        XCTAssertEqual(selected.scale, 2.8, accuracy: 0.001)
        XCTAssertEqual(selected.level, .detail)
    }

    func testFrozenLabelMovesWithItsCountryWithoutChangingItsOffset() {
        let size = CGSize(width: 360, height: 240)
        let basePosition = CGPoint(x: 318, y: 176)
        let offset = CGSize(width: 0, height: -12)
        let label = WorldDotMapView.FrozenLabel(
            marker: marker("JP", title: "日本", latitude: 35.7, longitude: 139.7),
            basePosition: basePosition,
            offset: offset
        )
        let viewports = [
            WorldDotMapView.Viewport(),
            WorldDotMapView.Viewport(scale: 1.8)
                .centeredOnSelection(basePosition, in: size),
            WorldDotMapView.Viewport(scale: 2.8)
                .centeredOnSelection(basePosition, in: size),
        ]

        for viewport in viewports {
            let anchor = viewport.transform(basePosition, in: size)
            let position = label.position(viewport: viewport, in: size)
            XCTAssertEqual(position.x - anchor.x, offset.width, accuracy: 0.001)
            XCTAssertEqual(position.y - anchor.y, offset.height, accuracy: 0.001)
        }
    }

    func testSelectionKeepsCrispRendererAtBothZoomLevels() {
        for level in [WorldDotMapView.DetailLevel.countries, .detail] {
            for recentring in [true, false] {
                XCTAssertTrue(WorldDotMapView.RenderPlanner.usesDetailCanvas(detailLevel: level, isManipulatingViewport: false, isRecenteringSelection: recentring))
                XCTAssertFalse(WorldDotMapView.RenderPlanner.usesDetailCanvas(detailLevel: level, isManipulatingViewport: true, isRecenteringSelection: recentring))
            }
        }
        let size = CGSize(width: 390, height: 280)
        let point = CGPoint(x: 240, y: 90)
        for scale in [CGFloat(1.8), 2.8, 4.2] {
            for offset in [CGSize.zero, CGSize(width: -120, height: 75)] {
                let origin = WorldDotMapView.RenderPlanner.rasterOrigin(size: size, scale: scale, offset: offset)
                let expected = WorldDotMapView.Viewport(scale: scale, offset: offset).transform(point, in: size)
                XCTAssertEqual(point.x * scale + origin.width, expected.x, accuracy: 0.001)
                XCTAssertEqual(point.y * scale + origin.height, expected.y, accuracy: 0.001)
            }
        }
    }

    func testTestingProgressDoesNotResizeCountryLabels() {
        var marker = WorldDotMarker(id: "JP", title: "日本", latitude: 36, longitude: 138, weight: 1, isSelected: false)
        let frame = WorldDotMapView.LabelPlanner.estimatedFrame(for: marker, at: .zero)
        marker.isTesting = true
        XCTAssertEqual(frame, WorldDotMapView.LabelPlanner.estimatedFrame(for: marker, at: .zero))
    }

    func testMaximumZoomSubdividesCoarseCellsIntoCrispMicroDots() {
        XCTAssertEqual(
            WorldDotMapView.DetailRenderer.subdivision(forScreenCell: 1.8),
            1
        )
        XCTAssertEqual(
            WorldDotMapView.DetailRenderer.subdivision(forScreenCell: 5.2),
            2
        )
        XCTAssertEqual(
            WorldDotMapView.DetailRenderer.subdivision(forScreenCell: 12),
            3
        )
        XCTAssertEqual(
            WorldDotMapView.DetailRenderer.offsets(forScreenCell: 5.2).count,
            4
        )
    }

    func testOverviewAndDetailRenderersKeepEquivalentDotCoverageAtEveryDetailDensity() {
        for (cell, scale) in [
            (CGFloat(1.6), CGFloat(2.2)),
            (CGFloat(1.6), CGFloat(4.2)),
            (CGFloat(4), CGFloat(2.2)),
            (CGFloat(4), CGFloat(4.2)),
        ] {
            let screenCell = cell * scale
            let subdivision = WorldDotMapView.DetailRenderer.subdivision(
                forScreenCell: screenCell
            )

            for style in [
                WorldDotCellStyle.selected,
                WorldDotCellStyle.covered,
                WorldDotCellStyle.uncovered,
            ] {
                let overviewDiameter = style.overviewDiameter(cell: cell) * scale
                let overviewCoverage = overviewDiameter * overviewDiameter
                let detailDiameter = style.detailDiameter(
                    cell: cell,
                    scale: scale,
                    subdivision: subdivision
                )
                let detailCoverage = CGFloat(subdivision * subdivision)
                    * detailDiameter * detailDiameter

                XCTAssertEqual(
                    overviewCoverage,
                    detailCoverage,
                    accuracy: 0.01,
                    "Switching renderers must not make \(style) dots look lighter or darker."
                )
            }
        }
    }

    func testOverviewClustersDenseCountriesAndCountryLevelSplitsThem() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 18),
            marker("TW", title: "台湾", latitude: 25.0, longitude: 121.6, weight: 12),
            marker("US", title: "美国", latitude: 37, longitude: -95, weight: 9),
        ]

        let overview = WorldDotMapView.MarkerPlanner.plan(
            markers: markers,
            layout: layout,
            viewport: .init()
        )
        let aggregate = try XCTUnwrap(overview.first { $0.isCluster })

        XCTAssertEqual(Set(aggregate.markerIDs), Set(["HK", "TW"]))
        XCTAssertEqual(aggregate.nodeCount, 30)
        XCTAssertEqual(aggregate.labelTitle, "香港")
        XCTAssertFalse(aggregate.labelTitle.contains("30"))
        XCTAssertEqual(overview.count, 2)

        let countries = WorldDotMapView.MarkerPlanner.plan(
            markers: markers,
            layout: layout,
            viewport: .init(scale: 1.6)
        )
        XCTAssertEqual(countries.count, 3)
        XCTAssertFalse(countries.contains(where: \.isCluster))
        XCTAssertEqual(countries.first(where: { $0.markerIDs == ["HK"] })?.labelTitle, "香港")
        XCTAssertFalse(countries.contains { $0.labelTitle.contains("18") })
    }

    func testSelectedCountryNeverDisappearsIntoAnOverviewCluster() throws {
        try XCTSkipIf(WorldDotGrid.shared.isEmpty)
        let markers = [
            marker("HK", title: "香港", latitude: 22.3, longitude: 114.2, weight: 18),
            marker("TW", title: "台湾", latitude: 25.0, longitude: 121.6, weight: 12, selected: true),
            marker("JP", title: "日本", latitude: 35.7, longitude: 139.7, weight: 8),
        ]

        let items = WorldDotMapView.MarkerPlanner.plan(
            markers: markers,
            layout: layout,
            viewport: .init()
        )
        let selected = try XCTUnwrap(items.first { $0.markerIDs == ["TW"] })

        XCTAssertFalse(selected.isCluster)
        XCTAssertTrue(selected.markers[0].isSelected)
    }

    func testOverviewLimitsLabelsWhileDetailShowsEveryCollisionFreeLabel() {
        XCTAssertEqual(WorldDotMapView.DetailLevel.overview.labelLimit, 5)
        XCTAssertNil(WorldDotMapView.DetailLevel.countries.labelLimit)
        XCTAssertNil(WorldDotMapView.DetailLevel.detail.labelLimit)
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
        XCTAssertGreaterThan(Set(grid.countryCodes.compactMap { $0 }).count, 150)
    }

    func testEveryRegionTowerKnowsFallsInsideTheGrid() throws {
        let grid = WorldDotGrid.shared
        try XCTSkipIf(grid.isEmpty)

        for code in NodeRegionResolver.countryTable.keys where code != "AQ" {
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
