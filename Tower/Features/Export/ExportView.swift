import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surgeSchemeAvailable = false
    @State private var preparedConfiguration: GeneratedConfiguration?
    @State private var preparedRequest: ConfigurationRequest?
    @State private var sharePayload: ExportPayload?
    @State private var directImportService = DirectImportService()
    @State private var macDocument: MacConfigurationDocument?
    @State private var isSavingMacFile = false
    @State private var macFileName = "Tower"
    @State private var isImporting = false
    @State private var isSettingsPresented = false
    @State private var isProtocolFilterPresented = false
    @State private var isLANSharingSelected = false
    @State private var configurationNameDraft = ConfigurationNameDraft()
    /// Long enough for the Settings sheet to finish sliding away.
    static let settingsDismissDelay: Duration = .milliseconds(450)
    @State private var previewPayload: ConfigurationPreviewPayload?
    /// The cold request that has been generating long enough to say so.
    @State private var pendingStatusRequest: ConfigurationRequest?

    var body: some View {
        // The LAN destination does not have one fixed configuration: the
        // requesting client chooses the format through its User-Agent or the
        // explicit target in the link. Avoid generating an unrelated client
        // profile while this destination is selected.
        let request = isLANSharingSelected ? nil : model.configurationRequest()
        let configuration = request.flatMap { model.cachedConfiguration(for: $0) }
            ?? (preparedRequest == request ? preparedConfiguration : nil)
        // The header describes the last completed conversion. Keep it mounted
        // while the next result is prepared; a timer that replaces the seal with
        // a spinner creates a visible ready/busy/ready flash on cold targets.
        // Only `configuration` (the current request) may enable export/preview.
        let statusConfiguration = configuration ?? preparedConfiguration
        // Most switches hit the cache (neighbours are prepared while idle), so
        // the header changes in one frame. A slower cold generation keeps the
        // same icon view and only dims it, with the title fading in place —
        // swapping the seal for a spinner is what used to flash.
        let showsPending = configuration == nil
            && (statusConfiguration == nil || (request != nil && pendingStatusRequest == request))
        let headerConfiguration = showsPending ? nil : statusConfiguration

        ScrollView {
            VStack(spacing: 22) {
                ClientPicker(
                    isLANSharingSelected: $isLANSharingSelected,
                    activateLANSharing: activateLANSharing
                )

                VStack(spacing: 22) {
                    if isLANSharingSelected {
                        LANSharingDestinationCard()
                            .transition(.opacity.animation(TowerMotion.selection(reduceMotion: reduceMotion)))
                        LANSharingGuide()
                            .transition(.opacity.animation(TowerMotion.selection(reduceMotion: reduceMotion)))
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                HStack(alignment: .center, spacing: 12) {
                                    Text(headerConfiguration == nil ? "正在转换…" : headerConfiguration!.hasExportableProxies ? "转换已就绪" : "暂时无法导出")
                                        .font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .contentTransition(.opacity)
                                    Spacer(minLength: 0)
                                    Image(systemName: statusConfiguration?.hasExportableProxies == false
                                          ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                        .font(.title2)
                                        .foregroundStyle(statusConfiguration?.hasExportableProxies == false
                                                         ? Color.orange : Color.green)
                                        .contentTransition(.symbolEffect(.replace))
                                        .frame(width: 28, height: 28)
                                        .opacity(statusConfiguration == nil ? 0 : showsPending ? 0.3 : 1)
                                        .accessibilityHidden(true)
                                }
                                // Scoped to the header's own text and icon; layout
                                // never animates, so the card below cannot jump.
                                .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: headerConfiguration?.hasExportableProxies)
                                .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: showsPending)
                                .accessibilityIdentifier("conversion-status-header")
                                .padding(.bottom, 18)
                            }
                            // A failed name condition exports no nodes by design;
                            // say why here instead of only in the filter screen.
                            if let error = model.nodeExportNameFilterError {
                                Label {
                                    Text("节点名称筛选无法完成，当前不会导出节点：\(error)")
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)
                                .accessibilityIdentifier("export-name-filter-error")
                            }
                            ExportContentModePicker()
                                .padding(.bottom, model.selectedTarget.supportedContentModes.count > 1 ? 12 : 0)
                            if model.exportContentMode(for: model.selectedTarget) == .fullConfiguration {
                                Button { model.selectedTab = .rules } label: {
                                    ExportOptionRow(title: "规则方案", value: model.activeRuleName, symbol: "list.bullet.rectangle")
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                            if ProtocolFilterPolicy.isVisible(compatibleKindCount: model.filterableKinds(for: model.selectedTarget).count) {
                                Button { isProtocolFilterPresented = true } label: {
                                    ExportOptionRow(title: "协议筛选", value: protocolSelectionSummary, compactValue: protocolSelectionCount, symbol: "line.3.horizontal.decrease")
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("open-protocol-filter")
                                Divider()
                            }
                            if model.exportContentMode(for: model.selectedTarget) == .fullConfiguration {
                                ExportAdvancedOptions()
                                Divider()
                            }
                            if let displayedConfiguration = configuration ?? preparedConfiguration {
                                VStack(alignment: .leading, spacing: 0) {
                                    ConversionSummary(configuration: displayedConfiguration)
                                        .padding(.vertical, 14)
                                    ConfigurationPreview(configuration: displayedConfiguration) {
                                        guard let configuration else { return }
                                        previewPayload = ConfigurationPreviewPayload(configuration: configuration)
                                    }
                                }
                                .redacted(reason: configuration == nil ? .placeholder : [])
                                .disabled(configuration == nil)
                                .accessibilityHidden(configuration == nil)
                            } else {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 64)
                            }
                        }
                        .padding(18)
                        .towerCard()
                        Group {
                            ImportPrivacyNote(
                                copiesSubscription: copiesSubscription,
                                target: model.selectedTarget,
                                contentMode: model.exportContentMode(for: model.selectedTarget),
                                embedsRemoteSubscriptions: model.embedRemoteSubscriptionLinks
                                    && model.selectedTarget.supportsEmbeddedRemoteSubscriptions
                            )
                        }
                    }
                }
                // Suppress only generation/target changes, not user disclosure.
                .animation(nil, value: request)
                .animation(nil, value: preparedRequest)
            }
            .frame(maxWidth: TowerPlatform.isMac ? TowerTheme.macContentMaxWidth : .infinity)
            .padding(.horizontal, TowerPlatform.isMac ? 28 : TowerTheme.pagePadding)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .task(id: request) {
            // LAN sharing temporarily hides this card; keep the settled result
            // for returning to it instead of resetting the header to busy.
            guard let request else { return }
            let result = await model.configuration(for: request)
            guard !Task.isCancelled else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                preparedConfiguration = result
                preparedRequest = request
            }
            // Idle for a moment, then prepare the clients on either side in
            // the background; switching cancels this task along with it.
            try? await Task.sleep(for: .milliseconds(400))
            for neighbour in model.adjacentUncachedExportRequests() {
                guard !Task.isCancelled else { return }
                _ = await model.configuration(for: neighbour, priority: .utility)
            }
        }
        .task(id: request) {
            // Only a cold generation that is still running after 200 ms marks
            // the header as pending; faster ones switch straight to the result.
            guard let request, model.cachedConfiguration(for: request) == nil else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, preparedRequest != request else { return }
            pendingStatusRequest = request
        }
        .onAppear { surgeSchemeAvailable = MacClientImportCapability.surgeSchemeAvailable }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { surgeSchemeAvailable = MacClientImportCapability.surgeSchemeAvailable }
        }
        .fileExporter(isPresented: $isSavingMacFile, document: macDocument,
                      contentType: .data, defaultFilename: macFileName) { result in
            if case .failure(let error) = result {
                model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("生成与导出")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    configurationNameDraft = ConfigurationNameDraft(text: model.configurationName)
                    isSettingsPresented = true
                } label: {
                    Text("设置")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("open-settings")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 12) {
            VStack(spacing: 0) {
                if !isLANSharingSelected {
                    ImportActionBar(
                        copiesSubscription: copiesSubscription,
                        target: model.selectedTarget,
                        contentMode: model.exportContentMode(for: model.selectedTarget),
                        isImporting: isImporting,
                        isDisabled: configuration?.hasExportableProxies != true,
                        importAction: {
                            guard let configuration else { return }
                            Task { await importConfiguration(configuration) }
                        },
                        shareAction: {
                            guard let configuration else { return }
                            export(configuration)
                        },
                        copyAction: {
                            guard let configuration else { return }
                            copy(configuration)
                        }
                    )
                    .transition(.opacity.animation(TowerMotion.selection(reduceMotion: reduceMotion)))
                }
            }
            .animation(reduceMotion ? nil : TowerMotion.selection(reduceMotion: false), value: isLANSharingSelected)
        }
        .sheet(item: $sharePayload) { payload in
            ActivitySheet(items: [payload.url])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isProtocolFilterPresented) {
            if TowerPlatform.isMac {
                // Catalyst uses a desktop modal. iPhone detents/grabber can
                // animate independently from that window during presentation.
                protocolFilterPanel
                    .frame(minWidth: 520, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
                    .presentationDragIndicator(.hidden)
            } else {
                protocolFilterPanel
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            ExportSettingsSheet(
                configurationNameDraft: $configurationNameDraft
            )
        }
        // "完成" is not the only way out of that sheet — it can also be dragged
        // down — and a name typed but never committed is simply lost. Catching
        // the flag covers every path; committing twice is harmless because the
        // draft is the same either way.
        .onChange(of: isSettingsPresented) { _, isPresented in
            guard !isPresented else { return }
            // After the sheet's slide, for the same reason as its Done button.
            let name = configurationNameDraft.committedName
            Task { @MainActor in
                try? await Task.sleep(for: Self.settingsDismissDelay)
                model.setConfigurationName(name)
            }
        }
        // A restore or an iCloud pull can replace the name while Settings is
        // open. Without this, closing it writes the stale draft back.
        .onChange(of: model.configurationName) { _, name in
            configurationNameDraft.followSavedName(name)
        }
        .fullScreenCover(item: $previewPayload) { payload in
            ConfigurationPreviewSheet(configuration: payload.configuration)
        }
        .sensoryFeedback(.selection, trigger: selectedDestinationID)
        // Deliberately no .onDisappear teardown. Handing the link to another
        // app backgrounds Tower, and SwiftUI may call onDisappear when it does
        // — which killed the server before the client had fetched. Hiddify
        // reported it as `Connection refused`. The 3-minute timer and the
        // background-task expiry handler already bound the lifetime.
    }

    private var protocolFilterPanel: some View {
        NavigationStack {
            ScrollView { ProtocolFilter().padding(TowerTheme.pagePadding) }
                .background(TowerTheme.background)
                .navigationTitle("协议筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            isProtocolFilterPresented = false
                        }
                    }
                }
        }
    }

    private var protocolSelectionSummary: String {
        let kinds = model.filterableKinds(for: model.selectedTarget)
        let selected = kinds.filter { !model.isExcluded($0.kind, for: model.selectedTarget) }
        if selected.isEmpty { return String(localized: "未选择协议") }
        if selected.count == kinds.count { return String(localized: "全部协议") }
        return selected.map { $0.kind.title }.joined(separator: " · ")
    }

    /// When the chosen protocols do not fit beside the title, the row shows
    /// how many are chosen; the full list is one tap away in the filter.
    private var protocolSelectionCount: String? {
        let kinds = model.filterableKinds(for: model.selectedTarget)
        let selected = kinds.filter { !model.isExcluded($0.kind, for: model.selectedTarget) }
        guard !selected.isEmpty, selected.count < kinds.count else { return nil }
        return String(localized: "已选 \(selected.count)/\(kinds.count) 种")
    }

    private var selectedDestinationID: String {
        isLANSharingSelected ? "lan" : model.selectedTarget.rawValue
    }

    @MainActor
    private func activateLANSharing() {
        isLANSharingSelected = true
        Task { await model.startLANSharing() }
    }

    private func export(_ configuration: GeneratedConfiguration) {
        do {
            if TowerPlatform.isMac {
                macDocument = MacConfigurationDocument(content: configuration.content)
                macFileName = configuration.fileName
                isSavingMacFile = true
            } else {
                sharePayload = ExportPayload(url: try model.makeExportURL(configuration: configuration))
            }
        } catch {
            model.showToast(String(localized: "生成失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
        }
    }

    private var copiesSubscription: Bool {
        model.selectedTarget.copiesAggregatedSubscription(mode: model.exportContentMode(for: model.selectedTarget))
        || MacClientImportCapability.copiesSubscription(
            target: model.selectedTarget, isMac: TowerPlatform.isMac,
            surgeSchemeAvailable: surgeSchemeAvailable
        )
    }

    private func copySubscription(for target: ClientTarget, contentMode: ExportContentMode = .fullConfiguration) async {
        model.setExportDestination(.lanSharing, isVisible: true)
        if !model.isLANSharingActive { await model.startLANSharing() }
        guard let url = model.lanSubscriptionURL(target: target, contentMode: contentMode) else { return }
        UIPasteboard.general.string = url.absoluteString
        model.showToast(String(localized: "局域网订阅链接已复制"), symbol: "doc.on.doc.fill")
    }

    @MainActor
    private func importConfiguration(_ configuration: GeneratedConfiguration) async {
        guard !isImporting else { return }
        if configuration.target.copiesAggregatedSubscription(mode: configuration.contentMode), !TowerPlatform.isMac {
            isImporting = true
            defer { isImporting = false }
            do {
                let url = try await directImportService.prepareNodeSubscriptionURL(configuration)
                UIPasteboard.general.string = url.absoluteString
                model.showToast(String(localized: "订阅链接已复制"), symbol: "doc.on.doc.fill")
            } catch {
                directImportService.stop()
                model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
            return
        }
        if configuration.target.copiesAggregatedSubscription(mode: configuration.contentMode)
            || MacClientImportCapability.copiesSubscription(target: configuration.target,
                isMac: TowerPlatform.isMac, surgeSchemeAvailable: surgeSchemeAvailable) {
            isImporting = true
            defer { isImporting = false }
            await copySubscription(for: configuration.target, contentMode: configuration.contentMode)
            return
        }
        guard configuration.target.supportsDirectImport(mode: configuration.contentMode) else {
            export(configuration)
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let schemeURL = try await directImportService.prepare(configuration)
            let didOpen = await withCheckedContinuation { continuation in
                UIApplication.shared.open(schemeURL, options: [:]) { opened in
                    continuation.resume(returning: opened)
                }
            }

            if didOpen {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                model.showToast(String(localized: "已交给 \(configuration.target.name) 导入"), symbol: "arrow.up.forward.app.fill")
            } else {
                directImportService.stop()
                if !TowerPlatform.isMac {
                    model.showToast(String(localized: "未找到 \(configuration.target.name)，请从分享列表选择"), symbol: "exclamationmark.circle.fill")
                }
                if TowerPlatform.isMac, configuration.target == .surgeMac {
                    surgeSchemeAvailable = false
                    await copySubscription(for: configuration.target, contentMode: configuration.contentMode)
                } else {
                    export(configuration)
                }
            }
        } catch {
            directImportService.stop()
            model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            export(configuration)
        }
    }

    private func copy(_ configuration: GeneratedConfiguration) {
        UIPasteboard.general.string = configuration.content
        model.showToast(String(localized: "配置已复制"), symbol: "doc.on.doc.fill")
    }
}

private struct ExportOptionRow: View {
    let title: LocalizedStringKey
    let value: String
    /// A shorter value for when `value` does not fit on the title's line. A
    /// wrapped list of protocol names read as a paragraph wedged between two
    /// dividers, with no clear end to the row.
    var compactValue: String? = nil
    var symbol: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let symbol { ExportOptionIcon(symbol: symbol) }
            ViewThatFits(in: .horizontal) {
                singleLine(value)
                if let compactValue { singleLine(compactValue) }
                // Only very large text sizes get here: stack, with room to breathe.
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(compactValue ?? value).font(.subheadline).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .font(.body)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func singleLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.primary).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 16)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct ExportOptionIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}

private struct ExportAdvancedOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : TowerMotion.disclosure(reduceMotion: false)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ExportOptionIcon(symbol: "slider.horizontal.3")
                    Text("高级选项")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export-advanced-options")
            .accessibilityValue(isExpanded ? Text("已展开") : Text("已收起"))

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("优先使用规则集", isOn: Binding(get: { model.preferRuleSets }, set: model.setPreferRuleSets))
                        .accessibilityIdentifier("prefer-rule-sets-toggle")
                    Text("兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.selectedTarget.supportsEmbeddedRemoteSubscriptions {
                        Toggle("代理集合", isOn: Binding(get: { model.embedRemoteSubscriptionLinks }, set: model.setEmbedRemoteSubscriptionLinks))
                            .accessibilityIdentifier("embed-remote-subscription-links-toggle")
                        Text("原始订阅链接直接写入配置文件，交由客户端更新。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, 12)
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
    }
}

private struct ExportContentModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selectedTarget.supportedContentModes.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    "导出内容",
                    selection: Binding(
                        get: { model.exportContentMode(for: model.selectedTarget) },
                        set: { model.setExportContentMode($0, for: model.selectedTarget) }
                    )
                ) {
                    ForEach(model.selectedTarget.supportedContentModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export-content-mode")

            }

        }
    }


}

