import SwiftUI

@main
struct TowerApp: App {
    // Coalesced rather than immediate: a burst of edits — ticking through the
    // node filter, reordering policy groups — becomes one write shortly after
    // the user stops, instead of a full snapshot encode inside every tap.
    @State private var model = AppModel(persistencePolicy: .coalesced(.milliseconds(250)))
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    for scene in UIApplication.shared.connectedScenes {
                        guard let windowScene = scene as? UIWindowScene else { continue }
                        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 650, height: 650)
                        #if DEBUG
                        // Pins the window for App Store screenshots: --window-size=960x1140
                        if let size = Self.screenshotWindowSize {
                            windowScene.sizeRestrictions?.minimumSize = size
                            windowScene.sizeRestrictions?.maximumSize = size
                        }
                        #endif
                    }
                    #endif
                }
                // The real use is "added a subscription on the other phone,
                // now picked this one up", which is exactly a return to the
                // foreground. Uploads were already automatic; without this the
                // other device only ever saw changes if someone opened
                // Settings and tapped a button, which is not sync.
                .task(id: hasSeenWelcome) {
                    guard hasSeenWelcome else { return }
                    await model.performForegroundOpenWork()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        if phase == .background { model.didEnterBackground() }
                        // Leaving the foreground is the last reliable moment to
                        // close the coalescing window: iOS may stop the process
                        // from here without another chance to write.
                        model.flushPendingWrite()
                        // Acquire the assertion while inactive, before iOS suspends us.
                        model.lanSharingWillLeaveForeground()
                        return
                    }
                    model.lanSharingDidBecomeActive()
                    guard hasSeenWelcome else { return }
                    Task {
                        await model.performForegroundOpenWork()
                    }
                }
        }
    }

    #if DEBUG
    private static var screenshotWindowSize: CGSize? {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--window-size=") }) else {
            return nil
        }
        let parts = argument.dropFirst("--window-size=".count).split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }
    #endif
}

struct AppRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the privacy introduction has been shown. Stored rather than
    /// derived so a user who already trusts the app never sees it twice, and
    /// so an existing install updating into this version is not interrupted.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        ZStack {
            if hasSeenWelcome {
                mainInterface
                    .disabled(model.isReplayingMacOnboarding)
                    .accessibilityHidden(model.isReplayingMacOnboarding)
            } else {
                WelcomeView {
                    withAnimation(TowerMotion.surface(reduceMotion: reduceMotion)) {
                        hasSeenWelcome = true
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
            MacOnboardingOverlay()
                .zIndex(2)
        }
    }

    private var mainInterface: some View {
        @Bindable var model = model

        return TabView(selection: $model.tabSelection) {
            NavigationStack {
                SubscriptionsView()
            }
            .tabItem { Label(AppTab.subscriptions.title, systemImage: AppTab.subscriptions.symbol) }
            .tag(AppTab.subscriptions)

            NavigationStack {
                RulesView()
            }
            .tabItem { Label(AppTab.rules.title, systemImage: AppTab.rules.symbol) }
            .tag(AppTab.rules)

            NavigationStack {
                ExportView()
            }
            .tabItem { Label(AppTab.export.title, systemImage: AppTab.export.symbol) }
            .tag(AppTab.export)
        }
        .task(id: model.ruleSchemePresentationRevision) {
            await model.prepareRulesPage()
        }
        .tint(.accentColor)
        .background { TabSelectionFeedback() }
        .towerToast(showsRefreshProgress: true)
    }
}

/// Keep the desktop welcome surface's transition independent of the settings
/// sheet being dismissed by its trigger.
private struct MacOnboardingOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(0)
                GeometryReader { geometry in
                    WelcomeView { model.isReplayingMacOnboarding = false }
                        .frame(width: min(720, max(300, geometry.size.width - 48)),
                               height: min(960, max(300, geometry.size.height - 48)))
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(TowerMotion.surfaceTransition(reduceMotion: reduceMotion))
                .zIndex(1)
            }
        }
        .allowsHitTesting(isPresented)
        .onChange(of: model.isReplayingMacOnboarding, initial: true) { _, value in
            withTransaction(Transaction(animation: TowerMotion.surface(reduceMotion: reduceMotion))) {
                isPresented = value
            }
        }
    }
}

