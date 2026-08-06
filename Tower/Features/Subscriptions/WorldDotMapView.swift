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
    static let minimumLatitude = -60.0
    static let maximumLatitude = 84.0

    static let shared: WorldDotGrid = load() ?? WorldDotGrid(columns: 0, rows: 0, land: [])

    var isEmpty: Bool { columns == 0 || rows == 0 }

    func isLand(column: Int, row: Int) -> Bool {
        guard column >= 0, column < columns, row >= 0, row < rows else { return false }
        return land[row * columns + column]
    }

    /// Equirectangular projection into unit space, clamped to the drawn band.
    static func unitPoint(latitude: Double, longitude: Double) -> CGPoint {
        let x = (longitude + 180) / 360
        let span = maximumLatitude - minimumLatitude
        let y = (maximumLatitude - latitude) / span
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
            // Tolerate a short final row rather than losing the whole grid.
            if line.count < columns {
                cells.append(contentsOf: Array(repeating: false, count: columns - line.count))
            }
        }

        guard columns > 0, rows > 0, cells.count >= columns * rows else { return nil }
        return WorldDotGrid(columns: columns, rows: rows, land: Array(cells.prefix(columns * rows)))
    }
}

/// A flat dot-matrix world map. Replaces the MapKit globe, which was heavy to
/// render and offered far more interaction than a node overview needs.
struct WorldDotMapView<Marker: View>: View {
    let markers: [WorldDotMarker]
    @ViewBuilder let marker: (WorldDotMarker) -> Marker

    private let grid = WorldDotGrid.shared

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, grid: grid)

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

                ForEach(markers) { entry in
                    marker(entry)
                        .position(layout.position(for: entry))
                }
            }
        }
    }

    /// Keeps the grid's aspect ratio and centres it, so the dots stay round and
    /// the markers land on the same cells the map drew.
    private struct Layout {
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
            let unit = WorldDotGrid.unitPoint(
                latitude: entry.latitude,
                longitude: entry.longitude
            )
            return CGPoint(
                x: origin.x + unit.x * cell * CGFloat(grid.columns),
                y: origin.y + unit.y * cell * CGFloat(grid.rows)
            )
        }
    }
}

struct WorldDotMarker: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
}
