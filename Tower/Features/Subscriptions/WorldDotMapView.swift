import SwiftUI

/// The land grid the map draws, loaded once from the bundled snapshot.
///
/// The resource is a text bitmap — a `size` header then one line per row using
/// `#` for land — so it needs no image decoding and stays readable in diffs.
/// Regenerate with `Scripts/update_world_dot_map.py`.
struct WorldDotGrid {
    let columns: Int
    let rows: Int
    /// Row-major, `columns * rows` entries.
    let land: [Bool]
    /// ISO 3166-1 alpha-2 ownership for each cell, or `nil` for water and
    /// Natural Earth cells that are not assigned to a country.
    let countryCodes: [String?]
    /// Indexes of the land cells, in row-major order.
    ///
    /// Roughly a fifth of the grid is land, and every renderer and every
    /// covered-country scan used to walk all 32,780 cells to find them —
    /// including the detail canvas, once per frame of a pan or a spring.
    let landCells: [Int]

    init(columns: Int, rows: Int, land: [Bool], countryCodes: [String?] = []) {
        self.columns = columns
        self.rows = rows
        self.land = land
        self.countryCodes = countryCodes.count == land.count
            ? countryCodes
            : Array(repeating: nil, count: land.count)
        landCells = land.indices.filter { land[$0] }
    }

    /// Must match the bounds the generator wrote.
    // Antarctica is omitted from this compact node overview, while Greenland
    // and every practical proxy-node region keep their real label point.
    static let minimumLatitude = -60.0
    static let maximumLatitude = 84.0
    // Keep the full date-line span. Cropping the Pacific looked denser, but it
    // clamped Fiji and New Zealand to the right edge and made their markers
    // indistinguishable.
    static let minimumLongitude = -180.0
    static let maximumLongitude = 180.0

    static let shared: WorldDotGrid = load() ?? WorldDotGrid(columns: 0, rows: 0, land: [])

    var isEmpty: Bool { columns == 0 || rows == 0 }

    /// Width over height of the land grid itself, before any label margin.
    var aspectRatio: CGFloat {
        isEmpty ? 2 : CGFloat(columns) / CGFloat(rows)
    }

    func isLand(column: Int, row: Int) -> Bool {
        guard column >= 0, column < columns, row >= 0, row < rows else { return false }
        return land[row * columns + column]
    }

    func countryCode(column: Int, row: Int) -> String? {
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return countryCodes[row * columns + column]
    }

    /// Every dot owned by a covered country is highlighted as part of the map
    /// itself. Very small regions omitted by Natural Earth 110m still receive
    /// one nearby land dot, instead of bringing back a separate location pin.
    func coveredCellIndexes(for markers: [WorldDotMarker]) -> Set<Int> {
        guard !isEmpty, !markers.isEmpty else { return [] }

        let requestedCodes = Set(markers.map { $0.id.uppercased() })
        var covered: Set<Int> = []
        var representedCodes: Set<String> = []

        for index in landCells {
            guard let code = countryCodes[index], requestedCodes.contains(code) else { continue }
            covered.insert(index)
            representedCodes.insert(code)
        }

        for marker in markers where !representedCodes.contains(marker.id.uppercased()) {
            if let nearest = nearestLandCell(to: marker) {
                covered.insert(nearest)
            }
        }
        return covered
    }

    /// Web-mercator vertical coordinate, the projection the grid was built with.
    static func mercatorY(_ latitude: Double) -> Double {
        let clamped = min(max(latitude, -85), 85)
        return log(tan(.pi / 4 + clamped * .pi / 360))
    }

    /// Mercator projection into unit space, clamped to the drawn band.
    ///
    /// Mercator rather than equirectangular because it is both the familiar web
    /// map shape and a much taller one, which suits a card that was reading as
    /// a squashed letterbox.
    static func unitPoint(latitude: Double, longitude: Double) -> CGPoint {
        let x = (longitude - minimumLongitude) / (maximumLongitude - minimumLongitude)
        let top = mercatorY(maximumLatitude)
        let bottom = mercatorY(minimumLatitude)
        let y = (top - mercatorY(latitude)) / (top - bottom)
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private static func load(bundle: Bundle = .main) -> WorldDotGrid? {
        guard let url = bundle.url(forResource: "WorldDotMap", withExtension: "txt", subdirectory: "WorldMap")
            ?? bundle.url(forResource: "WorldDotMap", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let countryURL = bundle.url(
            forResource: "WorldDotCountries",
            withExtension: "txt",
            subdirectory: "WorldMap"
        ) ?? bundle.url(forResource: "WorldDotCountries", withExtension: "txt")
        let countryText = countryURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return parse(text, countryText: countryText)
    }

    static func parse(_ text: String, countryText: String? = nil) -> WorldDotGrid? {
        var columns = 0
        var rows = 0
        var cells: [Bool] = []

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("size ") {
                let parts = line.split(separator: " ")
                guard parts.count == 3, let width = Int(parts[1]), let height = Int(parts[2]) else {
                    return nil
                }
                columns = width
                rows = height
                cells.reserveCapacity(width * height)
                continue
            }
            guard !line.isEmpty, columns > 0 else { continue }
            // A land row starts with "#" too, so a comment is told apart by
            // containing something other than the two cell characters rather
            // than by its first character.
            guard line.allSatisfy({ $0 == "#" || $0 == "." }) else { continue }
            for character in line.prefix(columns) {
                cells.append(character == "#")
            }
            if line.count < columns {
                cells.append(contentsOf: Array(repeating: false, count: columns - line.count))
            }
        }

        guard columns > 0, rows > 0, cells.count >= columns * rows else { return nil }
        let land = Array(cells.prefix(columns * rows))
        let countryCodes: [String?]
        if let countryText {
            guard let parsed = parseCountryCodes(
                countryText,
                columns: columns,
                rows: rows,
                land: land
            ) else {
                return nil
            }
            countryCodes = parsed
        } else {
            countryCodes = Array(repeating: nil, count: land.count)
        }
        return WorldDotGrid(
            columns: columns,
            rows: rows,
            land: land,
            countryCodes: countryCodes
        )
    }

    private static func parseCountryCodes(
        _ text: String,
        columns expectedColumns: Int,
        rows expectedRows: Int,
        land: [Bool]
    ) -> [String?]? {
        var columns = 0
        var rows = 0
        var codes: [String?] = []

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("size ") {
                let parts = line.split(separator: " ")
                guard parts.count == 3,
                      let width = Int(parts[1]),
                      let height = Int(parts[2]),
                      width == expectedColumns,
                      height == expectedRows else {
                    return nil
                }
                columns = width
                rows = height
                codes.reserveCapacity(width * height)
                continue
            }

            guard !line.isEmpty, !line.hasPrefix("#"), columns > 0 else { continue }
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count == columns else { return nil }
            for token in tokens {
                if token == ".." {
                    codes.append(nil)
                } else {
                    let code = token.uppercased()
                    guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                        return nil
                    }
                    codes.append(code)
                }
            }
        }

