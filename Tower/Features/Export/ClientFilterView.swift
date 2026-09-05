import SwiftUI

struct ClientFilterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isLANSharingSelected: Bool
    @State private var orderedDestinations: [ExportDestination] = []
    @State private var dragSession: ClientFilterDragSession?
    @State private var settlingSession: ClientFilterDragSession?
    @State private var dragLifted = false
    @State private var interactionFeedback = 0
    @State private var destinationRowFrames: [String: CGRect] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var autoScroller = ReorderAutoScroller(
        axis: .vertical,
        maximumSpeed: 520
    )

    private let rowHeight: CGFloat = 68
    private var visualSessions: [ClientFilterDragSession] {
        [settlingSession, dragSession].compactMap { $0 }
    }

    private var displayedDestinations: [ExportDestination] {
        orderedDestinations.isEmpty ? model.exportDestinationOrder : orderedDestinations
    }

    private var displayedRows: [ClientFilterRowPresentation] {
        displayedDestinations.map {
            ClientFilterRowPresentation(destination: $0, role: .displayed)
        }
    }

    private var hiddenRows: [ClientFilterRowPresentation] {
        model.hiddenExportDestinationOrder.map {
            ClientFilterRowPresentation(destination: $0, role: .hidden)
        }
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        displayedSection
                        hiddenSection
                    }
                    .padding(.horizontal, TowerTheme.pagePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                    .background {
                        ClientPickerReorderGestureBridge(
                            minimumPressDuration: 0,
                            allowableMovement: 12,
                            onScrollViewResolved: { autoScroller.attach($0) },
                            shouldReceiveTouch: { handleDestination(at: $0) != nil },
                            onBegan: { event in
                                guard let destination = handleDestination(at: event.location) else { return false }
                                beginDragging(destination)
                                return dragSession != nil
                            },
                            onChanged: updateDragging,
                            onEnded: { event in
                                guard let destination = dragSession?.source else { return }
                                updateDragging(event)
                                finishDragging(destination)
                            },
                            onCancelled: {
                                if let destination = dragSession?.source { cancelDragging(destination) }
                            },
                            coordinateOriginInWindow: viewport.frame(in: .global).origin
                        )
                    }
                }

                ForEach(visualSessions, id: \.token) { dragSession in
                    displayedDestinationRow(dragSession.source, isPreview: true)
                        .frame(
                            width: dragSession.sourceFrame.width,
                            height: dragSession.sourceFrame.height
                        )
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.7)
                        }
                        .scaleEffect(
                            dragSession.isSettling || reduceMotion
                                ? 1
                                : (dragLifted ? 1.015 : 1)
                        )
                        .shadow(
                            color: .black.opacity(
                                reduceMotion ? 0.08 : (dragLifted ? 0.14 : 0)
                            ),
                            radius: reduceMotion ? 5 : (dragLifted ? 12 : 0),
                            y: reduceMotion ? 2 : (dragLifted ? 6 : 0)
                        )
                        .offset(x: dragSession.sourceFrame.minX)
                        .modifier(TrackedReorderOffset(value: dragSession.sourceFrame.minY + dragSession.translation,
                                                      horizontal: false, recorder: dragSession.presentationOffset))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                        .animation(.easeOut(duration: 0.12), value: dragLifted)
                }
            }
            .coordinateSpace(name: ClientFilterReorderCoordinateSpace.name)
            .onPreferenceChange(DestinationRowFramePreferenceKey.self) { frames in
                guard frames != destinationRowFrames else { return }
                destinationRowFrames = frames
            }
            .onAppear {
                viewportHeight = viewport.size.height
            }
            .onChange(of: viewport.size.height) { _, height in
                viewportHeight = height
            }
            .onDisappear {
                autoScroller.stop()
                autoScroller.onScroll = nil
                resetDragState()
            }
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("客户端筛选")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: synchronizeOrder)
        .onChange(of: model.exportDestinationOrder) { _, destinations in
            guard dragSession == nil else { return }
            orderedDestinations = destinations
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, dragSession != nil || settlingSession != nil else { return }
            resetDragState()
        }
        .sensoryFeedback(.selection, trigger: interactionFeedback)
    }

    private var displayedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("导出界面显示")
                    .font(.headline)
                Spacer()
                Text("\(displayedDestinations.count) 个")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(
                        reduceMotion
                            ? .opacity
                            : .numericText(value: Double(displayedDestinations.count))
                    )
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(displayedRows) { row in
                    displayedDestinationSlot(
                        row.destination,
                        isLast: row.id == displayedRows.last?.id
                    )
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
            )

            Text("拖动右侧手柄调整顺序；点减号可从导出界面隐藏。至少保留一个客户端。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var hiddenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("所有导出目标")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if hiddenRows.isEmpty {
                    Label("所有导出目标均已显示", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: rowHeight)
                } else {
                    ForEach(hiddenRows) { row in
                        hiddenDestinationRow(
                            row.destination,
                            isLast: row.id == hiddenRows.last?.id
                        )
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
            )

            Text("未显示的导出目标会列在这里，点一下即可加入上方。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func displayedDestinationSlot(
        _ destination: ExportDestination,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            displayedDestinationRow(destination)
                .frame(minHeight: rowHeight)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DestinationRowFramePreferenceKey.self,
                            value: [
                                destination.id: proxy.frame(
                                    in: .named(ClientFilterReorderCoordinateSpace.name)
                                )
                            ]
                        )
                    }
                }
                .transition(.opacity)

            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    private func displayedDestinationRow(_ destination: ExportDestination, isPreview: Bool = false) -> some View {
        let isLifted = !isPreview && visualSessions.contains(where: { $0.source == destination })
        return HStack(spacing: 0) {
            destinationLabel(destination)
                .opacity(isLifted ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            if isPreview {
                // The lifted row is paint only. Reusing live Buttons here
                // exposes duplicate accessibility targets during removal.
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.canHideExportDestination(destination) ? Color.red : Color.secondary)
                    .frame(width: 44, height: 44)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 44)
            } else {
                Button {
                    hide(destination)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            model.canHideExportDestination(destination) ? Color.red : Color.secondary
                        )
                        // Hide pixels, never the Button's input surface.
                        .opacity(isLifted ? 0 : 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canHideExportDestination(destination))
                .accessibilityIdentifier("hide-\(destination.id)")
                .accessibilityLabel("从导出界面隐藏 \(destinationName(destination))")

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(
                        dragSession?.source == destination ? Color.accentColor : Color.secondary
                    )
                    .opacity(isLifted ? 0 : 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityIdentifier("reorder-\(destination.id)")
                    .accessibilityLabel("调整 \(destinationName(destination)) 的顺序")
                    .accessibilityAction(named: "上移") {
                        move(destination, by: -1)
                    }
                    .accessibilityAction(named: "下移") {
                        move(destination, by: 1)
                    }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func hiddenDestinationRow(
        _ destination: ExportDestination,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                show(destination)
            } label: {
                HStack(spacing: 0) {
                    destinationLabel(destination)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    Color.clear
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .frame(minHeight: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("show-\(destination.id)")
            .accessibilityLabel("在导出界面显示 \(destinationName(destination))")
            .compositingGroup()
            .transition(.opacity)

            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    private func handleDestination(at location: CGPoint) -> ExportDestination? {
        guard dragSession == nil else { return nil }
        return displayedDestinations.first { destination in
            guard var frame = destinationRowFrames[destination.id] else { return false }
            if let landing = settlingSession, landing.source == destination {
                frame.origin.y = landing.presentationOffset.value
            }
            let handle = CGRect(x: frame.maxX - 50, y: frame.midY - 22, width: 44, height: 44)
            return handle.contains(location)
        }
    }

    private func updateDragging(_ event: ClientPickerReorderGestureBridge.Event) {
        guard let destination = dragSession?.source else { return }
        updateDragging(destination, translation: event.translation.height, pointerPosition: event.location.y)
    }

    private func beginDragging(_ destination: ExportDestination) {
        guard dragSession == nil else { return }
        let order = displayedDestinations
        guard order.contains(destination),
              order.allSatisfy({ destinationRowFrames[$0.id] != nil }),
              var sourceFrame = destinationRowFrames[destination.id] else { return }
        if let landing = settlingSession, landing.source == destination {
            sourceFrame.origin.y = landing.presentationOffset.value
            settlingSession = nil
        }

        orderedDestinations = order
        dragSession = ClientFilterDragSession(
            source: destination,
            originalOrder: order,
            frozenFrames: destinationRowFrames,
            frozenMidpoints: Dictionary(
                uniqueKeysWithValues: order.compactMap { item in
                    destinationRowFrames[item.id].map { (item.id, item == destination ? sourceFrame.midY : $0.midY) }
                }
            ),
            sourceFrame: sourceFrame,
            presentationOffset: ReorderPresentationOffset(sourceFrame.minY),
            translation: 0,
            scrollDelta: 0,
            insertionIndex: order.firstIndex(of: destination) ?? 0,
            isSettling: false
        )
        autoScroller.onScroll = handleAutoScroll
        dragLifted = reduceMotion
        guard !reduceMotion else { return }
        DispatchQueue.main.async {
            guard dragSession?.source == destination,
                  dragSession?.isSettling == false else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                dragLifted = true
            }
        }
    }

    private func updateDragging(
        _ destination: ExportDestination,
        translation: CGFloat,
        pointerPosition: CGFloat
    ) {
        guard var session = dragSession,
              session.source == destination,
              !session.isSettling else { return }

        session.translation = translation
        updateInsertionIndex(in: &session)
        store(session)
        updateDraft(using: session)
        autoScroller.update(pointer: pointerPosition, viewportLength: viewportHeight)
    }

    private func handleAutoScroll(_ delta: CGFloat) {
        guard var session = dragSession, !session.isSettling else { return }
        session.scrollDelta += delta
        updateInsertionIndex(in: &session)
        store(session)
        updateDraft(using: session)
    }

    private func updateInsertionIndex(in session: inout ClientFilterDragSession) {
        let effectiveTranslation = session.translation + session.scrollDelta
        if let proposedIndex = ReorderPlanner.insertionIndex(
            sourceID: session.source.id,
            orderedIDs: session.originalOrder.map(\.id),
            frozenMidpoints: session.frozenMidpoints,
            translation: effectiveTranslation,
            activationThreshold: 8
        ) {
            let stableIndex = stabilizedInsertionIndex(
                proposedIndex,
                verticalPosition: session.sourceFrame.midY + effectiveTranslation,
                session: session
            )
            guard stableIndex != session.insertionIndex else { return }
            session.insertionIndex = stableIndex
            interactionFeedback += 1
        }
    }

    private func store(_ session: ClientFilterDragSession) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession = session
        }
    }

    private func updateDraft(using session: ClientFilterDragSession) {
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
        verticalPosition: CGFloat,
        session: ClientFilterDragSession
    ) -> Int {
        let currentIndex = session.insertionIndex
        guard proposedIndex != currentIndex else { return currentIndex }

        let remainingMidpoints = session.originalOrder
            .filter { $0 != session.source }
            .compactMap { session.frozenMidpoints[$0.id] }
        let hysteresis: CGFloat = 6

        if proposedIndex > currentIndex,
           currentIndex < remainingMidpoints.count,
           verticalPosition < remainingMidpoints[currentIndex] + hysteresis {
            return currentIndex
        }
        if proposedIndex < currentIndex,
           currentIndex > 0,
           verticalPosition > remainingMidpoints[currentIndex - 1] - hysteresis {
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
        let landingY = ReorderPlanner.landingOrigin(sourceID: destination.id,
            originalIDs: session.originalOrder.map(\.id), reorderedIDs: orderedDestinations.map(\.id),
            frames: session.frozenFrames) ?? session.sourceFrame.minY
        session.translation = landingY - session.sourceFrame.minY - session.scrollDelta
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
        session.translation = (session.frozenFrames[session.source.id]?.minY ?? session.sourceFrame.minY)
            - session.sourceFrame.minY - session.scrollDelta
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

    private func show(_ destination: ExportDestination) {
        guard dragSession == nil else { return }
        let previousOrder = model.exportDestinationOrder
        animateDestinationChange {
            model.setExportDestination(destination, isVisible: true)
            orderedDestinations = model.exportDestinationOrder
        }
        if model.exportDestinationOrder != previousOrder {
            interactionFeedback += 1
        }
    }

    private func hide(_ destination: ExportDestination) {
        guard dragSession == nil else { return }
        if settlingSession?.source == destination { settlingSession = nil }
        let previousOrder = model.exportDestinationOrder
        if destination == .lanSharing, model.isLANSharingActive {
            model.stopLANSharing()
        }

        animateDestinationChange {
            model.setExportDestination(destination, isVisible: false)
            orderedDestinations = model.exportDestinationOrder
            if destination == .lanSharing {
                isLANSharingSelected = false
            }
        }
        if model.exportDestinationOrder != previousOrder {
            interactionFeedback += 1
        }
    }

    private func move(_ destination: ExportDestination, by offset: Int) {
        guard dragSession == nil else { return }
        let previousOrder = model.exportDestinationOrder
        animateDestinationChange {
            model.moveExportDestination(destination, by: offset)
            orderedDestinations = model.exportDestinationOrder
        }
        if model.exportDestinationOrder != previousOrder {
            interactionFeedback += 1
        }
    }

    private func synchronizeOrder() {
        guard dragSession == nil else { return }
        orderedDestinations = model.exportDestinationOrder
    }

    private func animateDestinationChange(_ updates: () -> Void) {
        guard !reduceMotion else {
            updates()
            return
        }
        withAnimation(TowerMotion.disclosure(reduceMotion: false), updates)
    }

    @ViewBuilder
    private func destinationLabel(_ destination: ExportDestination) -> some View {
        switch destination {
        case .client(let target):
            clientLabel(target)
        case .lanSharing:
            lanSharingLabel
        }
    }

    private var lanSharingLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { lanIcon; lanText }
            VStack(alignment: .leading, spacing: 6) { lanIcon; lanText }
        }
    }

    private var lanIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    private var lanText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("局域网共享")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text("自动识别客户端")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func clientLabel(_ target: ClientTarget) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ClientAppIcon(target: target, size: 42); clientText(target) }
            VStack(alignment: .leading, spacing: 6) { ClientAppIcon(target: target, size: 42); clientText(target) }
        }
    }

    private func clientText(_ target: ClientTarget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(target.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(target.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func destinationName(_ destination: ExportDestination) -> String {
        switch destination {
        case .client(let target): target.name
        case .lanSharing: String(localized: "局域网共享")
        }
    }
}

private struct ClientFilterDragSession {
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

private struct ClientFilterRowPresentation: Identifiable {
    enum Role: Hashable {
        case displayed
        case hidden
    }

    struct ID: Hashable {
        let destinationID: String
        let role: Role
    }

    let destination: ExportDestination
    let role: Role

    var id: ID {
        ID(destinationID: destination.id, role: role)
    }
}

private enum ClientFilterReorderCoordinateSpace {
    static let name = "client-filter-reorder"
}

private struct DestinationRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
