import Foundation

struct ExportFileService {
    /// Exported configurations contain every node password, UUID and subscription
    /// derived credential in cleartext, so they get the same protection class as
    /// the persisted snapshot and are purged instead of accumulating in `tmp`.
    static let folderName = "TowerExports"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func write(_ configuration: GeneratedConfiguration) throws -> URL {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent(Self.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        purge(in: folder)

        let url = folder.appendingPathComponent(configuration.fileName, isDirectory: false)
        try Data(configuration.content.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Removes previously shared configurations. The share sheet still reads the
    /// file while it is presented, so only files older than the grace period go.
    func purge(in folder: URL, olderThan gracePeriod: TimeInterval = 300, now: Date = .now) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modifiedAt, now.timeIntervalSince(modifiedAt) > gracePeriod else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
