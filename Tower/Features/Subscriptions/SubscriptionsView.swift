import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAddSourcePresented = false
    @State private var isMacMapExpanded = false
    @State private var pendingDeletion: PendingDeletion?
    @State private var sourceManagementRoute: SourceManagementRoute?
    @State private var editingSubscription: SubscriptionSource?
    @State private var subscriptionNameDraft = SubscriptionNameDraft()
    @State private var editingLocalNode: ProxyNode?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Keep the page's card layout alive across bottom overscroll.
                // Recycling these List-backed cards during rebound can interrupt
                // the native scroll animation. Expanded node lists stay lazy.
                VStack(spacing: 12) {
                    if TowerPlatform.isMac {
                        macHeader
                            .padding(.bottom, 10)
                        // Counts first, then the map, as on iPhone: the
                        // map's latency key sits right above the region list
                        // that opens under it.
                        if !model.subscriptions.isEmpty || !model.localNodes.isEmpty {
                            MacSubscriptionSummary { metric in
                                sourceManagementRoute = metric.managementRoute
                            }
                            .padding(.bottom, 10)
                        }
                        if isMacMapExpanded {
                            NodeMapOverview(nodes: model.enabledNodes) {
                                proxy.scrollTo(SubscriptionScrollTarget.selectedRegionNodes)
                            }
                            .equatable()
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                            .accessibilityIdentifier("inline-node-map")
                            .padding(.bottom, 10)
                        }
                    } else if model.subscriptions.isEmpty && model.localNodes.isEmpty {
                        // A first visit has nothing to map or count: the add
                        // card below is the page, not the third card down.
                    } else {
                        // Once there is something to manage, the counts belong
                        // to the map they describe: one card, not two.
                        NodeMapOverview(nodes: model.enabledNodes, header: SubscriptionMetricsRow { metric in
                            sourceManagementRoute = metric.managementRoute
                        }) {
                            proxy.scrollTo(SubscriptionScrollTarget.selectedRegionNodes)
                        }
                        .equatable()
                        .padding(.bottom, 10)
                    }

                    if model.subscriptions.isEmpty && model.localNodes.isEmpty {
                        SubscriptionEmptyState {
                            isAddSourcePresented = true
                        }
                        .frame(maxWidth: TowerPlatform.isMac ? 600 : .infinity)
                        .padding(.top, TowerPlatform.isMac ? 32 : 0)
                    } else {
                        subscriptionsSection
                        localNodesSection

                        if TowerPlatform.isMac {
                            HStack {
                                PrivacyBadge()
                                Spacer()
                                Button("继续选择规则", systemImage: "arrow.right") {
                                    model.tabSelection = .rules
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .accessibilityIdentifier("continue-to-rules")
                            }
                        } else {
                            VStack(spacing: 12) {
                                // The privacy promise closes the page, next to the
                                // step it leads into, as on the Mac.
                                PrivacyBadge()
                                Button {
                                    model.tabSelection = .rules
                                } label: {
                                    // The tab bar reaches Rules too; this is a hint for the
                                    // next step, not the page's one main action.
                                    PrimaryActionLabel(title: "继续选择规则", symbol: "arrow.right", isProminent: false)
                                }
                                .buttonStyle(ResponsivePressButtonStyle())
                                .accessibilityIdentifier("continue-to-rules")
                            }
                        }
                    }
                }
                .frame(maxWidth: TowerPlatform.isMac ? TowerTheme.macContentMaxWidth : .infinity)
                .padding(.horizontal, TowerPlatform.isMac ? 28 : TowerTheme.pagePadding)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(TowerTheme.background.ignoresSafeArea())
            .navigationTitle("我的订阅")
            .navigationBarTitleDisplayMode(TowerPlatform.isMac ? .inline : .large)
            .task(id: TowerPlatform.isMac ? model.enabledNodes : []) {
                guard TowerPlatform.isMac else { return }
                await model.resolveIPCountries(for: model.enabledNodes)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("管理") {
                        sourceManagementRoute = .subscriptions
                    }
                    .accessibilityLabel("批量管理订阅和自有节点")
                    .accessibilityIdentifier("source-management-button")
                }
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
                model.startSubscriptionRefresh(sourceIDs: model.subscriptions.map(\.id))
                // Hand off immediately so the native pull indicator can retract;
                // the status at the top carries progress and cancel from here.
            }
            .sheet(isPresented: $isAddSourcePresented) {
                AddSourceSheet()
            }
            .sheet(item: $editingSubscription) { source in
                EditSubscriptionSheet(source: source, nameDraft: $subscriptionNameDraft)
            }
            .sheet(item: $editingLocalNode) { node in
                AddSourceSheet(editingNode: node)
            }
            .subscriptionRefreshReport()
            .navigationDestination(item: $sourceManagementRoute) { route in
                SourceManagementView(initialRoute: route)
            }
            .alert(
                pendingDeletion?.title ?? String(localized: "确认删除"),
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                presenting: pendingDeletion
            ) { deletion in
                Button("删除", role: .destructive) {
                    if case .subscription(let source) = deletion { model.deleteSubscription(source) }
                    if case .node(let node) = deletion { model.deleteNode(node) }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) { pendingDeletion = nil }
            } message: { deletion in
                Text(deletion.message)
            }
        }
    }

    private var macHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("我的订阅")
                    .font(.largeTitle.weight(.bold))
                Text("集中管理订阅和自有节点")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !model.enabledNodes.isEmpty {
                Button {
                    withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) {
                        isMacMapExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("节点地图", systemImage: "globe.asia.australia")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isMacMapExpanded ? 180 : 0))
                    }
                }
                .accessibilityAddTraits(isMacMapExpanded ? .isSelected : [])
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("open-node-map")
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        if !model.subscriptions.isEmpty {
            // Plain stacks inside the page's LazyVStack: nested lazy stacks
            // measured their rows only as they scrolled in, so the content
            // height kept changing near the bottom and the page bounced.
            // 2026-09-07 measurements also showed more hitches with them.
            VStack(spacing: 12) {
                SectionHeading(title: "订阅", detail: String(localized: "\(model.subscriptions.count) 个来源"))
                // Always the user's own order; enabled sources are not
                // floated to the top.
                ForEach(model.subscriptions) { source in
                    SubscriptionCard(source: source) {
                        model.startSubscriptionRefresh(sourceIDs: [source.id], singleSource: true)
                    } onEdit: {
                        subscriptionNameDraft = SubscriptionNameDraft(text: source.name)
                        editingSubscription = source
                    } onDelete: {
                        pendingDeletion = .subscription(source)
                    }
                }
            }
            .id(SubscriptionScrollTarget.subscriptions)
            .accessibilityIdentifier("subscriptions-section")
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var localNodesSection: some View {
        if !model.localNodes.isEmpty {
            SectionHeading(title: "自有节点", detail: String(localized: "\(model.localNodes.count) 个"))
                .id(SubscriptionScrollTarget.localNodes)
                .accessibilityIdentifier("local-nodes-section")
            ForEach(model.localNodes) { node in
                LocalNodeCard(node: node) {
                    editingLocalNode = node
                } onDelete: {
                    pendingDeletion = .node(node)
                }
                .padding(.bottom, node.id == model.localNodes.last?.id ? 10 : 0)
            }
        }
    }
}

