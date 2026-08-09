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
        return parse(text)
    }

    static func parse(_ text: String) -> WorldDotGrid? {
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
        return WorldDotGrid(columns: columns, rows: rows, land: Array(cells.prefix(columns * rows)))
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

    private let grid = WorldDotGrid.shared

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, grid: grid)
            let placements = LabelPlanner.plan(
                markers: markers,
                layout: layout,
                bounds: CGRect(origin: .zero, size: geometry.size)
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard !grid.isEmpty else { return }
                    let diameter = layout.dotDiameter
                    for row in 0 ..< grid.rows {
                        for column in 0 ..< grid.columns where grid.isLand(column: column, row: row) {
                            let center = layout.center(column: column, row: row)
                            context.fill(
                                Path(
                                    ellipseIn: CGRect(
                                        x: center.x - diameter / 2,
                                        y: center.y - diameter / 2,
                                        width: diameter,
                                        height: diameter
                                    )
                                ),
                                with: .color(.primary.opacity(0.16))
                            )
                        }
                    }
                }
                .drawingGroup()

                ForEach(Array(markers.enumerated()), id: \.element.id) { index, entry in
                    let placement = placements[entry.id]
                    AnimatedWorldDotMarker(entry: entry, index: index) {
                        onSelect(entry.id)
                    }
                    .position(layout.position(for: entry))

                    if let placement {
                        Text(entry.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(entry.isSelected ? Color.green : .secondary)
                            .fixedSize()
                            .allowsHitTesting(false)
                            .position(placement)
                    }
                }
            }
        }
        // Exactly the grid's own ratio, so width and height are constrained at
        // the same time and neither direction is left with a blank band.
        .aspectRatio(grid.aspectRatio, contentMode: .fit)
    }

    /// Keeps the grid's aspect ratio and centres it, so the dots stay round and
    /// the markers land on the same cells the map drew.
    struct Layout {
        let origin: CGPoint
        let cell: CGFloat
        let grid: WorldDotGrid

        init(size: CGSize, grid: WorldDotGrid) {
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

        func position(for entry: WorldDotMarker) -> CGPoint {
            let unit = WorldDotGrid.unitPoint(latitude: entry.latitude, longitude: entry.longitude)
            return CGPoint(
                x: origin.x + unit.x * cell * CGFloat(grid.columns),
                y: origin.y + unit.y * cell * CGFloat(grid.rows)
            )
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

        static func plan(
            markers: [WorldDotMarker],
            layout: Layout,
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
                let anchor = layout.position(for: marker)
                let size = CGSize(
                    width: CGFloat(marker.title.count) * characterWidth,
                    height: labelHeight
                )
                let vertical = size.height / 2 + 7
                let candidates = [
                    CGPoint(x: anchor.x, y: anchor.y - vertical),
                    CGPoint(x: anchor.x, y: anchor.y + vertical)
                ]

                for candidate in candidates {
                    let rect = CGRect(
                        x: candidate.x - size.width / 2,
                        y: candidate.y - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                    guard bounds.contains(rect) else { continue }
                    guard !placed.contains(where: { $0.intersects(rect.insetBy(dx: -2, dy: -1)) }) else {
                        continue
                    }
                    placed.append(rect)
                    result[marker.id] = candidate
                    break
                }
            }
            return result
        }
    }
}

private struct AnimatedWorldDotMarker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: WorldDotMarker
    let index: Int
    let onSelect: () -> Void
    @State private var isVisible = false

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: entry.isSelected ? 5 : 0)
                        .padding(-3)
                }
                .scaleEffect(entry.isSelected ? 1.3 : 1)
                // The visual dot stays small while the hit target remains easy.
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.92))
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.14)
                : .spring(response: 0.32, dampingFraction: 1),
            value: entry.isSelected
        )
        .accessibilityLabel(entry.title)
        .task(id: entry.id) {
            if !reduceMotion {
                let delay = min(Double(index) * 0.025, 0.2)
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.14)
                    : .spring(response: 0.36, dampingFraction: 1)
            ) {
                isVisible = true
            }
        }
    }
}
