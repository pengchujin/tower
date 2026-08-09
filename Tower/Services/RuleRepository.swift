import Foundation

struct RuleRepository {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Reading the snapshot walks the bundle and parses roughly twenty thousand
    /// lines. Doing that in `init` put it on the main actor during launch, even
    /// though the first tab never asks for a rule. It is now loaded once, on
    /// first use, and shared by every repository built from the same bundle.
    private var linesByPath: [String: [String]] {
        RuleSnapshotCache.shared.lines(in: bundle)
    }

    func lines(for assignment: RuleAssignment) -> [String] {
        let snapshot = linesByPath
        return snapshot[assignment.resourcePath]
            ?? snapshot[assignment.resourcePath.components(separatedBy: "/").last ?? assignment.resourcePath]
            ?? []
    }

    func count(for preset: RulePreset) -> Int {
        let localCount = preset.assignments.reduce(0) { $0 + lines(for: $1).count }
        return localCount + (preset.includeGeoIPCN ? 1 : 0) + 1
    }

    func count(for assignment: RuleAssignment) -> Int {
        lines(for: assignment).count
    }
}

private final class RuleSnapshotCache: @unchecked Sendable {
    static let shared = RuleSnapshotCache()

    private let lock = NSLock()
    private var snapshots: [String: [String: [String]]] = [:]

    func lines(in bundle: Bundle) -> [String: [String]] {
        let key = bundle.bundlePath
        lock.lock()
        if let cached = snapshots[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.load(from: bundle)

        lock.lock()
        snapshots[key] = loaded
        lock.unlock()
        return loaded
    }

    private static func load(from bundle: Bundle) -> [String: [String]] {
        var result: [String: [String]] = [:]
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return result
        }

        for case let url as URL in enumerator where url.pathExtension == "list" {
            // ACL4SSR snapshots are served by RuleSchemeRepository. The
            // legacy preset repository intentionally ignores them; downloaded
            // schemes live in RuleDownloadStore instead of the app bundle.
            guard !url.lastPathComponent.hasPrefix(RuleSchemeRepository.resourcePrefix) else {
                continue
            }
            let key = url.deletingPathExtension().lastPathComponent
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") }
            result[key] = lines
            result[url.deletingPathExtension().lastPathComponent] = lines
        }
        return result
    }
}
