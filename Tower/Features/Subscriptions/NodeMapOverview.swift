import CoreLocation
import SwiftUI

struct NodeMapPresentation {
    struct Inputs: Equatable {
        let nodes: [ProxyNode]
        let countryCodes: [UUID: String]
        let completedNodeIDs: Set<UUID>
    }

    let clusters: [NodeRegionCluster]
    let unlocatedCount: Int
    let pendingCount: Int

    static func revision(nodes: [ProxyNode], countryCodes: [UUID: String], completedNodeIDs: Set<UUID> = []) -> Int {
        var hasher = Hasher()
        hasher.combine(nodes)
        for node in nodes {
            hasher.combine(countryCodes[node.id])
            hasher.combine(completedNodeIDs.contains(node.id))
        }
        return hasher.finalize()
    }

    init(nodes: [ProxyNode], countryCodes: [UUID: String], completedNodeIDs: Set<UUID>? = nil) {
        clusters = NodeRegionResolver.clusters(for: nodes, countryCodes: countryCodes)
        let locatedCount = clusters.reduce(into: 0) { count, cluster in
            count += cluster.nodes.count
        }
        let locatedIDs = Set(clusters.flatMap { $0.nodes.map(\.id) })
        pendingCount = nodes.reduce(into: 0) { count, node in
            if !locatedIDs.contains(node.id), let completedNodeIDs, !completedNodeIDs.contains(node.id) {
                count += 1
            }
        }
        unlocatedCount = max(nodes.count - locatedCount - pendingCount, 0)
    }
}

struct NodeMapOverview<Header: View>: View, Equatable {
    // Parent layout/scroll updates don't change the map's inputs. Observation
    // inside this view still delivers country/latency changes independently.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.nodes == rhs.nodes }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    let nodes: [ProxyNode]
    /// Shares the map's card, above the map: the home page's counts. The map
    /// comes last so its latency key sits right above the region list that
    /// opens under the card. `==` compares nodes only, so a header observes
    /// what it shows by itself.
    let header: Header
    /// Scrolls the hosting page so a newly selected region's list is on
    /// screen. The list opens below the map and can start under the fold.
    var revealRegionNodes: (() -> Void)? = nil

    init(nodes: [ProxyNode], header: Header, revealRegionNodes: (() -> Void)? = nil) {
        self.nodes = nodes
        self.header = header
        self.revealRegionNodes = revealRegionNodes
    }

    @State private var selectedRegionCode: String?
    @State private var preparedRevision: NodeMapPresentation.Inputs?
    /// Only a batch started from the test button earns a completion haptic;
    /// stopping it, or a single node's retest elsewhere, stays silent.
    @State private var awaitsLatencyCompletion = false
    @State private var latencyCompletionFeedback = 0
    @State private var presentation = NodeMapPresentation(nodes: [], countryCodes: [:])

    var body: some View {
        let revision = presentationTaskID
        let isCurrent = preparedRevision == revision
        let clusters = presentation.clusters
        let selectedCluster = clusters.first { $0.id == selectedRegionCode }

        return VStack(alignment: .leading, spacing: 14) {
            map(clusters: clusters)
                .id(SubscriptionScrollTarget.regions)
            regionDetail(
                clusters: clusters,
                selectedCluster: selectedCluster,
                canShowUnavailable: isCurrent && presentation.pendingCount == 0
            )
            .padding(.horizontal, 4)
            .id(SubscriptionScrollTarget.nodes)
            .accessibilityIdentifier("nodes-section")
        }
        .sensoryFeedback(.selection, trigger: selectedRegionCode)
        .task(id: nodes) {
            await model.resolveIPCountries(for: nodes)
        }
        .task(id: revision) {
            guard preparedRevision != revision else { return }
            let latestNodes = nodes
            let countryCodes = model.nodeIPCountryCodes
            let completedNodeIDs = model.countryResolutionCompletedNodeIDs
            // Keep subscription selection responsive: render its selected
            // state first, then rebuild the map's derived clusters.
            await Task.yield()
            guard !Task.isCancelled else { return }
            // At 5,000 nodes this pure grouping pass can exceed a frame.
            // Only immutable inputs cross executors; publish on the view task.
            let worker = Task.detached(priority: .userInitiated) {
                NodeMapPresentation(nodes: latestNodes, countryCodes: countryCodes, completedNodeIDs: completedNodeIDs)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            presentation = prepared
            preparedRevision = revision
        }
        .onChange(of: clusters.map(\.id)) { _, clusterIDs in
            // A collapsed list stays collapsed; only a selection that no longer
            // exists is cleared.
            guard let selectedRegionCode, !clusterIDs.contains(selectedRegionCode) else { return }
            self.selectedRegionCode = nil
        }
        .onChange(of: isTestingAnyNode) { wasTesting, isTesting in
            guard wasTesting, !isTesting else { return }
            if awaitsLatencyCompletion { latencyCompletionFeedback += 1 }
            awaitsLatencyCompletion = false
        }
        .sensoryFeedback(.success, trigger: latencyCompletionFeedback)
    }

    private var isTestingAnyNode: Bool {
        nodes.contains { model.latencyTestingNodeIDs.contains($0.id) }
    }

    private func map(clusters: [NodeRegionCluster]) -> some View {
        VStack(spacing: 0) {
            header
            // On the map only: an identifier on the whole card is copied onto
            // every element inside it, the header's own buttons included.
            mapCanvas(clusters: clusters)
                .accessibilityIdentifier("regions-section")
        }
        // No inset: the map is meant to reach the card's edges.
        .clipShape(RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous))
        .towerCard()
    }