/// Keep the haptic trigger's observation out of the complete tab hierarchy.
/// The feedback dependency no longer invalidates the root on each selection.
private struct TabSelectionFeedback: View {
    @Environment(AppModel.self) private var model
    // Development-only A/B control for device haptics profiling. Default UI
    // behavior is unchanged; a simulator cannot measure Taptic Engine cost.
    private var tabHapticsEnabled: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("--disable-tab-haptics")
        #else
        true
        #endif
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sensoryFeedback(.selection, trigger: model.selectedTab) { _, _ in tabHapticsEnabled }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Toasts render into whatever layer this is attached to, so a sheet needs
    /// its own. Settings is presented as a sheet over the tab view, and for a
    /// while every message it produced — LAN sharing started, access key
    /// rotated, iCloud synced — was drawn underneath it and never seen.
    ///
    /// `showsRefreshProgress` is for the root only: a batch subscription
    /// refresh shows its progress in the same slot, then becomes its result.
    func towerToast(showsRefreshProgress: Bool = false) -> some View {
        overlay(alignment: .top) { ToastOverlay(showsRefreshProgress: showsRefreshProgress) }
    }
}

private struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var showsRefreshProgress = false
    @State private var presentedToast: ToastMessage?
    @State private var presentedRefresh: RefreshStatus?
    /// The surface keeps its identity while a refresh turns into its result
    /// (or a message briefly covers a running refresh); only a new message
    /// replacing another drops in afresh.
    @State private var surfaceID = UUID()

    private struct RefreshStatus: Equatable {
        let id: UUID
        let completed: Int
        let total: Int
    }

    private var refreshStatus: RefreshStatus? {
        // A card's own refresh button already spins in place, and the status
        // belongs to the subscriptions tab where the refresh was started.
        guard showsRefreshProgress, model.selectedTab == .subscriptions,
              let progress = model.subscriptionRefreshProgress, !progress.isSingleSource else { return nil }
        return RefreshStatus(id: progress.id, completed: progress.completedIDs.count, total: progress.sourceIDs.count)
    }

    var body: some View {
        ZStack {
            if presentedToast != nil || presentedRefresh != nil {
                ZStack {
                    if let toast = presentedToast {
                        ToastContent(toast: toast)
                            .task(id: toast.id) {
                                try? await Task.sleep(for: .seconds(2.6))
                                model.dismissToast(id: toast.id)
                            }
                    } else if let refresh = presentedRefresh {
                        SubscriptionRefreshStatusContent(
                            completed: refresh.completed,
                            total: refresh.total,
                            onCancel: model.cancelSubscriptionRefresh
                        )
                    }
                }
                .statusSurface(tone: presentedToast?.tone ?? .neutral)
                .id(surfaceID)
                .padding(.top, 8)
                .padding(.horizontal)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
            }
        }
        .onAppear {
            presentedToast = model.toast
            presentedRefresh = refreshStatus
        }
        .onChange(of: model.toast) { _, toast in
            withAnimation(appearance) {
                if let toast, let previous = presentedToast, previous.id != toast.id {
                    surfaceID = UUID()
                }
                presentedToast = toast
            }
        }
        .onChange(of: refreshStatus) { _, status in
            // Only appearing and leaving move the surface; a count ticking up
            // is a small in-place change.
            let visibilityChanged = (presentedRefresh == nil) != (status == nil)
            let animation: Animation = visibilityChanged || reduceMotion
                ? appearance
                : TowerMotion.selection(reduceMotion: false)
            // A fresh transaction also clears disablesAnimations inherited
            // from UIKit's pull-to-refresh handling.
            withTransaction(Transaction(animation: animation)) {
                presentedRefresh = status
            }
        }
    }

    private var appearance: Animation {
        TowerMotion.surface(reduceMotion: reduceMotion)
    }
}

/// Batch refresh progress: the badge fills as subscriptions finish, and the
/// page stays usable — browse, edit, export — while it runs.
private struct SubscriptionRefreshStatusContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completed: Int
    let total: Int
    let onCancel: () -> Void

    private var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    var body: some View {
        HStack(spacing: 11) {
            StatusBadge {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(fraction, 0.04))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: fraction)
                }
                .padding(7)
            }
            .accessibilityHidden(true)

            Text("正在刷新订阅（\(completed)/\(total)）")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(completed)))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button(action: onCancel) {
                Text("取消")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .foregroundStyle(Color.accentColor)
            // The surface's own padding already frames it; the taller hit
            // area should not make the status taller.
            .padding(.vertical, -10)
            .padding(.trailing, -6)
            .accessibilityIdentifier("subscription-refresh-progress-cancel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subscription-refresh-progress")
    }
}