        guard columns == expectedColumns,
              rows == expectedRows,
              codes.count == expectedColumns * expectedRows else {
            return nil
        }
        return zip(codes, land).map { code, isLand in isLand ? code : nil }
    }

    private func nearestLandCell(to marker: WorldDotMarker) -> Int? {
        let unit = Self.unitPoint(latitude: marker.latitude, longitude: marker.longitude)
        let targetColumn = unit.x * CGFloat(columns) - 0.5
        let targetRow = unit.y * CGFloat(rows) - 0.5
        var result: (index: Int, distance: CGFloat)?

        for index in land.indices where land[index] {
            let column = CGFloat(index % columns)
            let row = CGFloat(index / columns)
            let deltaColumn = column - targetColumn
            let deltaRow = row - targetRow
            let distance = deltaColumn * deltaColumn + deltaRow * deltaRow
            if result.map({ distance < $0.distance }) ?? true {
                result = (index, distance)
            }
        }
        return result?.index
    }
}

struct WorldDotMarker: Identifiable, Equatable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    /// Higher wins when two labels would overlap.
    let weight: Int
    let isSelected: Bool
}

/// A flat dot-matrix world map. Replaces the MapKit globe, which was heavy to
/// render and offered far more interaction than a node overview needs.
struct WorldDotMapView: View {
    let markers: [WorldDotMarker]
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewport = Viewport()
    @State private var displayedLevel: DetailLevel = .overview
    @State private var magnifyStartViewport: Viewport?
    @State private var dragStartViewport: Viewport?
    @State private var isManipulatingViewport = false
    @State private var isRecenteringSelection = false
    @State private var selectionRecenterToken: UUID?
    @State private var frozenLabels: [FrozenLabel]?

    private let grid: WorldDotGrid
    private let coveredCells: Set<Int>
    private let selectedCells: Set<Int>