private struct ExportSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Binding var configurationNameDraft: ConfigurationNameDraft

    var body: some View {
        NavigationStack {
            SettingsView(configurationNameDraft: $configurationNameDraft)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            // Read the name while the field still holds it,
                            // but save it once the sheet is down: saving
                            // redraws and regenerates the export page under
                            // the sheet, and in the same frame as dismiss it
                            // took the sheet's slide away.
                            let name = configurationNameDraft.committedName
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: ExportView.settingsDismissDelay)
                                model.setConfigurationName(name)
                            }
                        }
                    }
                }
                .towerToast()
        }
    }
}

private struct ExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ConfigurationPreviewPayload: Identifiable {
    let id = UUID()
    let configuration: GeneratedConfiguration
}

private struct ClientPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isLANSharingSelected: Bool
    let activateLANSharing: () -> Void
    @State private var orderedDestinations: [ExportDestination] = []
    @State private var dragSession: ClientPickerDragSession?
    @State private var settlingSession: ClientPickerDragSession?
    @ScaledMetric(relativeTo: .caption) private var pickerHeight: CGFloat = 128
    private var visualSessions: [ClientPickerDragSession] {
        [settlingSession, dragSession].compactMap { $0 }
    }
    private var currentDestination: ExportDestination {
        isLANSharingSelected ? .lanSharing : .client(model.selectedTarget)
    }
    @State private var dragLifted = false
    @State private var suppressSelection = false
    @State private var reorderFeedback = 0
    @State private var destinationFrames: [String: CGRect] = [:]
    @State private var autoScroller = ReorderAutoScroller(
        axis: .horizontal,
        maximumSpeed: 430
    )

    private var displayedDestinations: [ExportDestination] {
        orderedDestinations.isEmpty ? model.exportDestinationOrder : orderedDestinations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("目标客户端")
                    .font(.title3.weight(.semibold))
                Spacer()
                NavigationLink {
                    ClientFilterView(isLANSharingSelected: $isLANSharingSelected)
                } label: {
                    HStack(spacing: 4) {
                        Text("客户端筛选")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .accessibilityIdentifier("open-client-filter")
            }
            GeometryReader { viewport in
                ZStack(alignment: .topLeading) {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(displayedDestinations) { destination in
                                    Button {
                                        select(destination)
                                    } label: {
                                        destinationCard(destination)
                                            .opacity(visualSessions.contains(where: { $0.source == destination }) ? 0 : 1)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(ResponsivePressButtonStyle())
                                    .accessibilityIdentifier(accessibilityIdentifier(for: destination))
                                    .accessibilityAddTraits(currentDestination == destination ? .isSelected : [])
                                    .id(destination.id)
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ClientCardFramePreferenceKey.self,
                                                value: [
                                                    destination.id: proxy.frame(
                                                        in: .named(ClientPickerCoordinateSpace.name)
                                                    )
                                                ]
                                            )
                                        }
                                    }
                                    .accessibilityAction(named: "向前移动") {
                                        model.moveExportDestination(destination, by: -1)
                                    }
                                    .accessibilityAction(named: "向后移动") {
                                        model.moveExportDestination(destination, by: 1)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.bottom, TowerPlatform.isMac ? 16 : 0)
                            .background {
                                ClientPickerReorderGestureBridge(
                                    minimumPressDuration: 0.18,
                                    allowableMovement: 12,
                                    onScrollViewResolved: { scrollView in
                                        autoScroller.attach(scrollView)
                                    },
                                    shouldReceiveTouch: isTouchInsideDestination,
                                    onBegan: beginDragging,
                                    onChanged: { event in
                                        updateDragging(
                                            event,
                                            viewportWidth: viewport.size.width
                                        )
                                    },
                                    onEnded: { event in
                                        finishDragging(
                                            event,
                                            viewportWidth: viewport.size.width
                                        )
                                    },
                                    onCancelled: cancelDragging,
                                    mapsMouseWheelHorizontally: TowerPlatform.isMac
                                )
                            }
                        }
                        .scrollIndicators(TowerPlatform.isMac ? .visible : .hidden)
                        .onAppear { scrollProxy.scrollTo(currentDestination.id) }
                        .onChange(of: currentDestination) { _, destination in
                            guard dragSession == nil, settlingSession == nil else { return }
                            // Without an anchor, ScrollViewReader only moves enough
                            // to reveal a clipped card and leaves visible cards in place.
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                scrollProxy.scrollTo(destination.id)
                            }
                        }
                    }

                    ForEach(visualSessions, id: \.token) { dragSession in
                        destinationCard(dragSession.source)
                            .frame(
                                width: dragSession.sourceFrame.width,
                                height: dragSession.sourceFrame.height
                            )
                            .scaleEffect(
                                dragSession.isSettling || reduceMotion
                                    ? 1
                                    : (dragLifted ? 1.025 : 0.97)
                            )
                            .opacity(reduceMotion || dragLifted ? 1 : 0.86)
                            .shadow(
                                color: .black.opacity(
                                    reduceMotion ? 0.08 : (dragLifted ? 0.16 : 0)
                                ),
                                radius: reduceMotion ? 5 : (dragLifted ? 13 : 0),
                                y: reduceMotion ? 2 : (dragLifted ? 7 : 0)
                            )
                            .offset(y: dragSession.sourceFrame.minY)
                            .modifier(TrackedReorderOffset(value: dragSession.sourceFrame.minX + dragSession.translation,
                                                          horizontal: true, recorder: dragSession.presentationOffset))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .zIndex(2)
                            .animation(.easeOut(duration: 0.12), value: dragLifted)
                    }
                }
                .coordinateSpace(name: ClientPickerCoordinateSpace.name)
                .onPreferenceChange(ClientCardFramePreferenceKey.self) { frames in
                    guard frames != destinationFrames else { return }
                    destinationFrames = frames
                }
                .onDisappear {
                    autoScroller.stop()
                    autoScroller.onScroll = nil
                    resetDragState()
                    suppressSelection = false
                }
            }
            .frame(height: pickerHeight + (TowerPlatform.isMac ? 16 : 0))
        }
        .onAppear(perform: synchronizeOrder)
        .onChange(of: model.exportDestinationOrder) { _, destinations in
            guard dragSession == nil else { return }
            orderedDestinations = destinations
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, dragSession != nil || settlingSession != nil else { return }
            resetDragState()
            suppressSelection = false
        }
        .sensoryFeedback(.selection, trigger: reorderFeedback)
    }

    @ViewBuilder
    private func destinationCard(_ destination: ExportDestination) -> some View {
        switch destination {
        case .client(let target):
            ClientTargetCard(
                target: target,
                isSelected: !isLANSharingSelected && model.selectedTarget == target
            )
        case .lanSharing:
            LANExportTargetCard(isSelected: isLANSharingSelected)
                .accessibilityLabel("局域网共享")
                .accessibilityHint("自动识别客户端")
        }
    }

    private func select(_ destination: ExportDestination) {
        guard dragSession == nil, !suppressSelection else { return }
        switch destination {
        case .client(let target):
            guard isLANSharingSelected || model.selectedTarget != target else { return }
            isLANSharingSelected = false
            model.selectTarget(target)
        case .lanSharing:
            activateLANSharing()
        }
    }

    private func synchronizeOrder() {
        guard dragSession == nil else { return }
        orderedDestinations = model.exportDestinationOrder
    }

    private func isTouchInsideDestination(_ location: CGPoint) -> Bool {
        let destinations = displayedDestinations
        guard dragSession == nil,
              destinations.allSatisfy({ destinationFrames[$0.id] != nil }) else {
            return false
        }
        return destinations.contains { destination in
            hitFrame(for: destination)?.contains(location) == true
        }
    }

    private func hitFrame(for destination: ExportDestination) -> CGRect? {
        guard let landing = settlingSession, landing.source == destination else { return destinationFrames[destination.id] }
        var frame = landing.sourceFrame
        frame.origin.x = landing.presentationOffset.value
        return frame
    }

    private func beginDragging(_ event: ClientPickerReorderGestureBridge.Event) -> Bool {
        let landingSource = settlingSession.flatMap { session in
            hitFrame(for: session.source)?.contains(event.location) == true ? session.source : nil
        }
        guard dragSession == nil,
              let destination = landingSource ?? displayedDestinations.first(where: { destination in
                  hitFrame(for: destination)?.contains(event.location) == true
              }) else { return false }
        let order = displayedDestinations
        guard order.contains(destination),
              order.allSatisfy({ destinationFrames[$0.id] != nil }),
              let sourceFrame = hitFrame(for: destination) else { return false }
        if settlingSession?.source == destination { settlingSession = nil }

        orderedDestinations = order
        // UIKit leaves a failed long press entirely to the Button/ScrollView.
        // Once the long press succeeds, keep this guard as a second layer
        // against a selection action from that same touch sequence.
        suppressSelection = true
        dragSession = ClientPickerDragSession(
            source: destination,
            originalOrder: order,
            frozenFrames: destinationFrames,
            frozenMidpoints: Dictionary(
                uniqueKeysWithValues: order.compactMap { item in
                    destinationFrames[item.id].map { (item.id, item == destination ? sourceFrame.midX : $0.midX) }
                }
            ),
            sourceFrame: sourceFrame,
            presentationOffset: ReorderPresentationOffset(sourceFrame.minX),
            translation: 0,
            scrollDelta: 0,
            insertionIndex: order.firstIndex(of: destination) ?? 0,
            isSettling: false
        )
        autoScroller.onScroll = handleAutoScroll
        dragLifted = reduceMotion
        guard !reduceMotion else { return true }
        DispatchQueue.main.async {
            guard dragSession?.source == destination,
                  dragSession?.isSettling == false else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                dragLifted = true
            }
        }
        return true
    }

    private func updateDragging(
        _ event: ClientPickerReorderGestureBridge.Event,
        viewportWidth: CGFloat
    ) {
        guard var session = dragSession,
              !session.isSettling else { return }

        session.translation = event.translation.width
        updateInsertionIndex(in: &session)
        store(session)
        updateDraft(using: session)
        autoScroller.update(pointer: event.location.x, viewportLength: viewportWidth)
    }

    private func finishDragging(
        _ event: ClientPickerReorderGestureBridge.Event,
        viewportWidth: CGFloat
    ) {
        guard let destination = dragSession?.source else {
            releaseSelectionSuppressionAfterTouchDelivery()
            return
        }
        updateDragging(event, viewportWidth: viewportWidth)
        finishDragging(destination)
        releaseSelectionSuppressionAfterTouchDelivery()
    }

    private func cancelDragging() {
        guard let destination = dragSession?.source else {
            releaseSelectionSuppressionAfterTouchDelivery()
            return
        }
        cancelDragging(destination)
        releaseSelectionSuppressionAfterTouchDelivery()
    }

    private func handleAutoScroll(_ delta: CGFloat) {
        guard var session = dragSession, !session.isSettling else { return }
        session.scrollDelta += delta
        updateInsertionIndex(in: &session)
        store(session)
        updateDraft(using: session)
    }

    private func updateInsertionIndex(in session: inout ClientPickerDragSession) {
        let effectiveTranslation = session.translation + session.scrollDelta
        guard let proposedIndex = ReorderPlanner.insertionIndex(
            sourceID: session.source.id,
            orderedIDs: session.originalOrder.map(\.id),
            frozenMidpoints: session.frozenMidpoints,
            translation: effectiveTranslation,
            activationThreshold: 8
        ) else { return }

        let stableIndex = stabilizedInsertionIndex(
            proposedIndex,
            horizontalPosition: session.sourceFrame.midX + effectiveTranslation,
            session: session
        )
        guard stableIndex != session.insertionIndex else { return }
        session.insertionIndex = stableIndex
        reorderFeedback += 1
    }

    private func store(_ session: ClientPickerDragSession) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession = session
        }
    }

    private func updateDraft(using session: ClientPickerDragSession) {
        let reordered = ReorderPlanner.moving(
            session.originalOrder,
            identifiedBy: \.id,
            sourceID: session.source.id,
            toInsertionIndex: session.insertionIndex
        )
        guard reordered != orderedDestinations else { return }
        guard !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                orderedDestinations = reordered
            }
            return
        }
        withAnimation(TowerMotion.disclosure(reduceMotion: false)) {
            orderedDestinations = reordered
        }
    }

    private func stabilizedInsertionIndex(
        _ proposedIndex: Int,
        horizontalPosition: CGFloat,
        session: ClientPickerDragSession
    ) -> Int {
        let currentIndex = session.insertionIndex
        guard proposedIndex != currentIndex else { return currentIndex }

        let remainingMidpoints = session.originalOrder
            .filter { $0 != session.source }
            .compactMap { session.frozenMidpoints[$0.id] }
        let hysteresis: CGFloat = 6

        if proposedIndex > currentIndex,
           currentIndex < remainingMidpoints.count,
           horizontalPosition < remainingMidpoints[currentIndex] + hysteresis {
            return currentIndex
        }
        if proposedIndex < currentIndex,
           currentIndex > 0,
           horizontalPosition > remainingMidpoints[currentIndex - 1] - hysteresis {
            return currentIndex
        }
        return proposedIndex
    }

    private func finishDragging(_ destination: ExportDestination) {
        autoScroller.stop()
        autoScroller.onScroll = nil
        guard var session = dragSession,
              session.source == destination else {
            resetDragState()
            return
        }

        model.setExportDestinationOrder(orderedDestinations)
        let landingX = ReorderPlanner.landingOrigin(
            sourceID: session.source.id, originalIDs: session.originalOrder.map(\.id),
            reorderedIDs: orderedDestinations.map(\.id), frames: session.frozenFrames,
            horizontal: true) ?? session.sourceFrame.minX
        session.translation = landingX - session.sourceFrame.minX - session.scrollDelta
        session.isSettling = true

        guard !reduceMotion else {
            resetDragState()
            return
        }

        settlingSession = dragSession
        dragSession = nil
        let token = session.token
        withAnimation(
            TowerMotion.disclosure(reduceMotion: false),
            completionCriteria: .removed
        ) {
            settlingSession = session
        } completion: {
            guard settlingSession?.token == token else { return }
            settlingSession = nil
        }
    }

    private func cancelDragging(_ destination: ExportDestination) {
        autoScroller.stop()
        autoScroller.onScroll = nil
        guard var session = dragSession,
              session.source == destination else {
            resetDragState()
            return
        }
        session.translation = (session.frozenFrames[session.source.id]?.minX ?? session.sourceFrame.minX)
            - session.sourceFrame.minX - session.scrollDelta
        session.isSettling = true

        guard !reduceMotion else {
            orderedDestinations = session.originalOrder
            resetDragState()
            return
        }

        settlingSession = dragSession
        dragSession = nil
        let token = session.token
        withAnimation(
            TowerMotion.disclosure(reduceMotion: false),
            completionCriteria: .removed
        ) {
            orderedDestinations = session.originalOrder
            settlingSession = session
        } completion: {
            guard settlingSession?.token == token else { return }
            settlingSession = nil
        }
    }

    private func resetDragState() {
        autoScroller.stop()
        autoScroller.onScroll = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession = nil
            settlingSession = nil
            dragLifted = false
            orderedDestinations = model.exportDestinationOrder
        }
    }

    private func releaseSelectionSuppressionAfterTouchDelivery() {
        guard suppressSelection else { return }
        DispatchQueue.main.async {
            suppressSelection = false
        }
    }

    private func accessibilityIdentifier(for destination: ExportDestination) -> String {
        switch destination {
        case .client(let target): "client-\(target.rawValue)"
        case .lanSharing: "client-lan-sharing"
        }
    }
}

