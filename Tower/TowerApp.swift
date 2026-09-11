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
                    await model.synchronizeWithCloud()
                    await model.refreshOnOpenIfEnabled()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
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
                        await model.synchronizeWithCloud()
                        await model.refreshOnOpenIfEnabled()
                    }
                }
        }
    }
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
                    withAnimation(
                        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1)
                    ) {
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

        return TabView(selection: $model.selectedTab) {
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
        .tint(.accentColor)
        .background { TabSelectionFeedback() }
        .modifier(SubscriptionRefreshProgressModifier())
        .towerToast()
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
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .allowsHitTesting(isPresented)
        .onChange(of: model.isReplayingMacOnboarding, initial: true) { _, value in
            withTransaction(Transaction(animation: TowerMotion.disclosure(reduceMotion: reduceMotion))) {
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
    func towerToast() -> some View {
        overlay(alignment: .top) { ToastOverlay() }
    }
}

private struct ToastOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedToast: ToastMessage?

    var body: some View {
        ZStack {
            if let toast = presentedToast {
                ToastView(toast: toast)
                    .id(toast.id)
                    .padding(.top, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        model.dismissToast(id: toast.id)
                    }
            }
        }
        .onAppear {
            presentedToast = model.toast
        }
        .onChange(of: model.toast) { _, toast in
            withAnimation(appearance) {
                presentedToast = toast
            }
        }
    }

    private var appearance: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 1)
    }
}

/// Presentation has its own transaction: a native refresh can suppress animations
/// in the update that starts the task. Do not disable the underlying scroll view
/// while its pull gesture and refresh indicator are returning to rest.
private struct SubscriptionRefreshProgressModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedProgress: Presentation?

    private struct Presentation: Equatable {
        let id: UUID
        let title: String
        let sources: [String]
    }

    private var progress: Presentation? {
        guard let progress = model.subscriptionRefreshProgress else { return nil }
        return Presentation(
            id: progress.id,
            title: progress.title,
            sources: model.subscriptions.filter {
                progress.sourceIDs.contains($0.id) && model.refreshingSourceIDs.contains($0.id)
            }.map(\.name)
        )
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(presentedProgress != nil)
            .overlay {
                ZStack {
                    if let presentedProgress {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                            .zIndex(0)
                        TaskProgressCard(
                            title: presentedProgress.title,
                            sources: presentedProgress.sources,
                            message: "可随时取消，已更新的订阅会保留。",
                            identifier: "subscription-refresh-progress",
                            onCancel: model.cancelSubscriptionRefresh
                        )
                        .padding(24)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(presentedProgress != nil)
            }
            .onChange(of: progress, initial: true) { _, newProgress in
                let visibilityChanged = (presentedProgress == nil) != (newProgress == nil)
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: 0.18)
                    : visibilityChanged
                        ? .spring(response: 0.36, dampingFraction: 1)
                        : .easeInOut(duration: 0.2)
                // A fresh transaction also clears disablesAnimations inherited
                // from UIKit's refresh handling, without animating model writes.
                withTransaction(Transaction(animation: animation)) {
                    presentedProgress = newProgress
                }
            }
    }
}
