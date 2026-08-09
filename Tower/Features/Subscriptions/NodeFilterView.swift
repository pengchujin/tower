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
            let resolved = countryCodes[node.id] ?? NodeRegionResolver.countryCode(for: node)
            guard resolved?.uppercased() == countryCode.uppercased() else { return false }
        }
        if let kind, node.kind != kind { return false }
        if let sourceID, node.sourceID != sourceID { return false }
        if localOnly, !node.isLocal { return false }
        return true
    }
}

struct NodeFilterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let initialFocus: NodeFilterRoute

    @State private var searchText = ""
    @State private var countryCode: String?
    @State private var kind: ProxyKind?
    @State private var sourceID: UUID?
    @State private var localOnly = false

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: filterColumns, spacing: 9) {
                    countryFilter
                    protocolFilter
                    sourceFilter
                    localFilter
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
                    ForEach(filteredNodes) { node in
                        nodeRow(node)
                    }
                }
            } header: {
                HStack(spacing: 12) {
                    Text("节点 · \(filteredNodes.count)")
                    Spacer()
                    bulkSelectionButton
                }
                .textCase(nil)
            }
        }
        .navigationTitle(initialFocus == .regions
            ? String(localized: "覆盖地区")
            : String(localized: "节点筛选"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索节点、服务器或来源")
        .scrollDismissesKeyboard(.interactively)
        .task(id: resolutionTaskID) {
            await model.resolveIPCountries(for: model.availableNodes)
        }
        .accessibilityIdentifier("node-filter-list")
    }

    private var filteredNodes: [ProxyNode] {
        let criteria = NodeFilterCriteria(
            countryCode: countryCode,
            kind: kind,
            sourceID: sourceID,
            localOnly: localOnly
        )
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.availableNodes.filter { node in
            guard criteria.matches(node, countryCodes: model.nodeIPCountryCodes) else { return false }
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

    private var allFilteredNodesIncluded: Bool {
        !filteredNodes.isEmpty && filteredNodes.allSatisfy(model.isNodeIncluded)
    }

    private var filterColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 9), count: count)
    }

    private var bulkSelectionButton: some View {
        Button {
            model.setNodes(filteredNodes, included: !allFilteredNodesIncluded)
        } label: {
            Label(
                allFilteredNodesIncluded ? String(localized: "全不选") : String(localized: "全选"),
                systemImage: allFilteredNodesIncluded ? "xmark.circle.fill" : "checkmark.circle.fill"
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

    private var countryOptions: [(code: String, name: String)] {
        let codes = Set(model.availableNodes.compactMap { node in
            model.nodeIPCountryCodes[node.id] ?? NodeRegionResolver.countryCode(for: node)
        })
        return codes.map { code in
            (code.uppercased(), AppLocalization.regionName(for: code))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var protocolOptions: [ProxyKind] {
        Set(model.availableNodes.map(\.kind)).sorted { $0.title < $1.title }
    }

    private var sourceOptions: [SubscriptionSource] {
        model.subscriptions.filter { source in
            source.isEnabled && model.availableNodes.contains { $0.sourceID == source.id }
        }
    }

    private var countryFilter: some View {
        Menu {
            Button("全部地区") { countryCode = nil }
            ForEach(countryOptions, id: \.code) { option in
                Button(option.name) { countryCode = option.code }
            }
        } label: {
            FilterChip(
                title: countryCode.flatMap { code in countryOptions.first { $0.code == code }?.name }
                    ?? String(localized: "国家地区"),
                symbol: "globe.asia.australia",
                isActive: countryCode != nil
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var protocolFilter: some View {
        Menu {
            Button("全部协议") { kind = nil }
            ForEach(protocolOptions, id: \.self) { option in
                Button(option.title) { kind = option }
            }
        } label: {
            FilterChip(title: kind?.title ?? String(localized: "协议"), symbol: "network", isActive: kind != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceFilter: some View {
        Menu {
            Button("全部订阅来源") { sourceID = nil }
            ForEach(sourceOptions) { source in
                Button(source.name) { sourceID = source.id }
            }
        } label: {
            FilterChip(
                title: sourceID.flatMap { id in sourceOptions.first { $0.id == id }?.name }
                    ?? String(localized: "订阅来源"),
                symbol: "cloud",
                isActive: sourceID != nil
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var localFilter: some View {
        Button {
            localOnly.toggle()
            if localOnly { sourceID = nil }
        } label: {
            FilterChip(title: String(localized: "自有节点"), symbol: "house", isActive: localOnly)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let included = model.isNodeIncluded(node)
        let presentedNode = model.nodeForPresentation(node)
        return Button {
            model.setNode(node, included: !included)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: node.kind.symbol)
                    .font(.headline)
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
                SelectionIndicator(isSelected: included)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(included ? String(localized: "会导出") : String(localized: "不导出"))
    }

    private var resolutionTaskID: Int {
        model.availableNodes.map { "\($0.id):\($0.server)" }.hashValue
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: symbol)
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
