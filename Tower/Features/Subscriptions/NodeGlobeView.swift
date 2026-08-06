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
        .task(id: latencyTaskID) {
            await model.testLatencies(nodes)
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
            WorldDotMapView(markers: markers) { entry in
                if let cluster = clusters.first(where: { $0.id == entry.id }) {
                    Button {
                        withAnimation(expansionAnimation) {
                            // Tapping the selected marker again collapses its
                            // node list.
                            selectedRegionCode = selectedRegionCode == cluster.id ? nil : cluster.id
                        }
                    } label: {
                        NodeRegionPin(
                            cluster: cluster,
                            bestLatency: bestLatency(in: cluster),
                            isSelected: selectedRegionCode == cluster.id
                        )
                    }
                    .buttonStyle(ResponsivePressButtonStyle())
                    .accessibilityLabel("\(cluster.region.name)，\(cluster.nodes.count) 个节点")
                }
            }
            .padding(.vertical, 10)
            .frame(height: 260)
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
                latitude: $0.region.latitude,
                longitude: $0.region.longitude
            )
        }
    }

    @ViewBuilder
    private var regionDetail: some View {
        if let cluster = selectedCluster {
            SelectedRegionNodes(cluster: cluster)
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

    private var latencyTaskID: String {
        "\(nodes.map(\.id).hashValue)"
    }

    private var ipCountryTaskID: String {
        "\(nodes.map { "\($0.id):\($0.server)" }.hashValue)"
    }

    private func bestLatency(in cluster: NodeRegionCluster) -> NodeLatencyMeasurement? {
        cluster.nodes
            .compactMap { model.nodeLatencies[$0.id] }
            .filter { $0.milliseconds != nil }
            .min { ($0.milliseconds ?? .max) < ($1.milliseconds ?? .max) }
    }

    private func isVisible(_ point: CGPoint, in size: CGSize) -> Bool {
        point.x >= 20 && point.x <= size.width - 20
            && point.y >= 20 && point.y <= size.height - 20
    }
}

private struct NodeRegionPin: View {
    let cluster: NodeRegionCluster
    let bestLatency: NodeLatencyMeasurement?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            RegionFlagEmoji(region: cluster.region, size: 20)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(cluster.region.name)
                    .font(.caption2.weight(.semibold))
                HStack(spacing: 3) {
                    Text("\(cluster.nodes.count) 个")
                    if let milliseconds = bestLatency?.milliseconds {
                        Text("· \(milliseconds)ms")
                            .foregroundStyle(latencyColor(milliseconds: milliseconds))
                    }
                }
                .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .white.opacity(0.45), lineWidth: isSelected ? 2 : 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }
}

private struct SelectedRegionNodes: View {
    @Environment(AppModel.self) private var model
    let cluster: NodeRegionCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            }

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
                    if let countryCode = model.ipCountryCode(for: node) {
                        NodeCountryDetailLine(label: "IP 地区", countryCode: countryCode)
                    } else if let countryCode = NodeRegionResolver.countryCode(for: node) {
                        NodeCountryDetailLine(label: "名称地区", countryCode: countryCode)
                    } else if let region = NodeRegionResolver.region(for: node) {
                        NodeRegionDetailLine(region: region)
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
            Circle()
                .fill(Color.primary.opacity(0.055))
            Circle()
                .stroke(.white.opacity(0.5), lineWidth: 0.75)

            if let countryCode = model.ipCountryCode(for: node)
                ?? NodeRegionResolver.countryCode(for: node) {
                CountryFlagEmoji(countryCode: countryCode, size: 25)
                    .frame(width: 32, height: 27)
            } else {
                Image(systemName: node.kind.symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(protocolTint)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
        .task(id: node.server) {
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

    @ViewBuilder
    var body: some View {
        if countryCode.uppercased() == "TW" {
            TaiwanFlagEmoji()
                .frame(width: size * 1.32, height: size * 0.88)
                .accessibilityLabel(countryName)
        } else {
            Text(flag)
                .font(.system(size: size))
                .accessibilityLabel(countryName)
        }
    }

    private var countryName: String {
        Locale.autoupdatingCurrent.localizedString(forRegionCode: countryCode) ?? countryCode
    }

    private var flag: String {
        countryCode.uppercased().unicodeScalars.compactMap { scalar in
            UnicodeScalar(127_397 + scalar.value).map(String.init)
        }.joined()
    }
}

private struct TaiwanFlagEmoji: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let cornerRadius = min(size.width, size.height) * 0.14
            let flag = Path(roundedRect: bounds, cornerRadius: cornerRadius)
            context.clip(to: flag)
            context.fill(flag, with: .color(Color(red: 0.94, green: 0.06, blue: 0.08)))

            let canton = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2)
            context.fill(Path(canton), with: .color(Color(red: 0.02, green: 0.19, blue: 0.49)))

            let center = CGPoint(x: canton.midX, y: canton.midY)
            let outerRadius = min(canton.width, canton.height) * 0.42
            let innerRadius = outerRadius * 0.56
            for ray in 0..<12 {
                let angle = -Double.pi / 2 + Double(ray) * Double.pi / 6
                var path = Path()
                path.move(to: point(center: center, radius: outerRadius, angle: angle))
                path.addLine(to: point(center: center, radius: innerRadius, angle: angle + Double.pi / 24))
                path.addLine(to: point(center: center, radius: innerRadius, angle: angle - Double.pi / 24))
                path.closeSubpath()
                context.fill(path, with: .color(.white))
            }

            let sunRadius = outerRadius * 0.46
            let sun = Path(ellipseIn: CGRect(
                x: center.x - sunRadius,
                y: center.y - sunRadius,
                width: sunRadius * 2,
                height: sunRadius * 2
            ))
            context.fill(sun, with: .color(.white))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(.white.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
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
