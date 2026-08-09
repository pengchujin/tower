import CryptoKit
import Foundation

/// On-disk cache for rule lists the user imported by URL.
///
/// Imported rules are not credentials, but they sit next to `state.json` in
/// Application Support and are written with the same protection class so the
/// app has one rule for everything it persists.
struct RuleDownloadStore {
    private let folderURL: URL
    private let fileManager: FileManager

    init(folderURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let folderURL {
            self.folderURL = folderURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.folderURL = base
                .appendingPathComponent("Tower", isDirectory: true)
                .appendingPathComponent("ImportedRules", isDirectory: true)
        }
    }

    func lines(for url: URL) -> [String]? {
        guard let content = content(for: url) else { return nil }
        return RuleSchemeRepository.sanitizedLines(from: content)
    }

    /// The planner sometimes needs the original container syntax, not only
    /// the normalized payload lines. In particular a Clash provider YAML and
    /// a plain Surge ruleset can contain identical rules but are not
    /// interchangeable remote resources.
    func content(for url: URL) -> String? {
        let fileURL = folderURL.appendingPathComponent(Self.fileName(for: url), isDirectory: false)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func hasCachedRules(for url: URL) -> Bool {
        fileManager.fileExists(
            atPath: folderURL.appendingPathComponent(Self.fileName(for: url), isDirectory: false).path
        )
    }

    func store(_ content: String, for url: URL) throws {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent(Self.fileName(for: url), isDirectory: false)
        try Data(content.utf8).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// Drops every list a scheme referenced. Called when the user deletes an
    /// imported scheme so its rules do not linger on disk.
    func removeRules(for urls: [URL]) {
        for url in urls {
            let fileURL = folderURL.appendingPathComponent(Self.fileName(for: url), isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// A URL can be any length and contain characters the filesystem rejects,
    /// so the digest of the absolute URL names the file.
    static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".list"
    }
}
