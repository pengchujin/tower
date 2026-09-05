import SwiftUI
import UIKit

enum ReorderScrollAxis {
    case horizontal
    case vertical
}

/// Keeps a custom reorder gesture moving when the pointer reaches a scroll
/// view edge. UIKit owns the actual scroll offset, while the SwiftUI caller
/// receives the exact delta so its frozen reorder geometry stays coherent.
@MainActor
final class ReorderAutoScroller {
    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var velocity: CGFloat = 0
    private let axis: ReorderScrollAxis
    private let maximumSpeed: CGFloat

    var onScroll: ((CGFloat) -> Void)?

    init(axis: ReorderScrollAxis, maximumSpeed: CGFloat) {
        self.axis = axis
        self.maximumSpeed = maximumSpeed
    }

    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    func update(pointer: CGFloat, viewportLength: CGFloat) {
        guard viewportLength > 0 else {
            stop()
            return
        }

        let edgeWidth = min(axis == .horizontal ? 58 : 76, viewportLength * 0.28)
        let leadingProgress = min(max((edgeWidth - pointer) / edgeWidth, 0), 1)
        let trailingProgress = min(
            max((pointer - (viewportLength - edgeWidth)) / edgeWidth, 0),
            1
        )
        let signedProgress = trailingProgress - leadingProgress
        velocity = maximumSpeed * signedProgress * abs(signedProgress)

        if abs(velocity) < 1 {
            stopDisplayLink()
        } else {
            startDisplayLinkIfNeeded()
        }
    }

    func stop() {
        velocity = 0
        stopDisplayLink()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] displayLink in
            self?.step(displayLink)
        }
        let displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    private func step(_ displayLink: CADisplayLink) {
        guard let scrollView else {
            stop()
            return
        }

        let frameDuration: CGFloat
        if let lastTimestamp {
            // Clamp a delayed frame so returning from a brief main-thread stall
            // cannot fling the content by a large distance in one update.
            frameDuration = CGFloat(
                min(max(displayLink.timestamp - lastTimestamp, 1 / 240), 1 / 15)
            )
        } else {
            frameDuration = CGFloat(
                min(
                    max(displayLink.targetTimestamp - displayLink.timestamp, 1 / 240),
                    1 / 15
                )
            )
        }
        lastTimestamp = displayLink.timestamp

        let oldOffset: CGFloat
        let minimumOffset: CGFloat
        let maximumOffset: CGFloat

        switch axis {
        case .horizontal:
            oldOffset = scrollView.contentOffset.x
            minimumOffset = -scrollView.adjustedContentInset.left
            maximumOffset = max(
                minimumOffset,
                scrollView.contentSize.width
                    - scrollView.bounds.width
                    + scrollView.adjustedContentInset.right
            )
        case .vertical:
            oldOffset = scrollView.contentOffset.y
            minimumOffset = -scrollView.adjustedContentInset.top
            maximumOffset = max(
                minimumOffset,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
        }

        let newOffset = min(max(oldOffset + velocity * frameDuration, minimumOffset), maximumOffset)
        let delta = newOffset - oldOffset
        guard abs(delta) > 0.01 else {
            stopDisplayLink()
            return
        }

        switch axis {
        case .horizontal:
            scrollView.contentOffset.x = newOffset
        case .vertical:
            scrollView.contentOffset.y = newOffset
        }
        onScroll?(delta)
    }

    deinit {
        displayLink?.invalidate()
    }
}

private final class DisplayLinkProxy: NSObject {
    let handler: (CADisplayLink) -> Void

    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func tick(_ displayLink: CADisplayLink) {
        handler(displayLink)
    }
}
