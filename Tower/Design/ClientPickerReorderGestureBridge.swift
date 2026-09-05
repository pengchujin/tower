import SwiftUI
import UIKit

/// A UIKit-backed long-press recognizer that lives beside the scroll view's
/// own pan recognizer. Keeping reorder recognition out of the SwiftUI card
/// hierarchy leaves quick taps and immediate scrolling completely native.
struct ClientPickerReorderGestureBridge: UIViewRepresentable {
    struct Event {
        let location: CGPoint
        let translation: CGSize
    }

    let minimumPressDuration: TimeInterval
    let allowableMovement: CGFloat
    let onScrollViewResolved: (UIScrollView) -> Void
    let shouldReceiveTouch: (CGPoint) -> Bool
    let onBegan: (Event) -> Bool
    let onChanged: (Event) -> Void
    let onEnded: (Event) -> Void
    let onCancelled: () -> Void
    /// Vertical SwiftUI ScrollViews may extend under navigation/tab bars.
    /// Their UIKit viewport origin then differs from the parent's named space.
    var coordinateOriginInWindow: CGPoint? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.attach(toNearestScrollViewFrom: view)
        }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        context.coordinator.update(configuration: self)
        context.coordinator.attach(toNearestScrollViewFrom: view)
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        view.onHierarchyChange = nil
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onHierarchyChange: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHierarchyChange?()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onHierarchyChange?()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var minimumPressDuration: TimeInterval
        private var allowableMovement: CGFloat
        private var onScrollViewResolved: (UIScrollView) -> Void
        private var shouldReceiveTouch: (CGPoint) -> Bool
        private var onBegan: (Event) -> Bool
        private var onChanged: (Event) -> Void
        private var onEnded: (Event) -> Void
        private var onCancelled: () -> Void
        private var coordinateOriginInWindow: CGPoint?

        private weak var scrollView: UIScrollView?
        private var longPressRecognizer: UILongPressGestureRecognizer?
        private var initialWindowLocation: CGPoint?
        private var initialViewportLocation: CGPoint?
        private var isReordering = false

        init(configuration: ClientPickerReorderGestureBridge) {
            minimumPressDuration = configuration.minimumPressDuration
            allowableMovement = configuration.allowableMovement
            onScrollViewResolved = configuration.onScrollViewResolved
            shouldReceiveTouch = configuration.shouldReceiveTouch
            onBegan = configuration.onBegan
            onChanged = configuration.onChanged
            onEnded = configuration.onEnded
            onCancelled = configuration.onCancelled
            coordinateOriginInWindow = configuration.coordinateOriginInWindow
        }

        func update(configuration: ClientPickerReorderGestureBridge) {
            minimumPressDuration = configuration.minimumPressDuration
            allowableMovement = configuration.allowableMovement
            onScrollViewResolved = configuration.onScrollViewResolved
            shouldReceiveTouch = configuration.shouldReceiveTouch
            onBegan = configuration.onBegan
            onChanged = configuration.onChanged
            onEnded = configuration.onEnded
            onCancelled = configuration.onCancelled
            coordinateOriginInWindow = configuration.coordinateOriginInWindow
            longPressRecognizer?.minimumPressDuration = minimumPressDuration
            longPressRecognizer?.allowableMovement = allowableMovement
        }

        func attach(toNearestScrollViewFrom view: UIView) {
            var ancestor = view.superview
            while let candidate = ancestor, !(candidate is UIScrollView) {
                ancestor = candidate.superview
            }
            guard let resolvedScrollView = ancestor as? UIScrollView else { return }

            if resolvedScrollView !== scrollView {
                detach()
                installRecognizer(on: resolvedScrollView)
            }
            onScrollViewResolved(resolvedScrollView)
        }

        func detach() {
            let shouldReportCancellation = isReordering
            let recognizer = longPressRecognizer
            let recognizerView = recognizer?.view
            // Removing an active recognizer can synchronously emit cancelled.
            // Clear our ownership first so that path cannot publish twice.
            isReordering = false
            longPressRecognizer = nil
            scrollView = nil
            initialWindowLocation = nil
            initialViewportLocation = nil
            if let recognizer, let recognizerView {
                recognizerView.removeGestureRecognizer(recognizer)
            }
            if shouldReportCancellation {
                onCancelled()
            }
        }

        private func installRecognizer(on scrollView: UIScrollView) {
            let recognizer = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            recognizer.minimumPressDuration = minimumPressDuration
            recognizer.allowableMovement = allowableMovement
            // Keep touch-down feedback immediate. If the press succeeds,
            // The scroll pan remains exclusive. SwiftUI's button recognizer
            // may already be tracking press feedback before the hold elapses;
            // it must not prevent our long press from recognizing.
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
            self.scrollView = scrollView
            longPressRecognizer = recognizer
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let scrollView else { return }

            switch recognizer.state {
            case .began:
                let event = event(for: recognizer, in: scrollView)
                isReordering = onBegan(event)
            case .changed:
                guard isReordering else { return }
                onChanged(event(for: recognizer, in: scrollView))
            case .ended:
                guard isReordering else {
                    initialWindowLocation = nil
                    initialViewportLocation = nil
                    return
                }
                // Clear UIKit-side state before publishing the SwiftUI update.
                // That update may dismantle this representable synchronously;
                // detach must not then report a second cancellation.
                let finalEvent = event(for: recognizer, in: scrollView)
                initialWindowLocation = nil
                initialViewportLocation = nil
                isReordering = false
                onEnded(finalEvent)
            case .cancelled, .failed:
                let shouldReportCancellation = isReordering
                initialWindowLocation = nil
                initialViewportLocation = nil
                isReordering = false
                if shouldReportCancellation {
                    onCancelled()
                }
            case .possible:
                break
            @unknown default:
                let shouldReportCancellation = isReordering
                initialWindowLocation = nil
                initialViewportLocation = nil
                isReordering = false
                if shouldReportCancellation {
                    onCancelled()
                }
            }
        }

        private func event(
            for recognizer: UILongPressGestureRecognizer,
            in scrollView: UIScrollView
        ) -> Event {
            let currentViewportLocation = viewportLocation(
                for: recognizer.location(in: scrollView),
                in: scrollView
            )
            let windowLocation = recognizer.location(in: scrollView.window)
            let initialLocation = initialWindowLocation ?? windowLocation
            return Event(
                location: recognizer.state == .began
                    ? (initialViewportLocation ?? currentViewportLocation)
                    : currentViewportLocation,
                translation: CGSize(
                    width: windowLocation.x - initialLocation.x,
                    height: windowLocation.y - initialLocation.y
                )
            )
        }

        private func viewportLocation(for contentLocation: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            if let origin = coordinateOriginInWindow {
                let point = scrollView.convert(contentLocation, to: scrollView.window)
                return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            }
            return CGPoint(
                x: contentLocation.x - scrollView.bounds.minX,
                y: contentLocation.y - scrollView.bounds.minY
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard gestureRecognizer === longPressRecognizer,
                  let scrollView else { return false }
            let contentLocation = touch.location(in: scrollView)
            let viewportLocation = viewportLocation(
                for: contentLocation,
                in: scrollView
            )
            guard shouldReceiveTouch(viewportLocation) else {
                initialWindowLocation = nil
                initialViewportLocation = nil
                return false
            }
            initialWindowLocation = touch.location(in: scrollView.window)
            initialViewportLocation = viewportLocation
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === longPressRecognizer,
                  let scrollView,
                  initialWindowLocation != nil,
                  let initialViewportLocation,
                  shouldReceiveTouch(initialViewportLocation) else { return false }

            var candidate: UIView? = scrollView
            while let view = candidate {
                if let candidateScrollView = view as? UIScrollView {
                    switch candidateScrollView.panGestureRecognizer.state {
                    case .began, .changed:
                        return false
                    default:
                        break
                    }
                }
                candidate = view.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer === longPressRecognizer else { return false }
            // Allow button touch tracking, but never move the scroll view and
            // the lifted card with the same finger. Selection is suppressed
            // by the picker after onBegan accepts the long press.
            return !(otherGestureRecognizer is UIPanGestureRecognizer)
        }
    }
}
