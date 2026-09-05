import SwiftUI

enum TowerTheme {
    static let cornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 16
    static let pagePadding: CGFloat = 18
    static let actionBarButtonHeight: CGFloat = 50
    static let actionBarButtonCornerRadius: CGFloat = 16

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

/// A small shared motion vocabulary for Tower's high-frequency controls.
/// Keeping these transitions short and non-bouncy makes selection feel direct
/// on both iPhone and iPad, while still preserving state continuity.
enum TowerMotion {
    static let pressInDuration = 0.10
    static let pressReleaseDuration = 0.16
    static let selectionDuration = 0.16
    static let disclosureResponse = 0.28
    static let reducedMotionDuration = 0.14

    static func pressScale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? 0.97 : 1
    }

    static func pressAnimation(isPressed: Bool, reduceMotion: Bool) -> Animation {
        .easeOut(
            duration: reduceMotion
                ? 0.10
                : (isPressed ? pressInDuration : pressReleaseDuration)
        )
    }

    static func selectionSymbolScale(isSelected: Bool, reduceMotion: Bool) -> CGFloat {
        isSelected || reduceMotion ? 1 : 0.92
    }

    static func selection(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reducedMotionDuration : selectionDuration)
    }

    static func disclosure(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: reducedMotionDuration)
            : .interactiveSpring(response: disclosureResponse, dampingFraction: 1)
    }
}

struct TowerCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
            .geometryGroup()
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
            .scaleEffect(
                TowerMotion.pressScale(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                TowerMotion.pressAnimation(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
    }
}

/// Press feedback for controls whose surrounding text must remain stationary.
/// Only the control's contrast changes; there is no geometry transform.
struct SelectionIndicatorButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(
                TowerMotion.pressAnimation(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
    }
}

struct PrimaryActionLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.headline)
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity, minHeight: TowerTheme.actionBarButtonHeight)
        .padding(.horizontal, 14)
        .foregroundStyle(.white)
        .background(
            Color.accentColor,
            in: RoundedRectangle(
                cornerRadius: TowerTheme.actionBarButtonCornerRadius,
                style: .continuous
            )
        )
    }
}

struct SectionHeading: View {
    let title: LocalizedStringKey
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let detail {
                // Verbatim on purpose. A `LocalizedStringKey` built from a
                // runtime string is invisible to Xcode's extractor, so a
                // literal passed here never reached the catalog and rendered
                // in Chinese in the other fourteen languages — with
                // `check_localization.sh` still reporting PASS. Callers pass
                // `String(localized:)`, which the extractor does see, or a
                // value that is not translatable at all such as a file name.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(
                    reduceMotion ? .opacity : .numericText(value: Double(value))
                )
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.14)
                        : .spring(response: 0.34, dampingFraction: 1),
                    value: value
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: toast.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(accentColor.gradient, in: Circle())

            Text(toast.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(accentColor.opacity(toast.tone == .success ? 0.14 : 0.05))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(accentColor.opacity(toast.tone == .success ? 0.55 : 0.24), lineWidth: 1)
        }
        .shadow(color: accentColor.opacity(toast.tone == .success ? 0.2 : 0.1), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(toast.tone == .success ? .success : .selection, trigger: toast.id)
        .padding(.horizontal)
    }

    private var accentColor: Color {
        toast.tone == .success ? .green : .accentColor
    }
}

/// The round checkmark the rule list marks its selection with.
///
/// Shared so the subscription list can use the same mark: both are "this one
/// counts" choices, and a switch beside a checkmark read as two unrelated
/// controls doing the same job.
struct SelectionIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: isSelected)
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: isSelected)
            Image(systemName: "checkmark")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(
                    TowerMotion.selectionSymbolScale(
                        isSelected: isSelected,
                        reduceMotion: reduceMotion
                    )
                )
                .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: isSelected)
        }
        .frame(width: 25, height: 25)
        .padding(.top, 2)
    }
}

/// Draws a `Toggle` as that same checkmark.
///
/// A style rather than a plain Button so VoiceOver still announces the control
/// as a switch that is on or off — a subscription really is an independent
/// on/off, unlike the rule list where picking one deselects the rest.
///
/// A custom style owns its own accessibility, and the style cannot turn the
/// configuration's label view into the `Text` that `accessibilityLabel` wants,
/// so callers name the control themselves.
struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            SelectionIndicator(isSelected: configuration.isOn)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SelectionIndicatorButtonStyle())
        .accessibilityAddTraits(.isToggle)
        // Every other choice in the app taps back — the tab bar, the rule
        // list, the client picker. This one was the exception.
        .sensoryFeedback(.selection, trigger: configuration.isOn)
    }
}
