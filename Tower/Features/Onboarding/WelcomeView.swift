import SwiftUI

/// Replayable introduction; its examples never access user data or request permissions.
struct WelcomeView: View {
    static let repositoryURL = URL(string: "https://github.com/pengchujin/tower")!
    var onContinue: () -> Void
    private let readableContentWidth: CGFloat = TowerPlatform.isMac ? 760 : 680
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var page = 0
    @State private var dragStartPage: Int?
    @Namespace private var journeyNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("使用引导").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("跳过", action: onContinue)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(ResponsivePressButtonStyle())
                    .accessibilityIdentifier("onboarding-skip")
            }
            .padding(.horizontal, 26)
            journey
            if reduceMotion {
                WelcomePageContent(page: page, isActive: true)
                    .id(page)
                    .transition(.opacity)
            } else {
                TabView(selection: $page) {
                    ForEach(0..<4) { index in
                        WelcomePageContent(page: index, isActive: page == index)
                            .tag(index)

                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .onChanged { _ in
                        if dragStartPage == nil { dragStartPage = page }
                    }
                    .onEnded { value in
                        let source = dragStartPage ?? page
                        dragStartPage = nil
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        let forward = layoutDirection == .rightToLeft ? dx > 0 : dx < 0
                        move(to: source + (forward ? 1 : -1))
                    })
            }
            footer
        }
        .frame(maxWidth: readableContentWidth)
        // Keep the desktop journey together instead of pinning its controls
        // to the bottom of a tall window, far away from the example.
        .frame(maxHeight: TowerPlatform.isMac ? 760 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TowerTheme.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: page)
    }

    private var journey: some View {
        HStack(spacing: 8) {
            journeyItem("添加订阅", symbol: "link", step: 1)
            Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(.tertiary)
            journeyItem("选择规则", symbol: "line.3.horizontal.decrease", step: 2)
            Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(.tertiary)
            journeyItem("导出使用", symbol: "paperplane", step: 3)
        }
        .padding(.horizontal, 26).padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func journeyItem(_ title: LocalizedStringKey, symbol: String, step: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: page > step ? "checkmark" : symbol)
                .contentTransition(.symbolEffect(.replace))
            Text(title).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(page == step ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background {
            if page == step {
                if reduceMotion {
                    Capsule().fill(Color.accentColor.opacity(0.1))
                } else {
                    Capsule().fill(Color.accentColor.opacity(0.1))
                        .matchedGeometryEffect(id: "journey", in: journeyNamespace)
                }
            }
        }
        .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: page)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Circle().fill(Color.secondary.opacity(0.18)).frame(width: 7, height: 7)
                        .frame(width: 24)
                        .overlay {
                            if reduceMotion {
                                Capsule().fill(Color.accentColor).frame(width: 24, height: 7)
                                    .opacity(page == index ? 1 : 0)
                            }
                        }
                }
            }
            .overlay(alignment: .leading) {
                if !reduceMotion {
                    Capsule().fill(Color.accentColor).frame(width: 24, height: 7)
                        .offset(x: CGFloat(page * 30) * (layoutDirection == .rightToLeft ? -1 : 1))
                }
            }
            .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("第 \(page + 1) 页，共 4 页"))

            HStack(spacing: 12) {
                Button { changePage(by: -1) } label: {
                    Image(systemName: "arrow.backward")
                        .font(.title3.weight(.semibold))
                        .frame(width: 54, height: 54)
                        .foregroundStyle(page == 0 ? Color.secondary.opacity(0.35) : Color.accentColor)
                        .background(Color.accentColor.opacity(page == 0 ? 0.035 : 0.09),
                                    in: RoundedRectangle(cornerRadius: TowerTheme.actionBarButtonCornerRadius))
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .disabled(page == 0)
                .accessibilityLabel("上一步")
                .accessibilityIdentifier("onboarding-back")
                Button {
                    if page == 3 { onContinue() } else { changePage(by: 1) }
                } label: {
                    HStack(spacing: 12) {
                        Text(page == 3 ? "开始使用" : "下一步")
                            .contentTransition(.opacity)
                        Image(systemName: "arrow.forward")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(Color.accentColor.gradient,
                                in: RoundedRectangle(cornerRadius: TowerTheme.actionBarButtonCornerRadius))
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityIdentifier("onboarding-next")
            }
        }
        .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 12)
        .background {
            if !TowerPlatform.isMac { Rectangle().fill(.regularMaterial) }
        }
    }

    private func changePage(by offset: Int) {
        move(to: page + offset)
    }

    private func move(to target: Int) {
        let destination = min(3, max(0, target))
        guard destination != page else { return }
        withAnimation(reduceMotion ? .easeOut(duration: TowerMotion.reducedMotionDuration)
                      : .spring(duration: 0.5, bounce: 0.2)) {
            page = destination
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

    /// Detailed privacy explanations remain available in Settings.
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
            title: "联网选项由您决定",
            detail: "自动更新和 iCloud 同步默认关闭，只有您主动开启后才运行。"
        )
    ]
}

