import SwiftUI

/// One rendering path for protocol identity across filters, node rows and
/// sheets. Most protocols use SF Symbols; Trojan gets a purpose-built wooden
/// horse because the system library only offers a person riding a horse.
struct ProtocolGlyph: View {
    let kind: ProxyKind
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch kind.iconDescriptor {
            case .system(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
            case .trojanHorse:
                TrojanHorseShape()
                    .fill(.foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Compact classic Trojan horse: tall head, timber body, tail, outer legs,
/// central ladder, platform and two wheels. It stays legible at the 16–18 pt
/// sizes used beside protocol names and accepts the surrounding foreground
/// style just like an SF Symbol.
struct TrojanHorseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - unit / 2,
            y: rect.midY - unit / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(
                x: origin.x + x * unit,
                y: origin.y + y * unit,
                width: width * unit,
                height: height * unit
            )
        }

        var path = Path()

        // Broad wooden body.
        path.addRoundedRect(
            in: box(0.24, 0.34, 0.53, 0.30),
            cornerSize: CGSize(width: unit * 0.08, height: unit * 0.08)
        )

        // High neck, pointed ear and angular head from the supplied reference.
        path.move(to: point(0.63, 0.61))
        path.addLine(to: point(0.65, 0.35))
        path.addCurve(
            to: point(0.82, 0.03),
            control1: point(0.68, 0.18),
            control2: point(0.75, 0.08)
        )
        path.addLine(to: point(0.83, 0.13))
        path.addLine(to: point(0.90, 0.16))
        path.addLine(to: point(0.98, 0.31))
        path.addLine(to: point(0.93, 0.40))
        path.addLine(to: point(0.85, 0.34))
        path.addLine(to: point(0.77, 0.32))
        path.addLine(to: point(0.78, 0.54))
        path.addLine(to: point(0.70, 0.64))
        path.closeSubpath()

        // Thick, downward tail on the left.
        path.move(to: point(0.28, 0.42))
        path.addCurve(
            to: point(0.04, 0.60),
            control1: point(0.15, 0.28),
            control2: point(0.08, 0.38)
        )
        path.addLine(to: point(0.03, 0.70))
        path.addLine(to: point(0.14, 0.76))
        path.addLine(to: point(0.14, 0.63))
        path.addCurve(
            to: point(0.28, 0.47),
            control1: point(0.16, 0.45),
            control2: point(0.21, 0.41)
        )
        path.closeSubpath()

        // Outer wooden legs leave a clear gap for the central ladder.
        path.move(to: point(0.30, 0.60))
        path.addLine(to: point(0.41, 0.60))
        path.addLine(to: point(0.35, 0.83))
        path.addLine(to: point(0.24, 0.85))
        path.addLine(to: point(0.23, 0.75))
        path.closeSubpath()
        path.move(to: point(0.62, 0.60))
        path.addLine(to: point(0.73, 0.59))
        path.addLine(to: point(0.76, 0.84))
        path.addLine(to: point(0.65, 0.86))
        path.addLine(to: point(0.61, 0.75))
        path.closeSubpath()

        path.addPath(Self.ladderPath(in: rect))

        // Platform behind the wheels, matching the bold reference silhouette.
        path.addRect(box(0.10, 0.83, 0.80, 0.08))
        let wheelRadius = unit * 0.095
        for center in Self.wheelCenters(in: rect) {
            path.addEllipse(
                in: CGRect(
                    x: center.x - wheelRadius,
                    y: center.y - wheelRadius,
                    width: wheelRadius * 2,
                    height: wheelRadius * 2
                )
            )
        }

        return path
    }

    static func wheelCenters(in rect: CGRect) -> [CGPoint] {
        let unit = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - unit / 2,
            y: rect.midY - unit / 2
        )
        return [0.29, 0.73].map { x in
            CGPoint(x: origin.x + x * unit, y: origin.y + 0.87 * unit)
        }
    }

    static func ladderPath(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - unit / 2,
            y: rect.midY - unit / 2
        )
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(
                x: origin.x + x * unit,
                y: origin.y + y * unit,
                width: width * unit,
                height: height * unit
            )
        }

        var path = Path()
        path.addRect(box(0.43, 0.58, 0.035, 0.32))
        path.addRect(box(0.54, 0.58, 0.035, 0.32))
        for y in [0.66, 0.74, 0.82] {
            path.addRect(box(0.43, y, 0.145, 0.035))
        }
        return path
    }
}