extension View {
    /// Hosts batch-refresh failures in the page currently covering the screen.
    /// A host attached only to the subscriptions root sits behind a pushed
    /// management page and makes the report appear only after navigating back.
    func subscriptionRefreshReport() -> some View {
        overlay { SubscriptionRefreshReportHost() }
    }
}

private struct SubscriptionRefreshReportHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let report = model.subscriptionRefreshReport {
                // The dimmer only fades; the card enters like every other
                // floating task surface.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)
                    .zIndex(10)
                SubscriptionRefreshReportOverlay(report: report, onDismiss: dismiss)
                    .transition(TowerMotion.surfaceTransition(reduceMotion: reduceMotion))
                    .zIndex(11)
            }
        }
        .animation(TowerMotion.surface(reduceMotion: reduceMotion), value: model.subscriptionRefreshReport?.id)
    }

    private func dismiss() {
        withAnimation(TowerMotion.surface(reduceMotion: reduceMotion)) {
            model.dismissSubscriptionRefreshReport()
        }
    }
}

private struct SubscriptionRefreshReportOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let report: SubscriptionRefreshReport
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 48, height: 48)
                            .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("部分订阅更新失败")
                                .font(.title3.weight(.bold))
                            Text("\(report.succeededCount) 个成功，\(report.failures.count) 个失败")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(report.failures.enumerated()), id: \.element.id) { index, failure in
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(failure.sourceName)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(failure.message)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(16)

                                if index < report.failures.count - 1 {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .towerCard()
                    }
                .frame(maxHeight: min(CGFloat(report.failures.count) * 112, 330))

                Button(action: onDismiss) {
                    Text("完成")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .buttonStyle(ResponsivePressButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: 390)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.regularMaterial))
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .ignoresSafeArea()
    }
}