/// An explanation in the Settings "安全与开源" card.
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

#Preview {
    WelcomeView(onContinue: {})
}

private struct WelcomePageContent: View {
    let page: Int
    let isActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                introductionHeading.padding(.top, 12)
                scene
            }
            .padding(.horizontal, 26).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var introductionHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding-title")
            Text(detail)
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Each page acts out what it describes instead of fading in a picture
    /// of it: the scene is the explanation.
    @ViewBuilder private var scene: some View {
        switch page {
        case 0: WelcomeOverviewScene(isActive: isActive)
        case 1: WelcomeSubscriptionScene(isActive: isActive)
        case 2: WelcomeRoutingScene(isActive: isActive)
        default: WelcomeExportExample(isActive: isActive)
        }
    }

    private var title: LocalizedStringKey {
        switch page {
        case 0: "你的订阅，一处打理"
        case 1: "先添加订阅或节点"
        case 2: "选一套分流规则"
        default: "交给你常用的客户端"
        }
    }

    private var detail: LocalizedStringKey {
        switch page {
        case 0: "塔台帮你管理订阅和自有节点，搭配分流规则，生成适合不同客户端的配置。"
        case 1: "在「订阅」页点右上角加号，粘贴订阅或节点链接，也可以扫码、手动添加。勾选你想导出的订阅和节点。"
        case 2: "在「规则」页选择内置方案，就能决定哪些网站走代理、哪些直连。初次使用可以先选 ACL4SSR 默认。"
        default: "在「导出」页选择客户端，导出完整配置或仅节点。导入完成后，前往客户端选择配置并开启连接。"
        }
    }
}

// MARK: - Scene loop

/// Plays an explanatory scene on the visible page only.
///
/// The pager preloads its neighbours; those hold the scene's opening frame, so
/// a swipe lands on a scene that starts from exactly what was already on
/// screen. With Reduce Motion the finished frame is shown, still: the result
/// is what explains, the movement only shows how it got there.
///
/// Nothing inside a scene may run open-ended (a repeating symbol effect, a
/// spinner started in the phase's transaction): PhaseAnimator advances only
/// when the step's animations finish, and one that never ends stalls the loop.
private struct WelcomeSceneLoop<Phase: Equatable, Content: View>: View {
    let phases: [Phase]
    let finished: Phase
    let isActive: Bool
    let animation: (Phase) -> Animation?
    @ViewBuilder let content: (Phase) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(finished)
        } else if isActive {
            PhaseAnimator(phases, content: content, animation: animation)
        } else {
            content(phases[0])
        }
    }
}

/// A dashed track with an accent stroke that draws along it.
private struct FlowLine: View {
    let from: CGPoint
    let to: CGPoint
    let progress: CGFloat
    var tint: Color = .accentColor

