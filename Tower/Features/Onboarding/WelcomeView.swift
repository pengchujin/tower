import SwiftUI

/// The first thing a new user sees.
///
/// Tower asks for a subscription link, which is the single most sensitive
/// thing an airport gives a customer — a link that carries the account. Asking
/// for it before saying where it goes is the wrong order, so this screen makes
/// the promise first and in the user's own terms: nothing leaves the device.
///
/// It is a statement of fact rather than marketing, so every claim here names
/// the mechanism behind it and the repository that can be read to check it.
struct WelcomeView: View {
    /// Where the source actually lives. Shown in full rather than hidden
    /// behind a word, because "open source" is only worth anything if the
    /// reader can go and look.
    static let repositoryURL = URL(string: "https://github.com/pengchujin/tower")!

    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var didContinue = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 48)
                        .padding(.bottom, 36)

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(Self.promises.enumerated()), id: \.element.id) { index, promise in
                            row(for: promise)
                                .modifier(EntranceModifier(
                                    isVisible: hasAppeared,
                                    // A short stagger reads as one list arriving
                                    // rather than four separate animations.
                                    delay: reduceMotion ? 0 : 0.06 * Double(index) + 0.12,
                                    reduceMotion: reduceMotion
                                ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background {
            // Kept still and very low contrast: a moving or busy background
            // behind a privacy promise reads as decoration over substance.
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("您的节点不会被泄露")
                    // Large text reads too loose at default tracking, so it is
                    // tightened here and left alone in the body copy below.
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.6)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("塔台在本机把订阅转换成各客户端配置，订阅地址和节点不会上传。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(EntranceModifier(isVisible: hasAppeared, delay: 0, reduceMotion: reduceMotion))
    }

    /// The source row is a link; the rest are statements. Both use the same
    /// row so the list reads as one set of claims rather than a list plus an
    /// advertisement.
    @ViewBuilder
    private func row(for promise: Promise) -> some View {
        if promise.id == Self.sourceRowID {
            Link(destination: Self.repositoryURL) {
                PromiseRow(promise: promise, trailing: Self.repositoryURL.absoluteString)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel(Text("在浏览器中打开源代码仓库"))
        } else {
            PromiseRow(promise: promise)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                didContinue = true
                onContinue()
            } label: {
                PrimaryActionLabel(title: "开始使用", symbol: "arrow.right")
            }
            .buttonStyle(ResponsivePressButtonStyle())
            // The commit moment, and the only haptic on this screen.
            .sensoryFeedback(.success, trigger: didContinue)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background {
            // Floating chrome the content scrolls under, rather than an opaque
            // strip that eats a fixed band of the screen.
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Content

    struct Promise: Identifiable {
        let id: String
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    static let sourceRowID = "source"

    /// Four claims, each naming the mechanism rather than the adjective. The
    /// repository comes second, right after the promise it lets you verify —
    /// an open-source claim is only worth anything next to the thing to check.
    static let promises: [Promise] = [
        Promise(
            id: "local",
            symbol: "iphone.gen3",
            title: "转换在本机完成",
            detail: "订阅解析和配置生成都在这台设备上，不经过第三方转换服务。"
        ),
        Promise(
            id: sourceRowID,
            symbol: "chevron.left.forwardslash.chevron.right",
            title: "代码是公开的",
            detail: "上面这些都可以自己去代码里核对。"
        ),
        Promise(
            id: "offline",
            symbol: "globe.asia.australia",
            title: "地区识别不联网",
            detail: "先看节点名字，看不出来才查随 App 打包的离线 IP 库。"
        ),
        Promise(
            id: "network",
            symbol: "antenna.radiowaves.left.and.right",
            title: "只在您按下时联网",
            detail: "只有取订阅和您主动刷新规则时才发请求。"
        )
    ]
}

/// One claim: an icon, a title, and the mechanism behind it.
///
/// Shared with Settings so the first-launch page and the "安全与开源" card
/// cannot drift apart — a privacy promise that says two different things in
/// two places is worse than one that is only shown once.
struct PromiseRow: View {
    let promise: WelcomeView.Promise
    /// Shown verbatim under the detail. Only the source row uses it, to print
    /// the repository address in full rather than hide it behind a word.
    var trailing: String?

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: promise.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(promise.title)
                    .font(.headline)
                Text(promise.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fades a row in from slightly below, or plain cross-fades it when the system
/// asks for reduced motion.
private struct EntranceModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2).delay(delay)
                    // Critically damped: nothing here was thrown by a gesture,
                    // so there is no momentum to justify an overshoot.
                    : .spring(response: 0.45, dampingFraction: 1).delay(delay),
                value: isVisible
            )
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