private struct ClientPickerDragSession {
    let token = UUID()
    let source: ExportDestination
    let originalOrder: [ExportDestination]
    let frozenFrames: [String: CGRect]
    let frozenMidpoints: [String: CGFloat]
    let sourceFrame: CGRect
    let presentationOffset: ReorderPresentationOffset
    var translation: CGFloat
    var scrollDelta: CGFloat
    var insertionIndex: Int
    var isSettling: Bool
}

private enum ClientPickerCoordinateSpace {
    static let name = "client-picker-reorder"
}

private struct ClientCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct LANExportTargetCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 82
    @ScaledMetric(relativeTo: .caption) private var cardHeight: CGFloat = 94
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 5, y: 2)
                Image(systemName: "wifi.router.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white, Color.accentColor)
                        .background(.white, in: Circle())
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }

            Text("局域网共享")
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: cardWidth, height: cardHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

private struct ClientTargetCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 82
    @ScaledMetric(relativeTo: .caption) private var cardHeight: CGFloat = 94
    let target: ClientTarget
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ClientAppIcon(target: target, size: 58)
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(.white, in: Circle())
                            .offset(x: 4, y: 4)
                            .accessibilityHidden(true)
                    }
                }
            Text(target.name)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        // The app icon is the tile. A card around it, a tinted fill, an
        // outline and coloured text all repeated the check mark's message.
        .frame(width: cardWidth, height: cardHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

struct ClientAppIcon: View {
    let target: ClientTarget
    let size: CGFloat

    var body: some View {
        Group {
            if let asset = target.appIconAssetName {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(target.appIconFillScale)
            } else {
                Image(systemName: target.symbol)
                    .font(.system(size: size * 0.52))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: size, height: size)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.black.opacity(0.075), lineWidth: 0.65)
        }
        // Cast from the icon's shape, not from the clipped image, so it needs
        // no offscreen pass per icon.
        .background {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
        }
        .accessibilityHidden(true)
    }
}

