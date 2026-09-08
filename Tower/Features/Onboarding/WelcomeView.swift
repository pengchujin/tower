import SwiftUI

/// Replayable introduction; its examples never access user data or request permissions.
struct WelcomeView: View {
    static let repositoryURL = URL(string: "https://github.com/pengchujin/tower")!
    var onContinue: () -> Void
    private let readableContentWidth: CGFloat = 680
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
        .frame(maxWidth: .infinity)
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
                ForEach(0..<4) { _ in
                    Circle().fill(Color.secondary.opacity(0.18)).frame(width: 7, height: 7)
                        .frame(width: 24)
                }
            }
            .overlay(alignment: .leading) {
                Capsule().fill(Color.accentColor).frame(width: 24, height: 7)
                    .offset(x: CGFloat(page * 30) * (layoutDirection == .rightToLeft ? -1 : 1))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introductionHeading.padding(.top, 12)
                    .modifier(WelcomeEntrance(active: isActive, order: 0))
                if page == 0 { overview } else { illustration }
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

    private var overviewClients: [ClientTarget] {
        if TowerPlatform.isMac {
            return [.shadowrocket, .surgeMac, .clashVerge, .clashMac,
                    .flClash, .mihomoParty, .singBox, .clashApple,
                    .clash, .hiddify, .clashMi, .karing]
        }
        return [.surge, .clash, .shadowrocket, .loon,
                .quanx, .hiddify, .egern, .v2box,
                .clashApple, .singBox, .clashMi, .karing]
    }

    private var overview: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("支持的客户端").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                        count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 18) {
                    ForEach(overviewClients) { client in
                        VStack(spacing: 7) {
                            if let asset = client.appIconAssetName {
                                Image(asset).resizable().scaledToFit()
                                    .frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                                    .accessibilityHidden(true)
                            }
                            Text(verbatim: client.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 1))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    workflowStep("添加订阅", number: "1", symbol: "link")
                    flowArrow
                    workflowStep("选择规则", number: "2", symbol: "line.3.horizontal.decrease")
                    flowArrow
                    workflowStep("导出使用", number: "3", symbol: "paperplane")
                }
                VStack(spacing: 16) {
                    workflowStep("添加订阅", number: "1", symbol: "link")
                    workflowStep("选择规则", number: "2", symbol: "line.3.horizontal.decrease")
                    workflowStep("导出使用", number: "3", symbol: "paperplane")
                }
            }
            .padding(18).frame(maxWidth: .infinity).towerCard()
        }
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.forward")
            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func workflowStep(_ title: LocalizedStringKey, number: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 38)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(verbatim: number).foregroundStyle(Color.accentColor)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

    @ViewBuilder private var illustration: some View {
        switch page {
        case 1: subscriptionExample
        case 2: routingExample
        default: WelcomeExportExample(isActive: isActive)
        }
    }

    private var subscriptionExample: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("添加订阅", systemImage: "link").font(.headline)
                    Spacer()
                    Text("示例").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Color.accentColor)
                    Text(verbatim: "https://example.com/subscribe")
                        .font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .padding(13)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 16) {
                    Label("粘贴识别", systemImage: "doc.on.clipboard")
                    Label("扫码", systemImage: "qrcode.viewfinder")
                    Label("手动添加", systemImage: "square.and.pencil")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 1))
            Image(systemName: "arrow.down").foregroundStyle(Color.accentColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("我的订阅", systemImage: "rectangle.stack.fill").font(.headline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
                Divider()
                nodeExample("🇭🇰", region: "香港", latency: "38 ms").modifier(WelcomeEntrance(active: isActive, order: 2))
                nodeExample("🇯🇵", region: "日本", latency: "62 ms").modifier(WelcomeEntrance(active: isActive, order: 3))
                nodeExample("🇸🇬", region: "新加坡", latency: "85 ms").modifier(WelcomeEntrance(active: isActive, order: 4))
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 1))
        }
        .accessibilityElement(children: .combine)
    }

    private func nodeExample(_ flag: String, region: LocalizedStringKey, latency: String) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: flag).font(.title3)
            Text(region).font(.subheadline.weight(.medium))
            Spacer()
            Text(verbatim: latency).font(.caption.monospacedDigit()).foregroundStyle(.teal)
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        }
    }

    private var routingExample: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACL4SSR 默认").font(.headline)
                    Text("内置方案").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 1))
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("分流示例").font(.headline)
                    Spacer()
                    Text("服务 → 策略").font(.caption).foregroundStyle(.secondary)
                }
                routingRow("国外媒体", symbol: "play.rectangle.fill", policy: "代理", color: .indigo).modifier(WelcomeEntrance(active: isActive, order: 2))
                routingRow("AI 平台", symbol: "", emoji: "🤖", policy: "代理", color: .blue).modifier(WelcomeEntrance(active: isActive, order: 3))
                routingRow("国内网站", symbol: "globe.asia.australia.fill", policy: "直连", color: .teal).modifier(WelcomeEntrance(active: isActive, order: 4))
                routingRow("广告请求", symbol: "hand.raised.fill", policy: "拦截", color: .orange).modifier(WelcomeEntrance(active: isActive, order: 5))
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 1))
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.accentColor)
                Text("选择方案后，还可以按需调整策略组。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func routingRow(_ service: LocalizedStringKey, symbol: String, emoji: String? = nil,
                            policy: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 10) {
            Group {
                if let emoji {
                    Text(verbatim: emoji)
                } else {
                    Image(systemName: symbol)
                }
            }.font(.body)
                .foregroundStyle(color).frame(width: 34, height: 34)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(service).font(.subheadline.weight(.medium))
            Spacer(minLength: 4)
            Image(systemName: "arrow.forward").font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(policy).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(color.opacity(0.08), in: Capsule())
        }
    }


}