    init(markers: [WorldDotMarker], onSelect: @escaping (String) -> Void) {
        self.markers = markers
        self.onSelect = onSelect

        let grid = WorldDotGrid.shared
        self.grid = grid
        coveredCells = grid.coveredCellIndexes(for: markers)
        selectedCells = grid.coveredCellIndexes(for: markers.filter(\.isSelected))
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, grid: grid)
            let displayItems = MarkerPlanner.plan(
                markers: markers,
                layout: layout,
                viewport: viewport,
                detailLevel: displayedLevel
            )
            let labelMarkers = markersForLabels(from: displayItems)
            let markerPositions = Dictionary(
                uniqueKeysWithValues: displayItems.map { ($0.id, $0.position) }
            )
            let placements = LabelPlanner.plan(
                markers: labelMarkers,
                positions: markerPositions,
                bounds: CGRect(origin: .zero, size: geometry.size)
            )
            let presentedLabels = labelsForPresentation(
                displayItems: displayItems,
                labelMarkers: labelMarkers,
                placements: placements,
                viewport: viewport,
                size: geometry.size
            )
            ZStack(alignment: .topLeading) {
                if RenderPlanner.usesDetailCanvas(
                    detailLevel: displayedLevel,
                    isManipulatingViewport: isManipulatingViewport,
                    isRecenteringSelection: isRecenteringSelection
                ) {
                    WorldDotDetailCanvas(
                        grid: grid,
                        layout: layout,
                        scale: viewport.scale,
                        offset: viewport.offset,
                        coveredCells: coveredCells,
                        selectedCells: selectedCells,
                        colorScheme: colorScheme
                    )
                    .transition(.opacity)
                } else {
                    WorldDotCanvas(
                        grid: grid,
                        layout: layout,
                        coveredCells: coveredCells,
                        selectedCells: selectedCells,
                        colorScheme: colorScheme
                    )
                    .equatable()
                    .drawingGroup()
                    .scaleEffect(viewport.scale)
                    .offset(viewport.offset)
                }

                ForEach(displayItems) { item in
                    WorldDotHitTarget(item: item) {
                        if item.isCluster {
                            focus(on: item, in: geometry.size)
                        } else if let entry = item.markers.first {
                            if entry.isSelected {
                                recenterSelection(
                                    on: item.basePosition,
                                    in: geometry.size
                                )
                            }
                            onSelect(entry.id)
                        }
                    }
                    .position(item.position)
                }

                ForEach(presentedLabels) { label in
                    mapLabel(label.marker)
                        .position(label.position)
                        .zIndex(label.marker.isSelected ? 1 : 0)
                }

                if viewport.isModified {
                    Button {
                        cancelSelectionRecenter()
                        withViewportAnimation {
                            viewport = Viewport()
                            displayedLevel = .overview
                        }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(ResponsivePressButtonStyle())
                    .accessibilityLabel("恢复默认")
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .zIndex(2)
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(magnifyGesture(in: geometry.size))
            .simultaneousGesture(
                mapTapGesture(
                    layout: layout,
                    displayItems: displayItems,
                    presentedLabels: presentedLabels,
                    in: geometry.size
                )
            )
            .highPriorityGesture(
                panGesture(in: geometry.size),
                including: viewport.scale > Viewport.minimumScale + 0.001 ? .gesture : .none
            )
            .onChange(of: geometry.size) { _, size in
                let normalized = viewport.normalized(in: size)
                viewport = normalized
                displayedLevel = normalized.level
            }
            .onChange(of: selectedMarkerID) { _, markerID in
                guard let markerID,
                      let marker = markers.first(where: { $0.id == markerID }) else {
                    return
                }
                recenterSelection(
                    on: layout.position(for: marker),
                    in: geometry.size
                )
            }
        }
        // Exactly the grid's own ratio, so width and height are constrained at
        // the same time and neither direction is left with a blank band.
        .aspectRatio(grid.aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private func mapLabel(_ marker: WorldDotMarker) -> some View {
        Text(marker.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
                marker.isSelected
                    ? Color.primary
                    : Color.primary.opacity(colorScheme == .dark ? 0.80 : 0.68)
            )
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background {
                Capsule()
                    .fill(
                        Color(uiColor: .systemBackground)
                            .opacity(
                                marker.isSelected
                                    ? (colorScheme == .dark ? 0.94 : 0.96)
                                    : (colorScheme == .dark ? 0.68 : 0.78)
                            )
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                marker.isSelected
                                    ? Color.primary.opacity(0.16)
                                    : Color.clear,
                                lineWidth: 0.75
                            )
                    }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.05),
                radius: 1.5,
                y: 0.5
            )
            .allowsHitTesting(false)
            // Region selection also expands the node list with a spring. At
            // country/detail zoom that spring used to leak into this existing
            // label and interpolate its fill and border, which looked like a
            // drifting, deforming material. Keep the label's internal
            // appearance discrete; the outer `.position` in `body` still
            // inherits the viewport spring and moves the complete label.
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func markersForLabels(from items: [MarkerPlanner.Item]) -> [WorldDotMarker] {
        var result = items.map { item -> WorldDotMarker in
            let primary = item.markers.sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.id < $1.id
            }[0]
            return WorldDotMarker(
                id: item.id,
                title: item.labelTitle,
                latitude: primary.latitude,
                longitude: primary.longitude,
                weight: item.nodeCount,
                isSelected: item.markers.contains(where: \.isSelected)
            )
        }

        if let limit = displayedLevel.labelLimit, result.count > limit {
            let selected = result.filter(\.isSelected)
            let selectedIDs = Set(selected.map(\.id))
            let remaining = result
                .filter { !selectedIDs.contains($0.id) }
                .sorted {
                    if $0.weight != $1.weight { return $0.weight > $1.weight }
                    return $0.id < $1.id
                }
            result = selected + Array(remaining.prefix(max(0, limit - selected.count)))
        }
        return result
    }

    private func labelsForPresentation(
        displayItems: [MarkerPlanner.Item],
        labelMarkers: [WorldDotMarker],
        placements: [String: CGPoint],
        viewport: Viewport,
        size: CGSize
    ) -> [PresentedLabel] {
        if let frozenLabels {
            return frozenLabels.map { label in
                PresentedLabel(
                    marker: label.marker,
                    position: label.position(viewport: viewport, in: size)
                )
            }
        }

        return displayItems.compactMap { item in
            guard let marker = labelMarkers.first(where: { $0.id == item.id }),
                  let placement = placements[item.id] else {
                return nil
            }
            return PresentedLabel(marker: marker, position: placement)
        }
    }

    private var selectedMarkerID: String? {
        markers.first(where: \.isSelected)?.id
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isManipulatingViewport = true
                if magnifyStartViewport == nil {
                    cancelSelectionRecenter()
                    magnifyStartViewport = viewport
                }
                guard let start = magnifyStartViewport else { return }
                viewport = start.zoomed(
                    to: start.scale * value.magnification,
                    anchor: value.startAnchor,
                    in: size
                )
            }
            .onEnded { value in
                guard let start = magnifyStartViewport else { return }
                let settled = start.zoomed(
                    to: start.scale * value.magnification,
                    anchor: value.startAnchor,
                    in: size
                ).normalized(in: size)
                magnifyStartViewport = nil
                isManipulatingViewport = false
                withViewportAnimation {
                    viewport = settled
                    displayedLevel = settled.level
                }
            }
    }

    private func mapTapGesture(
        layout: Layout,
        displayItems: [MarkerPlanner.Item],
        presentedLabels: [PresentedLabel],
        in size: CGSize
    ) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let resetControlFrame = CGRect(
                    x: size.width - 54,
                    y: size.height - 54,
                    width: 54,
                    height: 54
                )
                guard !viewport.isModified || !resetControlFrame.contains(value.location) else {
                    return
                }

                if let itemID = LabelHitTester.markerID(
                    at: value.location,
                    labels: presentedLabels
                ), let item = displayItems.first(where: { $0.id == itemID }) {
                    if item.isCluster {
                        focus(on: item, in: size)
                    } else if let entry = item.markers.first {
                        if entry.isSelected {
                            recenterSelection(on: item.basePosition, in: size)
                        }
                        onSelect(entry.id)
                    }
                    return
                }

                switch RegionHitTester.hit(
                    at: value.location,
                    markers: markers,
                    grid: grid,
                    layout: layout,
                    viewport: viewport
                ) {
                case .marker(let markerID):
                    if markerID == selectedMarkerID,
                       let marker = markers.first(where: { $0.id == markerID }) {
                        recenterSelection(
                            on: layout.position(for: marker),
                            in: size
                        )
                    }
                    onSelect(markerID)
                    return
                case .uncoveredCountry:
                    // The tap landed inside a country with no nodes. Falling
                    // through to the proximity search below would select a
                    // neighbour the user did not touch.
                    return
                case .none:
                    break
                }

