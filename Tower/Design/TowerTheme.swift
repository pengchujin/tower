import SwiftUI

enum TowerTheme {
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 16
    static let pagePadding: CGFloat = 18

    static let background = LinearGradient(
        colors: [
            Color(uiColor: .systemGroupedBackground),
            Color.accentColor.opacity(0.075),
            Color(uiColor: .systemGroupedBackground)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func color(named name: String) -> Color {
        switch name {
        case "indigo": .indigo
        case "orange": .orange
        case "purple": .purple
        case "cyan": .cyan
        default: .accentColor
        }
    }
}

struct TowerCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(reduceTransparency ? 0 : 0.28), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.055), radius: 18, y: 8)
    }
}

extension View {
    func towerCard() -> some View {
        modifier(TowerCardModifier())
    }
}

struct ResponsivePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.28, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

struct PrimaryActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.headline)
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrivacyBadge: View {
    var body: some View {
        Label("全部在这台设备上处理", systemImage: "lock.shield.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.green.opacity(0.1), in: Capsule())
    }
}

struct MetricPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
            .padding(.horizontal)
    }
}
