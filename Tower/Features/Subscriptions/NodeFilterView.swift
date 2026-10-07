import SwiftUI

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
        countryCode: (ProxyNode) -> String?
    ) -> [CountryNodeExportGroup] {
        var groupedNodes: [String: [ProxyNode]] = [:]
        for node in nodes {
            guard let code = countryCode(node)?.uppercased() else { continue }
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

/// Memoized country and protocol groups for `NodeFilterSections`. Array and
/// dictionary equality short-circuit on shared storage, so an unchanged model
/// makes the check nearly free.
final class NodeExportGroupCache {
    private var nodes: [ProxyNode]?
    private var countryCodes: [UUID: String]?
    private(set) var countries: [CountryNodeExportGroup] = []
    private(set) var protocols: [ProtocolNodeExportGroup] = []

    func update(nodes: [ProxyNode], countryCodes: [UUID: String], countryCode: (ProxyNode) -> String?) {
        guard nodes != self.nodes || countryCodes != self.countryCodes else { return }
        self.nodes = nodes
        self.countryCodes = countryCodes
        countries = NodeExportGroupBuilder.countryGroups(nodes: nodes, countryCode: countryCode)
        protocols = NodeExportGroupBuilder.protocolGroups(nodes: nodes)
    }
}

struct NodeFilterSections: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model

    @Binding var searchText: String
    @Binding var showsNameFilter: Bool
    /// Country and protocol groups only change with the nodes or their
    /// resolved countries, not with each checkbox; rebuilding them copied
    /// every node several times per tap (device trace, 2026-09-27).
    @State private var groupCache = NodeExportGroupCache()

    var body: some View {
        // Filtering used to run once for the rows, once for the empty check,
        // once for the header count, once for the select-all state and once for
        // its disabled state — five passes over every node, each resolving a
        // display name and running four case-insensitive searches, on every
        // keystroke in the search field.
        let filteredNodes = self.filteredNodes
        let includedIDs = model.includedNodeIDs
        let allowedIDs = model.nodeNameAllowedIDs
        let includedFilteredNodeCount = filteredNodes.lazy.filter { includedIDs.contains($0.id) }.count
        let eligibleFilteredNodes = allowedIDs.map { ids in filteredNodes.filter { ids.contains($0.id) } } ?? filteredNodes
        let allFilteredNodesIncluded = !eligibleFilteredNodes.isEmpty
            && eligibleFilteredNodes.allSatisfy { includedIDs.contains($0.id) }

        return Group {
            // Three rows of one shape — icon, title, current value, accessory —
            // so the region and protocol menus line up with the name filter
            // instead of sitting as centred tiles above a left-aligned row.
            Section {
                countryFilter
                protocolFilter
                Button {
                    showsNameFilter = true
                } label: {
                    FilterRow(
                        title: String(localized: "节点名称"),
                        symbol: "text.magnifyingglass",
                        value: nameFilterSummary,
                        accessory: "chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("node-name-export-filter")
                .listRowInsets(FilterRow.insets)
            } header: {
                Text("筛选")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("取消勾选的节点仍保存在塔台中，但不会写入任何客户端配置。")
                    if let error = model.nodeExportNameFilterError {
                        Text(error).foregroundStyle(.red)
                    }
                }
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
                    Text("节点 · \(includedFilteredNodeCount) / \(filteredNodes.count)")
                        // Scope motion to glyphs; a header transaction must not
                        // animate the List's row diff when search is dismissed.
                        .animation(TowerMotion.selection(reduceMotion: reduceMotion)) { content in
                            content.contentTransition(reduceMotion ? .opacity : .numericText(value: Double(includedFilteredNodeCount)))
                        }
                    Spacer()
                    bulkSelectionButton(
                        filteredNodes: eligibleFilteredNodes,
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
        // No search: reuse the cached array instead of copying every node.
        guard !query.isEmpty else { return model.availableNodes }
        return model.availableNodes.filter { node in
            let presentedNode = model.nodeForPresentation(node)
            return [
                NodeRegionResolver.displayName(for: presentedNode),
                node.server,
                node.kind.title,
                model.subscriptionName(for: node),
            ].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// "全部" while every group still exports all of its nodes; otherwise how
    /// many groups still contribute at least one, out of all of them.
    private func selectionSummary(_ groups: [[ProxyNode]]) -> String {
        let includedIDs = model.includedNodeIDs
        let allowedIDs = model.nodeNameAllowedIDs
        var selected = 0
        var complete = true
        for nodes in groups {
            var eligible = 0
            var included = 0
            for node in nodes where allowedIDs?.contains(node.id) ?? true {
                eligible += 1
                if includedIDs.contains(node.id) { included += 1 }
            }
            let state = NodeExportGroupSelectionState(includedCount: included, totalCount: eligible)
            if state.isMenuSelected { selected += 1 }
            if state != .all, eligible > 0 { complete = false }
        }
        return complete
            ? String(localized: "全部")
            : "\(selected)/\(groups.count)"
    }

    private var nameFilterSummary: String {
        guard let filter = model.nodeExportNameFilter else {
            return String(localized: "未设置")
        }
        let draft = NodeNameFilterDraft(pattern: filter.pattern)
        return draft.usesRegex ? filter.pattern : draft.keywords.replacingOccurrences(of: "\n", with: " · ")
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
        groupCache.update(nodes: model.availableNodes, countryCodes: model.nodeIPCountryCodes,
                          countryCode: model.countryCode(for:))
        return groupCache.countries
    }

    private var protocolOptions: [ProtocolNodeExportGroup] {
        groupCache.update(nodes: model.availableNodes, countryCodes: model.nodeIPCountryCodes,
                          countryCode: model.countryCode(for:))
        return groupCache.protocols
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
            Divider()
            Button("完成") {}
                .menuActionDismissBehavior(.enabled)
        } label: {
            FilterRow(
                title: String(localized: "国家地区"),
                symbol: "globe.asia.australia",
                value: selectionSummary(countryOptions.map(\.nodes)),
                accessory: "chevron.up.chevron.down"
            )
        }
        // Region selection is a multi-select task: keep the native menu open
        // for toggles, and dismiss only via Done or a tap outside the menu.
        .menuActionDismissBehavior(.disabled)
        // A List tints a menu's label like a link; this row reads as a setting.
        .buttonStyle(.plain)
        .listRowInsets(FilterRow.insets)
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
            Divider()
            Button("完成") {}
                .menuActionDismissBehavior(.enabled)
        } label: {
            FilterRow(
                title: String(localized: "协议"),
                symbol: "network",
                value: selectionSummary(protocolOptions.map(\.nodes)),
                accessory: "chevron.up.chevron.down"
            )
        }
        // Keep the protocol menu open while selecting multiple kinds.
        .menuActionDismissBehavior(.disabled)
        // A List tints a menu's label like a link; this row reads as a setting.
        .buttonStyle(.plain)
        .listRowInsets(FilterRow.insets)
    }

    private func exportGroupSelectionToggle(
        title: String,
        nodes: [ProxyNode],
        kind: ProxyKind? = nil
    ) -> some View {
        // Set lookups only; the eligible array is built when a toggle is used.
        let includedIDs = model.includedNodeIDs
        let allowedIDs = model.nodeNameAllowedIDs
        var eligibleCount = 0
        var includedCount = 0
        for node in nodes where allowedIDs?.contains(node.id) ?? true {
            eligibleCount += 1
            if includedIDs.contains(node.id) { includedCount += 1 }
        }
        let selectionState = NodeExportGroupSelectionState(
            includedCount: includedCount,
            totalCount: eligibleCount
        )
        let countSummary = selectionState == .partial
            ? "\(includedCount)/\(eligibleCount)"
            : "\(eligibleCount)"

        return Toggle(
            isOn: Binding(
                get: { selectionState.isMenuSelected },
                set: { shouldInclude in
                    let eligibleNodes = allowedIDs.map { ids in nodes.filter { ids.contains($0.id) } } ?? nodes
                    model.setNodes(eligibleNodes, included: shouldInclude)
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
        .disabled(eligibleCount == 0)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let allowedByName = model.isNodeAllowedByName(node)
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
                Text(!allowedByName ? "名称不匹配" : (included ? "已启用" : "已停用"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(included ? Color.accentColor : Color.secondary)
                SelectionIndicator(isSelected: included)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!allowedByName)
        .accessibilityValue(included ? String(localized: "已启用") : String(localized: "已停用"))
    }

    private var resolutionTaskID: Int {
        model.availableNodes.map { "\($0.id):\($0.server)" }.hashValue
    }
}

/// The same editor used by policy-group name rules, with a separate saved
/// condition that controls which nodes reach every export destination.
struct NodeExportNameFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var previewResult: NodeNameFilterPreviewResult?
    @State private var saveError: String?
    let onSave: (NodeExportNameFilter?) throws -> Void

    init(filter: NodeExportNameFilter?, onSave: @escaping (NodeExportNameFilter?) throws -> Void) {
        _pattern = State(initialValue: filter?.pattern ?? "")
        self.onSave = onSave
    }

    private var previewInput: NodeNameFilterPreviewInput {
        .init(patterns: [pattern], candidates: model.availableNodes.map { [$0.name] }, insensitive: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NodeNameFilterFields(pattern: $pattern, caseInsensitiveDefault: true, simplified: true)
                } header: {
                    Text("节点名称")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("名称条件会用于所有客户端导出；订阅刷新后新增的节点也会自动匹配。")
                        Text("仅筛选本地节点；代理集合中的节点由客户端获取，不受此处筛选影响。")
                    }
                }
                NodeNameFilterPreview(input: previewInput, result: previewResult,
                    footer: String(localized: "预览基于当前已启用订阅的节点。手动取消勾选的节点仍不会导出。"))
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
                if model.nodeExportNameFilter != nil {
                    Section {
                        Button("清除名称筛选", role: .destructive) {
                            do {
                                try onSave(nil)
                                dismiss()
                            } catch { saveError = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle("节点名称筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try onSave(NodeExportNameFilter(pattern: pattern, ignoresCase: true))
                            dismiss()
                        } catch { saveError = error.localizedDescription }
                    }
                    .disabled(!pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && (previewResult?.input != previewInput || previewResult?.error != nil))
                }
            }
            .task(id: previewInput) {
                let input = previewInput
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                let result = await input.evaluate()
                guard !Task.isCancelled, input == previewInput else { return }
                previewResult = result
            }
        }
    }
}

/// One filter row. The title takes its space first; the current value
/// truncates instead, and moves under the title at accessibility sizes.
private struct FilterRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let symbol: String
    let value: String
    let accessory: String

    /// Tighter than a List's default so three settings read as one group.
    static let insets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                // The node rows' icon column, so every title on the page
                // starts on one line.
                .frame(width: 38)
                .accessibilityHidden(true)
            layout {
                Text(title)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(verbatim: value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Image(systemName: accessory)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