                guard let item = RegionHitTester.displayItem(
                    at: value.location,
                    items: displayItems
                ) else {
                    return
                }
                if item.isCluster {
                    focus(on: item, in: size)
                } else if let entry = item.markers.first {
                    onSelect(entry.id)
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isManipulatingViewport = true
                if dragStartViewport == nil {
                    cancelSelectionRecenter()
                    dragStartViewport = viewport
                }
                guard let start = dragStartViewport else { return }
                viewport = start.translated(
                    by: PanMotion.tracked(value.translation),
                    in: size
                )
            }
            .onEnded { value in
                guard let start = dragStartViewport else { return }
                let translation = PanMotion.settled(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    reduceMotion: reduceMotion
                )
                let settled = start.translated(by: translation, in: size)
                dragStartViewport = nil
                isManipulatingViewport = false
                withViewportAnimation {
                    viewport = settled
                }
            }
    }

    /// Track the finger one-to-one while it is down. The earlier damped drag
    /// only applied 46% of the translation and felt as if the map were pulling
    /// against the gesture. Keep release momentum deliberately small instead,
    /// so direct manipulation stays responsive without letting a flick throw
    /// the compact map across several countries.
    enum PanMotion {
        static let trackingFactor: CGFloat = 1
        static let momentumFactor: CGFloat = 0.04

        static func tracked(_ translation: CGSize) -> CGSize {
            CGSize(
                width: translation.width * trackingFactor,
                height: translation.height * trackingFactor
            )
        }

        static func settled(
            translation: CGSize,
            predictedEndTranslation: CGSize,
            reduceMotion: Bool
        ) -> CGSize {
            guard !reduceMotion else { return tracked(translation) }

            let projected = CGSize(
                width: translation.width
                    + (predictedEndTranslation.width - translation.width) * momentumFactor,
                height: translation.height
                    + (predictedEndTranslation.height - translation.height) * momentumFactor
            )
            return tracked(projected)
        }
    }

    private func focus(on item: MarkerPlanner.Item, in size: CGSize) {
        let targetScale = max(viewport.scale, 1.6)
        cancelSelectionRecenter()
        withViewportAnimation {
            viewport = viewport.focused(on: item.basePosition, scale: targetScale, in: size)
            displayedLevel = .countries
        }
    }

    private func recenterSelection(on point: CGPoint, in size: CGSize) {
        let target = viewport.centeredOnSelection(point, in: size)
        guard target != viewport else { return }

        if reduceMotion {
            cancelSelectionRecenter()
            withAnimation(nil) {
                viewport = target
                displayedLevel = target.level
            }
            return
        }

        let token = UUID()
        let labelSnapshot = captureLabelSnapshot(in: size)
        selectionRecenterToken = token
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            frozenLabels = labelSnapshot
            isRecenteringSelection = true
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 1)) {
            viewport = target
            displayedLevel = target.level
        } completion: {
            guard selectionRecenterToken == token else { return }
            selectionRecenterToken = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                frozenLabels = nil
            }
            withAnimation(.easeOut(duration: 0.14)) {
                isRecenteringSelection = false
            }
        }
    }

    private func captureLabelSnapshot(in size: CGSize) -> [FrozenLabel] {
        let layout = Layout(size: size, grid: grid)
        let displayItems = MarkerPlanner.plan(
            markers: markers,
            layout: layout,
            viewport: viewport,
            detailLevel: displayedLevel
        )
        let labelMarkers = markersForLabels(from: displayItems)
        let markerPositions = Dictionary(
            uniqueKeysWithValues: displayItems.map { ($0.id, $0.position) }
        )
        let placements = LabelPlanner.plan(
            markers: labelMarkers,
            positions: markerPositions,
            bounds: CGRect(origin: .zero, size: size)
        )

        return displayItems.compactMap { item in
            guard let marker = labelMarkers.first(where: { $0.id == item.id }),
                  let placement = placements[item.id] else {
                return nil
            }
            return FrozenLabel(
                marker: marker,
                basePosition: item.basePosition,
                offset: CGSize(
                    width: placement.x - item.position.x,
                    height: placement.y - item.position.y
                )
            )
        }
    }

    private func cancelSelectionRecenter() {
        selectionRecenterToken = nil
        guard isRecenteringSelection || frozenLabels != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            frozenLabels = nil
            isRecenteringSelection = false
        }
    }

    private func withViewportAnimation(_ updates: () -> Void) {
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.34, dampingFraction: 1),
            updates
        )
    }

    enum DetailLevel: Equatable {
        case overview
        case countries
        case detail

        var labelLimit: Int? {
            switch self {
            case .overview: 5
            case .countries, .detail: nil
            }
        }
    }

    enum RenderPlanner {
        static func usesDetailCanvas(
            detailLevel: DetailLevel,
            isManipulatingViewport: Bool,
            isRecenteringSelection _: Bool
        ) -> Bool {
            detailLevel == .detail
                && !isManipulatingViewport
        }
    }

    struct FrozenLabel: Identifiable, Equatable {
        let marker: WorldDotMarker
        let basePosition: CGPoint
        let offset: CGSize

        var id: String { marker.id }

        func position(viewport: Viewport, in size: CGSize) -> CGPoint {
            let anchor = viewport.transform(basePosition, in: size)
            return CGPoint(
                x: anchor.x + offset.width,
                y: anchor.y + offset.height
            )
        }
    }

    struct PresentedLabel: Identifiable, Equatable {
        let marker: WorldDotMarker
        let position: CGPoint

        var id: String { marker.id }
    }

    struct Viewport: Equatable {
        static let minimumScale: CGFloat = 1
        static let maximumScale: CGFloat = 4.2
        static let selectionScale: CGFloat = 1.8

        var scale: CGFloat
        var offset: CGSize

        init(scale: CGFloat = minimumScale, offset: CGSize = .zero) {
            self.scale = scale
            self.offset = offset
        }

        var level: DetailLevel {
            if scale < 1.35 { return .overview }
            if scale < 2.2 { return .countries }
            return .detail
        }

        var isModified: Bool {
            scale > Self.minimumScale + 0.001
                || abs(offset.width) > 0.5
                || abs(offset.height) > 0.5
        }

        func normalized(in size: CGSize) -> Viewport {
            let boundedScale = min(max(scale, Self.minimumScale), Self.maximumScale)
            guard boundedScale > Self.minimumScale + 0.001 else { return Viewport() }

            // Let a date-line or polar country reach the centre instead of
            // pinning it to the card edge. The furthest legal pan keeps the
            // map's own edge at the centre, so the world can never disappear
            // completely even though some neutral card background is visible.
            let maximumX = size.width * boundedScale / 2
            let maximumY = size.height * boundedScale / 2
            return Viewport(
                scale: boundedScale,
                offset: CGSize(
                    width: min(max(offset.width, -maximumX), maximumX),
                    height: min(max(offset.height, -maximumY), maximumY)
                )
            )
        }

        func transform(_ point: CGPoint, in size: CGSize) -> CGPoint {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            return CGPoint(
                x: center.x + (point.x - center.x) * scale + offset.width,
                y: center.y + (point.y - center.y) * scale + offset.height
            )
        }

        func inverseTransform(_ point: CGPoint, in size: CGSize) -> CGPoint {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let safeScale = max(scale, Self.minimumScale)
            return CGPoint(
                x: center.x + (point.x - center.x - offset.width) / safeScale,
                y: center.y + (point.y - center.y - offset.height) / safeScale
            )
        }

        func zoomed(to requestedScale: CGFloat, anchor: UnitPoint, in size: CGSize) -> Viewport {
            let currentScale = max(scale, Self.minimumScale)
            let targetScale = min(max(requestedScale, Self.minimumScale), Self.maximumScale)
            let ratio = targetScale / currentScale
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let anchorPoint = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
            let targetOffset = CGSize(
                width: (anchorPoint.x - center.x) * (1 - ratio) + offset.width * ratio,
                height: (anchorPoint.y - center.y) * (1 - ratio) + offset.height * ratio
            )
            return Viewport(scale: targetScale, offset: targetOffset).normalized(in: size)
        }

        func translated(by translation: CGSize, in size: CGSize) -> Viewport {
            Viewport(
                scale: scale,
                offset: CGSize(
                    width: offset.width + translation.width,
                    height: offset.height + translation.height
                )
            ).normalized(in: size)
        }

        func focused(on point: CGPoint, scale targetScale: CGFloat, in size: CGSize) -> Viewport {
            let boundedScale = min(max(targetScale, Self.minimumScale), Self.maximumScale)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            return Viewport(
                scale: boundedScale,
                offset: CGSize(
                    width: -(point.x - center.x) * boundedScale,
                    height: -(point.y - center.y) * boundedScale
                )
            ).normalized(in: size)
        }

        func centeredOnSelection(_ point: CGPoint, in size: CGSize) -> Viewport {
            focused(
                on: point,
                scale: max(scale, Self.selectionScale),
                in: size
            )
        }
    }

    /// Keeps the grid's aspect ratio and centres it, so the dots stay round and
    /// the markers land on the same cells the map drew.
    struct Layout {
        let size: CGSize
        let origin: CGPoint
        let cell: CGFloat
        let grid: WorldDotGrid

        init(size: CGSize, grid: WorldDotGrid) {
            self.size = size
            self.grid = grid
            guard !grid.isEmpty else {
                origin = .zero
                cell = 0
                return
            }
            // No reserved band: the grid fills the card edge to edge, and a
            // label that cannot sit above its dot is placed below instead.
            let cellSize = min(size.width / CGFloat(grid.columns), size.height / CGFloat(grid.rows))
            cell = cellSize
            origin = CGPoint(
                x: (size.width - cellSize * CGFloat(grid.columns)) / 2,
                y: (size.height - cellSize * CGFloat(grid.rows)) / 2
            )
        }

        var dotDiameter: CGFloat { max(cell * 0.62, 1) }

        func center(column: Int, row: Int) -> CGPoint {
            CGPoint(
                x: origin.x + (CGFloat(column) + 0.5) * cell,
                y: origin.y + (CGFloat(row) + 0.5) * cell
            )
        }

        func cell(at point: CGPoint) -> (column: Int, row: Int)? {
            guard cell > 0 else { return nil }
            let column = Int(floor((point.x - origin.x) / cell))
            let row = Int(floor((point.y - origin.y) / cell))
            guard column >= 0, column < grid.columns, row >= 0, row < grid.rows else {
                return nil
            }
            return (column, row)
        }

        func position(for entry: WorldDotMarker) -> CGPoint {
            let unit = WorldDotGrid.unitPoint(latitude: entry.latitude, longitude: entry.longitude)
            return CGPoint(
                x: origin.x + unit.x * cell * CGFloat(grid.columns),
                y: origin.y + unit.y * cell * CGFloat(grid.rows)
            )
        }

        func position(for entry: WorldDotMarker, viewport: Viewport) -> CGPoint {
            viewport.transform(position(for: entry), in: size)
        }
    }

    enum LabelHitTester {
        private static let minimumTapSize: CGFloat = 44

        static func markerID(
            at point: CGPoint,
            labels: [PresentedLabel]
        ) -> String? {
            labels
                .compactMap { label -> (label: PresentedLabel, distance: CGFloat)? in
                    let visualFrame = LabelPlanner.estimatedFrame(
                        for: label.marker,
                        at: label.position
                    )
                    let hitFrame = CGRect(
                        x: visualFrame.midX - max(visualFrame.width, minimumTapSize) / 2,
                        y: visualFrame.midY - max(visualFrame.height, minimumTapSize) / 2,
                        width: max(visualFrame.width, minimumTapSize),
                        height: max(visualFrame.height, minimumTapSize)
                    )
                    guard hitFrame.contains(point) else { return nil }
                    return (
                        label,
                        hypot(label.position.x - point.x, label.position.y - point.y)
                    )
                }
                .min { first, second in
                    if first.label.marker.isSelected != second.label.marker.isSelected {
                        return first.label.marker.isSelected
                    }
                    return first.distance < second.distance
                }?
                .label.marker.id
        }
    }

    enum RegionHitTester {
        /// What a tap on the map itself resolved to.
        ///
        /// `uncoveredCountry` is deliberately distinct from `none`: the map
        /// answered the tap, and the answer is "this country has no nodes".
        /// Collapsing the two let the caller's proximity fallback hand the tap
        /// to whichever covered neighbour happened to be within a few points,
        /// which is the very thing the country layer exists to prevent.
        enum Hit: Equatable {
            case marker(String)
            case uncoveredCountry
            case none
        }

        static func markerID(
            at visiblePoint: CGPoint,
            markers: [WorldDotMarker],
            grid: WorldDotGrid,
            layout: Layout,
            viewport: Viewport
        ) -> String? {
            guard case .marker(let id) = hit(
                at: visiblePoint,
                markers: markers,
                grid: grid,
                layout: layout,
                viewport: viewport
            ) else { return nil }
            return id
        }

        static func hit(
            at visiblePoint: CGPoint,
            markers: [WorldDotMarker],
            grid: WorldDotGrid,
            layout: Layout,
            viewport: Viewport
        ) -> Hit {
            guard !grid.isEmpty, !markers.isEmpty else { return .none }

            let requestedMarkers = Dictionary(
                uniqueKeysWithValues: markers.map { ($0.id.uppercased(), $0) }
            )
            let mapPoint = viewport.inverseTransform(visiblePoint, in: layout.size)
            if let cell = layout.cell(at: mapPoint),
               let countryCode = grid.countryCode(column: cell.column, row: cell.row) {
                // A different, uncovered country owns this cell. Do not let a
                // nearby covered microstate steal that explicit map hit.
                guard let marker = requestedMarkers[countryCode] else {
                    return .uncoveredCountry
                }
                return .marker(marker.id)
            }

            // Water has no competing country identity, so give every marker a
            // stable minimum screen-space target. This matters at high zoom:
            // Singapore, Macao and other microstates may still occupy only a
            // few dots even though their map is visually much larger.
            let fallbackRadius: CGFloat = 26
            let nearest: String? = markers
                .map { (marker: WorldDotMarker) -> (marker: WorldDotMarker, distance: CGFloat) in
                    let position = layout.position(for: marker, viewport: viewport)
                    return (
                        marker: marker,
                        distance: hypot(position.x - visiblePoint.x, position.y - visiblePoint.y)
                    )
                }
                .filter { $0.distance <= fallbackRadius }
                .min { $0.distance < $1.distance }?
                .marker.id
            guard let nearest else { return .none }
            return .marker(nearest)
        }

        static func displayItem(
            at point: CGPoint,
            items: [MarkerPlanner.Item]
        ) -> MarkerPlanner.Item? {
            items
                .map { item in
                    (
                        item: item,
                        distance: hypot(item.position.x - point.x, item.position.y - point.y)
                    )
                }
                .filter { entry in
                    entry.distance <= (entry.item.isCluster ? 22 : 17)
                }
                .min { $0.distance < $1.distance }?
                .item
        }
    }

    enum MarkerPlanner {
        struct Item: Identifiable, Equatable {
            let markers: [WorldDotMarker]
            let basePosition: CGPoint
            let position: CGPoint

            var markerIDs: [String] { markers.map(\.id).sorted() }
            var id: String { markerIDs.joined(separator: "+") }
            var isCluster: Bool { markers.count > 1 }
            var nodeCount: Int { markers.reduce(0) { $0 + $1.weight } }
            var labelTitle: String {
                markers.sorted {
                    if $0.weight != $1.weight { return $0.weight > $1.weight }
                    return $0.id < $1.id
                }.first?.title ?? ""
            }
        }

        private static let clusterDistance: CGFloat = 30

        static func plan(
            markers: [WorldDotMarker],
            layout: Layout,
            viewport: Viewport,
            detailLevel: DetailLevel? = nil
        ) -> [Item] {
            let ordered = markers.sorted {
                if $0.isSelected != $1.isSelected { return $0.isSelected }
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.id < $1.id
            }

            guard (detailLevel ?? viewport.level) == .overview else {
                return ordered.map { marker in
                    let base = layout.position(for: marker)
                    return Item(
                        markers: [marker],
                        basePosition: base,
                        position: viewport.transform(base, in: layout.size)
                    )
                }
            }

            var remaining = ordered.filter { !$0.isSelected }
            var groups = ordered.filter(\.isSelected).map { [$0] }

            while let seed = remaining.first {
                remaining.removeFirst()
                let seedPosition = viewport.transform(layout.position(for: seed), in: layout.size)
                var group = [seed]
                remaining.removeAll { candidate in
                    let candidatePosition = viewport.transform(
                        layout.position(for: candidate),
                        in: layout.size
                    )
                    let distance = hypot(
                        candidatePosition.x - seedPosition.x,
                        candidatePosition.y - seedPosition.y
                    )
                    if distance <= clusterDistance {
                        group.append(candidate)
                        return true
                    }
                    return false
                }
                groups.append(group)
            }

            return groups.map { group in
                let totalWeight = max(group.reduce(0) { $0 + $1.weight }, 1)
                let base = group.reduce(CGPoint.zero) { partial, marker in
                    let point = layout.position(for: marker)
                    let weight = CGFloat(max(marker.weight, 1))
                    return CGPoint(
                        x: partial.x + point.x * weight,
                        y: partial.y + point.y * weight
                    )
                }
                let average = CGPoint(
                    x: base.x / CGFloat(totalWeight),
                    y: base.y / CGFloat(totalWeight)
                )
                return Item(
                    markers: group,
                    basePosition: average,
                    position: viewport.transform(average, in: layout.size)
                )
            }
        }
    }

    /// At high magnification a single source cell would otherwise become one
    /// large, soft raster dot. Split that cell into a small screen-space grid
    /// instead: the overview remains cheap to transform, while settled detail
    /// views gain crisp points without shipping a much larger map resource.
    enum DetailRenderer {
        static func subdivision(forScreenCell screenCell: CGFloat) -> Int {
            if screenCell < 3 { return 1 }
            if screenCell < 8 { return 2 }
            return 3
        }

        static func offsets(forScreenCell screenCell: CGFloat) -> [CGSize] {
            let subdivision = subdivision(forScreenCell: screenCell)
            guard subdivision > 1 else { return [.zero] }

            let step = screenCell / CGFloat(subdivision)
            let first = -screenCell / 2 + step / 2
            return (0 ..< subdivision).flatMap { row in
                (0 ..< subdivision).map { column in
                    CGSize(
                        width: first + CGFloat(column) * step,
                        height: first + CGFloat(row) * step
                    )
                }
            }
        }
    }

    /// Places labels directly above or below their dots, dropping the ones
    /// that cannot fit without overlap.
    ///
    /// East and Southeast Asia put a dozen regions within a few dots of each
    /// other, so labels stacked on top of one another and became unreadable.
    /// Heavier markers — more nodes — claim their spot first, and a label that
    /// still collides is left out rather than drawn over its neighbour.
    ///
    /// The previous multi-ring planner could move a country name far enough to
    /// look like a different location. Position accuracy wins here: a hidden
    /// label is less misleading than a readable label over the wrong country.
    enum LabelPlanner {
        /// Roughly one em per CJK character, which is what these names are.
        private static let characterWidth: CGFloat = 10.5
        private static let labelHeight: CGFloat = 13
        private static let safeInset: CGFloat = 6

        static func estimatedFrame(for marker: WorldDotMarker, at centre: CGPoint) -> CGRect {
            // Selected and ordinary labels deliberately share the same
            // geometry. Selection only changes contrast and stacking, so the
            // capsule cannot resize or move independently during a recenter.
            let horizontalPadding: CGFloat = 8
            let verticalPadding: CGFloat = 3
            let size = CGSize(
                width: CGFloat(marker.title.count) * characterWidth + horizontalPadding,
                height: labelHeight + verticalPadding
            )
            return CGRect(
                x: centre.x - size.width / 2,
                y: centre.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        static func plan(
            markers: [WorldDotMarker],
            layout: Layout,
            bounds: CGRect
        ) -> [String: CGPoint] {
            let positions = Dictionary(
                uniqueKeysWithValues: markers.map { ($0.id, layout.position(for: $0)) }
            )
            return plan(markers: markers, positions: positions, bounds: bounds)
        }

        static func plan(
            markers: [WorldDotMarker],
            positions: [String: CGPoint],
            bounds: CGRect
        ) -> [String: CGPoint] {
            var placed: [CGRect] = []
            var result: [String: CGPoint] = [:]

            // Selection must never participate in the layout order. Doing so
            // made neighbouring country names exchange positions every time a
            // pin was tapped. Node count and the stable country id are enough
            // to keep the exact same inputs at the exact same coordinates.
            let ordered = markers.sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.id < $1.id
            }

            for marker in ordered {
                guard let anchor = positions[marker.id] else { continue }
                let size = estimatedFrame(for: marker, at: .zero).size
                let vertical = size.height / 2 + 7
                let candidates = [
                    CGPoint(x: anchor.x, y: anchor.y - vertical),
                    CGPoint(x: anchor.x, y: anchor.y + vertical)
                ]

                for candidate in candidates {
                    let rect = estimatedFrame(for: marker, at: candidate)
                    guard bounds.contains(rect) else { continue }
                    guard !placed.contains(where: { $0.intersects(rect.insetBy(dx: -2, dy: -1)) }) else {
                        continue
                    }
                    placed.append(rect)
                    result[marker.id] = candidate
                    break
                }
            }

            // An edge selection is more important than collision avoidance:
            // keep its pill inside the card even when both exact above/below
            // candidates fall outside (New Zealand is the common case).
            for marker in markers where marker.isSelected && result[marker.id] == nil {
                guard let anchor = positions[marker.id] else { continue }
                let size = estimatedFrame(for: marker, at: .zero).size
                let preferred = CGPoint(x: anchor.x, y: anchor.y - size.height / 2 - 7)
                let safeBounds = bounds.insetBy(dx: safeInset, dy: safeInset)
                let minimumX = safeBounds.minX + size.width / 2
                let maximumX = safeBounds.maxX - size.width / 2
                let minimumY = safeBounds.minY + size.height / 2
                let maximumY = safeBounds.maxY - size.height / 2
                result[marker.id] = CGPoint(
                    x: minimumX <= maximumX
                        ? min(max(preferred.x, minimumX), maximumX)
                        : safeBounds.midX,
                    y: minimumY <= maximumY
                        ? min(max(preferred.y, minimumY), maximumY)
                        : safeBounds.midY
                )
            }
            return result
        }
    }
}

