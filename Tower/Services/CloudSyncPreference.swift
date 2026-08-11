import Foundation

/// Whether the user turned iCloud sync on.
///
/// Kept out of the snapshot on purpose: the snapshot is the thing being
/// synced, so storing the switch inside it would let one device decide for
/// another. Enabling sync is a per-device choice about where that device's
/// data may go.
enum CloudSyncPreference {
    private static let key = "icloud-sync-enabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}
