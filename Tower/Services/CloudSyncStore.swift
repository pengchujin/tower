import Foundation

enum CloudSyncError: LocalizedError, Equatable {
    case unavailable
    case noRemoteSnapshot

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "iCloud 不可用，请检查系统设置里的 iCloud 云盘是否开启")
        case .noRemoteSnapshot: String(localized: "iCloud 上还没有配置")
        }
    }
}

/// The user's own iCloud, holding one snapshot file.
///
/// Tower's state is a single document rather than a set of records, so the
/// ubiquity container matches it exactly and CloudKit would only add machinery.
/// The cost is that merging is per-file: two devices that both edited produce
/// one winner, decided by `AppSnapshot.updatedAt`. That is the right shape for
/// this data — a configuration is one thing a person edits from whichever phone
/// is in hand, not a document two people write at once.
///
/// Everything here is deliberately explicit rather than automatic. Sync is off
/// until the user turns it on, and turning it on is the moment their
/// subscription URLs and node passwords first leave the device.
actor CloudSyncStore {
    static let containerIdentifier = "iCloud.com.jzb.tower"
    private static let fileName = "state.json"

    private let containerID: String?
    private let fileURLOverride: URL?
    private let removeItem: (URL) throws -> Void
    private nonisolated let accountAvailableOverride: Bool?

    init(containerIdentifier: String? = CloudSyncStore.containerIdentifier) {
        self.containerID = containerIdentifier
        self.fileURLOverride = nil
        self.removeItem = { try FileManager.default.removeItem(at: $0) }
        self.accountAvailableOverride = nil
    }

    /// Local file injection keeps the coordination and encoding paths under
    /// test without requiring the test runner to own an iCloud container.
    init(
        fileURL: URL,
        isAccountAvailable: Bool = true,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.containerID = nil
        self.fileURLOverride = fileURL
        self.removeItem = removeItem
        self.accountAvailableOverride = isAccountAvailable
    }

    /// Whether the device has an iCloud account Tower can write to.
    ///
    /// Signing out of iCloud leaves the identity token nil, which is the only
    /// check that does not block on the network.
    nonisolated var isAccountAvailable: Bool {
        if let accountAvailableOverride { return accountAvailableOverride }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// Resolving the container touches the file system and can be slow the
    /// first time, so it never runs on the main actor.
    private func documentsURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw CloudSyncError.unavailable
        }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    private func fileURL() throws -> URL {
        if let fileURLOverride { return fileURLOverride }
        return try documentsURL().appendingPathComponent(Self.fileName, isDirectory: false)
    }

    func upload(_ snapshot: AppSnapshot) throws {
        try Task.checkCancellation()
        let url = try fileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try Task.checkCancellation()

        var coordinationError: NSError?
        var writeError: Error?
        // Coordinated so a sync that lands mid-write cannot read a half file.
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// The snapshot stored in iCloud, or nil when there is none yet.
    func download() throws -> AppSnapshot? {
        let url = try fileURL()

        // A file that exists in the container may not be on this device yet;
        // asking for it starts the transfer.
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }

        var coordinationError: NSError?
        var result: Result<AppSnapshot?, Error> = .success(nil)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                let data = try Data(contentsOf: target)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                result = .success(try decoder.decode(AppSnapshot.self, from: data))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func removeRemoteSnapshot() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        var removalError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do {
                try removeItem(target)
            } catch {
                removalError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let removalError { throw removalError }
    }
}

/// Which of two snapshots is the one to keep.
///
/// Split out from the store so the rule can be tested without an iCloud
/// account, and so there is exactly one place that decides it.
enum CloudSyncResolution: Equatable {
    case keepLocal
    case takeRemote

    /// A snapshot written before sync existed carries no date. It loses to any
    /// dated one, because it cannot have been the newer edit made on another
    /// device — sync did not exist when it was written.
    static func resolve(local: Date?, remote: Date?) -> CloudSyncResolution {
        switch (local, remote) {
        case (_, nil): .keepLocal
        case (nil, _): .takeRemote
        case let (localDate?, remoteDate?): remoteDate > localDate ? .takeRemote : .keepLocal
        }
    }
}