enum ProtocolFilterPolicy {
    static func isVisible(compatibleKindCount: Int) -> Bool {
        compatibleKindCount > 0
    }
}

/// A client can support a protocol the user's licence does not cover — Surge
/// needs a paid tier for AnyTLS — and Tower cannot detect that, so the choice
/// is offered per client and only for protocols the nodes actually contain.
private struct ProtocolFilter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let kinds = model.filterableKinds(for: model.selectedTarget)
        if ProtocolFilterPolicy.isVisible(compatibleKindCount: kinds.count) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "协议筛选", detail: String(localized: "只影响 \(model.selectedTarget.name)"))
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element.kind) { index, entry in
                        if index > 0 { Divider().padding(.leading, 66) }
                        Toggle(isOn: binding(for: entry.kind)) {
                            HStack(spacing: 12) {
                                ProtocolSymbolBadge(kind: entry.kind)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.kind.title)
                                        .font(.body.weight(.semibold))
                                    Text("\(entry.count) 个节点")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("filter-\(entry.kind.rawValue)")
                    }
                }
                .towerCard()
                Text(model.embeddedRemoteSubscriptions(for: model.selectedTarget).isEmpty
                     ? String(localized: "关掉的协议不会写进 \(model.selectedTarget.name) 的配置，并计入“已跳过”。其他客户端不受影响。")
                     : String(localized: "仅筛选本地节点；代理集合中的节点由客户端获取，不受此处筛选影响。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func binding(for kind: ProxyKind) -> Binding<Bool> {
        Binding(
            get: { !model.isExcluded(kind, for: model.selectedTarget) },
            set: { model.setExcluded(!$0, kind: kind, for: model.selectedTarget) }
        )
    }
}

