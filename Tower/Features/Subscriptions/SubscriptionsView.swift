import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAddSourcePresented = false
    @State private var pendingDeletion: PendingDeletion?
    @State private var nodeFilterRoute: NodeFilterRoute?
    @State private var editingSubscription: SubscriptionSource?
    @State private var editingLocalNode: ProxyNode?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    Color.clear
                        .frame(height: 0)
                        .id(SubscriptionScrollTarget.top)
                    SubscriptionOverviewCard { metric in
                        switch metric {
                        case .nodes:
                            nodeFilterRoute = .all
                        case .regions:
                            nodeFilterRoute = .regions
                        case .subscriptions, .localNodes:
                            proxy.scrollTo(metric.scrollTarget, anchor: .top)
                        }
                    }

                    NodeMapOverview(nodes: model.enabledNodes)

                    if model.subscriptions.isEmpty && model.localNodes.isEmpty {
                        SubscriptionEmptyState {
                            isAddSourcePresented = true
                        }
                    } else {
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
                await model.refreshEnabledSubscriptions()
                // A refresh replaces the subscription rows, and the new
                // identities leave the scroll view holding the offset the
                // spinner had pushed it to — so the list stays pulled down
                // with a gap above it. Returning to the anchor is what the
                // gesture implies anyway: you pulled from the top to see the
                // top.
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1)) {
                    proxy.scrollTo(SubscriptionScrollTarget.top, anchor: .top)
                }
            }
            .sheet(isPresented: $isAddSourcePresented) {
                AddSourceSheet()
            }
            .sheet(item: $editingSubscription) { source in
                EditSubscriptionSheet(source: source)
            }
            .sheet(item: $editingLocalNode) { node in
                AddSourceSheet(editingNode: node)
            }
            .navigationDestination(item: $nodeFilterRoute) { route in
                NodeFilterView(initialFocus: route)
            }
            .confirmationDialog(
                pendingDeletion?.title ?? String(localized: "确认删除"),
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
                SectionHeading(title: "订阅", detail: String(localized: "\(model.subscriptions.count) 个来源"))
                ForEach(model.subscriptions) { source in
                    SubscriptionCard(source: source) {
                        Task { await model.updateSubscription(id: source.id) }
                    } onEdit: {
                        editingSubscription = source
                    } onMoveUp: {
                        model.moveSubscription(source, by: -1)
                    } onMoveDown: {
                        model.moveSubscription(source, by: 1)
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
            LazyVStack(spacing: 12) {
                SectionHeading(title: "自有节点", detail: String(localized: "\(model.localNodes.count) 个"))
                ForEach(model.localNodes) { node in
                    LocalNodeCard(node: node) {
                        editingLocalNode = node
                    } onMoveUp: {
                        model.moveLocalNode(node, by: -1)
                    } onMoveDown: {
                        model.moveLocalNode(node, by: 1)
                    } onDelete: {
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
    /// An anchor at the very top of the list, so a finished refresh has
    /// somewhere to return to.
    case top
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
        case .subscription(let source): String(localized: "删除“\(source.name)”？")
        case .node(let node): String(localized: "删除“\(NodeRegionResolver.displayName(for: node))”？")
        }
    }

    var message: String {
        switch self {
        case .subscription: String(localized: "该订阅及已读取的节点会从这台设备移除。")
        case .node: String(localized: "这个自有节点会从这台设备移除。")
        }
    }
}

private struct EditSubscriptionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let source: SubscriptionSource
    @State private var name: String
    @State private var urlString: String
    @State private var userAgent: String
    @State private var dnsOverHTTPSURL: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(source: SubscriptionSource) {
        self.source = source
        _name = State(initialValue: source.name)
        _urlString = State(initialValue: source.urlString)
        _userAgent = State(initialValue: source.requestOptions?.userAgent ?? "")
        _dnsOverHTTPSURL = State(initialValue: source.requestOptions?.dnsOverHTTPSURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅") {
                    TextField("名称（可选）", text: $name)
                        .textContentType(.organizationName)
                    TextField("订阅链接", text: $urlString, axis: .vertical)
                        .lineLimit(2...5)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("自定义 User-Agent（可选）", text: $userAgent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("DNS-over-HTTPS 地址（可选）", text: $dnsOverHTTPSURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("高级请求设置")
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await model.updateSubscriptionDetails(
                source,
                name: name,
                urlString: urlString,
                userAgent: userAgent,
                dnsOverHTTPSURL: dnsOverHTTPSURL
            )
            dismiss()
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
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
                    Text("准备您的节点")
                        .font(.title2.weight(.bold))
                    Text("集中管理代理订阅和自建节点，再转换成常用客户端配置。")
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
                    MetricPill(value: model.enabledSubscriptionCount, label: "已启用")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.subscriptions.isEmpty)
                .accessibilityHint("跳到订阅列表")
                .accessibilityIdentifier("overview-subscriptions")
                Divider().frame(height: 38)
                Button { onMetricTap(.nodes) } label: {
                    MetricPill(value: model.enabledNodes.count, label: "节点")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.availableNodes.isEmpty)
                .accessibilityHint("打开节点筛选")
                .accessibilityIdentifier("overview-nodes")
                Divider().frame(height: 38)
                Button { onMetricTap(.regions) } label: {
                    MetricPill(value: model.coveredCountryCount, label: "地区")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.coveredCountryCount == 0)
                .accessibilityHint("按国家地区筛选节点")
                .accessibilityIdentifier("overview-regions")
                Divider().frame(height: 38)
                Button { onMetricTap(.localNodes) } label: {
                    MetricPill(value: model.localNodes.count, label: "自有节点")
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
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    @State private var isExpanded = false
    @State private var sharePayload: SharePayload?

    private var isRefreshing: Bool { model.refreshingSourceIDs.contains(source.id) }
    private var sourceNodes: [ProxyNode] { model.nodes(for: source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Button {
                    isExpanded.toggle()
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
                            .animation(expansionAnimation, value: isExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityLabel(isExpanded
                    ? String(localized: "收起 \(source.name) 的节点")
                    : String(localized: "展开 \(source.name) 的节点"))

                Toggle(
                    "启用 \(source.name)",
                    isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setSubscription(source, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(CheckmarkToggleStyle())
                .frame(width: 34, height: 44)
                .transaction { $0.animation = nil }
                .accessibilityLabel("启用 \(source.name)")
            }
            // Scoped to the header. On the whole card a long press anywhere —
            // including a node row in the expanded list — lifted the entire
            // subscription into the preview, which read as the card turning
            // into a delete affordance.
            .contextMenu {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                Button(action: onMoveUp) { Label("上移", systemImage: "arrow.up") }
                    .disabled(!model.canMoveSubscription(source, by: -1))
                Button(action: onMoveDown) { Label("下移", systemImage: "arrow.down") }
                    .disabled(!model.canMoveSubscription(source, by: 1))
                Button(action: onRefresh) { Label("更新订阅", systemImage: "arrow.triangle.2.circlepath") }
                Button {
                    sharePayload = SharePayloadFactory.subscription(source)
                } label: {
                    Label("分享订阅", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            }

            if let usage = source.usage, !usage.isEmpty {
                SubscriptionUsageRow(usage: usage)
            }

            HStack {
                Button {
                    isExpanded.toggle()
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
                // Lazy, not a plain VStack: a large airport expands to several
                // hundred rows, and building them all to show ten is what made
                // expanding a big subscription stutter.
                LazyVStack(spacing: 8) {
                    ForEach(sourceNodes) { node in
                        ExpandableNodeRow(node: node)
                    }
                }
            }

            Button(action: onRefresh) {
                HStack {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isRefreshing ? String(localized: "正在更新") : String(localized: "更新订阅"))
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
    @Environment(AppModel.self) private var model
    let node: ProxyNode
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ExpandableNodeRow(node: node, usesInsetBackground: false, showsInclusionToggle: true)
            .padding(5)
            .towerCard()
        .contextMenu {
            Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
            Button(action: onMoveUp) { Label("上移", systemImage: "arrow.up") }
                .disabled(!model.canMoveLocalNode(node, by: -1))
            Button(action: onMoveDown) { Label("下移", systemImage: "arrow.down") }
                .disabled(!model.canMoveLocalNode(node, by: 1))
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
        }
    }
}


/// Plan usage as the airport reports it.
///
/// Some airports send a `subscription-userinfo` header, which gives byte counts
/// worth a progress bar. Others only write sentences into the node list, which
/// are shown verbatim because they are all there is.
private struct SubscriptionUsageRow: View {
    let usage: SubscriptionUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = usage.usedFraction {
                ProgressView(value: fraction)
                    .tint(fraction > 0.9 ? .orange : Color.accentColor)
            }
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Airports that send structured quota often repeat it in their own
            // wording; only what the summary above does not already say.
            ForEach(usage.distinctNotices, id: \.self) { notice in
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summary: String? {
        var parts: [String] = []
        if let used = usage.usedBytes, let total = usage.totalBytes {
            parts.append(String(localized: "已用 \(format(used)) / \(format(total))"))
        } else if let remaining = usage.remainingBytes {
            parts.append(String(localized: "剩余 \(format(remaining))"))
        }
        if let expiresAt = usage.expiresAt {
            parts.append(String(localized: "到期 \(expiresAt.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .binary))
    }
}
