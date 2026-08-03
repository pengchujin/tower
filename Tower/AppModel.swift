import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var subscriptions: [SubscriptionSource]
    var nodes: [ProxyNode]
    var selectedPresetID: String
    var selectedTarget: ClientTarget
    var selectedTab: AppTab = .subscriptions
    var refreshingSourceIDs: Set<UUID> = []
    var nodeLatencies: [UUID: NodeLatencyMeasurement] = [:]
    var latencyTestingNodeIDs: Set<UUID> = []
    var nodeIPCountryCodes: [UUID: String] = [:]
    var countryResolutionCompletedNodeIDs: Set<UUID> = []
    var toast: ToastMessage?

    private let persistence: PersistenceStore
    private let subscriptionService: SubscriptionService
    private let ruleRepository: RuleRepository
    private let exportService: ExportFileService
    private let latencyService: NodeLatencyService
    private let ipCountryLookupService: IPCountryLookupService
    private let isDemoMode: Bool
    @ObservationIgnored private var generationCache = ConfigurationCache()
    @ObservationIgnored private var countryResolutionInFlightNodeIDs: Set<UUID> = []

    init(
        persistence: PersistenceStore = PersistenceStore(),
        subscriptionService: SubscriptionService = SubscriptionService(),
        ruleRepository: RuleRepository = RuleRepository(),
        exportService: ExportFileService = ExportFileService(),
        latencyService: NodeLatencyService = NodeLatencyService(),
        ipCountryLookupService: IPCountryLookupService = IPCountryLookupService(),
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.persistence = persistence
        self.subscriptionService = subscriptionService
        self.ruleRepository = ruleRepository
        self.exportService = exportService
        self.latencyService = latencyService
        self.ipCountryLookupService = ipCountryLookupService
        self.isDemoMode = arguments.contains("--demo")

        if isDemoMode {
            let demo = Self.demoSnapshot
            subscriptions = demo.subscriptions
            nodes = demo.nodes
            selectedPresetID = demo.selectedPresetID
            selectedTarget = demo.selectedTarget
        } else if let snapshot = try? persistence.load() {
            subscriptions = snapshot.subscriptions
            nodes = snapshot.nodes
            selectedPresetID = RulePreset.builtIns.contains(where: { $0.id == snapshot.selectedPresetID })
                ? snapshot.selectedPresetID
                : RulePreset.builtIns[0].id
            selectedTarget = snapshot.selectedTarget
        } else {
            subscriptions = []
            nodes = []
            selectedPresetID = RulePreset.builtIns[0].id
            selectedTarget = .surge
        }

        if isDemoMode {
            let demoMilliseconds = [36, 72, 94]
            for (node, milliseconds) in zip(nodes, demoMilliseconds) {
                nodeLatencies[node.id] = .success(milliseconds: milliseconds, method: .icmp)
            }
        }

        if let tabArgument = arguments.first(where: { $0.hasPrefix("--tab=") }),
           let tab = AppTab(rawValue: String(tabArgument.dropFirst("--tab=".count))) {
            selectedTab = tab
        }
    }

    var selectedPreset: RulePreset {
        RulePreset.builtIns.first(where: { $0.id == selectedPresetID }) ?? RulePreset.builtIns[0]
    }

    var enabledNodes: [ProxyNode] {
        let enabledSourceIDs = Set(subscriptions.filter(\.isEnabled).map(\.id))
        return nodes.filter { node in
            node.sourceID == nil || enabledSourceIDs.contains(node.sourceID!)
        }
    }

    var localNodes: [ProxyNode] { nodes.filter(\.isLocal) }
    var enabledSubscriptionCount: Int { subscriptions.filter(\.isEnabled).count }
    var coveredCountryCount: Int {
        Set(enabledNodes.compactMap { node in
            nodeIPCountryCodes[node.id] ?? NodeRegionResolver.countryCode(for: node)
        }).count
    }
    var currentRuleCount: Int { ruleRepository.count(for: selectedPreset) }

    func nodes(for source: SubscriptionSource) -> [ProxyNode] {
        nodes.filter { $0.sourceID == source.id }
    }

    func latency(for node: ProxyNode) -> NodeLatencyMeasurement? {
        nodeLatencies[node.id]
    }

    func ipCountryCode(for node: ProxyNode) -> String? {
        nodeIPCountryCodes[node.id]
    }

    func hasResolvedIPCountry(for node: ProxyNode) -> Bool {
        countryResolutionCompletedNodeIDs.contains(node.id)
    }

    func resolveIPCountry(for node: ProxyNode) async {
        await resolveIPCountries(for: [node])
    }

    func resolveIPCountries(for nodes: [ProxyNode]) async {
        let candidates = nodes.filter {
            !countryResolutionCompletedNodeIDs.contains($0.id)
                && !countryResolutionInFlightNodeIDs.contains($0.id)
        }
        guard !candidates.isEmpty else { return }

        let candidateIDs = Set(candidates.map(\.id))
        countryResolutionInFlightNodeIDs.formUnion(candidateIDs)
        defer { countryResolutionInFlightNodeIDs.subtract(candidateIDs) }

        let service = ipCountryLookupService
        await withTaskGroup(of: (UUID, String?).self) { group in
            for node in candidates {
                group.addTask {
                    (node.id, await service.countryCode(forHost: node.server))
                }
            }

            for await (id, countryCode) in group {
                countryResolutionCompletedNodeIDs.insert(id)
                if let countryCode { nodeIPCountryCodes[id] = countryCode }
            }
        }
    }

    func testLatency(_ node: ProxyNode, force: Bool = true) async {
        await testLatencies([node], force: force)
    }

    func testLatencies(_ nodes: [ProxyNode], force: Bool = false) async {
        let uniqueNodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }).values
        let candidates = uniqueNodes.filter { node in
            !latencyTestingNodeIDs.contains(node.id)
                && (force || nodeLatencies[node.id] == nil)
        }
        guard !candidates.isEmpty else { return }

        let candidateIDs = Set(candidates.map(\.id))
        if force {
            for id in candidateIDs { nodeLatencies[id] = nil }
        }
        latencyTestingNodeIDs.formUnion(candidateIDs)
        defer { latencyTestingNodeIDs.subtract(candidateIDs) }

        let service = latencyService
        let orderedNodes = candidates.sorted {
            NodeRegionResolver.displayName(for: $0)
                .localizedStandardCompare(NodeRegionResolver.displayName(for: $1)) == .orderedAscending
        }

        for start in stride(from: 0, to: orderedNodes.count, by: 8) {
            guard !Task.isCancelled else { return }
            let end = min(start + 8, orderedNodes.count)
            let batch = Array(orderedNodes[start ..< end])

            await withTaskGroup(of: (UUID, NodeLatencyMeasurement?).self) { group in
                for node in batch {
                    group.addTask {
                        do {
                            return (node.id, try await service.measure(node))
                        } catch {
                            return (node.id, nil)
                        }
                    }
                }

                for await (id, measurement) in group {
                    latencyTestingNodeIDs.remove(id)
                    guard !Task.isCancelled, let measurement else { continue }
                    nodeLatencies[id] = measurement
                }
            }
        }
    }

    func ruleCount(for preset: RulePreset) -> Int {
        ruleRepository.count(for: preset)
    }

    func ruleCount(for assignment: RuleAssignment) -> Int {
        ruleRepository.count(for: assignment)
    }

    func addSubscription(name: String, urlString: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = SubscriptionSource(
            name: trimmedName.isEmpty ? (URL(string: urlString)?.host ?? "新订阅") : trimmedName,
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        refreshingSourceIDs.insert(source.id)
        defer { refreshingSourceIDs.remove(source.id) }

        let result = try await subscriptionService.fetch(source)
        var updated = source
        updated.lastUpdatedAt = .now
        subscriptions.append(updated)
        nodes.append(contentsOf: result.nodes)
        persist()
        showToast("已添加 \(result.nodes.count) 个节点", symbol: "checkmark.circle.fill")
    }

    func updateSubscription(id: UUID) async {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }),
              !refreshingSourceIDs.contains(id) else { return }
        refreshingSourceIDs.insert(id)
        defer { refreshingSourceIDs.remove(id) }

        do {
            let source = subscriptions[index]
            let result = try await subscriptionService.fetch(source)
            let replacedNodeIDs = Set(nodes.filter { $0.sourceID == source.id }.map(\.id))
            nodes.removeAll { $0.sourceID == source.id }
            for id in replacedNodeIDs {
                nodeLatencies[id] = nil
                nodeIPCountryCodes[id] = nil
                countryResolutionCompletedNodeIDs.remove(id)
            }
            nodes.append(contentsOf: result.nodes)
            subscriptions[index].lastUpdatedAt = .now
            subscriptions[index].lastError = nil
            persist()
            showToast("已更新 \(result.nodes.count) 个节点", symbol: "arrow.triangle.2.circlepath.circle.fill")
        } catch {
            subscriptions[index].lastError = error.localizedDescription
            persist()
            showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    func addLocalNode(name: String, uri: String) throws {
        let parser = SubscriptionParser()
        guard var node = parser.parseURI(uri, sourceID: nil) else {
            throw SubscriptionError.noSupportedNodes
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { node.name = trimmedName }
        nodes.append(node)
        persist()
        showToast("节点已保存在本机", symbol: "checkmark.circle.fill")
    }

    func deleteSubscription(_ source: SubscriptionSource) {
        subscriptions.removeAll { $0.id == source.id }
        let removedNodeIDs = Set(nodes.filter { $0.sourceID == source.id }.map(\.id))
        nodes.removeAll { $0.sourceID == source.id }
        for id in removedNodeIDs {
            nodeLatencies[id] = nil
            nodeIPCountryCodes[id] = nil
            countryResolutionCompletedNodeIDs.remove(id)
        }
        persist()
    }

    func deleteNode(_ node: ProxyNode) {
        nodes.removeAll { $0.id == node.id }
        nodeLatencies[node.id] = nil
        nodeIPCountryCodes[node.id] = nil
        countryResolutionCompletedNodeIDs.remove(node.id)
        persist()
    }

    func setSubscription(_ source: SubscriptionSource, enabled: Bool) {
        guard let index = subscriptions.firstIndex(where: { $0.id == source.id }) else { return }
        subscriptions[index].isEnabled = enabled
        persist()
    }

    func selectPreset(_ preset: RulePreset) {
        selectedPresetID = preset.id
        persist()
    }

    func selectTarget(_ target: ClientTarget) {
        selectedTarget = target
        persist()
    }

    func configuration(target: ClientTarget? = nil) -> GeneratedConfiguration {
        let resolvedTarget = target ?? selectedTarget
        let currentNodes = enabledNodes
        let currentNodeIDs = Set(currentNodes.map(\.id))
        let currentCountryCodes = nodeIPCountryCodes.filter { currentNodeIDs.contains($0.key) }
        let countryCodesHash = currentCountryCodes
            .map { "\($0.key.uuidString)=\($0.value.uppercased())" }
            .sorted()
            .joined(separator: "|")
            .hashValue
        let key = GenerationCacheKey(
            target: resolvedTarget,
            presetID: selectedPreset.id,
            nodesHash: currentNodes.hashValue,
            countryCodesHash: countryCodesHash
        )
        if let cached = generationCache[key] { return cached }
        let generated = ConfigurationGenerator(rules: ruleRepository).generate(
            nodes: currentNodes,
            preset: selectedPreset,
            target: resolvedTarget,
            countryCodes: currentCountryCodes
        )
        generationCache[key] = generated
        return generated
    }

    func makeExportURL() throws -> URL {
        try exportService.write(configuration())
    }

    func showToast(_ text: String, symbol: String) {
        toast = ToastMessage(text: text, symbol: symbol)
    }

    func dismissToast(id: UUID) {
        guard toast?.id == id else { return }
        toast = nil
    }

    private func persist() {
        guard !isDemoMode else { return }
        do {
            try persistence.save(
                AppSnapshot(
                    subscriptions: subscriptions,
                    nodes: nodes,
                    selectedPresetID: selectedPresetID,
                    selectedTarget: selectedTarget
                )
            )
        } catch {
            toast = ToastMessage(text: "保存失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    private static var demoSnapshot: AppSnapshot {
        let source = SubscriptionSource(
            name: "云帆机场",
            urlString: "https://example.com/private-subscription",
            lastUpdatedAt: .now
        )
        let nodes = [
            ProxyNode(
                sourceID: source.id,
                kind: .shadowsocks,
                name: "香港 · 高速 01",
                server: "hk1.example.com",
                port: 443,
                cipher: "chacha20-ietf-poly1305",
                password: "demo-password",
                rawURI: "ss://demo"
            ),
            ProxyNode(
                sourceID: source.id,
                kind: .vmess,
                name: "日本 · 流媒体",
                server: "jp1.example.com",
                port: 443,
                uuid: "5d1c3d8f-77b7-45c7-98c7-6fa54d37766e",
                transport: "ws",
                tls: true,
                sni: "jp1.example.com",
                hostHeader: "jp1.example.com",
                path: "/gateway",
                rawURI: "vmess://demo"
            ),
            ProxyNode(
                kind: .trojan,
                name: "自建 · 新加坡",
                server: "sg.example.net",
                port: 443,
                password: "demo-password",
                tls: true,
                sni: "sg.example.net",
                rawURI: "trojan://demo"
            )
        ]
        return AppSnapshot(
            subscriptions: [source],
            nodes: nodes,
            selectedPresetID: "self-configuration",
            selectedTarget: .surge
        )
    }
}

struct GenerationCacheKey: Hashable {
    let target: ClientTarget
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int

    fileprivate var signature: GenerationCacheSignature {
        GenerationCacheSignature(
            presetID: presetID,
            nodesHash: nodesHash,
            countryCodesHash: countryCodesHash
        )
    }
}

private struct GenerationCacheSignature: Hashable {
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int
}

struct ConfigurationCache {
    private var values: [GenerationCacheKey: GeneratedConfiguration] = [:]
    private var signature: GenerationCacheSignature?

    var count: Int { values.count }

    subscript(key: GenerationCacheKey) -> GeneratedConfiguration? {
        get { values[key] }
        set {
            guard let newValue else {
                values[key] = nil
                return
            }
            if signature != key.signature {
                values.removeAll(keepingCapacity: true)
                signature = key.signature
            }
            values[key] = newValue
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}
