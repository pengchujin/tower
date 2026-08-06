import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAddSourcePresented = false
    @State private var pendingDeletion: PendingDeletion?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    SubscriptionOverviewCard { metric in
                        if reduceMotion {
                            proxy.scrollTo(metric.scrollTarget, anchor: .top)
                        } else {
                            withAnimation(.smooth(duration: 0.32)) {
                                proxy.scrollTo(metric.scrollTarget, anchor: .top)
                            }
                        }
                    }

                    if model.subscriptions.isEmpty && model.localNodes.isEmpty {
                        SubscriptionEmptyState {
                            isAddSourcePresented = true
                        }
                    } else {
                        if !model.enabledNodes.isEmpty {
                            NodeGlobeOverview(nodes: model.enabledNodes)
                        }
                        subscriptionsSection
                        localNodesSection

                        Button {
                            model.selectedTab = .rules
                        } label: {
                            PrimaryActionLabel(title: "继续选择规则", symbol: "arrow.right")
                        }
                        .buttonStyle(ResponsivePressButtonStyle())
                        .accessibilityIdentifier("continue-to-rules")
                    }
                }
                .padding(.horizontal, TowerTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(TowerTheme.background.ignoresSafeArea())
            .navigationTitle("我的订阅")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddSourcePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加订阅或节点")
                    .accessibilityIdentifier("add-source-button")
                }
            }
            .refreshable {
                for source in model.subscriptions where source.isEnabled {
                    await model.updateSubscription(id: source.id)
                }
            }
            .sheet(isPresented: $isAddSourcePresented) {
                AddSourceSheet()
            }
            .confirmationDialog(
                pendingDeletion?.title ?? "确认删除",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if case .subscription(let source) = pendingDeletion { model.deleteSubscription(source) }
                    if case .node(let node) = pendingDeletion { model.deleteNode(node) }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text(pendingDeletion?.message ?? "")
            }
        }
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        if !model.subscriptions.isEmpty {
            VStack(spacing: 12) {
                SectionHeading(title: "订阅", detail: "\(model.subscriptions.count) 个来源")
                ForEach(model.subscriptions) { source in
                    SubscriptionCard(source: source) {
                        Task { await model.updateSubscription(id: source.id) }
                    } onDelete: {
                        pendingDeletion = .subscription(source)
                    }
                }
            }
            .id(SubscriptionScrollTarget.subscriptions)
            .accessibilityIdentifier("subscriptions-section")
        }
    }

    @ViewBuilder
    private var localNodesSection: some View {
        if !model.localNodes.isEmpty {
            VStack(spacing: 12) {
                SectionHeading(title: "自有节点", detail: "\(model.localNodes.count) 个")
                ForEach(model.localNodes) { node in
                    LocalNodeCard(node: node) {
                        pendingDeletion = .node(node)
                    }
                }
            }
            .id(SubscriptionScrollTarget.localNodes)
            .accessibilityIdentifier("local-nodes-section")
        }
    }
}

enum SubscriptionScrollTarget: Hashable {
    case subscriptions
    case nodes
    case regions
    case localNodes
}

enum SubscriptionOverviewMetric: CaseIterable {
    case subscriptions
    case nodes
    case regions
    case localNodes

    var scrollTarget: SubscriptionScrollTarget {
        switch self {
        case .subscriptions: .subscriptions
        case .nodes: .nodes
        case .regions: .regions
        case .localNodes: .localNodes
        }
    }
}

private enum PendingDeletion {
    case subscription(SubscriptionSource)
    case node(ProxyNode)

    var title: String {
        switch self {
        case .subscription(let source): "删除“\(source.name)”？"
        case .node(let node): "删除“\(NodeRegionResolver.displayName(for: node))”？"
        }
    }

    var message: String {
        switch self {
        case .subscription: "该订阅及已读取的节点会从这台设备移除。"
        case .node: "这个自有节点会从这台设备移除。"
        }
    }
}

