import CoreLocation
import SwiftUI

struct NodeGlobeOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let nodes: [ProxyNode]

    @State private var selectedRegionCode: String?
    @State private var didSelectInitialRegion = false

    init(nodes: [ProxyNode]) {
        self.nodes = nodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            map
                .id(SubscriptionScrollTarget.regions)
                .accessibilityIdentifier("regions-section")
            regionDetail
                .padding(.horizontal, 4)
                .id(SubscriptionScrollTarget.nodes)
                .accessibilityIdentifier("nodes-section")
        }
        .sensoryFeedback(.selection, trigger: selectedRegionCode)
        .onAppear {
            // Only the first appearance picks a region. Re-selecting here would
            // undo a deliberate collapse whenever the view comes back on screen.
            if !didSelectInitialRegion {
                didSelectInitialRegion = true
                selectedRegionCode = clusters.first?.id
            }
        }
        .task(id: ipCountryTaskID) {
            await model.resolveIPCountries(for: nodes)
        }
        .onChange(of: clusters.map(\.id)) { _, clusterIDs in
            // A collapsed list stays collapsed; only a selection that no longer
            // exists is cleared.
            guard let selectedRegionCode, !clusterIDs.contains(selectedRegionCode) else { return }
            self.selectedRegionCode = nil
        }
    }

    private var map: some View {
        ZStack(alignment: .topTrailing) {
            WorldDotMapView(markers: markers) { id in
                withAnimation(expansionAnimation) {
                    // Tapping the selected marker again collapses its node list.
                    selectedRegionCode = selectedRegionCode == id ? nil : id
                }
            }
            // No inset: the map is meant to reach the card's edges.
            .clipShape(RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous))
            .towerCard()

            Button {
                Task { await model.testLatencies(nodes, force: true) }
            } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel("重新测试全部节点延迟")
            .padding(12)
        }
    }

    private var markers: [WorldDotMarker] {
        clusters.map {
            WorldDotMarker(
                id: $0.id,
                title: $0.region.name,
                latitude: $0.region.latitude,
                longitude: $0.region.longitude,
                weight: $0.nodes.count,
                isSelected: selectedRegionCode == $0.id
            )
        }
    }

    @ViewBuilder
    private var regionDetail: some View {
        if let cluster = selectedCluster {
            SelectedRegionNodes(cluster: cluster) {
                withAnimation(expansionAnimation) { selectedRegionCode = nil }
            }
            .id(cluster.id)
        } else if clusters.isEmpty {
            ContentUnavailableView(
                "还不能定位节点",
                systemImage: "mappin.slash",
                description: Text("正在根据节点 IP 判断国家和地区；无法解析时会参考节点名称。")
            )
            .frame(minHeight: 130)
        }

        if unlocatedCount > 0 {
            Label("另有 \(unlocatedCount) 个节点暂时无法按 IP 或名称定位，仍可正常测试与导出。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Nil means the list is collapsed, so there is no fallback to the first
    /// cluster: that would make a second tap on a pin appear to do nothing.
    private var selectedCluster: NodeRegionCluster? {
        clusters.first { $0.id == selectedRegionCode }
    }

    private var clusters: [NodeRegionCluster] {
        NodeRegionResolver.clusters(for: nodes, countryCodes: model.nodeIPCountryCodes)
    }

    private var unlocatedCount: Int {
        NodeRegionResolver.unlocatedNodes(in: nodes, countryCodes: model.nodeIPCountryCodes).count
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .interactiveSpring(response: 0.36, dampingFraction: 1)
    }

    private var ipCountryTaskID: String {
        "\(nodes.map { "\($0.id):\($0.server)" }.hashValue)"
    }

}

private struct SelectedRegionNodes: View {
    @Environment(AppModel.self) private var model
    let cluster: NodeRegionCluster
    let onCollapse: () -> Void

    var body: some View {
        // Lazy for the same reason the subscription list is: a popular region
        // can hold a hundred nodes and only a few are ever on screen.
        LazyVStack(alignment: .leading, spacing: 10) {
            // The heading collapses the list, matching a second tap on the map
            // marker. Without it the only way back was to find the dot again.
            Button(action: onCollapse) {
                HStack {
                    RegionFlagEmoji(region: cluster.region, size: 25)
                        .frame(width: 31, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cluster.region.name)
                            .font(.headline)
                        Text("\(cluster.nodes.count) 个节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let value = bestLatency {
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
            .accessibilityLabel("收起 \(cluster.region.name) 的节点")

            ForEach(cluster.nodes) { node in
                ExpandableNodeRow(node: node)
            }
        }
        .padding(.top, 2)
    }

    private var bestLatency: Int? {
        cluster.nodes.compactMap { model.nodeLatencies[$0.id]?.milliseconds }.min()
    }
}

struct ExpandableNodeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: ProxyNode
    @State private var isExpanded = false
    @State private var sharePayload: SharePayload?

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(expansionAnimation) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        NodeRegionLogo(node: node)

                        VStack(alignment: .leading, spacing: 3) {
                            NodeDisplayNameLabel(node: node)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(node.protocolSummary)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .tracking(0.18)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer(minLength: 6)
                        NodeLatencyBadge(node: node)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityLabel(
                    isExpanded
                        ? "收起 \(NodeRegionResolver.displayName(for: node))"
                        : "展开 \(NodeRegionResolver.displayName(for: node))"
                )

                Button {
                    sharePayload = SharePayloadFactory.node(node)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("分享 \(NodeRegionResolver.displayName(for: node))")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    NodeDetailLine(label: "协议", value: node.protocolSummary)
                    NodeDetailLine(label: "服务器", value: node.endpoint)
                    if let countryCode = NodeRegionResolver.countryCode(for: node) {
                        NodeCountryDetailLine(label: "名称地区", countryCode: countryCode)
                    } else if let countryCode = model.ipCountryCode(for: node) {
                        NodeCountryDetailLine(label: "IP 地区", countryCode: countryCode)
                    }
                    if let measurement = model.nodeLatencies[node.id] {
                        NodeDetailLine(
                            label: "测试方式",
                            value: measurement.method?.rawValue ?? measurement.errorMessage ?? "不可达"
                        )
                    }

                    Button {
                        Task { await model.testLatency(node) }
                    } label: {
                        Label("重新测试延迟", systemImage: "gauge.with.dots.needle.50percent")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(ResponsivePressButtonStyle())
                    .disabled(model.latencyTestingNodeIDs.contains(node.id))
                }
                .padding(.leading, 54)
                .transition(.opacity)
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: isExpanded)
        .sheet(item: $sharePayload) { payload in
            SharePayloadSheet(payload: payload)
        }
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .interactiveSpring(response: 0.32, dampingFraction: 1)
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
    let node: ProxyNode

    var body: some View {
        ZStack {
            // The node's own name decides the flag; the IP database only
            // answers for names that say nothing about where they are.
            if let countryCode = NodeRegionResolver.countryCode(for: node)
                ?? model.ipCountryCode(for: node) {
                CountryFlagEmoji(countryCode: countryCode, size: 27)
            } else {
                Image(systemName: node.kind.symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(protocolTint)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
        .task(id: node.server) {
            // A name that already answers makes the lookup pointless work, and
            // for domain nodes that lookup costs a DNS resolution.
            guard NodeRegionResolver.countryCode(for: node) == nil else { return }
            await model.resolveIPCountry(for: node)
        }
    }

    private var protocolTint: Color {
        switch node.kind {
        case .shadowsocks, .shadowsocksR: .blue
        case .vmess, .vless: .indigo
        case .trojan: .red
        case .hysteria2: .orange
        case .anytls: .mint
        case .snell: .brown
        case .socks5: .teal
        case .http: .cyan
        case .unknown: .secondary
        }
    }
}

private struct NodeCountryDetailLine: View {
    let label: String
    let countryCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                CountryFlagEmoji(countryCode: countryCode, size: 15)
                    .frame(width: 19, height: 16)
                Text(Locale.autoupdatingCurrent.localizedString(forRegionCode: countryCode) ?? countryCode)
            }
            .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct NodeRegionDetailLine: View {
    let region: NodeRegion

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("地区")
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                RegionFlagEmoji(region: region, size: 15)
                    .frame(width: 19, height: 16)
                Text(region.name)
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
            .accessibilityLabel(region.name)
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
        Locale.autoupdatingCurrent.localizedString(forRegionCode: countryCode) ?? countryCode
    }
}

private struct NodeLatencyBadge: View {
    @Environment(AppModel.self) private var model
    let node: ProxyNode

    var body: some View {
        Group {
            if model.latencyTestingNodeIDs.contains(node.id) {
                ProgressView()
                    .controlSize(.mini)
                    .frame(minWidth: 48)
            } else if let measurement = model.nodeLatencies[node.id] {
                if let milliseconds = measurement.milliseconds {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(milliseconds) ms")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(latencyColor(milliseconds: milliseconds))
                        Text(measurement.method?.rawValue ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("不可达")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else {
                Text("待测试")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NodeDetailLine: View {
    let label: String
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
    switch milliseconds {
    case ...100: return .green
    case ...220: return .orange
    default: return .red
    }
}