private struct ProtocolSymbolBadge: View {
    let kind: ProxyKind

    var body: some View {
        ProtocolGlyph(kind: kind, size: 18)
            .foregroundStyle(Color.accentColor)
            .frame(width: 38, height: 38)
            .background(
                Color.accentColor.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct ConversionSummary: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    let configuration: GeneratedConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { counts }
                VStack(alignment: .leading, spacing: 6) { counts }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !configuration.hasExportableProxies {
                if !model.hasExportableSources {
                    Text("请先添加或启用订阅和节点，再生成配置。")
                        .font(.subheadline)
                }
            }
            if configuration.skippedNodeCount > 0 || !configuration.diagnostics.isEmpty {
                ExportResultDetails(configuration: configuration)
                    .id(configuration.target)
            }
            if configuration.remoteSourceCount > 0 {
                Label("\(configuration.remoteSourceCount) 个代理集合 · 节点由客户端更新，以上仅统计本地节点。", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var counts: some View {
        HStack(spacing: 5) {
            Text(configuration.supportedNodeCount, format: .number).monospacedDigit()
            Text("兼容节点")
        }
        if configuration.contentMode == .fullConfiguration {
            HStack(spacing: 5) {
                Text(configuration.ruleCount, format: .number).monospacedDigit()
                Text("本地规则")
            }
        }
    }


}

private struct ExportResultDetails: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Detail?
    let configuration: GeneratedConfiguration

    private enum Detail { case skipped, compatibility }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                if configuration.skippedNodeCount > 0 {
                    disclosureRow(.skipped, title: "已跳过", count: configuration.skippedNodeCount, identifier: "export-skipped-nodes")
                }
                if !configuration.diagnostics.isEmpty {
                    disclosureRow(.compatibility, title: "兼容性提示", count: configuration.diagnostics.count, identifier: "export-compatibility-notes")
                }
            }
            if let selection {
                VStack(alignment: .leading, spacing: 0) {
                    if selection == .skipped {
                        ForEach(Array(configuration.skippedNodes.enumerated()), id: \.offset) { index, node in
                            if index > 0 { Divider() }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: node.name).font(.subheadline.weight(.semibold))
                                Text(verbatim: node.kind.title).font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: node.reason).font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                        }
                    } else {
                        ForEach(Array(configuration.diagnostics.enumerated()), id: \.offset) { index, diagnostic in
                            if index > 0 { Divider() }
                            HStack(alignment: .top, spacing: 10) {
                                Text(index + 1, format: .number)
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .leading)
                                    .padding(.top, 3)
                                Text(verbatim: diagnostic)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
    }

    private func disclosureRow(_ detail: Detail, title: LocalizedStringKey, count: Int, identifier: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : TowerMotion.disclosure(reduceMotion: false)) {
                selection = selection == detail ? nil : detail
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Text(count, format: .number).monospacedDigit()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(selection == detail ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selection == detail ? Text("已展开") : Text("已收起"))
    }
}

private struct ConfigurationPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: GeneratedConfiguration
    let onOpen: () -> Void


    var body: some View {
        // Same row grammar as the settings above: icon, title, value, chevron.
        Button(action: onOpen) {
            ExportOptionRow(title: "配置预览", value: configuration.fileName, symbol: "doc.text.magnifyingglass")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-config")
    }
}

private struct ConfigurationPreviewSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let configuration: GeneratedConfiguration
    @State private var highlightedSpans: [ConfigurationSyntaxHighlighter.Span]?
    /// The profile as shown: tailnet auth keys masked. Copy still takes the
    /// real content, because the copied profile has to work.
    @State private var displayedText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let highlightedSpans {
                    ConfigurationTextView(
                        text: displayedText ?? configuration.content,
                        spans: highlightedSpans
                    )
                    .transition(.opacity)
                } else {
                    ProgressView("正在加载完整配置…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: highlightedSpans != nil)
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle(configuration.target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("复制", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = configuration.content
                        model.showToast(String(localized: "配置已复制"), symbol: "doc.on.doc.fill")
                    }
                    .accessibilityIdentifier("preview-copy")
                }
            }
            .towerToast()
            // Scanning a full configuration is measured in tenths of a second
            // on a phone. Yielding first only moved the freeze one runloop
            // turn later — long enough to show the progress view, not long
            // enough to keep the sheet interactive while it happened.
            .task {
                let content = model.maskingTailnetAuthKeys(in: configuration.content)
                let spans = await Task.detached(priority: .userInitiated) {
                    ConfigurationSyntaxHighlighter.spans(in: content)
                }.value
                guard !Task.isCancelled else { return }
                displayedText = content
                highlightedSpans = spans
            }
        }
    }
}

private struct ImportPrivacyNote: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var copiesSubscription = false
    let target: ClientTarget
    let contentMode: ExportContentMode
    let embedsRemoteSubscriptions: Bool

