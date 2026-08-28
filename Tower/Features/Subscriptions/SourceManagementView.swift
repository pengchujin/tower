import SwiftUI

enum EnabledFirstOrdering {
    static func apply<Element>(
        _ values: [Element],
        isEnabled: (Element) -> Bool
    ) -> [Element] {
        values.filter(isEnabled) + values.filter { !isEnabled($0) }
    }
}

struct SourceManagementView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: SourceManagementTab
    @State private var searchText = ""
    @State private var selectedSubscriptionIDs: Set<UUID> = []
    @State private var selectedLocalNodeIDs: Set<UUID> = []
    @State private var pendingDeletion: SourceManagementDeletion?

    init(initialRoute: SourceManagementRoute = .subscriptions) {
        _tab = State(initialValue: initialRoute.tab)
    }

    var body: some View {
        List {
            Section {
                Picker("管理内容", selection: $tab) {
                    ForEach(SourceManagementTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            switch tab {
            case .subscriptions:
                subscriptionsContent
            case .localNodes:
                localNodesContent
            case .exportFilter:
                NodeFilterSections(searchText: $searchText)
            }
        }
        .accessibilityIdentifier("source-management-list")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("批量管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: tab.searchPrompt)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SubscriptionRefreshToolbarButton(sources: subscriptionsToRefresh)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            batchActionBar
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
                performDeletion(deletion)
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { deletion in
            Text(deletion.message)
        }
        .onChange(of: tab) { _, _ in
            searchText = ""
        }
        .onChange(of: model.subscriptions.map(\.id)) { _, sourceIDs in
            selectedSubscriptionIDs.formIntersection(sourceIDs)
        }
        .onChange(of: model.localNodes.map(\.id)) { _, nodeIDs in
            selectedLocalNodeIDs.formIntersection(nodeIDs)
        }
        .towerToast()
        .subscriptionRefreshReport()
    }

    @ViewBuilder
    private var subscriptionsContent: some View {
        if filteredSubscriptions.isEmpty {
            managementEmptyState(
                title: searchText.isEmpty ? "暂无订阅" : "没有匹配的订阅",
                symbol: searchText.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "magnifyingglass"
            )
        } else {
            Section {
                ForEach(displayedSubscriptions) { source in
                    Button {
                        toggleSubscription(source)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(source.isEnabled ? Color.accentColor : Color.secondary)
                                .frame(width: 38, height: 38)
                                .background(
                                    Color.accentColor.opacity(source.isEnabled ? 0.1 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(source.safeHost) · \(model.nodeCount(for: source)) 个节点")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(source.isEnabled ? "已启用" : "已停用")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(source.isEnabled ? Color.accentColor : Color.secondary)

                            SelectionIndicator(isSelected: selectedSubscriptionIDs.contains(source.id))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        selectedSubscriptionIDs.contains(source.id)
                            ? String(localized: "已选择")
                            : String(localized: "未选择")
                    )
                }
            } header: {
                subscriptionSectionHeader
            }
        }
    }

    @ViewBuilder
    private var localNodesContent: some View {
        if filteredLocalNodes.isEmpty {
            managementEmptyState(
                title: searchText.isEmpty ? "暂无自有节点" : "没有匹配的自有节点",
                symbol: searchText.isEmpty ? "house.slash" : "magnifyingglass"
            )
        } else {
            Section {
                ForEach(displayedLocalNodes) { node in
                    Button {
                        toggleLocalNode(node)
                    } label: {
                        HStack(spacing: 12) {
                            ProtocolGlyph(kind: node.kind, size: 18)
                                .foregroundStyle(model.isNodeIncluded(node) ? Color.accentColor : Color.secondary)
                                .frame(width: 38, height: 38)
                                .background(
                                    Color.accentColor.opacity(model.isNodeIncluded(node) ? 0.1 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(NodeRegionResolver.displayName(for: model.nodeForPresentation(node)))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(node.kind.title) · \(node.server)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(model.isNodeIncluded(node) ? "已启用" : "已停用")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(model.isNodeIncluded(node) ? Color.accentColor : Color.secondary)

                            SelectionIndicator(isSelected: selectedLocalNodeIDs.contains(node.id))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        selectedLocalNodeIDs.contains(node.id)
                            ? String(localized: "已选择")
                            : String(localized: "未选择")
                    )
                }
            } header: {
                localNodeSectionHeader
            }
        }
    }

    @ViewBuilder
    private var batchActionBar: some View {
        if tab.supportsBatchSelection {
            VStack(spacing: 10) {
                HStack {
                    Text("已选择 \(selectedItemCount) 项")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())

                    Spacer()

                    if selectedItemCount > 0 {
                        Button("清除选择") {
                            clearSelection()
                        }
                        .font(.subheadline)
                    }
                }

                switch tab {
                case .subscriptions:
                    subscriptionActions
                case .localNodes:
                    localNodeActions
                case .exportFilter:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var subscriptionActions: some View {
        HStack(spacing: 10) {
            ManagementActionButton(
                title: subscriptionEnablementTitle,
                symbol: subscriptionEnablementSymbol
            ) {
                model.setSubscriptions(selectedSubscriptions, enabled: subscriptionEnablementTarget)
            }

            ManagementActionButton(title: "删除", symbol: "trash", role: .destructive) {
                pendingDeletion = .subscriptions(selectedSubscriptions)
            }
        }
        .disabled(selectedSubscriptions.isEmpty)
    }

    private var localNodeActions: some View {
        HStack(spacing: 10) {
            ManagementActionButton(title: localNodeEnablementTitle, symbol: localNodeEnablementSymbol) {
                model.setNodes(selectedLocalNodes, included: localNodeEnablementTarget)
            }

            ManagementActionButton(title: "删除", symbol: "trash", role: .destructive) {
                pendingDeletion = .localNodes(selectedLocalNodes)
            }
        }
        .disabled(selectedLocalNodes.isEmpty)
    }

    private func managementEmptyState(title: LocalizedStringKey, symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol)
            .listRowBackground(Color.clear)
    }

    private var filteredSubscriptions: [SubscriptionSource] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return model.subscriptions }
        return model.subscriptions.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.safeHost.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredLocalNodes: [ProxyNode] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return model.localNodes }
        return model.localNodes.filter {
            NodeRegionResolver.displayName(for: $0).localizedCaseInsensitiveContains(query)
                || $0.server.localizedCaseInsensitiveContains(query)
                || $0.kind.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedSubscriptions: [SubscriptionSource] {
        EnabledFirstOrdering.apply(filteredSubscriptions, isEnabled: \.isEnabled)
    }

    private var displayedLocalNodes: [ProxyNode] {
        EnabledFirstOrdering.apply(filteredLocalNodes, isEnabled: model.isNodeIncluded)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedSubscriptions: [SubscriptionSource] {
        model.subscriptions.filter { selectedSubscriptionIDs.contains($0.id) }
    }

    private var selectedLocalNodes: [ProxyNode] {
        model.localNodes.filter { selectedLocalNodeIDs.contains($0.id) }
    }

    private var selectedItemCount: Int {
        switch tab {
        case .subscriptions: selectedSubscriptionIDs.count
        case .localNodes: selectedLocalNodeIDs.count
        case .exportFilter: 0
        }
    }

    private var subscriptionEnablementTarget: Bool {
        !selectedSubscriptions.allSatisfy(\.isEnabled)
    }

    private var subscriptionEnablementTitle: LocalizedStringKey {
        subscriptionEnablementTarget ? "启用" : "停用"
    }

    private var subscriptionEnablementSymbol: String {
        subscriptionEnablementTarget ? "checkmark.circle" : "pause.circle"
    }

    private var localNodeEnablementTarget: Bool {
        !selectedLocalNodes.allSatisfy(model.isNodeIncluded)
    }

    private var localNodeEnablementTitle: LocalizedStringKey {
        localNodeEnablementTarget ? "启用" : "停用"
    }

    private var localNodeEnablementSymbol: String {
        localNodeEnablementTarget ? "checkmark.circle" : "pause.circle"
    }

    private var subscriptionsToRefresh: [SubscriptionSource] {
        guard tab == .subscriptions else { return model.subscriptions }
        return selectedSubscriptions.isEmpty ? filteredSubscriptions : selectedSubscriptions
    }

    private var subscriptionSectionHeader: some View {
        HStack(spacing: 12) {
            Text("订阅")
            Spacer()
            Button("全选") {
                selectAllVisibleSubscriptions()
            }
            .disabled(filteredSubscriptions.isEmpty)
        }
        .textCase(nil)
    }

    private var localNodeSectionHeader: some View {
        HStack(spacing: 12) {
            Text("自有节点")
            Spacer()
            Button("全选") {
                selectAllVisibleLocalNodes()
            }
            .disabled(filteredLocalNodes.isEmpty)
        }
        .textCase(nil)
    }

    private func toggleSubscription(_ source: SubscriptionSource) {
        if selectedSubscriptionIDs.contains(source.id) {
            selectedSubscriptionIDs.remove(source.id)
        } else {
            selectedSubscriptionIDs.insert(source.id)
        }
    }

    private func toggleLocalNode(_ node: ProxyNode) {
        if selectedLocalNodeIDs.contains(node.id) {
            selectedLocalNodeIDs.remove(node.id)
        } else {
            selectedLocalNodeIDs.insert(node.id)
        }
    }

    private func selectAllVisibleSubscriptions() {
        selectedSubscriptionIDs.formUnion(filteredSubscriptions.map(\.id))
    }

    private func selectAllVisibleLocalNodes() {
        selectedLocalNodeIDs.formUnion(filteredLocalNodes.map(\.id))
    }

    private func clearSelection() {
        switch tab {
        case .subscriptions: selectedSubscriptionIDs.removeAll()
        case .localNodes: selectedLocalNodeIDs.removeAll()
        case .exportFilter: break
        }
    }

    private func performDeletion(_ deletion: SourceManagementDeletion) {
        switch deletion {
        case .subscriptions(let sources):
            model.deleteSubscriptions(sources)
            selectedSubscriptionIDs.subtract(sources.map(\.id))
        case .localNodes(let nodes):
            model.deleteLocalNodes(nodes)
            selectedLocalNodeIDs.subtract(nodes.map(\.id))
        }
        pendingDeletion = nil
    }
}

/// Owns its progress state so starting and finishing a refresh invalidates only
/// the toolbar control, not the management list and its thousand-node filters.
private struct SubscriptionRefreshToolbarButton: View {
    @Environment(AppModel.self) private var model
    @State private var isRefreshing = false
    let sources: [SubscriptionSource]

    var body: some View {
        Button {
            guard !sources.isEmpty, !isRefreshing else { return }
            isRefreshing = true
            Task {
                await model.refreshSubscriptions(sources)
                isRefreshing = false
            }
        } label: {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 22, height: 22)
            .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .disabled(sources.isEmpty || isRefreshing)
        .accessibilityLabel(isRefreshing ? String(localized: "更新中") : String(localized: "更新"))
    }
}

enum SourceManagementRoute: String, Identifiable {
    case subscriptions
    case nodes
    case regions
    case localNodes

    var id: String { rawValue }

    var tab: SourceManagementTab {
        switch self {
        case .subscriptions: .subscriptions
        case .localNodes: .localNodes
        case .nodes, .regions: .exportFilter
        }
    }
}

enum SourceManagementTab: String, CaseIterable, Identifiable {
    case subscriptions
    case localNodes
    case exportFilter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptions: String(localized: "订阅")
        case .localNodes: String(localized: "自有节点")
        case .exportFilter: String(localized: "导出筛选")
        }
    }

    var searchPrompt: String {
        switch self {
        case .subscriptions: String(localized: "搜索名称或域名")
        case .localNodes: String(localized: "搜索名称、地址或协议")
        case .exportFilter: String(localized: "搜索节点、服务器或来源")
        }
    }

    var supportsBatchSelection: Bool {
        switch self {
        case .subscriptions, .localNodes: true
        case .exportFilter: false
        }
    }
}

private enum SourceManagementDeletion: Hashable {
    case subscriptions([SubscriptionSource])
    case localNodes([ProxyNode])

    var title: String {
        switch self {
        case .subscriptions(let sources): String(localized: "删除 \(sources.count) 个订阅？")
        case .localNodes(let nodes): String(localized: "删除 \(nodes.count) 个自有节点？")
        }
    }

    var message: String {
        switch self {
        case .subscriptions:
            String(localized: "所选订阅及其已经读取的节点会从这台设备移除。")
        case .localNodes:
            String(localized: "所选自有节点会从这台设备移除，此操作无法撤销。")
        }
    }
}

private struct ManagementActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        symbol: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 13))
    }
}
