import SwiftUI
import os

/// SwiftUI can evaluate animation data off the main actor. This tiny recorder
/// stores presentation geometry without publishing a per-frame model update.
final class ReorderPresentationOffset {
    private let storage: OSAllocatedUnfairLock<CGFloat>
    init(_ value: CGFloat) { storage = OSAllocatedUnfairLock(initialState: value) }
    var value: CGFloat {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

struct TrackedReorderOffset: AnimatableModifier {
    var value: CGFloat
    let horizontal: Bool
    let recorder: ReorderPresentationOffset

    var animatableData: CGFloat {
        get { value }
        set { value = newValue; recorder.value = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: horizontal ? value : 0, y: horizontal ? 0 : value)
    }
}