    var body: some View {
        Text(detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }


    private var detail: String {
        // Egern drops the import link when that link is what launches it; the
        // second tap reaches the running app. Confirmed on Egern 2.20.
        guard target.supportsDirectImport(mode: contentMode) else { return baseDetail }
        switch target {
        case .egern:
            return baseDetail + String(localized: "如果 Egern 刚启动后没有出现新配置，回到塔台再点一次。")
        case .karing:
            // Karing skips a link it already has, so each import is a new profile.
            return baseDetail + String(localized: "Karing 每次导入都会新建一份以导出时间命名的配置，旧的塔台配置可以删除。")
        default:
            return baseDetail
        }
    }

    private var baseDetail: String {
        if target.copiesAggregatedSubscription(mode: contentMode) {
            if target.usesClashFormat {
                return String(localized: "将链接添加到现有配置的代理集合（proxy-providers），不含规则或策略组。刷新时需保持塔台运行；链接失效后请重新复制。")
            }
            if TowerPlatform.isMac {
                return String(localized: "复制后，在 Surge 的“策略 → 策略组”中新建或编辑策略组，勾选“同时包含外部策略”，将链接粘贴到“URL 或本地路径”（policy-path）。链接聚合已启用且通过筛选的节点，刷新时保持塔台运行；可在“局域网共享”中停止服务。WireGuard 请使用完整配置导出。")
            }
            return String(localized: "复制后，请在 3 分钟内切换到 Surge，在策略组的外部策略（policy-path）中粘贴链接。只聚合已启用且通过筛选的节点，不替换规则。链接仅在本机临时有效；更新节点时回到塔台重新复制，再在 Surge 中刷新。WireGuard 请使用完整配置导出。")
        }
        if copiesSubscription {
            if target == .surgeMac {
                return String(localized: "点击“复制订阅”，打开 Surge Mac，在“更多 → 配置 → 从 URL 安装配置”中粘贴链接并安装，然后选择该配置使用。更新订阅时请保持塔台运行；可在塔台的“局域网共享”中停止服务。")
            }
            return String(localized: "点击“复制订阅”，打开 ClashMac 的“配置”页面，点击右上角“＋ → 导入订阅”，粘贴链接、填写名称并点击“完成”。下载后选择该配置使用。更新订阅时请保持塔台运行；可在塔台的“局域网共享”中停止服务。")
        }
        if contentMode == .nodesOnly {
            return String(localized: "塔台只会把节点订阅交给 \(target.name)，不会替换客户端现有的规则和策略组。订阅保留在这台 iPhone 的临时地址，不会上传。")
        }
        if embedsRemoteSubscriptions {
            return String(localized: "生成的配置包含原始订阅链接，\(target.name) 可直接刷新远程节点。请只交给可信客户端；塔台规则与自有节点变化后仍需重新导出。")
        }
        if target.supportsDirectConfigurationImport {
            return String(localized: "塔台会通过 \(target.name) 的 URL Scheme 打开客户端。配置只在本机的 127.0.0.1 临时地址保留 3 分钟，不会上传；需要更新时回到塔台再次导入。")
        }
        if target == .clashMac {
            return String(localized: "导出 YAML 文件后，在 ClashMac 的配置文件页面导入；也可以添加局域网订阅链接。")
        }
        return String(localized: "Quantumult X 目前没有公开完整配置导入的 URL Scheme。点击下方按钮会立即打开系统文件分享，不上传您的订阅，也不会用不完整的远程资源替代本地规则。")
    }
}

private struct ImportActionBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var copiesSubscription = false
    let target: ClientTarget
    let contentMode: ExportContentMode
    let isImporting: Bool
    let isDisabled: Bool
    let importAction: () -> Void
    let shareAction: () -> Void
    let copyAction: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: importAction) {
                HStack(spacing: 9) {
                    ZStack {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                                .transition(.opacity)
                        } else {
                            ClientAppIcon(target: target, size: 27)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 27, height: 27)
                    .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: isImporting)
                    Text(importTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: TowerTheme.actionBarButtonHeight)
                .padding(.horizontal, 14)
                .foregroundStyle(.white)
                .background(
                    Color.accentColor,
                    in: RoundedRectangle(
                        cornerRadius: TowerTheme.actionBarButtonCornerRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isDisabled || isImporting)
            .accessibilityIdentifier("export-config")

            Menu {
                Button("分享配置文件", systemImage: "square.and.arrow.up", action: shareAction)
                Button("复制配置文本", systemImage: "doc.on.doc", action: copyAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(
                        width: TowerTheme.actionBarButtonHeight,
                        height: TowerTheme.actionBarButtonHeight
                    )
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(
                            cornerRadius: TowerTheme.actionBarButtonCornerRadius,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isDisabled || isImporting)
            .accessibilityLabel("其他导入方式")
        }
        .padding(.horizontal, TowerTheme.pagePadding)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .modifier(BottomBarEdgeBackground())
    }

    private var importTitle: String {
        if target.copiesAggregatedSubscription(mode: contentMode) {
            return String(localized: "复制聚合的订阅链接")
        }
        if copiesSubscription { return String(localized: "复制订阅") }
        switch contentMode {
        case .nodesOnly:
            return String(localized: "仅导出节点到 \(target.name)")
        case .fullConfiguration:
            return target.primaryImportTitle
        }
    }
}

private struct MacConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var content: String

    init(content: String) { self.content = content }
    init(configuration: ReadConfiguration) throws {
        content = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: Data(content.utf8))
        wrapper.fileAttributes[FileAttributeKey.protectionKey.rawValue] = FileProtectionType.complete
        return wrapper
    }
}