private enum WorldDotCellStyle {
    case selected
    case covered
    case uncovered

    static func resolve(
        index: Int,
        coveredCells: Set<Int>,
        selectedCells: Set<Int>
    ) -> Self {
        if selectedCells.contains(index) { return .selected }
        if coveredCells.contains(index) { return .covered }
        return .uncovered
    }

    func color(in colorScheme: ColorScheme) -> Color {
        switch self {
        case .selected:
            return colorScheme == .dark
                ? Color(red: 0.37, green: 0.96, blue: 0.58)
                : Color(red: 0.00, green: 0.38, blue: 0.20)
        case .covered:
            return colorScheme == .dark
                ? Color(red: 0.20, green: 0.82, blue: 0.43)
                : Color(red: 0.06, green: 0.70, blue: 0.33)
        case .uncovered:
            return .primary.opacity(colorScheme == .dark ? 0.22 : 0.17)
        }
    }

    func overviewDiameter(cell: CGFloat) -> CGFloat {
        switch self {
        case .selected: max(cell * 0.9, 1.2)
        case .covered: max(cell * 0.72, 1.1)
        case .uncovered: max(cell * 0.56, 1)
        }
    }

    func detailDiameter(step: CGFloat) -> CGFloat {
        let factor: CGFloat
        let maximum: CGFloat
        switch self {
        case .selected:
            factor = 0.66
            maximum = 2
        case .covered:
            factor = 0.56
            maximum = 1.65
        case .uncovered:
            factor = 0.46
            maximum = 1.65
        }
        return min(max(step * factor, 1), maximum)
    }
}