    private func mapCanvas(clusters: [NodeRegionCluster]) -> some View {
        let markers = markers(from: clusters)
        let hasLatencyResult = markers.contains { $0.latencyBand != .untested }
        return WorldDotMapView(markers: markers) { id in
            let isSelecting = selectedRegionCode != id
            withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) {
                // Tapping the selected marker again collapses its node list.
                selectedRegionCode = isSelecting ? id : nil
            }
            guard isSelecting, let revealRegionNodes else { return }
            // Reveal after the map has recentred, not during it: moving the
            // whole page under a moving map doubled the work of those frames.
            // The scroll is minimal and does nothing when the heading and
            // first rows are already visible.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 360))
                guard selectedRegionCode == id else { return }
                withAnimation(reduceMotion ? nil : TowerMotion.disclosure(reduceMotion: false)) {
                    revealRegionNodes()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            latencyButton
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        // The key sits in the map's empty southern band, so the colours are
        // explained where they are seen rather than in a strip under the card.
        .overlay(alignment: .bottomLeading) {
            ZStack {
                if hasLatencyResult {
                    latencyLegend.transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .allowsHitTesting(false)
            // Scoped to the key so the first result never animates the map.
            .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: hasLatencyResult)
        }
    }

    private var latencyButton: some View {
        let testingCount = nodes.reduce(into: 0) { count, node in
            if model.latencyTestingNodeIDs.contains(node.id) { count += 1 }
        }
        let isTestingAnyNode = testingCount > 0

        return Button {
            guard !nodes.isEmpty else { return }
            if isTestingAnyNode {
                awaitsLatencyCompletion = false
                model.cancelLatencyTests()
            } else {
                awaitsLatencyCompletion = true
                Task { await model.testLatencies(nodes, force: true) }
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    if isTestingAnyNode {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.accentColor)
                            .transition(.opacity)
                    } else {
                        Image(systemName: model.selectedLatencyTestMode.symbol)
                            .transition(.opacity)
                    }
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

                ZStack(alignment: .trailing) {
                    if isTestingAnyNode {
                        // Reserve the completed count's widest value so batches
                        // crossing 9/99 don't repeatedly resize the capsule.
                        Text(verbatim: "\(nodes.count)/\(nodes.count) · \(String(localized: "停止"))")
                            .hidden()
                            .overlay(alignment: .trailing) {
                                Text(verbatim: "\(nodes.count - testingCount)/\(nodes.count) · \(String(localized: "停止"))")
                            }
                            .monospacedDigit()
                            .transition(.opacity)
                    } else {
                        Text(String(localized: "测速"))
                            .transition(.opacity)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .frame(height: 34)
            // The same material as the map's own reset control: the button
            // floats over the map without outweighing what it measures.
            .background {
                Capsule()
                    .fill(reduceTransparency || contrast == .increased
                        ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                        : AnyShapeStyle(.regularMaterial))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.06), lineWidth: 1)
            }
            // Smaller to look at, not to hit: keep a 44pt tall target.
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .disabled(nodes.isEmpty)
        .accessibilityLabel(
            isTestingAnyNode
                ? String(localized: "停止测试全部节点")
                : String(localized: "测试全部节点，当前方式为 \(model.selectedLatencyTestMode.title)")
        )
        .accessibilityHint(isTestingAnyNode ? "轻点停止测试，保留已有结果" : "轻点开始测试；长按选择测试方式")
        .accessibilityIdentifier("test-all-latencies")
        .contextMenu {
            ForEach(NodeLatencyTestMode.allCases) { mode in
                Button {
                    model.selectedLatencyTestMode = mode
                } label: {
                    if model.selectedLatencyTestMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            }
        }
        // Keep the right edge anchored while the capsule changes width. Scope
        // motion to this control, never the map or every progress-count update.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(reduceMotion ? nil : TowerMotion.disclosure(reduceMotion: false), value: isTestingAnyNode)
    }

    private func markers(from clusters: [NodeRegionCluster]) -> [WorldDotMarker] {
        clusters.map { cluster in
            let summary = MapLatencySummary(nodes: cluster.nodes, measurements: model.nodeLatencies, testingIDs: model.latencyTestingNodeIDs)
            return WorldDotMarker(
                id: cluster.id,
                title: cluster.region.localizedName,
                latitude: cluster.region.latitude,
                longitude: cluster.region.longitude,
                weight: cluster.nodes.count,
                isSelected: selectedRegionCode == cluster.id,
                latencyBand: summary.band,
                isTesting: summary.testing
            )
        }
    }

    /// A ramp, like a weather map's key: the four measured bands read as one
    /// fast-to-slow scale between its two thresholds. It appears only once a
    /// region has a result; before that every country shares one colour and
    /// a key would explain nothing.
    private var latencyLegend: some View {
        let dark = colorScheme == .dark
        return HStack(spacing: 5) {
            Text(verbatim: "100")
            Capsule()
                .fill(LinearGradient(
                    colors: [MapLatencyBand.fast, .normal, .slow, .verySlow].map { $0.color(dark: dark) },
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 36, height: 4)
                .accessibilityHidden(true)
            Text(verbatim: "350 ms")
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(reduceTransparency || contrast == .increased
                    ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                    : AnyShapeStyle(.regularMaterial), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func regionDetail(
        clusters: [NodeRegionCluster],
        selectedCluster: NodeRegionCluster?,
        canShowUnavailable: Bool
    ) -> some View {
        if let cluster = selectedCluster {
            // One list whose rows change in place when another country is
            // picked. Keying the list by country made a switch fade the old
            // list out over the new one — two lists rendered and every row
            // rebuilt inside the recentring spring.
            SelectedRegionNodes(cluster: cluster) {
                withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) { selectedRegionCode = nil }
            }
        } else if !TowerPlatform.isMac && canShowUnavailable && clusters.isEmpty && !nodes.isEmpty {
            ContentUnavailableView(
                "还不能定位节点",
                systemImage: "mappin.slash",
                description: Text("优先使用手动地区和节点名称；未标注时查询离线 IP 国家库。")
            )
            .frame(minHeight: 130)
        }

    }

    private var presentationTaskID: NodeMapPresentation.Inputs {
        NodeMapPresentation.Inputs(nodes: nodes, countryCodes: model.nodeIPCountryCodes,
                                   completedNodeIDs: model.countryResolutionCompletedNodeIDs)
    }

}

private struct SelectedRegionNodes: View {
    @Environment(AppModel.self) private var model
    let cluster: NodeRegionCluster
    let onCollapse: () -> Void

    var body: some View {
        // Lazy for the same reason the subscription list is: a popular region
        // can hold a hundred nodes and only a few are ever on screen.
        LazyVStack(alignment: .leading, spacing: 0) {
            // The heading collapses the list, matching a second tap on the map
            // marker. Without it the only way back was to find the dot again.
            Button(action: onCollapse) {
                HStack {
                    RegionFlagEmoji(region: cluster.region, size: 25)
                        .frame(width: 31, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cluster.region.localizedName)
                            .font(.headline)
                        Text("\(cluster.nodes.count) 个节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let value = regionMedianLatency {
                        Label("\(value) ms", systemImage: "speedometer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(latencyColor(milliseconds: value))
                    }
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel(Text("收起 \(cluster.region.localizedName) 的节点"))
            .padding(.bottom, 4)

            ForEach(cluster.nodes) { node in
                CompactNodeRow(node: node, resolvesRegionOnAppear: false)
                    .overlay(alignment: .bottom) {
                        if node.id != cluster.nodes.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                    // Swapping countries replaces rows outright; only the
                    // list's height animates, never two sets of rows at once.
                    .transition(.identity)
            }
        }
        .padding(.top, 2)
        // What the page reveals after a map selection: the heading plus the
        // first few rows, not the whole list, so the map stays in view.
        .background(alignment: .top) {
            Color.clear
                .frame(height: 44 + CGFloat(min(cluster.nodes.count, 3)) * 60)
                .id(SubscriptionScrollTarget.selectedRegionNodes)
                .accessibilityHidden(true)
        }
    }

    private var regionMedianLatency: Int? {
        MapLatencySummary(nodes: cluster.nodes, measurements: model.nodeLatencies, testingIDs: model.latencyTestingNodeIDs).median
    }
}

struct CompactNodeRow: View {
    @Environment(AppModel.self) private var model
    let node: ProxyNode
    let resolvesRegionOnAppear: Bool
    @State private var sharePayload: SharePayload?
    @State private var showsDetails = false

    init(node: ProxyNode, resolvesRegionOnAppear: Bool = true) {
        self.node = node
        self.resolvesRegionOnAppear = resolvesRegionOnAppear
    }

    var body: some View {
        let presentedNode = model.nodeForPresentation(node)
        HStack(spacing: 8) {
            // A tap opens the same details the context menu offers; before,
            // these rows ignored taps while local node rows expanded on tap.
            Button { showsDetails = true } label: {
                HStack(spacing: 8) {
                    NodeRegionLogo(
                        node: node,
                        resolvesRegionOnAppear: resolvesRegionOnAppear,
                        diameter: 34
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        NodeDisplayNameLabel(node: presentedNode)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(node.protocolSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 6)
                    NodeLatencyBadge(node: node, showsUntestedState: false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SelectionIndicatorButtonStyle())
            .foregroundStyle(.primary)
            .accessibilityHint("轻点查看节点详情")

            Button {
                guard let latest = model.nodes.first(where: { $0.id == node.id }) else { return }
                sharePayload = SharePayloadFactory.node(model.nodeForPresentation(latest))
            } label: {
                RowIconButtonLabel(symbol: "square.and.arrow.up")
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel("分享 \(NodeRegionResolver.displayName(for: presentedNode))")
        }
        .frame(minHeight: 54)
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .contextMenu {
            Button("节点详情", systemImage: "info.circle") { showsDetails = true }
        }
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                ScrollView {
                    ExpandableNodeRow(node: model.nodes.first(where: { $0.id == node.id }) ?? node, presentsAsDetail: true)
                        .padding()
                }
                .navigationTitle("节点详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsDetails = false } } }
            }
            // Full height on purpose: from a medium-detent sheet, the country
            // picker's search field trips a UISearchController assertion
            // (`_setInlineSearchAccessoryEnabled:`) and the app aborts.
        }
        .sheet(item: $sharePayload) { payload in
            SharePayloadSheet(payload: payload)
        }
    }
}

struct ExpandableNodeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: ProxyNode
    let resolvesRegionOnAppear: Bool
    let usesInsetBackground: Bool
    let showsInclusionToggle: Bool
    /// Shown on its own in the details sheet: always open, nothing to fold.
    let presentsAsDetail: Bool
    let onDelete: (() -> Void)?
    @State private var isExpanded = false
    @State private var showsCountryPicker = false
    @State private var sharePayload: SharePayload?

    init(
        node: ProxyNode,
        resolvesRegionOnAppear: Bool = true,
        usesInsetBackground: Bool = true,
        showsInclusionToggle: Bool = false,
        presentsAsDetail: Bool = false,
        onDelete: (() -> Void)? = nil
    ) {
        self.node = node
        self.resolvesRegionOnAppear = resolvesRegionOnAppear
        self.usesInsetBackground = presentsAsDetail ? false : usesInsetBackground
        self.showsInclusionToggle = showsInclusionToggle
        self.presentsAsDetail = presentsAsDetail
        self.onDelete = onDelete
        self._isExpanded = State(initialValue: presentsAsDetail)
    }

    var body: some View {
        let presentedNode = model.nodeForPresentation(node)
        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    // The same geometry as `CompactNodeRow`, so a local node
                    // and a subscription node read as the same kind of row.
                    HStack(spacing: 8) {
                        NodeRegionLogo(
                            node: node,
                            resolvesRegionOnAppear: resolvesRegionOnAppear,
                            diameter: 34
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            NodeDisplayNameLabel(node: presentedNode)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(presentsAsDetail ? 2 : 1)
                            Text(node.protocolSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(presentsAsDetail ? 2 : 1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer(minLength: 6)
                        NodeLatencyBadge(node: node)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Not `.disabled`: that would dim the header text.
                .allowsHitTesting(!presentsAsDetail)
                .accessibilityLabel(
                    isExpanded
                        ? String(localized: "收起 \(NodeRegionResolver.displayName(for: presentedNode))")
                        : String(localized: "展开 \(NodeRegionResolver.displayName(for: presentedNode))")
                )

                Button {
                    sharePayload = SharePayloadFactory.node(presentedNode)
                } label: {
                    RowIconButtonLabel(symbol: "square.and.arrow.up")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityLabel("分享 \(NodeRegionResolver.displayName(for: presentedNode))")

                if showsInclusionToggle {
                    Toggle(
                        "启用 \(NodeRegionResolver.displayName(for: presentedNode))",
                        isOn: Binding(
                            get: { model.isNodeIncluded(node) },
                            set: { model.setNode(node, included: $0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(CheckmarkToggleStyle())
                    .frame(width: 34, height: 44)
                    .accessibilityIdentifier("node-inclusion-\(node.id)")
                    .accessibilityLabel("启用 \(NodeRegionResolver.displayName(for: presentedNode))")
                }
            }
            .modifier(CardSwipeDeletion(onDelete: onDelete))

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    // The protocol is the row's own subtitle; no second copy.
                    NodeDetailLine(label: "服务器", value: node.endpoint)
                    if let countryCode = node.countryOverride {
                        NodeCountryDetailLine(label: "手动地区", countryCode: countryCode)
                    } else if let countryCode = NodeRegionResolver.countryCode(for: node) {
                        NodeCountryDetailLine(label: "名称地区", countryCode: countryCode)
                    } else if let countryCode = model.ipCountryCode(for: node) {
                        NodeCountryDetailLine(label: "IP 地区", countryCode: countryCode)
                    } else {
                        NodeDetailLine(label: "IP 地区", value: String(localized: "未知"))
                    }
                    if let organizations = model.nodeNetworkOrganizations[node.id] {
                        NodeDetailLine(label: "网络组织", value: organizations.isEmpty
                            ? String(localized: "未知")
                            : organizations.map { "AS\($0.asn) · \($0.name)" }.joined(separator: "\n"))
                    }
                    Text("IP 地区和网络组织来自服务器地址，不代表实际出口。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Two equal actions on one line, both in the accent color,
                    // instead of a lone link above a tinted bar with dark text.
                    HStack(spacing: 8) {
                        Button { showsCountryPicker = true } label: {
                            NodeDetailActionLabel(title: "设置地区", symbol: "mappin.and.ellipse")
                        }
                        .buttonStyle(ResponsivePressButtonStyle())

                        Button {
                            Task { await model.testLatency(node) }
                        } label: {
                            NodeDetailActionLabel(title: "重新测试延迟", symbol: "gauge.with.dots.needle.50percent")
                        }
                        .buttonStyle(ResponsivePressButtonStyle())
                        .disabled(model.latencyTestingNodeIDs.contains(node.id))
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, presentsAsDetail ? 0 : 42)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 11)
        .background(
            usesInsetBackground ? Color.primary.opacity(0.045) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .geometryGroup()
        .clipped()
        .task(id: "\(node.server)|\(isExpanded)") {
            if isExpanded { await model.resolveNetworkDetails(for: node) }
        }
        .sheet(isPresented: $showsCountryPicker) {
            NodeCountryPicker(node: node)
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
        .sheet(item: $sharePayload) { payload in
            SharePayloadSheet(payload: payload)
        }
    }

}

private struct NodeDetailActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct NodeDisplayNameLabel: View {
    let node: ProxyNode

    var body: some View {
        Text(NodeRegionResolver.title(for: node))
    }
}

private struct NodeRegionLogo: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSwipeSizingCopy) private var isSwipeSizingCopy
    let node: ProxyNode
    let resolvesRegionOnAppear: Bool
    let diameter: CGFloat

    init(node: ProxyNode, resolvesRegionOnAppear: Bool, diameter: CGFloat = 42) {
        self.node = node
        self.resolvesRegionOnAppear = resolvesRegionOnAppear
        self.diameter = diameter
    }

    @ViewBuilder
    var body: some View {
        if resolvesRegionOnAppear {
            logo
                .task(id: node.server) {
                    // A name that already answers makes the lookup pointless
                    // work, and domain nodes would also need DNS resolution.
                    guard !isSwipeSizingCopy,
                          NodeRegionResolver.countryCode(for: node) == nil else { return }
                    model.resolveIPCountry(for: node)
                }
        } else {
            logo
        }
    }

    private var logo: some View {
        ZStack {
            // The node's own name decides the flag; the IP database only
            // answers for names that say nothing about where they are.
            if let countryCode = model.countryCode(for: node) {
                CountryFlagEmoji(countryCode: countryCode, size: diameter * 0.64)
            } else {
                ProtocolGlyph(kind: node.kind, size: diameter * 0.43)
                    .foregroundStyle(protocolTint)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var protocolTint: Color {
        switch node.kind {
        case .shadowsocks, .shadowsocksR: .blue
        case .vmess, .vless: .indigo
        case .trojan: .red
        case .hysteria, .hysteria2: .orange
        case .tuic, .masque: .pink
        case .wireguard: .green
        case .anytls: .mint
        case .snell: .brown
        case .socks5: .teal
        case .http: .cyan
        case .ssh: .gray
        case .trustTunnel: .purple
        case .unknown: .secondary
        }
    }
}

private struct NodeCountryDetailLine: View {
    let label: LocalizedStringKey
    let countryCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                CountryFlagEmoji(countryCode: countryCode, size: 15)
                    .frame(width: 19, height: 16)
                Text(AppLocalization.regionName(for: countryCode))
            }
            .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct RegionFlagEmoji: View {
    let region: NodeRegion
    let size: CGFloat

    var body: some View {
        CountryFlagEmoji(countryCode: region.code, size: size)
            .accessibilityLabel(region.localizedName)
    }
}

private struct CountryFlagEmoji: View {
    let countryCode: String
    let size: CGFloat

    var body: some View {
        // Every region draws as its plain regional-indicator pair. iOS ships no
        // glyph for a few of them, Taiwan included, so those render as the two
        // letters instead — which is still the country, just not as a picture.
        Text(NodeRegionResolver.flagEmoji(for: countryCode))
            .font(.system(size: size))
            .accessibilityLabel(countryName)
    }

    private var countryName: String {
        AppLocalization.regionName(for: countryCode)
    }
}

private struct NodeLatencyBadge: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: ProxyNode
    let showsUntestedState: Bool

    init(node: ProxyNode, showsUntestedState: Bool = true) {
        self.node = node
        self.showsUntestedState = showsUntestedState
    }

    private enum Phase: Equatable { case none, untested, testing, measured, failed }

    private var phase: Phase {
        if model.latencyTestingNodeIDs.contains(node.id) { return .testing }
        if let measurement = model.nodeLatencies[node.id] {
            return measurement.milliseconds == nil ? .failed : .measured
        }
        return showsUntestedState ? .untested : .none
    }

    var body: some View {
        let phase = phase
        ZStack(alignment: .trailing) {
            if phase == .testing {
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
            } else if let measurement = model.nodeLatencies[node.id] {
                if let milliseconds = measurement.milliseconds {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(milliseconds) ms")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(latencyColor(milliseconds: milliseconds))
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(milliseconds)))
                        Text(measurement.method?.rawValue ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                } else {
                    Text(verbatim: measurement.isApplicable ? String(localized: "不可达") : "—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(measurement.isApplicable ? MapLatencyBand.unreachable.color() : .secondary)
                        .accessibilityLabel(measurement.errorMessage ?? String(localized: "不可达"))
                        .transition(.opacity)
                }
            } else if phase == .untested {
                Text("待测试")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: phase)
        .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: model.nodeLatencies[node.id]?.milliseconds)
        // One stable slot while a batch streams results in, so each row's
        // name keeps its truncation point. Applied outside the animations:
        // only the badge's contents fade, the row layout never interpolates.
        .frame(minWidth: phase == .none ? 0 : 56, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

private struct NodeDetailLine: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 14)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

private func latencyColor(milliseconds: Int?) -> Color {
    guard let milliseconds else { return .secondary }
    return MapLatencyBand.measured(milliseconds).color()
}

extension NodeMapOverview where Header == EmptyView {
    init(nodes: [ProxyNode], revealRegionNodes: (() -> Void)? = nil) {
        self.init(nodes: nodes, header: EmptyView(), revealRegionNodes: revealRegionNodes)
    }
}