/// Driven by selection rather than onAppear: the native pager preloads neighbors.
/// No delayed tasks survive a quick reversal; animations retarget current values.
private struct WelcomeEntrance: ViewModifier {
    let active: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0.6)
            .offset(y: reduceMotion || active ? 0 : 18)
            .scaleEffect(reduceMotion || active ? 1 : 0.97, anchor: .top)
            .animation(reduceMotion ? .easeOut(duration: TowerMotion.reducedMotionDuration)
                       : .spring(duration: 0.5, bounce: 0.2).delay(active ? Double(order) * 0.04 : 0),
                       value: active)
    }
}

/// A local, interactive sample. It never generates or opens a real configuration.
private struct WelcomeExportExample: View {
    let isActive: Bool
    @State private var client: ClientTarget = .shadowrocket
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    private let clients: [ClientTarget] = [.shadowrocket, .surge, .egern, .clash]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("目标客户端").font(.headline)
                Spacer()
                Text("示例").font(.caption).foregroundStyle(.secondary)
            }
            .modifier(WelcomeEntrance(active: isActive, order: 1))

            // A wrapping grid keeps the sample swipe gesture available for paging.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 12)], spacing: 12) {
                ForEach(Array(clients.enumerated()), id: \.element.id) { index, target in
                    Button {
                        withAnimation(TowerMotion.selection(reduceMotion: reduceMotion)) { client = target }
                    } label: {
                        VStack(spacing: 8) {
                            Image(target.appIconAssetName!).resizable().scaledToFit()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(spacing: 5) {
                                Text(verbatim: target.name).font(.caption.weight(.semibold))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Image(systemName: client == target ? "checkmark.circle.fill" : "circle")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .foregroundStyle(client == target ? Color.accentColor : Color.primary)
                        .padding(.vertical, 12).padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 90)
                        .background(.background, in: RoundedRectangle(cornerRadius: 20))
                        .background {
                            if client == target && !reduceMotion {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .padding(-2)
                                    .matchedGeometryEffect(id: "selected-client", in: selectionNamespace)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(client == target ? Color.accentColor : Color.secondary.opacity(0.1), lineWidth: 1)
                        }
                    }
                    .buttonStyle(ResponsivePressButtonStyle())
                    .accessibilityIdentifier("onboarding-client-\(target.id)")
                    .accessibilityAddTraits(client == target ? .isSelected : [])
                    .modifier(WelcomeEntrance(active: isActive, order: index + 2))
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("转换已就绪").font(.headline)
                        Text("ACL4SSR 默认")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title).foregroundStyle(.green)
                }
                HStack(spacing: 10) {
                    Image(client.appIconAssetName!).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .id(client).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.9)))
                    Text("一键导出到 \(client.name)").font(.subheadline.weight(.semibold)).contentTransition(.opacity)
                    Spacer()
                    Image(systemName: "arrow.up.forward.app").font(.title3)
                }
                .foregroundStyle(.white).padding(14)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("onboarding-export-preview")
                .accessibilityElement(children: .combine)
            }
            .padding(18).towerCard()
            .modifier(WelcomeEntrance(active: isActive, order: 5))
        }
        .sensoryFeedback(.selection, trigger: client)
    }
}
