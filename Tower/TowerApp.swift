import SwiftUI

@main
struct TowerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
        }
    }
}

struct AppRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
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
        .overlay(alignment: .top) {
            ToastOverlay()
        }
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
