import SwiftUI

enum NodeFilterRoute: String, Hashable, Identifiable {
    case all
    case regions

    var id: String { rawValue }
}

struct NodeFilterCriteria: Equatable {
    var countryCode: String?
    var kind: ProxyKind?
    var sourceID: UUID?
    var localOnly = false

    func matches(_ node: ProxyNode, countryCodes: [UUID: String]) -> Bool {
        if let countryCode {
            // Name first, IP database only as a fallback — the same order the
            // map, the metric pill and the policy groups use.
            let resolved = NodeRegionResolver.countryCode(for: node) ?? countryCodes[node.id]
            guard resolved?.uppercased() == countryCode.uppercased() else { return false }
        }
        if let kind, node.kind != kind { return false }
        if let sourceID, node.sourceID != sourceID { return false }
        if localOnly, !node.isLocal { return false }
        return true
    }
}

struct CountryNodeExportGroup: Identifiable {
    let code: String
    let title: String
    let nodes: [ProxyNode]

    var id: String { code }
}

struct ProtocolNodeExportGroup: Identifiable {
    let kind: ProxyKind
    let nodes: [ProxyNode]

    var id: ProxyKind { kind }
}

enum NodeExportGroupBuilder {
    static func countryGroups(
        nodes: [ProxyNode],
        countryCodes: [UUID: String]
    ) -> [CountryNodeExportGroup] {
        var groupedNodes: [String: [ProxyNode]] = [:]
        for node in nodes {
            guard let code = (
                NodeRegionResolver.countryCode(for: node) ?? countryCodes[node.id]
            )?.uppercased() else { continue }
            groupedNodes[code, default: []].append(node)
        }

        return groupedNodes.map { code, nodes in
            CountryNodeExportGroup(
                code: code,
                title: AppLocalization.regionName(for: code),
                nodes: nodes
            )
        }.sorted { lhs, rhs in
            if lhs.nodes.count != rhs.nodes.count {
                return lhs.nodes.count > rhs.nodes.count
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func protocolGroups(nodes: [ProxyNode]) -> [ProtocolNodeExportGroup] {
        Dictionary(grouping: nodes, by: \.kind)
            .map { ProtocolNodeExportGroup(kind: $0.key, nodes: $0.value) }
            .sorted { lhs, rhs in
                if lhs.nodes.count != rhs.nodes.count {
                    return lhs.nodes.count > rhs.nodes.count
                }
                return lhs.kind.title.localizedStandardCompare(rhs.kind.title) == .orderedAscending
            }
    }
}

enum NodeExportGroupSelectionState: Equatable {
    case none
    case partial
    case all

    init(includedCount: Int, totalCount: Int) {
        if totalCount > 0, includedCount >= totalCount {
            self = .all
        } else if includedCount > 0 {
            self = .partial
        } else {
            self = .none
        }
    }

    /// A group remains selected while it still contributes at least one node.
    /// The count beside a partial group communicates the exceptions; removing
    /// the checkmark as soon as one child is disabled incorrectly reads as if
    /// the entire country or protocol were excluded.
    var isMenuSelected: Bool {
        self != .none
    }
}

struct NodeFilterView: View {
    let initialFocus: NodeFilterRoute
    @State private var searchText = ""

    var body: some View {
        List {
            NodeFilterSections(searchText: $searchText)
        }
        .navigationTitle(initialFocus == .regions
            ? String(localized: "覆盖地区")
            : String(localized: "节点筛选"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索节点、服务器或来源")
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("node-filter-list")
    }
}

struct NodeFilterSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var searchText: String

    var body: some View {
        // Filtering used to run once for the rows, once for the empty check,
        // once for the header count, once for the select-all state and once for
        // its disabled state — five passes over every node, each resolving a
        // display name and running four case-insensitive searches, on every
        // keystroke in the search field.
        let filteredNodes = self.filteredNodes
        let displayedNodes = EnabledFirstOrdering.apply(
            filteredNodes,
            isEnabled: model.isNodeIncluded
        )
        let includedFilteredNodeCount = filteredNodes.lazy.filter(model.isNodeIncluded).count
        let allFilteredNodesIncluded = !filteredNodes.isEmpty
            && filteredNodes.allSatisfy(model.isNodeIncluded)

        return Group {
            Section {
                LazyVGrid(columns: filterColumns, spacing: 9) {
                    countryFilter
                    protocolFilter
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("筛选")
            } footer: {
                Text("取消勾选的节点仍保存在塔台中，但不会写入任何客户端配置。")
            }

            Section {
                if filteredNodes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedNodes) { node in
                        nodeRow(node)
                    }
                }
            } header: {
                HStack(spacing: 12) {
                    Text("节点 · \(includedFilteredNodeCount) / \(filteredNodes.count)")
                        .contentTransition(.numericText())
                    Spacer()
                    bulkSelectionButton(
                        filteredNodes: filteredNodes,
                        allIncluded: allFilteredNodesIncluded
                    )
                }
                .textCase(nil)
            }
        }
        .task(id: resolutionTaskID) {
            await model.resolveIPCountries(for: model.availableNodes)
        }
    }

    private var filteredNodes: [ProxyNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.availableNodes.filter { node in
            guard !query.isEmpty else { return true }
            let presentedNode = model.nodeForPresentation(node)
            return [
                NodeRegionResolver.displayName(for: presentedNode),
                node.server,
                node.kind.title,
                model.subscriptionName(for: node),
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var filterColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 9), count: count)
    }

    private func bulkSelectionButton(
        filteredNodes: [ProxyNode],
        allIncluded: Bool
    ) -> some View {
        Button {
            model.setNodes(filteredNodes, included: !allIncluded)
        } label: {
            Label(
                allIncluded ? String(localized: "全不选") : String(localized: "全选"),
                systemImage: allIncluded ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(filteredNodes.isEmpty)
        .accessibilityIdentifier("toggle-all-filtered-nodes")
    }

    private var countryOptions: [CountryNodeExportGroup] {
        NodeExportGroupBuilder.countryGroups(
            nodes: model.availableNodes,
            countryCodes: model.nodeIPCountryCodes
        )
    }

    private var protocolOptions: [ProtocolNodeExportGroup] {
        NodeExportGroupBuilder.protocolGroups(nodes: model.availableNodes)
    }

    private var countryFilter: some View {
        Menu {
            exportGroupSelectionToggle(
                title: String(localized: "全部地区"),
                nodes: model.availableNodes
            )
            Divider()
            ForEach(countryOptions) { option in
                exportGroupSelectionToggle(title: option.title, nodes: option.nodes)
            }
        } label: {
            FilterChip(
                title: String(localized: "国家地区"),
                symbol: "globe.asia.australia",
                isActive: false
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var protocolFilter: some View {
        Menu {
            exportGroupSelectionToggle(
                title: String(localized: "全部协议"),
                nodes: model.availableNodes
            )
            Divider()
            ForEach(protocolOptions) { group in
                let option = group.kind
                exportGroupSelectionToggle(
                    title: option.title,
                    nodes: group.nodes,
                    kind: option
                )
            }
        } label: {
            FilterChip(
                title: String(localized: "协议"),
                kind: nil,
                isActive: false
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func exportGroupSelectionToggle(
        title: String,
        nodes: [ProxyNode],
        kind: ProxyKind? = nil
    ) -> some View {
        let includedCount = nodes.lazy.filter(model.isNodeIncluded).count
        let selectionState = NodeExportGroupSelectionState(
            includedCount: includedCount,
            totalCount: nodes.count
        )
        let countSummary = selectionState == .partial
            ? "\(includedCount)/\(nodes.count)"
            : "\(nodes.count)"

        return Toggle(
            isOn: Binding(
                get: { selectionState.isMenuSelected },
                set: { shouldInclude in
                    model.setNodes(nodes, included: shouldInclude)
                }
            )
        ) {
            if let option = kind {
                Label {
                    Text("\(title) · \(countSummary)")
                } icon: {
                    ProtocolMenuIcon(kind: option)
                }
            } else {
                Text("\(title) · \(countSummary)")
            }
        }
        .disabled(nodes.isEmpty)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let included = model.isNodeIncluded(node)
        let presentedNode = model.nodeForPresentation(node)
        return Button {
            model.setNode(node, included: !included)
        } label: {
            HStack(spacing: 12) {
                ProtocolGlyph(kind: node.kind, size: 18)
                    .foregroundStyle(included ? Color.accentColor : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(included ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(NodeRegionResolver.displayName(for: presentedNode))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(node.kind.title) · \(model.subscriptionName(for: node))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(included ? "已启用" : "已停用")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(included ? Color.accentColor : Color.secondary)
                SelectionIndicator(isSelected: included)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(included ? String(localized: "已启用") : String(localized: "已停用"))
    }

    private var resolutionTaskID: Int {
        model.availableNodes.map { "\($0.id):\($0.server)" }.hashValue
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let kind: ProxyKind?
    let isActive: Bool

    init(title: String, symbol: String, isActive: Bool) {
        self.title = title
        self.symbol = symbol
        self.kind = nil
        self.isActive = isActive
    }

    init(title: String, kind: ProxyKind?, isActive: Bool) {
        self.title = title
        self.symbol = "network"
        self.kind = kind
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 7) {
            if let kind {
                ProtocolGlyph(kind: kind)
            } else {
                Image(systemName: symbol)
            }
            Text(title)
        }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(
                isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}
