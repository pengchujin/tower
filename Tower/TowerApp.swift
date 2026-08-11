import SwiftUI

@main
struct TowerApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
                // The real use is "added a subscription on the other phone,
                // now picked this one up", which is exactly a return to the
                // foreground. Uploads were already automatic; without this the
                // other device only ever saw changes if someone opened
                // Settings and tapped a button, which is not sync.
                .task { await model.synchronizeWithCloud() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.synchronizeWithCloud() }
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
        mainInterface
            .overlay {
                if !hasSeenWelcome {
                    WelcomeView {
                        withAnimation(
                            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1)
                        ) {
                            hasSeenWelcome = true
                        }
                    }
                    .background(Color(uiColor: .systemBackground))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
                }
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
        .sensoryFeedback(.selection, trigger: model.selectedTab)
        .towerToast()
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

    var body: some View {
        if let toast = model.toast {
            ToastView(toast: toast)
                .padding(.top, 8)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(2.6))
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 1)) {
                        model.dismissToast(id: toast.id)
                    }
                }
        }
    }
}
