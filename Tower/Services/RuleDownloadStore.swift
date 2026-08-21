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
        parsed(for: url)?.lines
    }

    /// Whether the stored list is a Clash provider document rather than a plain
    /// ruleset. Answered from the same cache as `lines(for:)` so the rules
    /// screen does not read the file twice to learn two things about it.
    func isClashProvider(for url: URL) -> Bool? {
        parsed(for: url)?.isClashProvider
    }

    private func parsed(for url: URL) -> RuleFileCache.Entry? {
        RuleFileCache.shared.entry(
            at: folderURL.appendingPathComponent(Self.fileName(for: url), isDirectory: false)
        )
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

/// Rule lists already read from disk and split into rules.
///
/// Reading and sanitizing was previously repeated on every call, and the rules
/// screen asks for every ruleset of every scheme on every redraw — one ACL4SSR
/// set is around 430 KB across its lists, with a single file over 190 KB. That
/// is hundreds of thousands of lines re-split per frame on the main actor. The
/// lists shipped in the bundle already had a cache; the downloaded ones, which
/// are the larger half, had none.
///
/// Entries are validated against the file's modification date and size, so a
/// refresh that rewrites a list is picked up without any explicit invalidation
/// from the callers that trigger it.
private final class RuleFileCache: @unchecked Sendable {
    struct Entry {
        let lines: [String]
        let isClashProvider: Bool
    }

    private struct Stamp: Equatable {
        let modifiedAt: Date
        let size: Int
    }

    static let shared = RuleFileCache()

    private let lock = NSLock()
    private var entries: [String: (stamp: Stamp, entry: Entry)] = [:]

    func entry(at fileURL: URL) -> Entry? {
        guard let stamp = Self.stamp(of: fileURL) else {
            // The file is gone; make sure a stale copy cannot answer for it.
            lock.lock()
            entries[fileURL.path] = nil
            lock.unlock()
            return nil
        }

        lock.lock()
        if let cached = entries[fileURL.path], cached.stamp == stamp {
            lock.unlock()
            return cached.entry
        }
        lock.unlock()

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let entry = Entry(
            lines: RuleSchemeRepository.sanitizedLines(from: content),
            isClashProvider: content.components(separatedBy: .newlines).contains { rawLine in
                rawLine
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")) == "payload:"
            }
        )

        lock.lock()
        // A scheme references a few dozen lists. The cap only stops a very
        // long-lived process from growing this without bound.
        if entries.count > 512 { entries.removeAll(keepingCapacity: true) }
        entries[fileURL.path] = (stamp, entry)
        lock.unlock()
        return entry
    }

    private static func stamp(of fileURL: URL) -> Stamp? {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ),
            let modifiedAt = values.contentModificationDate,
            let size = values.fileSize else { return nil }
        return Stamp(modifiedAt: modifiedAt, size: size)
    }
}