enum SubscriptionScrollTarget: Hashable {
    case subscriptions
    /// The top of a map region's node list, revealed after selecting it.
    case selectedRegionNodes
    case nodes
    case regions
    case localNodes
}

enum SubscriptionOverviewMetric: CaseIterable {
    case subscriptions
    case nodes
    case regions
    case localNodes

    var managementRoute: SourceManagementRoute {
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
    @Binding var nameDraft: SubscriptionNameDraft
    @State private var urlString: String
    @State private var userAgent: String
    @State private var dnsOverHTTPSURL: String
    @State private var isSaving = false
    @State private var requestsDiscard = false
    @State private var errorMessage: String?
    /// Held so 取消 stops the refetch instead of letting it finish unseen.
    @State private var saveTask: Task<Void, Never>?

    init(source: SubscriptionSource, nameDraft: Binding<SubscriptionNameDraft>) {
        self.source = source
        _nameDraft = nameDraft
        _urlString = State(initialValue: source.urlString)
        _userAgent = State(initialValue: source.requestOptions?.userAgent ?? "")
        _dnsOverHTTPSURL = State(initialValue: source.requestOptions?.dnsOverHTTPSURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅") {
                    TextField("名称（可选）", text: $nameDraft.text)
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
                    Button("取消") {
                        requestsDiscard = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveTask = Task { await save() }
                    }
                    .disabled(isSaving || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmDiscardChanges(
                hasChanges: nameDraft.text != source.name || urlString != source.urlString
                    || userAgent != (source.requestOptions?.userAgent ?? "")
                    || dnsOverHTTPSURL != (source.requestOptions?.dnsOverHTTPSURL ?? ""),
                isBusy: isSaving, requested: $requestsDiscard
            ) { saveTask?.cancel() }
            .onDisappear { saveTask?.cancel() }
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
                name: nameDraft.committedName,
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

/// The same four counts as the iPhone card, in the same order, icons and
/// tints; only the spacing is the Mac's, with room between the columns.
private struct MacSubscriptionSummary: View {
    @Environment(AppModel.self) private var model
    let onMetricTap: (SubscriptionOverviewMetric) -> Void

    var body: some View {
        HStack(spacing: 0) {
            metric(model.enabledNodes.count, label: "节点", symbol: "network", tint: .blue,
                   target: .nodes, enabled: !model.availableNodes.isEmpty, id: "overview-nodes")
            Divider().frame(height: 32)
            metric(model.coveredCountryCount, label: "地区", symbol: "globe.asia.australia.fill", tint: .teal,
                   target: .regions, enabled: model.coveredCountryCount > 0, id: "overview-regions")
            Divider().frame(height: 32)
            metric(model.enabledSubscriptionCount, total: model.subscriptions.count,
                   label: "订阅", symbol: "antenna.radiowaves.left.and.right", tint: .indigo,
                   target: .subscriptions, enabled: !model.subscriptions.isEmpty, id: "overview-subscriptions")
            Divider().frame(height: 32)
            metric(model.localNodes.count, label: "自有节点", symbol: "server.rack", tint: .orange,
                   target: .localNodes, enabled: !model.localNodes.isEmpty, id: "overview-local-nodes")
        }
        .padding(.vertical, 16)
        .towerCard()
    }

    private func metric(_ value: Int, total: Int? = nil, label: LocalizedStringKey, symbol: String,
                        tint: Color, target: SubscriptionOverviewMetric, enabled: Bool,
                        id: String) -> some View {
        Button { onMetricTap(target) } label: {
            MetricPill(value: value, total: total, label: label, symbol: symbol, tint: tint)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}

/// The counts above the home map, inside its card. It reads the model itself:
/// the map's card is `equatable()` and rebuilds only when its nodes change.
///
/// Ordered by what the map shows — nodes, then the regions they cover — then
/// where they come from. Each count has its own icon and tint, the same
/// shape as the Mac summary.
private struct SubscriptionMetricsRow: View {
    @Environment(AppModel.self) private var model
    let onMetricTap: (SubscriptionOverviewMetric) -> Void

    var body: some View {
        HStack(spacing: 8) {
            metric(model.enabledNodes.count, label: "节点", symbol: "network", tint: .blue,
                   target: .nodes, enabled: !model.availableNodes.isEmpty,
                   hint: "打开节点筛选", id: "overview-nodes")
            metric(model.coveredCountryCount, label: "地区", symbol: "globe.asia.australia.fill", tint: .teal,
                   target: .regions, enabled: model.coveredCountryCount > 0,
                   hint: "按国家地区筛选节点", id: "overview-regions")
            // Enabled out of all, so a switched-off subscription is visible
            // here rather than only as a smaller node count.
            metric(model.enabledSubscriptionCount, total: model.subscriptions.count,
                   label: "订阅", symbol: "antenna.radiowaves.left.and.right", tint: .indigo,
                   target: .subscriptions, enabled: !model.subscriptions.isEmpty,
                   hint: "跳到订阅列表", id: "overview-subscriptions")
            metric(model.localNodes.count, label: "自有节点", symbol: "server.rack", tint: .orange,
                   target: .localNodes, enabled: !model.localNodes.isEmpty,
                   hint: "跳到自有节点列表", id: "overview-local-nodes")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func metric(_ value: Int, total: Int? = nil, label: LocalizedStringKey, symbol: String,
                        tint: Color, target: SubscriptionOverviewMetric, enabled: Bool,
                        hint: LocalizedStringKey, id: String) -> some View {
        Button { onMetricTap(target) } label: {
            MetricPill(value: value, total: total, label: label, symbol: symbol, tint: tint)
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!enabled)
        .accessibilityHint(hint)
        .accessibilityIdentifier(id)
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
            // The one promise worth making before anything is added.
            PrivacyBadge()
        }
        .padding(22)
        .towerCard()
    }
}

struct SubscriptionCardMetrics: Equatable {
    let nodeCount: Int
    let remainingBytes: Int64?
    let totalBytes: Int64?
    let expiryDaysRemaining: Int?
    let usedFraction: Double?

    init(
        nodeCount: Int,
        usage: SubscriptionUsage?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.nodeCount = nodeCount
        remainingBytes = usage?.displayRemainingBytes
        totalBytes = usage?.totalBytes
        usedFraction = usage?.usedFraction
        if let expiresAt = usage?.displayExpiresAt(calendar: calendar) {
            let start = calendar.startOfDay(for: now)
            let end = calendar.startOfDay(for: expiresAt)
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            expiryDaysRemaining = max(days, 0)
        } else {
            expiryDaysRemaining = nil
        }
    }
}

private struct SubscriptionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let source: SubscriptionSource
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isExpanded = false
    @State private var sharePayload: SharePayload?

    private var isRefreshing: Bool { model.refreshingSourceIDs.contains(source.id) }

    var body: some View {
        let metrics = SubscriptionCardMetrics(
            nodeCount: model.nodeCount(for: source),
            usage: source.usage
        )

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 38, height: 38)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .buttonStyle(.plain)
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
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("启用 \(source.name)")
                }

                if let remainingBytes = metrics.remainingBytes {
                    SubscriptionTrafficBar(
                        remainingBytes: remainingBytes,
                        totalBytes: metrics.totalBytes,
                        usedFraction: metrics.usedFraction
                    )
                }

                SubscriptionFactsRow(
                    metrics: metrics,
                    source: source,
                    isRefreshing: isRefreshing,
                    onRefresh: onRefresh,
                    onShare: { sharePayload = SharePayloadFactory.subscription(source) }
                )
            }
            .contentShape(Rectangle())
            .modifier(CardSwipeDeletion(onDelete: onDelete))
            .padding(14)
            // Own a bounded preview surface; the outer card joins it to the
            // expanded list without making that list part of the menu snapshot.
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous))
            .geometryGroup()
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous))
            .contextMenu {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                Button(action: onRefresh) { Label("更新订阅", systemImage: "arrow.triangle.2.circlepath") }
                Button {
                    Task { await model.testLatencies(model.nodes(for: source), force: true) }
                } label: {
                    Label("测速", systemImage: "gauge.with.dots.needle.50percent")
                }
                // The cached count, not `nodes(for:)`: this menu is built on
                // every render of every card, expanded or not.
                .disabled(metrics.nodeCount == 0)
                Button {
                    sharePayload = SharePayloadFactory.subscription(source)
                } label: {
                    Label("分享订阅", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            }

            if isExpanded {
                // Lazy, not a plain VStack: a large airport expands to several
                // hundred rows, and building them all to show ten is what made
                // expanding a big subscription stutter.
                LazyVStack(spacing: 0) {
                    SubscriptionAnnouncementSection(notices: source.usage?.distinctNotices ?? [])

                    // Built only while expanded. Asking for it unconditionally
                    // copied every node of every subscription on every redraw.
                    let nodes = model.nodes(for: source)
                    ForEach(nodes) { node in
                        CompactNodeRow(node: node)
                            .overlay(alignment: .bottom) {
                                if node.id != nodes.last?.id {
                                    Divider()
                                        .padding(.leading, 42)
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .clipped()
                .transition(.opacity)
            }

        }
        .towerCard()
        // A map region's node list can move this whole card by a large amount.
        // Keep text and the progress bar in the same animated
        // coordinate space, instead of independently interpolating their origins.
        .geometryGroup()
        .clipped()
        .sensoryFeedback(.selection, trigger: isExpanded)
        .sheet(item: $sharePayload) { payload in
            SharePayloadSheet(payload: payload)
        }
    }

}

private struct SubscriptionAnnouncementSection: View {
    let notices: [String]

    @ViewBuilder
    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("机场公告", systemImage: "megaphone.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(notices.enumerated()), id: \.offset) { index, notice in
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if index < notices.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .accessibilityIdentifier("subscription-announcements")
        }
    }
}

private struct SubscriptionTrafficBar: View {
    let remainingBytes: Int64
    let totalBytes: Int64?
    let usedFraction: Double?

    private var formattedRemaining: String {
        remainingBytes.formatted(.byteCount(style: .binary))
    }

    private var formattedTotal: String? {
        totalBytes?.formatted(.byteCount(style: .binary))
    }

    private var accessibilityTrafficValue: String {
        guard let formattedTotal else { return formattedRemaining }
        return "\(formattedRemaining), \(String(localized: "总流量")) \(formattedTotal)"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.primary)
                Text("剩余")
                    .foregroundStyle(.primary)
                Text(formattedRemaining)
                    .monospacedDigit()

                if let formattedTotal {
                    Spacer(minLength: 6)
                    Text("总流量")
                        .foregroundStyle(.secondary)
                    Text(formattedTotal)
                        .monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            if let usedFraction {
                ProgressView(value: 1 - min(max(usedFraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(Color.green)
                    .scaleEffect(y: 0.72)
                    .accessibilityHidden(true)
            } else {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余流量")
        .accessibilityValue(accessibilityTrafficValue)
    }
}

private struct SubscriptionFactsRow: View {
    let metrics: SubscriptionCardMetrics
    let source: SubscriptionSource
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("\(metrics.nodeCount) 个节点")
                    .foregroundStyle(.secondary)

                if let expiryDaysRemaining = metrics.expiryDaysRemaining {
                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)
                    Text("\(expiryDaysRemaining) 天到期")
                        .foregroundStyle(expiryDaysRemaining <= 3 ? Color.orange : Color.secondary)
                }
            }
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .layoutPriority(2)

            Spacer(minLength: 0)

            status
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button(action: onRefresh) {
                Group {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 44, height: 44)
                    } else {
                        RowIconButtonLabel(symbol: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "正在更新" : "更新订阅")

            Button(action: onShare) {
                RowIconButtonLabel(symbol: "square.and.arrow.up")
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel("分享 \(source.name)")
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = source.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let date = source.lastUpdatedAt {
            Label {
                Text(date, format: .relative(presentation: .named))
            } icon: {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
            }
        } else {
            Label("尚未更新", systemImage: "clock")
        }
    }
}

private struct LocalNodeCard: View {
    let node: ProxyNode
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ExpandableNodeRow(node: node, usesInsetBackground: false, showsInclusionToggle: true,
                          onDelete: onDelete)
            .padding(5)
            .towerCard()
            .geometryGroup()
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous))
            .contextMenu {
                Button(action: onEdit) { Label("编辑", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            }
    }
}