/// The expensive dot raster is independent from pan and zoom. Keeping it in an
/// equatable view lets SwiftUI transform the cached drawing instead of walking
/// the complete grid for every magnification update.
private struct WorldDotCanvas: View, Equatable {
    let grid: WorldDotGrid
    let layout: WorldDotMapView.Layout
    let coveredCells: Set<Int>
    let selectedCells: Set<Int>
    let colorScheme: ColorScheme

    static func == (lhs: WorldDotCanvas, rhs: WorldDotCanvas) -> Bool {
        lhs.grid.columns == rhs.grid.columns
            && lhs.grid.rows == rhs.grid.rows
            && lhs.layout.size == rhs.layout.size
            && lhs.layout.origin == rhs.layout.origin
            && lhs.layout.cell == rhs.layout.cell
            && lhs.coveredCells == rhs.coveredCells
            && lhs.selectedCells == rhs.selectedCells
            && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        Canvas { context, _ in
            guard !grid.isEmpty else { return }

            for index in grid.landCells {
                let center = layout.center(
                    column: index % grid.columns,
                    row: index / grid.columns
                )
                let appearance = appearance(for: index)
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: center.x - appearance.diameter / 2,
                            y: center.y - appearance.diameter / 2,
                            width: appearance.diameter,
                            height: appearance.diameter
                        )
                    ),
                    with: .color(appearance.color)
                )
            }
        }
    }

    private func appearance(for index: Int) -> (color: Color, diameter: CGFloat) {
        let style = WorldDotCellStyle.resolve(
            index: index,
            coveredCells: coveredCells,
            selectedCells: selectedCells
        )
        return (style.color(in: colorScheme), style.overviewDiameter(cell: layout.cell))
    }
}

