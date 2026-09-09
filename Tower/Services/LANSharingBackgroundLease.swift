import UIKit

/// A finite iOS execution assertion, not a promise of permanent background hosting.
@MainActor
final class LANSharingBackgroundLease {
    typealias Begin = (@escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    private let begin: Begin
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private var identifier = UIBackgroundTaskIdentifier.invalid
    private var generation: UUID?

    init(
        begin: @escaping Begin = { expiration in
            UIApplication.shared.beginBackgroundTask(withName: "TowerLANSharing", expirationHandler: expiration)
        },
        end: @escaping (UIBackgroundTaskIdentifier) -> Void = { UIApplication.shared.endBackgroundTask($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    func retainUntilExpiration(onExpiration: @escaping @MainActor () -> Void) {
        guard generation == nil else { return }
        let current = UUID()
        generation = current
        identifier = begin { [weak self] in
            guard let self, self.generation == current else { return }
            self.finish()
            onExpiration()
        }
        if identifier == .invalid {
            generation = nil
            onExpiration()
        }
    }

    /// Returning to the foreground releases the assertion without closing the server.
    func finish() {
        generation = nil
        let previous = identifier
        identifier = .invalid
        if previous != .invalid { end(previous) }
    }
}
