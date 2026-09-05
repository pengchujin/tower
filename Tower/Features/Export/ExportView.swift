import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @State private var sharePayload: ExportPayload?
    @State private var directImportService = DirectImportService()
    @State private var isImporting = false
    @State private var isSettingsPresented = false
    @State private var isLANSharingSelected = false
    @State private var configurationNameDraft = ConfigurationNameDraft()
    @State private var previewPayload: ConfigurationPreviewPayload?

    var body: some View {
        // The LAN destination does not have one fixed configuration: the
        // requesting client chooses the format through its User-Agent or the
        // explicit target in the link. Avoid generating an unrelated client
        // profile while this destination is selected.
        let configuration = isLANSharingSelected ? nil : model.configuration()

        ScrollView {
            LazyVStack(spacing: 22) {
                ClientPicker(
                    isLANSharingSelected: $isLANSharingSelected,
                    activateLANSharing: activateLANSharing
                )

                if isLANSharingSelected {
                    LANSharingDestinationCard()
                    LANSharingGuide()
                } else if let configuration {
                    ExportContentModePicker()
                    ProtocolFilter()
                    ConversionSummary(configuration: configuration)
                    ImportPrivacyNote(
                        target: model.selectedTarget,
                        contentMode: model.exportContentMode(for: model.selectedTarget),
                        embedsRemoteSubscriptions: model.embedRemoteSubscriptionLinks
                            && model.selectedTarget.supportsEmbeddedRemoteSubscriptions
                    )
                    ConfigurationPreview(configuration: configuration) {
                        previewPayload = ConfigurationPreviewPayload(configuration: configuration)
                    }
                }
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 18)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let configuration {
                ImportActionBar(
                    target: model.selectedTarget,
                    contentMode: configuration.contentMode,
                    isImporting: isImporting,
                    isDisabled: !configuration.hasExportableProxies,
                    importAction: {
                        Task { await importConfiguration(configuration) }
                    },
                    shareAction: export,
                    copyAction: { copy(configuration) }
                )
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivitySheet(items: [payload.url])
                .presentationDetents([.medium, .large])
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
            model.setConfigurationName(configurationNameDraft.committedName)
        }
        .fullScreenCover(item: $previewPayload) { payload in
            ConfigurationPreviewSheet(configuration: payload.configuration)
        }
        .sensoryFeedback(.selection, trigger: selectedDestinationID)
        // Deliberately no .onDisappear teardown. Handing the link to another
        // app backgrounds Tower, and SwiftUI may call onDisappear when it does
        // — which killed the server before the client had fetched. Hiddify
        // reported it as `Connection refused`. The 45-second timer and the
        // background-task expiry handler already bound the lifetime.
    }

    private var selectedDestinationID: String {
        isLANSharingSelected ? "lan" : model.selectedTarget.rawValue
    }

    @MainActor
    private func activateLANSharing() {
        isLANSharingSelected = true
        Task { await model.startLANSharing() }
    }

    private func export() {
        do {
            sharePayload = ExportPayload(url: try model.makeExportURL())
        } catch {
            model.showToast(String(localized: "生成失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
        }
    }

    @MainActor
    private func importConfiguration(_ configuration: GeneratedConfiguration) async {
        guard !isImporting else { return }
        guard configuration.target.supportsDirectImport(mode: configuration.contentMode) else {
            export()
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
                model.showToast(String(localized: "未找到 \(configuration.target.name)，请从分享列表选择"), symbol: "exclamationmark.circle.fill")
                export()
            }
        } catch {
            directImportService.stop()
            model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            export()
        }
    }

    private func copy(_ configuration: GeneratedConfiguration) {
        UIPasteboard.general.string = configuration.content
        model.showToast(String(localized: "配置已复制"), symbol: "doc.on.doc.fill")
    }
}

private struct ExportContentModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selectedTarget.supportedContentModes.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "导出内容", detail: model.selectedTarget.name)
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

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .towerCard()
        }
    }

    private var modeExplanation: String {
        switch model.exportContentMode(for: model.selectedTarget) {
        case .nodesOnly:
            return String(localized: "只添加节点订阅，不替换客户端现有的规则和策略组。")
        case .fullConfiguration:
            return String(localized: "导出节点、规则和策略组组成的完整配置。")
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
                            model.setConfigurationName(configurationNameDraft.committedName)
                            dismiss()
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
                                    onCancelled: cancelDragging
                                )
                            }
                        }
                        .scrollIndicators(.hidden)
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
            .frame(height: pickerHeight)
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
            .shadow(color: Color.accentColor.opacity(0.18), radius: 5, y: 2)

            Text("局域网共享")
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: cardWidth, height: cardHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.105)
                : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13),
                    lineWidth: isSelected ? 1.5 : 0.7
                )
        }
        .scaleEffect(reduceMotion || isSelected ? 1 : 0.97)
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
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: cardWidth, height: cardHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.105) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13), lineWidth: isSelected ? 1.5 : 0.7)
        }
        .scaleEffect(reduceMotion || isSelected ? 1 : 0.97)
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
        .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
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
    @Environment(AppModel.self) private var model
    let configuration: GeneratedConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("转换已就绪")
                        .font(.title3.weight(.semibold))
                    Text(summarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: configuration.hasExportableProxies ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(configuration.hasExportableProxies ? .green : .orange)
            }
            HStack(spacing: 16) {
                MetricPill(
                    value: configuration.supportedNodeCount,
                    label: "兼容节点"
                )
                Divider().frame(height: 38)
                MetricPill(value: configuration.ruleCount, label: "本地规则")
                Divider().frame(height: 38)
                MetricPill(value: configuration.skippedNodeCount, label: "已跳过")
            }
            if configuration.skippedNodeCount > 0 {
                Label(
                    "目标客户端不支持、或您在协议筛选里关掉的节点不会写入配置，原节点仍保留在塔台中。",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            if configuration.remoteSourceCount > 0 {
                Label("\(configuration.remoteSourceCount) 个代理集合 · 节点由客户端更新，以上仅统计本地节点。", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .towerCard()
    }

    private var summarySubtitle: String {
        switch configuration.contentMode {
        case .nodesOnly:
            String(localized: "仅节点 · \(model.selectedTarget.name)")
        case .fullConfiguration:
            "\(model.activeRuleName) · \(model.selectedTarget.name)"
        }
    }
}

private struct ConfigurationPreview: View {
    let configuration: GeneratedConfiguration
    let onOpen: () -> Void

    private var preview: String {
        ConfigurationPreviewFormatter.summary(from: configuration.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "配置预览", detail: configuration.fileName)
            ConfigurationSummaryView(text: preview)
                .frame(height: 220)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onOpen) {
                Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .towerCard()
    }
}

private struct ConfigurationPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let configuration: GeneratedConfiguration
    @State private var highlightedSpans: [ConfigurationSyntaxHighlighter.Span]?

    var body: some View {
        NavigationStack {
            Group {
                if let highlightedSpans {
                    ConfigurationTextView(
                        text: configuration.content,
                        spans: highlightedSpans
                    )
                } else {
                    ProgressView("正在加载完整配置…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
                }
            }
            // Scanning a full configuration is measured in tenths of a second
            // on a phone. Yielding first only moved the freeze one runloop
            // turn later — long enough to show the progress view, not long
            // enough to keep the sheet interactive while it happened.
            .task {
                let content = configuration.content
                highlightedSpans = await Task.detached(priority: .userInitiated) {
                    ConfigurationSyntaxHighlighter.spans(in: content)
                }.value
            }
        }
    }
}

private struct ImportPrivacyNote: View {
    let target: ClientTarget
    let contentMode: ExportContentMode
    let embedsRemoteSubscriptions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ClientAppIcon(target: target, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(target.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.green.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        target.supportsDirectImport(mode: contentMode)
            ? String(localized: "本机一键导出")
            : String(localized: "使用本地文件导出")
    }

    private var detail: String {
        if contentMode == .nodesOnly {
            return String(localized: "塔台只会把节点订阅交给 \(target.name)，不会替换客户端现有的规则和策略组。订阅保留在这台 iPhone 的临时地址，不会上传。")
        }
        if embedsRemoteSubscriptions {
            return String(localized: "生成的配置包含原始订阅链接，\(target.name) 可直接刷新远程节点。请只交给可信客户端；塔台规则与自有节点变化后仍需重新导出。")
        }
        if target.supportsDirectConfigurationImport {
            return String(localized: "塔台会通过 \(target.name) 的 URL Scheme 打开客户端。配置只在这台 iPhone 的 127.0.0.1 临时地址保留 45 秒，不会上传；需要更新时回到塔台再次导入。")
        }
        return String(localized: "Quantumult X 目前没有公开完整配置导入的 URL Scheme。点击下方按钮会立即打开系统文件分享，不上传您的订阅，也不会用不完整的远程资源替代本地规则。")
    }
}

private struct ImportActionBar: View {
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
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        ClientAppIcon(target: target, size: 27)
                    }
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
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var importTitle: String {
        switch contentMode {
        case .nodesOnly:
            return String(localized: "仅导出节点到 \(target.name)")
        case .fullConfiguration:
            return target.primaryImportTitle
        }
    }
}