    var body: some View {
        let curve = FlowCurve(from: from, to: to)
        ZStack {
            curve.stroke(Color.secondary.opacity(0.18),
                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
            curve.trim(from: 0, to: progress)
                .stroke(tint.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct FlowCurve: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let middle = (from.x + to.x) / 2
        path.addCurve(to: to,
                      control1: CGPoint(x: middle, y: from.y),
                      control2: CGPoint(x: middle, y: to.y))
        return path
    }
}

private struct SceneChip: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct SceneDocument: View {
    var body: some View {
        Image(systemName: "doc.text.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(6)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

private struct SceneClientIcon: View {
    let client: ClientTarget
    var size: CGFloat = 40

    var body: some View {
        if let asset = client.appIconAssetName {
            Image(asset).resizable().scaledToFit()
                .scaleEffect(client.appIconFillScale)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                // The name is always written next to it; VoiceOver would
                // otherwise read the asset's name.
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Page 1: what Tower does

private enum OverviewPhase {
    case idle, gather, process, deliver, done
    /// Not part of the loop: the still frame for Reduce Motion, with inputs
    /// and finished outputs on screen together.
    case summary

    static let loop: [OverviewPhase] = [.idle, .gather, .process, .deliver, .done]

    /// The animation that carries the scene into this phase. The pauses are
    /// the delays: PhaseAnimator only moves on once the previous step lands.
    func animation(index: Int = 0) -> Animation {
        switch self {
        case .gather: .spring(duration: 0.7, bounce: 0).delay(0.8 + Double(index) * 0.08)
        case .process: .spring(duration: 0.45, bounce: 0.3)
        case .deliver: .spring(duration: 0.75, bounce: 0).delay(0.15 + Double(index) * 0.09)
        case .done: .spring(duration: 0.4, bounce: 0.35).delay(Double(index) * 0.09)
        case .idle: .easeOut(duration: 0.35).delay(1.8)
        case .summary: .default
        }
    }
}

/// Subscriptions, nodes and rules go into Tower; one configuration per
/// client comes out — on this device.
private struct WelcomeOverviewScene: View {
    let isActive: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var clients: [ClientTarget] {
        TowerPlatform.isMac ? [.surgeMac, .clashVerge, .singBox] : [.surge, .clash, .shadowrocket]
    }

    private var moreClients: [ClientTarget] {
        TowerPlatform.isMac
            ? [.clashMac, .flClash, .mihomoParty, .shadowrocket, .clashApple, .hiddify, .clash, .clashMi]
            : [.loon, .quanx, .egern, .hiddify, .v2box, .singBox, .clashMi, .anywhere]
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                WelcomeSceneLoop(phases: OverviewPhase.loop, finished: .summary, isActive: isActive,
                                 animation: { $0.animation() }) { phase in
                    OverviewDiagram(phase: phase, clients: clients)
                }
                .frame(height: 196)
                // On iPad and Mac a full-width diagram stretched its links
                // into long flat lines; the flow reads better compact.
                .frame(maxWidth: 520)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
                PrivacyBadge()
            }
            .padding(.vertical, 18).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .towerCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("支持的客户端").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(moreClients.prefix(dynamicTypeSize.isAccessibilitySize ? 5 : 8)) { client in
                        SceneClientIcon(client: client, size: 30)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .towerCard()
            .accessibilityElement(children: .combine)
        }
    }

    private var accessibilitySummary: String {
        let inputs = [String(localized: "订阅"), String(localized: "节点"), String(localized: "规则")]
        return inputs.joined(separator: ", ") + " → " + TowerBrand.localizedName + " → "
            + clients.map(\.name).joined(separator: ", ")
    }
}

private struct OverviewDiagram: View {
    let phase: OverviewPhase
    let clients: [ClientTarget]

    private let inputs: [(title: LocalizedStringKey, symbol: String)] = [
        ("订阅", "link"), ("节点", "server.rack"), ("规则", "list.bullet.rectangle")
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let hub = CGPoint(x: width / 2, y: height / 2)
            let rows = [height * 0.14, height * 0.5, height * 0.86]
            let inputX = width * 0.15
            let clientX = width * 0.86

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    FlowLine(from: CGPoint(x: inputX + 34, y: rows[index]),
                             to: CGPoint(x: hub.x - Self.hubSize / 2 - 2, y: hub.y),
                             progress: phase == .idle ? 0 : 1)
                        .animation(phase.animation(index: index), value: phase)
                    FlowLine(from: CGPoint(x: hub.x + Self.hubSize / 2 + 2, y: hub.y),
                             to: CGPoint(x: clientX - 24, y: rows[index]),
                             progress: [.deliver, .done, .summary].contains(phase) ? 1 : 0)
                        .animation(phase.animation(index: index), value: phase)
                }

                hubView.position(hub)

                ForEach(0..<3, id: \.self) { index in
                    let gathering = phase == .gather
                    SceneChip(title: inputs[index].title, symbol: inputs[index].symbol)
                        .scaleEffect(gathering ? 0.4 : 1)
                        .opacity(phase == .idle || phase == .summary ? 1 : 0)
                        // After merging, a chip returns to its column while
                        // invisible, so the next loop never shows it travel back.
                        .position(gathering ? hub : CGPoint(x: inputX, y: rows[index]))
                        .animation(phase.animation(index: index), value: phase)
                }

                ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                    SceneClientIcon(client: client)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white, .green)
                                .background(Circle().fill(.white).padding(2))
                                .offset(x: 5, y: 5)
                                .scaleEffect([.done, .summary].contains(phase) ? 1 : 0.4)
                                .opacity([.done, .summary].contains(phase) ? 1 : 0)
                        }
                        .position(x: clientX, y: rows[index])
                        .animation(phase.animation(index: index), value: phase)
                }

                ForEach(0..<3, id: \.self) { index in
                    let travelling = [.deliver, .done].contains(phase)
                    SceneDocument()
                        .scaleEffect(phase == .process ? 0.6 : (phase == .done ? 0.5 : 1))
                        .opacity([.process, .deliver].contains(phase) ? 1 : 0)
                        .position(travelling ? CGPoint(x: clientX, y: rows[index]) : hub)
                        .animation(phase.animation(index: index), value: phase)
                }
            }
        }
    }

    private static let hubSize: CGFloat = 76

    /// Tower's own icon at the centre: the thing in the middle of the diagram
    /// is the app the person is about to use, not an abstract symbol.
    private var hubView: some View {
        let shape = RoundedRectangle(cornerRadius: Self.hubSize * 0.2237, style: .continuous)
        return ZStack {
            shape
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: Self.hubSize, height: Self.hubSize)
                .scaleEffect(phase == .process ? 1.5 : 1)
                .opacity(phase == .gather ? 0.5 : 0)
            Image("TowerLogo")
                .resizable()
                .scaledToFill()
                .frame(width: Self.hubSize, height: Self.hubSize)
                // The artwork carries its own smaller corners; the system
                // icon mask is larger and hides them.
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
                .shadow(color: Color.accentColor.opacity(phase == .process ? 0.4 : 0.16),
                        radius: phase == .process ? 16 : 8, y: 4)
                .scaleEffect(phase == .process ? 1.08 : 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Page 2: adding a subscription

private enum AddPhase: CaseIterable {
    case empty, press, pasted, recognized, nodes, measured, chosen

    func animation(index: Int = 0) -> Animation {
        switch self {
        case .press: .easeOut(duration: 0.2).delay(0.7)
        // Linear, because the link reads as text arriving left to right.
        case .pasted: .linear(duration: 0.5).delay(0.1)
        case .recognized: .spring(duration: 0.4, bounce: 0.2).delay(0.25)
        case .nodes: .spring(duration: 0.5, bounce: 0.15).delay(0.35 + Double(index) * 0.08)
        case .measured: .easeOut(duration: 0.25).delay(0.6 + Double(index) * 0.15)
        case .chosen: .spring(duration: 0.35, bounce: 0.3).delay(0.8)
        case .empty: .easeOut(duration: 0.3).delay(2)
        }
    }

    func reached(_ other: AddPhase) -> Bool {
        let order = Self.allCases
        return order.firstIndex(of: self)! >= order.firstIndex(of: other)!
    }
}

/// A paste becomes a recognised link, the link becomes nodes, the nodes get
/// measured, and one is left out of the export.
private struct WelcomeSubscriptionScene: View {
    let isActive: Bool

    var body: some View {
        WelcomeSceneLoop(phases: AddPhase.allCases, finished: .chosen, isActive: isActive,
                         animation: { $0.animation() }) { phase in
            AddSourceDiagram(phase: phase)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        [String(localized: "粘贴识别"), String(localized: "已识别为订阅链接"), String(localized: "我的订阅"),
         [String(localized: "香港"), String(localized: "日本"), String(localized: "新加坡")].joined(separator: ", ")]
            .joined(separator: " · ")
    }
}

private struct AddSourceDiagram: View {
    let phase: AddPhase

    private let nodes: [(flag: String, region: LocalizedStringKey, latency: String)] = [
        ("🇭🇰", "香港", "38 ms"), ("🇯🇵", "日本", "62 ms"), ("🇸🇬", "新加坡", "85 ms")
    ]

    var body: some View {
        VStack(spacing: 12) {
            inputCard
            Image(systemName: "arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(phase.reached(.recognized) ? 1 : 0.25)
                .offset(y: phase.reached(.nodes) ? 0 : -3)
            nodesCard
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                modeChip("粘贴识别", symbol: "doc.on.clipboard", selected: true)
                    .scaleEffect(phase == .press ? 0.94 : 1)
                    .overlay {
                        // Where the finger lands, then lifts.
                        Circle()
                            .fill(Color.accentColor.opacity(0.28))
                            .frame(width: 38, height: 38)
                            .scaleEffect(phase == .empty ? 0.4 : (phase == .press ? 1 : 1.9))
                            .opacity(phase == .press ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                modeChip("扫码", symbol: "qrcode.viewfinder", selected: false)
                modeChip("手动添加", symbol: "square.and.pencil", selected: false)
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            ZStack(alignment: .leading) {
                Text("粘贴订阅链接或节点协议")
                    .font(.caption).foregroundStyle(.tertiary)
                    .opacity(phase.reached(.pasted) ? 0 : 1)
                Text(verbatim: "https://example.com/subscribe")
                    .font(.caption.monospaced())
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width * (phase.reached(.pasted) ? 1 : 0))
                        }
                    }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.green.opacity(phase.reached(.recognized) ? 0.7 : 0), lineWidth: 1.5)
            }

            Label("已识别为订阅链接", systemImage: "link.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(phase.reached(.recognized) ? 1 : 0)
                .offset(y: phase.reached(.recognized) ? 0 : -4)
        }
        .padding(16)
        .towerCard()
    }

    private func modeChip(_ title: LocalizedStringKey, symbol: String, selected: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
            }
    }

    private var nodesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("我的订阅", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(nodes.count) 个节点")
                    .font(.caption).foregroundStyle(.secondary)
                    .opacity(phase.reached(.nodes) ? 1 : 0)
            }
            Divider()
            ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                let excluded = index == nodes.count - 1 && phase == .chosen
                HStack(spacing: 10) {
                    Text(verbatim: node.flag).font(.title3)
                    Text(node.region).font(.subheadline.weight(.medium))
                    Spacer()
                    ZStack(alignment: .trailing) {
                        ProgressView().controlSize(.mini)
                            .opacity(phase == .nodes ? 1 : 0)
                        Text(verbatim: node.latency)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.green)
                            .opacity(phase.reached(.measured) ? 1 : 0)
                    }
                    .frame(width: 52, alignment: .trailing)
                    Image(systemName: excluded ? "circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(excluded ? Color.secondary : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .opacity(phase.reached(.nodes) ? (excluded ? 0.45 : 1) : 0)
                .offset(y: phase.reached(.nodes) ? 0 : -10)
                .animation(phase.animation(index: index), value: phase)
            }
        }
        .padding(16)
        .towerCard()
    }
}

// MARK: - Page 3: routing

private struct RoutingRequest {
    let domain: String
    let symbol: String
    let category: LocalizedStringResource
    let lane: RoutingLane
}

private enum RoutingLane: Int, CaseIterable {
    /// AI gets its own group pinned to another region: the usual reason a
    /// scheme splits it from general proxy traffic.
    case proxy, ai, direct, reject

    /// "AI" is the group's name in every language, so it is not localized.
    var title: String {
        switch self {
        case .proxy: String(localized: "代理")
        case .ai: "AI"
        case .direct: String(localized: "直连")
        case .reject: String(localized: "拦截")
        }
    }

    var tint: Color {
        switch self {
        case .proxy: .indigo
        case .ai: .purple
        case .direct: .teal
        case .reject: .orange
        }
    }
}

/// Requests reach the selected scheme one at a time; it names the rule each
/// one matches and sends it down the proxy, direct or block lane.
private struct WelcomeRoutingScene: View {
    let isActive: Bool

    fileprivate static let requests: [RoutingRequest] = [
        RoutingRequest(domain: "youtube.com", symbol: "play.rectangle.fill", category: "国外媒体", lane: .proxy),
        RoutingRequest(domain: "chatgpt.com", symbol: "sparkles", category: "AI 平台", lane: .ai),
        RoutingRequest(domain: "taobao.com", symbol: "bag.fill", category: "国内网站", lane: .direct),
        RoutingRequest(domain: "ads.example", symbol: "megaphone.fill", category: "广告请求", lane: .reject)
    ]

    /// 0 resets; request i stops at the scheme on 2i+1 and reaches its lane on 2i+2.
    private static let phases = Array(0...(requests.count * 2))
    /// Outside the loop: Reduce Motion's still frame, every route at once.
    fileprivate static let summary = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeSceneLoop(phases: Self.phases, finished: Self.summary, isActive: isActive,
                             animation: Self.animation) { phase in
                RoutingDiagram(phase: phase, requests: Self.requests)
            }
            .frame(height: 236)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16).padding(.horizontal, 10)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .towerCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("选择方案后，还可以按需调整策略组。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func animation(_ phase: Int) -> Animation {
        if phase == 0 { return .easeOut(duration: 0.3).delay(1.8) }
        if phase.isMultiple(of: 2) {
            // A pause at the scheme first, long enough to read the rule.
            return .spring(duration: 0.55, bounce: 0.1).delay(0.65)
        }
        return .spring(duration: 0.5, bounce: 0).delay(phase == 1 ? 0.6 : 0.15)
    }

    private var accessibilitySummary: String {
        Self.requests
            .map { "\(String(localized: $0.category)) → \($0.lane.title)" }
            .joined(separator: ", ")
    }
}

private struct RoutingDiagram: View {
    let phase: Int
    let requests: [RoutingRequest]

    /// The request currently held at the scheme, if any.
    private var matching: RoutingRequest? {
        guard phase % 2 == 1 else { return nil }
        return requests[(phase - 1) / 2]
    }

    /// The lane a request is arriving in during this phase, if any.
    private var receivingLane: RoutingLane? {
        guard phase > 0, phase.isMultiple(of: 2) else { return nil }
        return requests[(phase - 2) / 2].lane
    }

    private var isSummary: Bool { phase == WelcomeRoutingScene.summary }

    private func arrivedCount(in lane: RoutingLane) -> Int {
        requests.indices.filter { requests[$0].lane == lane && (isSummary || phase >= $0 * 2 + 2) }.count
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let gate = CGPoint(x: width * 0.5, y: height / 2)
            let lanes = RoutingLane.allCases.map { height * (0.11 + CGFloat($0.rawValue) * 0.26) }
            let startX = width * 0.16
            let laneX = width * 0.85

            ZStack {
                if isSummary {
                    ForEach(requests.indices, id: \.self) { index in
                        FlowLine(from: CGPoint(x: startX + 44, y: summaryY(index, height: height)),
                                 to: CGPoint(x: gate.x - 48, y: gate.y), progress: 1)
                    }
                } else {
                    FlowLine(from: CGPoint(x: startX + 40, y: gate.y), to: CGPoint(x: gate.x - 48, y: gate.y),
                             progress: phase == 0 ? 0 : 1)
                }
                ForEach(RoutingLane.allCases, id: \.rawValue) { lane in
                    FlowLine(from: CGPoint(x: gate.x + 48, y: gate.y),
                             to: CGPoint(x: laneX - 42, y: lanes[lane.rawValue]),
                             progress: isSummary || receivingLane == lane ? 1 : 0,
                             tint: lane.tint)
                }

                ForEach(Array(requests.enumerated()), id: \.offset) { index, request in
                    let atScheme = phase == index * 2 + 1
                    let arriving = phase == index * 2 + 2
                    let delivered = phase != 0 && phase >= index * 2 + 2
                    // Drawn under the scheme and the lanes: a request passes
                    // through the rule and slips into its lane, out of sight.
                    requestChip(request)
                        .scaleEffect(isSummary ? 0.9 : (delivered ? 0.45 : 1))
                        .opacity(isSummary || atScheme || arriving ? 1 : 0)
                        .position(isSummary
                                  ? CGPoint(x: startX, y: summaryY(index, height: height))
                                  : delivered
                                  ? CGPoint(x: laneX, y: lanes[request.lane.rawValue])
                                  : CGPoint(x: atScheme ? startX : startX - 24, y: gate.y))
                }

                gateView.position(gate)

                ForEach(RoutingLane.allCases, id: \.rawValue) { lane in
                    laneView(lane).position(x: laneX, y: lanes[lane.rawValue])
                }
            }
        }
    }

    private func summaryY(_ index: Int, height: CGFloat) -> CGFloat {
        height * (0.14 + CGFloat(index) * 0.24)
    }

    private func requestChip(_ request: RoutingRequest) -> some View {
        HStack(spacing: 5) {
            Image(systemName: request.symbol).font(.caption2.weight(.bold))
            Text(verbatim: request.domain).font(.caption2.weight(.semibold).monospaced())
        }
        .lineLimit(1)
        .foregroundStyle(.primary)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var gateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("ACL4SSR 默认")
                .font(.caption2.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.7)
            ZStack {
                Text("服务 → 策略").opacity(matching == nil ? 1 : 0)
                ForEach(Array(requests.enumerated()), id: \.offset) { index, request in
                    Text(request.category)
                        .foregroundStyle(request.lane.tint)
                        .opacity(phase == index * 2 + 1 ? 1 : 0)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 96, height: 92)
        .background(Color.accentColor.opacity(matching == nil ? 0.06 : 0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(matching == nil ? 0.15 : 0.5), lineWidth: 1.5)
        }
        .scaleEffect(matching == nil ? 1 : 1.04)
    }

    private func laneView(_ lane: RoutingLane) -> some View {
        let count = arrivedCount(in: lane)
        return HStack(spacing: 5) {
            Group {
                switch lane {
                case .proxy: Text(verbatim: "🇭🇰")
                case .ai: Text(verbatim: "🇸🇬")
                case .direct: Image(systemName: "house.fill")
                case .reject: Image(systemName: "nosign")
                }
            }
            .font(.caption.weight(.bold))
            Text(verbatim: lane.title).font(.caption.weight(.semibold))
            Text(verbatim: "\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
                .foregroundStyle(.white)
                .frame(minWidth: 16, minHeight: 16)
                .background(lane.tint, in: Circle())
                .opacity(count > 0 ? 1 : 0)
        }
        .lineLimit(1)
        .foregroundStyle(lane.tint)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(lane.tint.opacity(receivingLane == lane ? 0.22 : 0.1), in: Capsule())
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .scaleEffect(receivingLane == lane ? 1.08 : 1)
    }
}

// MARK: - Page 4: export

/// A local, interactive sample. It never generates or opens a real configuration.
private struct WelcomeExportExample: View {
    let isActive: Bool
    @State private var client: ClientTarget = TowerPlatform.isMac ? .surgeMac : .shadowrocket
    /// Each change sends the chosen client's icon from its tile to the button.
    @State private var deliveries = 0
    /// Where each tile's icon and the button's icon sit, so the flight starts
    /// at the tile that was tapped rather than above the button.
    @State private var tileIconFrames: [String: CGRect] = [:]
    @State private var receiverFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var clients: [ClientTarget] {
        TowerPlatform.isMac
            ? [.surgeMac, .clashVerge, .clashMac, .singBox]
            : [.shadowrocket, .surge, .egern, .clash]
    }

    private var exportPreviewTitle: String {
        // Demonstrate the Mac subscription-copy path without probing installed
        // apps or starting an import from this replayable example.
        if TowerPlatform.isMac && [.surgeMac, .clashMac].contains(client) {
            return String(localized: "复制订阅")
        }
        return client.primaryImportTitle
    }

    /// Shadowrocket takes Tower's Clash YAML.
    private var fileName: String {
        "\(TowerBrand.localizedName).\(client == .shadowrocket ? "yaml" : client.fileExtension)"
    }

    private var clientColumns: [GridItem] {
        if TowerPlatform.isMac {
            // Adaptive columns reserve empty slots on wide desktop windows.
            // Explicit columns let these four examples fill the content width.
            let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
        }
        return [GridItem(.adaptive(minimum: 70), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("目标客户端").font(.headline)
                Spacer()
                Text("示例").font(.caption).foregroundStyle(.secondary)
            }

            // A wrapping grid keeps the sample swipe gesture available for paging.
            LazyVGrid(columns: clientColumns, spacing: 12) {
                ForEach(clients) { target in
                    Button {
                        withAnimation(TowerMotion.selection(reduceMotion: reduceMotion)) { client = target }
                    } label: {
                        VStack(spacing: 7) {
                            SceneClientIcon(client: target, size: 44)
                                .scaleEffect(client == target || reduceMotion ? 1 : 0.92)
                                .onGeometryChange(for: CGRect.self) {
                                    $0.frame(in: .named(Self.space))
                                } action: { tileIconFrames[target.id] = $0 }
                            Text(verbatim: target.name).font(.caption.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(.primary)
                            Image(systemName: client == target ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(client == target ? Color.accentColor : Color.secondary.opacity(0.5))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 84)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsivePressButtonStyle())
                    .accessibilityIdentifier("onboarding-client-\(target.id)")
                    .accessibilityAddTraits(client == target ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("转换已就绪").font(.headline)
                        (Text("ACL4SSR 默认") + Text(verbatim: " · \(fileName)"))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title).foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 10) {
                    receivingIcon
                    Text(exportPreviewTitle).font(.subheadline.weight(.semibold)).contentTransition(.opacity)
                    Spacer()
                    Image(systemName: TowerPlatform.isMac && [.surgeMac, .clashMac].contains(client)
                          ? "doc.on.doc" : "arrow.up.forward.app").font(.title3)
                }
                .foregroundStyle(.white).padding(14)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("onboarding-export-preview")
                .accessibilityElement(children: .combine)
            }
            .padding(18).towerCard()
        }
        .coordinateSpace(.named(Self.space))
        .overlay { flight }
        .sensoryFeedback(.selection, trigger: client)
        .onChange(of: client) { deliveries += 1 }
        .task(id: isActive) {
            // Hand the first configuration over once the page has settled.
            guard isActive else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            deliveries += 1
        }
    }

    private static let space = "onboarding-export"
    private static let flightDuration = 0.52

    /// The button's icon is taken by the flight: hidden while the copy is in
    /// the air, then it takes the landing with a small bounce. Hidden from
    /// accessibility: the animator would make it an element of its own, named
    /// after its asset, inside the button whose title already names the client.
    private var receivingIcon: some View {
        animatedReceivingIcon
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(Self.space))
            } action: { receiverFrame = $0 }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var animatedReceivingIcon: some View {
        let icon = Image(client.appIconAssetName!).resizable().scaledToFit()
            .scaleEffect(client.appIconFillScale)
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        if reduceMotion {
            icon
        } else {
            KeyframeAnimator(initialValue: ReceiverFrame(), trigger: deliveries) { frame in
                icon
                    .opacity(frame.opacity)
                    .scaleEffect(frame.scale)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.01)
                    LinearKeyframe(0, duration: Self.flightDuration - 0.05)
                    LinearKeyframe(1, duration: 0.04)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: Self.flightDuration)
                    SpringKeyframe(1.16, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                }
            }
        }
    }

    /// A copy of the tapped client's icon arcs from its tile down into the
    /// button, shrinking to the button's icon size on the way: choosing a
    /// client is what sets where the configuration goes.
    @ViewBuilder private var flight: some View {
        if !reduceMotion, let start = tileIconFrames[client.id], receiverFrame != .zero {
            let end = receiverFrame
            KeyframeAnimator(initialValue: FlightFrame(), trigger: deliveries) { frame in
                let t = frame.progress
                // Lift a little before falling, so the path reads as thrown
                // from the tile rather than slid across the card.
                let arc = -sin(.pi * t) * 28
                SceneClientIcon(client: client, size: start.width)
                    .scaleEffect(1 + (end.width / start.width - 1) * t)
                    .position(x: start.midX + (end.midX - start.midX) * t,
                              y: start.midY + (end.midY - start.midY) * t + arc)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.01)
                    SpringKeyframe(1, duration: Self.flightDuration, spring: .smooth)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.01)
                    LinearKeyframe(1, duration: Self.flightDuration - 0.02)
                    LinearKeyframe(0, duration: 0.01)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct ReceiverFrame {
    var opacity: Double = 1
    var scale: CGFloat = 1
}

private struct FlightFrame {
    var progress: CGFloat = 0
    var opacity: Double = 0
}