private struct SubscriptionOverviewCard: View {
    @Environment(AppModel.self) private var model
    let onMetricTap: (SubscriptionOverviewMetric) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("准备你的节点")
                        .font(.title2.weight(.bold))
                    Text("集中管理机场订阅和自建节点，再转换成常用客户端配置。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            HStack(spacing: 10) {
                Button { onMetricTap(.subscriptions) } label: {
                    MetricPill(value: "\(model.enabledSubscriptionCount)", label: "启用订阅")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.subscriptions.isEmpty)
                .accessibilityHint("跳到订阅列表")
                .accessibilityIdentifier("overview-subscriptions")
                Divider().frame(height: 38)
                Button { onMetricTap(.nodes) } label: {
                    MetricPill(value: "\(model.enabledNodes.count)", label: "可用节点")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.enabledNodes.isEmpty)
                .accessibilityHint("跳到节点列表")
                .accessibilityIdentifier("overview-nodes")
                Divider().frame(height: 38)
                Button { onMetricTap(.regions) } label: {
                    MetricPill(value: "\(model.coveredCountryCount)", label: "覆盖地区")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.coveredCountryCount == 0)
                .accessibilityHint("跳到地球覆盖区域")
                .accessibilityIdentifier("overview-regions")
                Divider().frame(height: 38)
                Button { onMetricTap(.localNodes) } label: {
                    MetricPill(value: "\(model.localNodes.count)", label: "自有节点")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.localNodes.isEmpty)
                .accessibilityHint("跳到自有节点列表")
                .accessibilityIdentifier("overview-local-nodes")
            }
            PrivacyBadge()
        }
        .padding(20)
        .towerCard()
    }
}

private struct SubscriptionEmptyState: View {
    let addSource: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 92, height: 92)
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 6) {
                Text("先添加一个来源")
                    .font(.title3.weight(.semibold))
                Text("支持机场订阅链接，也可以直接粘贴 SS、VMess、VLESS、Trojan 等节点。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: addSource) {
                PrimaryActionLabel(title: "添加订阅或节点", symbol: "plus")
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityIdentifier("empty-add-source")
        }
        .padding(22)
        .towerCard()
    }
}

private struct SubscriptionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let source: SubscriptionSource
    let onRefresh: () -> Void
    let onDelete: () -> Void
    @State private var isExpanded = false
    @State private var sharePayload: SharePayload?

    private var isRefreshing: Bool { model.refreshingSourceIDs.contains(source.id) }
    private var sourceNodes: [ProxyNode] { model.nodes(for: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Button {
                    withAnimation(expansionAnimation) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "cloud.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(source.safeHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityLabel(isExpanded ? "收起 \(source.name) 的节点" : "展开 \(source.name) 的节点")

                Toggle(
                    "启用 \(source.name)",
                    isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setSubscription(source, enabled: $0) }
                    )
                )
                .labelsHidden()
            }
            // Scoped to the header. On the whole card a long press anywhere —
            // including a node row in the expanded list — lifted the entire
            // subscription into the preview, which read as the card turning
            // into a delete affordance.
            .contextMenu {
                Button(action: onRefresh) { Label("更新订阅", systemImage: "arrow.triangle.2.circlepath") }
                Button {
                    sharePayload = SharePayloadFactory.subscription(source)
                } label: {
                    Label("分享订阅", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            }

            HStack {
                Button {
                    withAnimation(expansionAnimation) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label("\(sourceNodes.count) 个节点", systemImage: "circle.grid.2x2.fill")
                }
                .buttonStyle(.plain)
                Spacer()
                if let error = source.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let date = source.lastUpdatedAt {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("尚未更新")
                }
                Button {
                    sharePayload = SharePayloadFactory.subscription(source)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityLabel("分享 \(source.name)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(sourceNodes) { node in
                        ExpandableNodeRow(node: node)
                    }
                }
                .transition(.opacity)
            }

            Button(action: onRefresh) {
                HStack {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isRefreshing ? "正在更新" : "更新订阅")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isRefreshing)
        }
        .padding(16)
        .towerCard()
        .sensoryFeedback(.selection, trigger: isExpanded)
        .sheet(item: $sharePayload) { payload in
            SharePayloadSheet(payload: payload)
        }
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .interactiveSpring(response: 0.34, dampingFraction: 1)
    }

}

private struct LocalNodeCard: View {
    let node: ProxyNode
    let onDelete: () -> Void

    var body: some View {
        ExpandableNodeRow(node: node)
            .padding(5)
            .towerCard()
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
    }
}
