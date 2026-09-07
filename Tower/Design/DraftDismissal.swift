import SwiftUI

extension View {
    /// Saved forms keep their draft on an accidental swipe; the Cancel button
    /// offers an explicit way to discard it. Busy cancellation is immediate.
    func confirmDiscardChanges(
        hasChanges: Bool,
        isBusy: Bool = false,
        requested: Binding<Bool>,
        onDiscard: @escaping () -> Void = {}
    ) -> some View {
        modifier(DraftDismissal(hasChanges: hasChanges, isBusy: isBusy,
                               requested: requested, onDiscard: onDiscard))
    }
}

private struct DraftDismissal: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let hasChanges: Bool
    let isBusy: Bool
    @Binding var requested: Bool
    let onDiscard: () -> Void
    @State private var showsConfirmation = false

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(hasChanges || isBusy)
            .onChange(of: requested) { _, value in
                guard value else { return }
                requested = false
                if hasChanges && !isBusy { showsConfirmation = true }
                else { discard() }
            }
            .alert("放弃更改？", isPresented: $showsConfirmation) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃更改", role: .destructive) { discard() }
            } message: {
                Text("尚未保存的内容将丢失。")
            }
    }

    private func discard() {
        onDiscard()
        dismiss()
    }
}