/// Settled high-zoom rendering uses screen-space micro dots instead of
/// magnifying the cached overview bitmap. Offscreen cells are discarded before
/// subdivision, which keeps the clearer result affordable on iPad as well.
private struct WorldDotDetailCanvas: View, Animatable {
    let grid: WorldDotGrid
    let layout: WorldDotMapView.Layout
    let scale: CGFloat
    var offset: CGSize
    let coveredCells: Set<Int>
    let selectedCells: Set<Int>
    let colorScheme: ColorScheme

    /// Country selection at the detail level only changes the viewport's
    /// translation. Interpolating that translation inside the screen-space
    /// renderer keeps every micro dot at a stable visual diameter throughout
    /// the spring instead of temporarily magnifying the overview raster.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offset.width, offset.height) }
        set {
            offset = CGSize(width: newValue.first, height: newValue.second)
        }
    }

    var body: some View {
        Canvas { context, size in
            guard !grid.isEmpty else { return }

            let viewport = WorldDotMapView.Viewport(scale: scale, offset: offset)
            let screenCell = layout.cell * scale
            let subdivision = WorldDotMapView.DetailRenderer.subdivision(
                forScreenCell: screenCell
            )
            let step = screenCell / CGFloat(subdivision)
            let offsets = WorldDotMapView.DetailRenderer.offsets(forScreenCell: screenCell)
            let visibleBounds = CGRect(origin: .zero, size: size)
                .insetBy(dx: -screenCell, dy: -screenCell)

            for index in grid.landCells {
                let base = viewport.transform(
                    layout.center(
                        column: index % grid.columns,
                        row: index / grid.columns
                    ),
                    in: layout.size
                )
                guard visibleBounds.contains(base) else { continue }

                let style = WorldDotCellStyle.resolve(
                    index: index,
                    coveredCells: coveredCells,
                    selectedCells: selectedCells
                )
                let diameter = style.detailDiameter(step: step)
                let color = style.color(in: colorScheme)
                for offset in offsets {
                    let center = CGPoint(x: base.x + offset.width, y: base.y + offset.height)
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: center.x - diameter / 2,
                                y: center.y - diameter / 2,
                                width: diameter,
                                height: diameter
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

private struct WorldDotHitTarget: View {
    let item: WorldDotMapView.MarkerPlanner.Item
    let onSelect: () -> Void

    var body: some View {
        Color.clear
            .frame(width: item.isCluster ? 44 : 34, height: item.isCluster ? 44 : 34)
            .contentShape(Circle())
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.markers.map(\.title).joined(separator: "、"))
            .accessibilityValue("\(item.nodeCount) 个节点")
            .accessibilityAction {
                onSelect()
            }
            .allowsHitTesting(false)
    }
}
