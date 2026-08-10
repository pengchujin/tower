import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let defaultRuleSchemeID = "acl4ssr-default"

    var subscriptions: [SubscriptionSource]
    var nodes: [ProxyNode]
    var selectedPresetID: String
    var selectedTarget: ClientTarget
    var selectedTab: AppTab = .subscriptions
    var refreshingSourceIDs: Set<UUID> = []
    var nodeLatencies: [UUID: NodeLatencyMeasurement] = [:]
    var latencyTestingNodeIDs: Set<UUID> = []
    var selectedLatencyTestMode: NodeLatencyTestMode = .automatic
    var nodeIPCountryCodes: [UUID: String] = [:]
    var countryResolutionCompletedNodeIDs: Set<UUID> = []
    var toast: ToastMessage?
    /// The persistent service credential is deliberately unrelated to every
    /// airport URL. Only this random token appears in LAN sharing links.
    var lanSharingToken = LANSubscriptionAccessTokenStore.loadOrCreate()
    var lanSharingURL: URL?
    var isLANSharingStarting = false
    var renewalRemindersEnabled = false
    var isUpdatingRenewalReminders = false
    var clientOrder = ClientTarget.allCases
    var appendSubscriptionNameToNodes = false
    var filterSubscriptionInfoNodes = false
    var configurationName = TowerBrand.localizedName
    var preferRuleSets = false
    private var preferRuleSetsWasExplicitlySet = false
    var exportContentModes: [ClientTarget: ExportContentMode] = [:]
    /// Schemes the user imported by URL. The bundled ACL4SSR ones live in the
    /// app bundle and are added by `ruleSchemes`.
    var importedSchemes: [RuleScheme] = []
    /// A missing scheme id means "follow the source exactly". Once the user
    /// changes a checkbox we keep the explicit set separately from the
    /// downloaded scheme, so refreshing that scheme cannot undo the choice.
    var selectedRuleGroups: [String: Set<String>] = [:]
    /// Missing means follow the source and show its emoji. Only explicit
    /// overrides are persisted so newly imported schemes retain their design.
    var ruleGroupEmojisEnabled: [String: Bool] = [:]
    var excludedNodeIDs: Set<UUID> = []
    /// User-authored flows are also stored outside imported schemes. This is
    /// what lets a Tailscale rule survive every upstream ruleset refresh.
    var customRuleFlows: [CustomRuleFlow] = []
    var importingSchemeIDs: Set<String> = []
    var isImportingScheme = false
    /// Protocols the user chose not to write, per client. A client may support
    /// a protocol while the user's licence does not — Surge needs a paid tier
    /// for AnyTLS — and Tower cannot detect that, so it is a manual choice.
    var excludedKinds: [ClientTarget: Set<ProxyKind>] = [:]

    private let persistence: PersistenceStore
    private let subscriptionService: any SubscriptionFetching
    private let ruleRepository: RuleRepository
    private let schemeRepository: RuleSchemeRepository
    private let schemeImportService: RuleSchemeImportService
    private let downloadStore: RuleDownloadStore
    private let exportService: ExportFileService
    private let latencyService: NodeLatencyService
    private let ipCountryLookupService: IPCountryLookupService
    private let reminderScheduler: any SubscriptionReminderScheduling
    private let isDemoMode: Bool
    /// Latency probes and DNS lookups both run in small batches so expanding a
    /// large subscription cannot flood the network stack or stall the main actor.
    private static let resolutionBatchSize = 8
    @ObservationIgnored private var generationCache = ConfigurationCache()
    @ObservationIgnored private var countryResolutionInFlightNodeIDs: Set<UUID> = []
    @ObservationIgnored private var lanSubscriptionServer: LANSubscriptionServer?

    init(
        persistence: PersistenceStore = PersistenceStore(),
        subscriptionService: any SubscriptionFetching = SubscriptionService(),
        ruleRepository: RuleRepository = RuleRepository(),
        schemeRepository: RuleSchemeRepository? = nil,
        schemeImportService: RuleSchemeImportService? = nil,
        downloadStore: RuleDownloadStore = RuleDownloadStore(),
        exportService: ExportFileService = ExportFileService(),
        latencyService: NodeLatencyService = NodeLatencyService(),
        ipCountryLookupService: IPCountryLookupService = IPCountryLookupService(),
        reminderScheduler: (any SubscriptionReminderScheduling)? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.persistence = persistence
        self.subscriptionService = subscriptionService
        self.ruleRepository = ruleRepository
        self.downloadStore = downloadStore
        // The repository resolves imported rule lists through the same store the
        // importer writes to, so a scheme keeps working offline after import.
        self.schemeRepository = schemeRepository ?? RuleSchemeRepository(downloadStore: downloadStore)
        self.schemeImportService = schemeImportService ?? RuleSchemeImportService(store: downloadStore)
        self.exportService = exportService
        self.latencyService = latencyService
        self.ipCountryLookupService = ipCountryLookupService
        self.reminderScheduler = reminderScheduler ?? SubscriptionReminderScheduler()
        self.isDemoMode = arguments.contains("--demo")

        if isDemoMode {
            let demo = Self.demoSnapshot
            subscriptions = demo.subscriptions
            nodes = demo.nodes
            selectedPresetID = demo.selectedPresetID
            selectedTarget = demo.selectedTarget
        } else if let snapshot = try? persistence.load() {
            subscriptions = snapshot.subscriptions.map { source in
                var source = source
                if Self.isCancellationMessage(source.lastError) { source.lastError = nil }
                return source
            }
            nodes = snapshot.nodes
            importedSchemes = snapshot.importedSchemes ?? []
            selectedRuleGroups = snapshot.selectedRuleGroups?.mapValues(Set.init) ?? [:]
            ruleGroupEmojisEnabled = snapshot.ruleGroupEmojisEnabled ?? [:]
            excludedNodeIDs = Set(snapshot.excludedNodeIDs ?? [])
            customRuleFlows = snapshot.customRuleFlows ?? []
            excludedKinds = Self.decodeExcludedKinds(snapshot.excludedKinds)
            renewalRemindersEnabled = snapshot.renewalRemindersEnabled ?? false
            clientOrder = ClientTargetOrder.normalized(rawValues: snapshot.clientOrder)
            appendSubscriptionNameToNodes = snapshot.appendSubscriptionNameToNodes ?? false
            filterSubscriptionInfoNodes = snapshot.filterSubscriptionInfoNodes ?? false
            configurationName = TowerBrand.migratedDefaultName(snapshot.configurationName)
            let ruleSetPreferenceWasExplicit = snapshot.preferRuleSetsWasExplicitlySet ?? false
            preferRuleSetsWasExplicitlySet = ruleSetPreferenceWasExplicit
            preferRuleSets = ruleSetPreferenceWasExplicit
                ? (snapshot.preferRuleSets ?? false)
                : false
            exportContentModes = Self.decodeExportContentModes(snapshot.exportContentModes)
            selectedPresetID = snapshot.selectedPresetID
            selectedTarget = snapshot.selectedTarget
        } else {
            subscriptions = []
            nodes = []
            selectedPresetID = Self.defaultRuleSchemeID
            selectedTarget = .surge
        }

        // Old builds stored this now-removed bundled preset id. Migrate it
        // without parsing every bundled scheme on the launch path.
        if selectedPresetID == "self-configuration" {
            selectedPresetID = Self.defaultRuleSchemeID
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

        if renewalRemindersEnabled {
            Task { [weak self] in
                await self?.synchronizeRenewalReminders(showFailure: false)
            }
        }
    }

    var selectedPreset: RulePreset {
        RulePreset.builtIns.first(where: { $0.id == selectedPresetID }) ?? RulePreset.builtIns[0]
    }

    /// Bundled ACL4SSR schemes first, then whatever the user imported.
    var ruleSchemes: [RuleScheme] {
        schemeRepository.bundledSchemes() + importedSchemes
    }

    /// The imported scheme in use, or nil when a built-in preset is selected.
    /// A stale id — a deleted scheme — resolves to nil and falls back to the
    /// built-in preset rather than leaving the app with no rules.
    var selectedScheme: RuleScheme? {
        ruleSchemes.first { $0.id == selectedPresetID }
    }

    var activeRuleName: String {
        selectedScheme?.name ?? selectedPreset.name
    }

    var selfConfigurationScheme: RuleScheme? {
        importedSchemes.first(where: SelfConfigurationSource.matches)
    }

    func ruleCount(for scheme: RuleScheme) -> Int {
        effectiveScheme(scheme).rulesets.reduce(0) {
            $0 + schemeRepository.lines(for: $1.resource).count
        }
    }

    func selectedRuleGroupNames(for scheme: RuleScheme) -> Set<String> {
        selectedRuleGroups[scheme.id] ?? Set(scheme.selectableRuleGroupNames)
    }

    func isRuleGroupSelectionCustomized(for scheme: RuleScheme) -> Bool {
        selectedRuleGroups[scheme.id] != nil
    }

    func setRuleGroup(_ name: String, enabled: Bool, for scheme: RuleScheme) {
        let available = Set(scheme.selectableRuleGroupNames)
        guard available.contains(name) else { return }

        var selection = selectedRuleGroups[scheme.id] ?? available
        if enabled {
            selection.insert(name)
        } else {
            selection.remove(name)
        }

        // The complete set is equivalent to the untouched upstream default.
        // Dropping the key also means newly added upstream groups become
        // enabled automatically until the user customizes the list again.
        selectedRuleGroups[scheme.id] = selection == available ? nil : selection
        persist()
    }

    func resetRuleGroupSelection(for scheme: RuleScheme) {
        selectedRuleGroups[scheme.id] = nil
        persist()
    }

    func ruleGroupEmojisAreEnabled(for scheme: RuleScheme) -> Bool {
        ruleGroupEmojisEnabled[scheme.id] ?? true
    }

    func setRuleGroupEmojisEnabled(_ enabled: Bool, for scheme: RuleScheme) {
        if enabled {
            ruleGroupEmojisEnabled[scheme.id] = nil
        } else {
            ruleGroupEmojisEnabled[scheme.id] = false
        }
        persist()
    }

    func customRuleFlows(for scheme: RuleScheme) -> [CustomRuleFlow] {
        customRuleFlows.filter { $0.schemeID == scheme.id }
    }

    func upsertCustomRuleFlow(_ flow: CustomRuleFlow) {
        if let index = customRuleFlows.firstIndex(where: { $0.id == flow.id }) {
            customRuleFlows[index] = flow
        } else {
            customRuleFlows.append(flow)
        }
        persist()
    }

    func setCustomRuleFlow(_ flow: CustomRuleFlow, enabled: Bool) {
        guard let index = customRuleFlows.firstIndex(where: { $0.id == flow.id }) else { return }
        customRuleFlows[index].isEnabled = enabled
        persist()
    }

    func deleteCustomRuleFlow(_ flow: CustomRuleFlow) {
        customRuleFlows.removeAll { $0.id == flow.id }
        persist()
    }

    func effectiveScheme(_ scheme: RuleScheme) -> RuleScheme {
        scheme.customized(
            enabledRuleGroupNames: selectedRuleGroups[scheme.id],
            customRuleFlows: customRuleFlows
        ).withGroupEmojis(ruleGroupEmojisAreEnabled(for: scheme))
    }

    /// True once every list a scheme references is available locally.
    func isSchemeReady(_ scheme: RuleScheme) -> Bool {
        if scheme.isBundled { return true }
        return scheme.remoteRulesetURLs.allSatisfy(downloadStore.hasCachedRules)
    }

    func selectScheme(_ scheme: RuleScheme) {
        selectedPresetID = scheme.id
        persist()
    }

    func importScheme(name: String, urlString: String) async throws {
        guard !isImportingScheme else { return }
        isImportingScheme = true
        defer { isImportingScheme = false }

        let result = try await schemeImportService.importScheme(from: urlString, name: name)
        importedSchemes.append(result.scheme)
        selectedPresetID = result.scheme.id
        persist()

        if result.failedRulesetCount > 0 {
            showToast(
                String(localized: "已导入 \(result.scheme.groups.count) 个策略组，\(result.failedRulesetCount) 个规则列表下载失败"),
                symbol: "exclamationmark.triangle.fill"
            )
        } else {
            showToast(String(localized: "已导入 \(result.scheme.groups.count) 个策略组"), symbol: "checkmark.circle.fill")
        }
    }

    /// Re-downloads the rule lists a scheme references. Bundled schemes read
    /// from the app bundle and have nothing to refresh.
    func refreshScheme(_ scheme: RuleScheme) async {
        guard !scheme.isBundled, !importingSchemeIDs.contains(scheme.id) else { return }
        importingSchemeIDs.insert(scheme.id)
        defer { importingSchemeIDs.remove(scheme.id) }

        let failed = await schemeImportService.refreshRulesets(for: scheme)
        if let index = importedSchemes.firstIndex(where: { $0.id == scheme.id }) {
            importedSchemes[index].updatedAt = .now
            persist()
        }

        if failed > 0 {
            showToast(String(localized: "\(failed) 个规则列表刷新失败"), symbol: "exclamationmark.triangle.fill")
        } else {
            showToast(String(localized: "规则已更新"), symbol: "arrow.triangle.2.circlepath.circle.fill")
        }
    }

    func deleteScheme(_ scheme: RuleScheme) {
        guard !scheme.isBundled else { return }
        importedSchemes.removeAll { $0.id == scheme.id }
        selectedRuleGroups[scheme.id] = nil
        ruleGroupEmojisEnabled[scheme.id] = nil
        customRuleFlows.removeAll { $0.schemeID == scheme.id }
        downloadStore.removeRules(for: scheme.remoteRulesetURLs)
        if selectedPresetID == scheme.id {
            selectedPresetID = Self.defaultRuleSchemeID
        }
        persist()
    }

    /// Nodes whose parent subscription is enabled, before the user's per-node
    /// export selection is applied. The filter screen and map use this list.
    var availableNodes: [ProxyNode] {
        let enabledSourceIDs = Set(subscriptions.filter(\.isEnabled).map(\.id))
        return nodes.filter { node in
            let sourceIsEnabled = node.sourceID == nil || enabledSourceIDs.contains(node.sourceID!)
            let metadataIsVisible = !filterSubscriptionInfoNodes || node.isSubscriptionMetadata != true
            return sourceIsEnabled && metadataIsVisible
        }
    }

    /// The single source of truth used by every configuration generator.
    var enabledNodes: [ProxyNode] {
        availableNodes.filter { !excludedNodeIDs.contains($0.id) }
    }

    var localNodes: [ProxyNode] { nodes.filter(\.isLocal) }
    var enabledSubscriptionCount: Int { subscriptions.filter(\.isEnabled).count }
    var coveredCountryCount: Int {
        Set(enabledNodes.compactMap(countryCode(for:))).count
    }
    var currentRuleCount: Int { ruleRepository.count(for: selectedPreset) }

    func nodes(for source: SubscriptionSource) -> [ProxyNode] {
        nodes.filter { $0.sourceID == source.id }
    }

    func nodeForPresentation(_ node: ProxyNode) -> ProxyNode {
        guard appendSubscriptionNameToNodes,
              let sourceID = node.sourceID,
              let sourceName = subscriptions.first(where: { $0.id == sourceID })?.name,
              !sourceName.isEmpty else { return node }
        let suffix = " · \(sourceName)"
        guard !node.name.hasSuffix(suffix) else { return node }
        var copy = node
        copy.name += suffix
        return copy
    }

    func setAppendSubscriptionNameToNodes(_ enabled: Bool) {
        guard appendSubscriptionNameToNodes != enabled else { return }
        appendSubscriptionNameToNodes = enabled
        persist()
    }

    func setFilterSubscriptionInfoNodes(_ enabled: Bool) {
        guard filterSubscriptionInfoNodes != enabled else { return }
        filterSubscriptionInfoNodes = enabled
        persist()
    }

    func setConfigurationName(_ value: String) {
        let resolved = ExportFilePresentation.profileName(value)
        guard configurationName != resolved else { return }
        configurationName = resolved
        persist()
    }

    func setPreferRuleSets(_ enabled: Bool) {
        guard preferRuleSets != enabled || !preferRuleSetsWasExplicitlySet else { return }
        preferRuleSets = enabled
        preferRuleSetsWasExplicitlySet = true
        persist()
    }

    func exportContentMode(for target: ClientTarget) -> ExportContentMode {
        let saved = exportContentModes[target] ?? .fullConfiguration
        return target.supportedContentModes.contains(saved) ? saved : .fullConfiguration
    }

    func setExportContentMode(_ mode: ExportContentMode, for target: ClientTarget) {
        let resolved = target.supportedContentModes.contains(mode) ? mode : .fullConfiguration
        guard exportContentMode(for: target) != resolved else { return }
        if resolved == .fullConfiguration {
            exportContentModes[target] = nil
        } else {
            exportContentModes[target] = resolved
        }
        persist()
    }

    func isNodeIncluded(_ node: ProxyNode) -> Bool {
        !excludedNodeIDs.contains(node.id)
    }

    func setNode(_ node: ProxyNode, included: Bool) {
        guard nodes.contains(where: { $0.id == node.id }) else { return }
        if included {
            excludedNodeIDs.remove(node.id)
        } else {
            excludedNodeIDs.insert(node.id)
        }
        persist()
    }

    /// Applies one export choice to a visible group in a single transaction.
    /// The filter screen can contain hundreds of nodes, so calling `setNode`
    /// for every row would rewrite the snapshot hundreds of times.
    func setNodes(_ selectedNodes: [ProxyNode], included: Bool) {
        let managedNodeIDs = Set(nodes.map(\.id))
        let selectedNodeIDs = Set(selectedNodes.map(\.id)).intersection(managedNodeIDs)
        guard !selectedNodeIDs.isEmpty else { return }

        if included {
            excludedNodeIDs.subtract(selectedNodeIDs)
        } else {
            excludedNodeIDs.formUnion(selectedNodeIDs)
        }
        persist()
    }

    func subscriptionName(for node: ProxyNode) -> String {
        guard let sourceID = node.sourceID else { return String(localized: "自有节点") }
        return subscriptions.first(where: { $0.id == sourceID })?.name ?? String(localized: "订阅节点")
    }

    func latency(for node: ProxyNode) -> NodeLatencyMeasurement? {
        nodeLatencies[node.id]
    }

    func ipCountryCode(for node: ProxyNode) -> String? {
        nodeIPCountryCodes[node.id]
    }

    /// The one place that decides which country a node belongs to.
    ///
    /// Name first, offline IP database only when the name says nothing — the
    /// order the map already used, and the order the policy groups are built
    /// with. The metric pill and the filter used to ask the other way round,
    /// and the IP lookup is asynchronous: every result that landed *replaced* a
    /// country the name had already settled, so the region count visibly
    /// climbed past its answer and came back down while resolution finished.
    func countryCode(for node: ProxyNode) -> String? {
        NodeRegionResolver.countryCode(for: node) ?? nodeIPCountryCodes[node.id]
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

        // Each lookup can block on getaddrinfo, and every visible node row asks
        // for its own. Without the same batching the latency probes use, opening
        // a large region starts one DNS resolution per node at once.
        let service = ipCountryLookupService
        for start in stride(from: 0, to: candidates.count, by: Self.resolutionBatchSize) {
            guard !Task.isCancelled else { return }
            let end = min(start + Self.resolutionBatchSize, candidates.count)
            let batch = Array(candidates[start ..< end])

            let result = await NodeCountryResolutionBatch.resolve(nodes: batch) { node in
                await service.countryCode(forHost: node.server)
            }
            guard !Task.isCancelled else { return }

            countryResolutionCompletedNodeIDs.formUnion(result.completedIDs)
            nodeIPCountryCodes.merge(result.countryCodes) { _, new in new }
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
            nodeLatencies = nodeLatencies.filter { !candidateIDs.contains($0.key) }
        }
        latencyTestingNodeIDs.formUnion(candidateIDs)
        defer { latencyTestingNodeIDs.subtract(candidateIDs) }

        let service = latencyService
        let testMode = selectedLatencyTestMode
        let orderedNodes = candidates.sorted {
            NodeRegionResolver.displayName(for: $0)
                .localizedStandardCompare(NodeRegionResolver.displayName(for: $1)) == .orderedAscending
        }

        for start in stride(from: 0, to: orderedNodes.count, by: Self.resolutionBatchSize) {
            guard !Task.isCancelled else { return }
            let end = min(start + Self.resolutionBatchSize, orderedNodes.count)
            let batch = Array(orderedNodes[start ..< end])

            let result = await NodeLatencyResultBatch.resolve(nodes: batch) { node in
                do {
                    return try await service.measure(node, mode: testMode)
                } catch {
                    return nil
                }
            }
            guard !Task.isCancelled else { return }

            latencyTestingNodeIDs.subtract(result.completedIDs)
            nodeLatencies.merge(result.measurements) { _, new in new }
        }
    }

    func isExcluded(_ kind: ProxyKind, for target: ClientTarget) -> Bool {
        excludedKinds[target]?.contains(kind) ?? false
    }

    func setExcluded(_ excluded: Bool, kind: ProxyKind, for target: ClientTarget) {
        var kinds = excludedKinds[target] ?? []
        if excluded { kinds.insert(kind) } else { kinds.remove(kind) }
        excludedKinds[target] = kinds.isEmpty ? nil : kinds
        persist()
    }

    /// Protocols present in the enabled nodes that the client could write, with
    /// how many nodes each covers. Only these are worth offering as a choice.
    func filterableKinds(for target: ClientTarget) -> [(kind: ProxyKind, count: Int)] {
        var counts: [ProxyKind: Int] = [:]
        for node in enabledNodes where target.supports(node.kind) {
            counts[node.kind, default: 0] += 1
        }
        return counts
            .map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.kind.title < $1.kind.title : $0.count > $1.count }
    }

    private static func decodeExcludedKinds(_ stored: [String: [String]]?) -> [ClientTarget: Set<ProxyKind>] {
        guard let stored else { return [:] }
        var result: [ClientTarget: Set<ProxyKind>] = [:]
        for (rawTarget, rawKinds) in stored {
            guard let target = ClientTarget(rawValue: rawTarget) else { continue }
            let kinds = Set(rawKinds.compactMap(ProxyKind.init(rawValue:)))
            if !kinds.isEmpty { result[target] = kinds }
        }
        return result
    }

    private static func encodeExcludedKinds(_ kinds: [ClientTarget: Set<ProxyKind>]) -> [String: [String]]? {
        guard !kinds.isEmpty else { return nil }
        return kinds.reduce(into: [String: [String]]()) { result, entry in
            guard !entry.value.isEmpty else { return }
            result[entry.key.rawValue] = entry.value.map(\.rawValue).sorted()
        }
    }

    private static func decodeExportContentModes(_ values: [String: String]?) -> [ClientTarget: ExportContentMode] {
        (values ?? [:]).reduce(into: [:]) { result, entry in
            guard let target = ClientTarget(rawValue: entry.key),
                  target.supportsNodesOnlyImport,
                  let mode = ExportContentMode(rawValue: entry.value),
                  mode == .nodesOnly else { return }
            result[target] = mode
        }
    }

    private static func encodeExportContentModes(_ values: [ClientTarget: ExportContentMode]) -> [String: String]? {
        let encoded = values.reduce(into: [String: String]()) { result, entry in
            guard entry.key.supportsNodesOnlyImport, entry.value == .nodesOnly else { return }
            result[entry.key.rawValue] = entry.value.rawValue
        }
        return encoded.isEmpty ? nil : encoded
    }

    func ruleCount(for preset: RulePreset) -> Int {
        ruleRepository.count(for: preset)
    }

    func ruleCount(for assignment: RuleAssignment) -> Int {
        ruleRepository.count(for: assignment)
    }

    func addSubscription(
        name: String,
        urlString: String,
        userAgent: String? = nil,
        dnsOverHTTPSURL: String? = nil
    ) async throws {
        try await addSubscriptions(
            name: name,
            urlStrings: [urlString],
            userAgent: userAgent,
            dnsOverHTTPSURL: dnsOverHTTPSURL
        )
    }

    func addSubscriptions(
        name: String,
        urlStrings: [String],
        userAgent: String? = nil,
        dnsOverHTTPSURL: String? = nil
    ) async throws {
        var seen = Set<String>()
        let urls = urlStrings.compactMap { rawValue -> String? in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
        guard !urls.isEmpty else { throw SubscriptionError.invalidURL }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = SubscriptionRequestOptions(
            userAgent: userAgent,
            dnsOverHTTPSURL: dnsOverHTTPSURL
        )
        let sources = urls.enumerated().map { index, urlString in
            let sourceName: String
            if !trimmedName.isEmpty {
                sourceName = urls.count == 1 ? trimmedName : "\(trimmedName) \(index + 1)"
            } else {
                sourceName = Self.fallbackSubscriptionName(urlString: urlString, index: index)
            }
            return SubscriptionSource(
                name: sourceName,
                urlString: urlString,
                requestOptions: options.isEmpty ? nil : options,
                nameWasAutoGenerated: trimmedName.isEmpty
            )
        }
        let sourceIDs = Set(sources.map(\.id))
        refreshingSourceIDs.formUnion(sourceIDs)
        defer { refreshingSourceIDs.subtract(sourceIDs) }

        var stagedSources: [SubscriptionSource] = []
        var stagedNodes: [ProxyNode] = []
        var rejectedLineCount = 0
        for source in sources {
            let result = try await subscriptionService.fetch(source)
            var updated = source
            if updated.nameWasAutoGenerated == true,
               let suggestedName = result.suggestedName {
                updated.name = suggestedName
            }
            updated.lastUpdatedAt = .now
            updated.usage = result.usage
            stagedSources.append(updated)
            stagedNodes.append(contentsOf: result.nodes)
            rejectedLineCount += result.rejectedLineCount
        }

        subscriptions.append(contentsOf: stagedSources)
        nodes.append(contentsOf: stagedNodes)
        persist()
        await synchronizeRenewalReminders(showFailure: false)
        let sourceSummary = sources.count == 1
            ? String(localized: "已添加")
            : String(localized: "已添加 \(sources.count) 个订阅，共")
        let result = ImportResult(nodes: stagedNodes, rejectedLineCount: rejectedLineCount, usage: nil)
        showToast(importSummary(sourceSummary, result: result), symbol: "checkmark.circle.fill")
    }

    /// Nodes the parser cannot represent faithfully — an unsupported SIP003
    /// plugin, a malformed line — are counted rather than dropped in silence,
    /// so the node total on screen always matches what was actually imported.
    private func importSummary(_ prefix: String, result: ImportResult) -> String {
        guard result.rejectedLineCount > 0 else {
            return String(localized: "\(prefix) \(result.nodes.count) 个节点")
        }
        return String(localized: "\(prefix) \(result.nodes.count) 个节点，跳过 \(result.rejectedLineCount) 条无法识别")
    }

    @discardableResult
    func updateSubscription(id: UUID) async -> Bool {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }),
              !refreshingSourceIDs.contains(id) else { return true }
        refreshingSourceIDs.insert(id)
        defer { refreshingSourceIDs.remove(id) }

        do {
            let source = subscriptions[index]
            let result = try await subscriptionService.fetch(source)
            let replacedNodes = nodes.filter { $0.sourceID == source.id }
            let replacedNodeIDs = Set(replacedNodes.map(\.id))
            let excludedKeys = Set(
                replacedNodes
                    .filter { excludedNodeIDs.contains($0.id) }
                    .map(Self.nodeRefreshIdentity)
            )
            nodes.removeAll { $0.sourceID == source.id }
            excludedNodeIDs.subtract(replacedNodeIDs)
            for id in replacedNodeIDs {
                nodeLatencies[id] = nil
                nodeIPCountryCodes[id] = nil
                countryResolutionCompletedNodeIDs.remove(id)
            }
            nodes.append(contentsOf: result.nodes)
            sortNodesToMatchSubscriptionOrder()
            excludedNodeIDs.formUnion(
                result.nodes
                    .filter { excludedKeys.contains(Self.nodeRefreshIdentity($0)) }
                    .map(\.id)
            )
            subscriptions[index].lastUpdatedAt = .now
            subscriptions[index].lastError = nil
            subscriptions[index].usage = result.usage
            if subscriptions[index].nameWasAutoGenerated == true,
               let suggestedName = result.suggestedName {
                subscriptions[index].name = suggestedName
            }
            persist()
            await synchronizeRenewalReminders(showFailure: false)
            showToast(importSummary(String(localized: "已更新"), result: result), symbol: "arrow.triangle.2.circlepath.circle.fill")
            return true
        } catch {
            if Self.isCancellationError(error) { return false }
            subscriptions[index].lastError = error.localizedDescription
            persist()
            showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            return false
        }
    }

    /// Pull-to-refresh is intentionally sequential: subscription providers
    /// often rate-limit bursts, and after the first failure continuing only
    /// hides the error beneath later success toasts while the spinner lingers.
    func refreshEnabledSubscriptions() async {
        for source in subscriptions where source.isEnabled {
            guard await updateSubscription(id: source.id) else { break }
        }
    }

    func addLocalNode(name: String, uri: String) throws {
        let result = try LocalNodeImporter().parse(uri, preferredName: name)
        nodes.append(contentsOf: result.nodes)
        persist()
        showToast(String(localized: "节点已保存在本机"), symbol: "checkmark.circle.fill")
    }

    @discardableResult
    func addLocalNodes(name: String, content: String) throws -> Int {
        let result = try LocalNodeImporter().parse(content, preferredName: name)
        nodes.append(contentsOf: result.nodes)
        persist()
        showToast(importSummary(String(localized: "已添加"), result: result), symbol: "checkmark.circle.fill")
        return result.nodes.count
    }

    func addManualNode(_ draft: ManualNodeDraft) throws {
        nodes.append(try draft.makeNode())
        persist()
        showToast(String(localized: "节点已保存在本机"), symbol: "checkmark.circle.fill")
    }

    func updateSubscriptionDetails(
        _ source: SubscriptionSource,
        name: String,
        urlString: String,
        userAgent: String?,
        dnsOverHTTPSURL: String?
    ) async throws {
        guard let index = subscriptions.firstIndex(where: { $0.id == source.id }) else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.host != nil,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw SubscriptionError.invalidURL
        }
        let options = SubscriptionRequestOptions(
            userAgent: userAgent,
            dnsOverHTTPSURL: dnsOverHTTPSURL
        )
        _ = try options.validatedDNSOverHTTPSURL()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = subscriptions[index]
        updated.name = trimmedName.isEmpty
            ? Self.fallbackSubscriptionName(urlString: trimmedURL, index: index)
            : trimmedName
        updated.urlString = trimmedURL
        updated.requestOptions = options.isEmpty ? nil : options
        updated.nameWasAutoGenerated = trimmedName.isEmpty
        updated.lastError = nil

        let requestChanged = source.urlString != trimmedURL || source.requestOptions != updated.requestOptions
        if requestChanged {
            refreshingSourceIDs.insert(source.id)
            defer { refreshingSourceIDs.remove(source.id) }
            let result = try await subscriptionService.fetch(updated)
            let replacedNodes = nodes.filter { $0.sourceID == source.id }
            let replacedNodeIDs = Set(replacedNodes.map(\.id))
            let excludedKeys = Set(
                replacedNodes
                    .filter { excludedNodeIDs.contains($0.id) }
                    .map(Self.nodeRefreshIdentity)
            )
            nodes.removeAll { $0.sourceID == source.id }
            excludedNodeIDs.subtract(replacedNodeIDs)
            for id in replacedNodeIDs {
                nodeLatencies[id] = nil
                nodeIPCountryCodes[id] = nil
                countryResolutionCompletedNodeIDs.remove(id)
            }
            nodes.append(contentsOf: result.nodes)
            excludedNodeIDs.formUnion(
                result.nodes
                    .filter { excludedKeys.contains(Self.nodeRefreshIdentity($0)) }
                    .map(\.id)
            )
            updated.lastUpdatedAt = .now
            updated.usage = result.usage
            if updated.nameWasAutoGenerated == true, let suggestedName = result.suggestedName {
                updated.name = suggestedName
            }
        }
        subscriptions[index] = updated
        persist()
        await synchronizeRenewalReminders(showFailure: false)
        showToast(String(localized: "已更新"), symbol: "checkmark.circle.fill")
    }

    func updateLocalNode(_ node: ProxyNode, with draft: ManualNodeDraft) throws {
        guard node.isLocal, let index = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[index] = try draft.makeNode(id: node.id)
        nodeLatencies[node.id] = nil
        nodeIPCountryCodes[node.id] = nil
        countryResolutionCompletedNodeIDs.remove(node.id)
        persist()
        showToast(String(localized: "节点已保存在本机"), symbol: "checkmark.circle.fill")
    }

    func moveSubscription(_ source: SubscriptionSource, by offset: Int) {
        guard let sourceIndex = subscriptions.firstIndex(where: { $0.id == source.id }) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), subscriptions.count - 1)
        guard destinationIndex != sourceIndex else { return }
        let value = subscriptions.remove(at: sourceIndex)
        subscriptions.insert(value, at: destinationIndex)
        sortNodesToMatchSubscriptionOrder()
        persist()
    }

    private func sortNodesToMatchSubscriptionOrder() {
        let sourceRanks = Dictionary(uniqueKeysWithValues: subscriptions.enumerated().map { ($1.id, $0) })
        nodes = nodes.enumerated().sorted { lhs, rhs in
            let lhsRank = lhs.element.sourceID.flatMap { sourceRanks[$0] } ?? subscriptions.count
            let rhsRank = rhs.element.sourceID.flatMap { sourceRanks[$0] } ?? subscriptions.count
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    func moveLocalNode(_ node: ProxyNode, by offset: Int) {
        let localIndices = nodes.indices.filter { nodes[$0].isLocal }
        guard let localPosition = localIndices.firstIndex(where: { nodes[$0].id == node.id }) else { return }
        let destinationPosition = min(max(localPosition + offset, 0), localIndices.count - 1)
        guard destinationPosition != localPosition else { return }
        nodes.swapAt(localIndices[localPosition], localIndices[destinationPosition])
        persist()
    }

    func canMoveSubscription(_ source: SubscriptionSource, by offset: Int) -> Bool {
        guard let index = subscriptions.firstIndex(where: { $0.id == source.id }) else { return false }
        return subscriptions.indices.contains(index + offset)
    }

    func canMoveLocalNode(_ node: ProxyNode, by offset: Int) -> Bool {
        let localNodes = self.localNodes
        guard let index = localNodes.firstIndex(where: { $0.id == node.id }) else { return false }
        return localNodes.indices.contains(index + offset)
    }

    func deleteSubscription(_ source: SubscriptionSource) {
        subscriptions.removeAll { $0.id == source.id }
        let removedNodeIDs = Set(nodes.filter { $0.sourceID == source.id }.map(\.id))
        nodes.removeAll { $0.sourceID == source.id }
        excludedNodeIDs.subtract(removedNodeIDs)
        for id in removedNodeIDs {
            nodeLatencies[id] = nil
            nodeIPCountryCodes[id] = nil
            countryResolutionCompletedNodeIDs.remove(id)
        }
        persist()
        Task { [weak self] in
            await self?.synchronizeRenewalReminders(showFailure: false)
        }
    }

    func deleteNode(_ node: ProxyNode) {
        nodes.removeAll { $0.id == node.id }
        excludedNodeIDs.remove(node.id)
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

    func moveClient(_ source: ClientTarget, before destination: ClientTarget) {
        guard source != destination,
              clientOrder.contains(source),
              clientOrder.contains(destination) else { return }
        var reordered = clientOrder
        reordered.removeAll { $0 == source }
        guard let destinationIndex = reordered.firstIndex(of: destination) else { return }
        reordered.insert(source, at: destinationIndex)
        guard reordered != clientOrder else { return }
        clientOrder = reordered
        persist()
    }

    func moveClient(_ target: ClientTarget, by offset: Int) {
        guard let sourceIndex = clientOrder.firstIndex(of: target) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), clientOrder.count - 1)
        guard destinationIndex != sourceIndex else { return }
        var reordered = clientOrder
        let value = reordered.remove(at: sourceIndex)
        reordered.insert(value, at: destinationIndex)
        clientOrder = reordered
        persist()
    }

    func configuration(
        target: ClientTarget? = nil,
        contentMode: ExportContentMode? = nil
    ) -> GeneratedConfiguration {
        let resolvedTarget = target ?? selectedTarget
        let resolvedMode = contentMode ?? exportContentMode(for: resolvedTarget)
        let currentNodes = enabledNodes.map(nodeForPresentation)
        let currentNodeIDs = Set(currentNodes.map(\.id))
        let currentCountryCodes = nodeIPCountryCodes.filter { currentNodeIDs.contains($0.key) }
        let countryCodesHash = currentCountryCodes
            .map { "\($0.key.uuidString)=\($0.value.uppercased())" }
            .sorted()
            .joined(separator: "|")
            .hashValue
        let scheme = selectedScheme.map(effectiveScheme)
        let excluded = excludedKinds[resolvedTarget] ?? []
        let key = GenerationCacheKey(
            target: resolvedTarget,
            presetID: scheme?.id ?? selectedPreset.id,
            nodesHash: currentNodes.hashValue,
            countryCodesHash: countryCodesHash,
            rulesHash: scheme?.hashValue ?? selectedPreset.hashValue,
            // Without this, toggling a protocol would keep serving the cached
            // configuration for that client.
            excludedHash: excluded.map(\.rawValue).sorted().joined(separator: "|").hashValue,
            preferRuleSets: preferRuleSets
        )
        if let cached = generationCache[key] {
            let named = cached.named(configurationName)
            switch resolvedMode {
            case .fullConfiguration:
                return named
            case .nodesOnly:
                return generatorForNodeOnly().generateNodeSubscription(
                    nodes: currentNodes,
                    target: resolvedTarget,
                    excludedKinds: excluded,
                    profileName: configurationName
                )
            case .rulesOnly:
                return generatorForNodeOnly().generateQuanXRuleSubscription(
                    from: named,
                    profileName: configurationName
                )
            }
        }

        let generator = ConfigurationGenerator(rules: ruleRepository)
        let generated: GeneratedConfiguration
        if let scheme {
            generated = generator.generate(
                nodes: currentNodes,
                scheme: scheme,
                target: resolvedTarget,
                schemes: schemeRepository,
                excludedKinds: excluded,
                preferRuleSets: preferRuleSets
            )
        } else {
            generated = generator.generate(
                nodes: currentNodes,
                preset: selectedPreset,
                target: resolvedTarget,
                countryCodes: currentCountryCodes,
                excludedKinds: excluded
            )
        }
        generationCache[key] = generated
        if resolvedMode == .nodesOnly {
            return generator.generateNodeSubscription(
                nodes: currentNodes,
                target: resolvedTarget,
                excludedKinds: excluded,
                profileName: configurationName
            )
        }
        let named = generated.named(configurationName)
        if resolvedMode == .rulesOnly {
            return generator.generateQuanXRuleSubscription(
                from: named,
                profileName: configurationName
            )
        }
        return named
    }

    private func generatorForNodeOnly() -> ConfigurationGenerator {
        ConfigurationGenerator(rules: ruleRepository)
    }

    var isLANSharingActive: Bool { lanSharingURL != nil }

    /// Starts a foreground LAN endpoint. iOS may suspend all networking after
    /// Tower leaves the foreground, so the Settings screen communicates that
    /// Tower must remain open while a desktop client refreshes.
    func startLANSharing() async {
        guard !isLANSharingStarting, !isLANSharingActive else { return }
        guard !enabledNodes.isEmpty else {
            showToast(String(localized: "请先添加一个可用节点"), symbol: "exclamationmark.triangle.fill")
            return
        }

        isLANSharingStarting = true
        defer { isLANSharingStarting = false }

        let server = LANSubscriptionServer(token: lanSharingToken) { [weak self] target in
            guard let self else {
                return GeneratedConfiguration(
                    target: target,
                    content: "",
                    supportedNodeCount: 0,
                    skippedNodeCount: 0,
                    ruleCount: 0
                )
            }
            return self.configuration(target: target, contentMode: .fullConfiguration)
        }
        lanSubscriptionServer = server

        do {
            lanSharingURL = try await server.start()
            showToast(String(localized: "局域网订阅已开启"), symbol: "wifi.circle.fill")
        } catch {
            server.stop()
            lanSubscriptionServer = nil
            lanSharingURL = nil
            showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    func stopLANSharing() {
        lanSubscriptionServer?.stop()
        lanSubscriptionServer = nil
        lanSharingURL = nil
        showToast(String(localized: "局域网订阅已关闭"), symbol: "wifi.slash")
    }

    func rotateLANSharingToken() {
        if isLANSharingActive { stopLANSharing() }
        lanSharingToken = LANSubscriptionAccessTokenStore.rotate()
        showToast(String(localized: "访问密钥已更换，旧链接已失效"), symbol: "key.fill")
    }

    func lanSubscriptionURL(target: ClientTarget?) -> URL? {
        guard let activeURL = lanSharingURL,
              let host = activeURL.host,
              let port = activeURL.port else { return nil }
        return try? LANSubscriptionURLBuilder.make(
            host: host,
            port: UInt16(port),
            token: lanSharingToken,
            target: target?.rawValue
        )
    }

    var scheduledRenewalReminderCount: Int {
        scheduledRenewalReminders.count
    }

    var scheduledRenewalReminders: [SubscriptionReminderPlan] {
        SubscriptionReminderPlanner.plans(for: subscriptions)
    }

    var renewalReminderEntries: [SubscriptionExpiryEntry] {
        SubscriptionReminderPlanner.expiryEntries(for: subscriptions)
    }

    func setRenewalRemindersEnabled(_ enabled: Bool) async {
        guard !isUpdatingRenewalReminders, renewalRemindersEnabled != enabled else { return }
        isUpdatingRenewalReminders = true
        defer { isUpdatingRenewalReminders = false }

        if enabled {
            do {
                guard try await reminderScheduler.requestAuthorization() else {
                    showToast(String(localized: "没有获得通知权限，续费提醒未开启"), symbol: "bell.slash.fill")
                    return
                }
                renewalRemindersEnabled = true
                persist()
                await synchronizeRenewalReminders(showFailure: true)
                let count = scheduledRenewalReminderCount
                showToast(
                    count == 0
                        ? String(localized: "已开启，检测到到期时间后会提醒")
                        : String(localized: "已安排 \(count) 个续费提醒"),
                    symbol: "bell.badge.fill"
                )
            } catch {
                showToast(String(localized: "通知权限请求失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
            }
        } else {
            renewalRemindersEnabled = false
            persist()
            await reminderScheduler.removeReminders()
            showToast(String(localized: "续费提醒已关闭"), symbol: "bell.slash.fill")
        }
    }

    private func synchronizeRenewalReminders(showFailure: Bool) async {
        guard renewalRemindersEnabled else { return }
        do {
            try await reminderScheduler.replaceReminders(
                with: SubscriptionReminderPlanner.plans(for: subscriptions)
            )
        } catch {
            if showFailure {
                showToast(String(localized: "安排提醒失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
            }
        }
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
                    selectedTarget: selectedTarget,
                    importedSchemes: importedSchemes,
                    selectedRuleGroups: selectedRuleGroups.isEmpty
                        ? nil
                        : selectedRuleGroups.mapValues { $0.sorted() },
                    ruleGroupEmojisEnabled: ruleGroupEmojisEnabled.isEmpty
                        ? nil
                        : ruleGroupEmojisEnabled,
                    excludedNodeIDs: excludedNodeIDs.isEmpty
                        ? nil
                        : excludedNodeIDs.sorted { $0.uuidString < $1.uuidString },
                    customRuleFlows: customRuleFlows.isEmpty ? nil : customRuleFlows,
                    excludedKinds: Self.encodeExcludedKinds(excludedKinds),
                    renewalRemindersEnabled: renewalRemindersEnabled,
                    clientOrder: clientOrder.map(\.rawValue),
                    appendSubscriptionNameToNodes: appendSubscriptionNameToNodes,
                    filterSubscriptionInfoNodes: filterSubscriptionInfoNodes,
                    configurationName: configurationName,
                    preferRuleSets: preferRuleSets,
                    preferRuleSetsWasExplicitlySet: preferRuleSetsWasExplicitlySet,
                    exportContentModes: Self.encodeExportContentModes(exportContentModes)
                )
            )
        } catch {
            toast = ToastMessage(text: String(localized: "保存失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
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
            selectedPresetID: Self.defaultRuleSchemeID,
            selectedTarget: .surge
        )
    }

    private static func nodeRefreshIdentity(_ node: ProxyNode) -> String {
        [
            node.kind.rawValue,
            node.server.lowercased(),
            String(node.port),
            node.name,
            node.rawURI,
        ].joined(separator: "|")
    }

    private static func fallbackSubscriptionName(urlString: String, index: Int) -> String {
        guard let host = URL(string: urlString)?.host else {
            return String(localized: "新订阅 \(index + 1)")
        }
        let labels = host.split(separator: ".").map(String.init)
        return labels.first(where: { $0.lowercased() != "www" }) ?? host
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return (error as? URLError)?.code == .cancelled
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
    }

    private static func isCancellationMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["已取消", "cancelled", "canceled"].contains(normalized)
            || normalized.contains("nsurlerrordomain error -999")
    }
}

struct GenerationCacheKey: Hashable {
    let target: ClientTarget
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int
    let rulesHash: Int
    let excludedHash: Int
    let preferRuleSets: Bool

    init(
        target: ClientTarget,
        presetID: String,
        nodesHash: Int,
        countryCodesHash: Int,
        rulesHash: Int = 0,
        excludedHash: Int = 0,
        preferRuleSets: Bool = true
    ) {
        self.target = target
        self.presetID = presetID
        self.nodesHash = nodesHash
        self.countryCodesHash = countryCodesHash
        self.rulesHash = rulesHash
        self.excludedHash = excludedHash
        self.preferRuleSets = preferRuleSets
    }

    fileprivate var signature: GenerationCacheSignature {
        GenerationCacheSignature(
            presetID: presetID,
            nodesHash: nodesHash,
            countryCodesHash: countryCodesHash,
            rulesHash: rulesHash
        )
    }
}

private struct GenerationCacheSignature: Hashable {
    let presetID: String
    let nodesHash: Int
    let countryCodesHash: Int
    let rulesHash: Int
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
