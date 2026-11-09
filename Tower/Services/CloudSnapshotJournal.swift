import Foundation

struct CloudRecoveryCopy: Identifiable, Sendable {
    let id: String
    let snapshot: AppSnapshot

    /// Keep caller ordering (current local first, then newest history). Dates
    /// describe versions, not configuration content, and do not affect equality.
    static func unique(_ copies: [CloudRecoveryCopy]) -> [CloudRecoveryCopy] {
        var fingerprints = Set<Data>()
        return copies.filter { copy in
            // Versions that differ only in refresh status or caches are one
            // version to the user; see `CloudSnapshotMerge.signature`.
            guard let content = CloudSnapshotMerge.signature(copy.snapshot) else { return true }
            return fingerprints.insert(content).inserted
        }
    }
}

/// Immutable commits preserve concurrent writes across machines. File coordination
/// alone only serializes this machine's iCloud cache, not every device's cache.
struct CloudSnapshotJournal {
    /// Versions kept: meaningful ones only now, so five covers the recent
    /// history while halving what a full snapshot per version costs.
    static let retentionLimit = 5
    struct Commit: Codable {
        let id: String
        let parents: [String]
        let snapshot: AppSnapshot?
    }
    let directory: URL

    func commits() throws -> [String: Commit] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .contentModificationDateKey, .fileSizeKey]
        )
        var result: [String: Commit] = [:]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var listed = Set<String>()
        // Ask for every missing file before giving up. Stopping at the first
        // one fetched a single file per sync: with hundreds of records the
        // history never finished downloading and every sync said so.
        var missing = false
        for file in files {
            if file.pathExtension == "icloud" {
                let name = file.deletingPathExtension().lastPathComponent
                // Not part of the history; `compactedIDs` fetches it when needed.
                guard name != ".compacted.txt" else { continue }
                let target = directory.appendingPathComponent(name.hasPrefix(".") ? String(name.dropFirst()) : name)
                try FileManager.default.startDownloadingUbiquitousItem(at: target)
                missing = true
                continue
            }
            guard ["json", "pruned"].contains(file.pathExtension) else { continue }
            let stamp = CloudCommitCache.Stamp(file)
            listed.insert(file.path)
            let commit: Commit
            if let cached = CloudCommitCache.shared.commit(at: file.path, stamp: stamp) {
                commit = cached
            } else {
                guard try Self.startDownloadIfNeeded(file) else { missing = true; continue }
                commit = try decoder.decode(Commit.self, from: Data(contentsOf: file))
                guard UUID(uuidString: commit.id) != nil, file.deletingPathExtension().lastPathComponent == commit.id else { throw CloudSyncError.conflict }
                CloudCommitCache.shared.store(commit, at: file.path, stamp: stamp)
            }
            // A pruning marker wins if iCloud delivers an old full file again.
            if file.pathExtension == "pruned" || result[commit.id] == nil {
                result[commit.id] = commit
            }
        }
        if missing { throw CloudSyncError.downloading }
        CloudCommitCache.shared.retain(only: listed, in: directory.path)
        let dangling = Set(result.values.flatMap(\.parents).filter { result[$0] == nil })
        guard !dangling.isEmpty else { return result }
        // A parent that `compact` deleted is history, not a file in transit:
        // a device that stayed offline across a compaction still names it.
        let deleted = try compactedIDs()
        // Missing parents may simply still be travelling through iCloud.
        guard dangling.isSubset(of: deleted) else { throw CloudSyncError.downloading }
        // Stand-ins with no payload and no parents, like a compacted root:
        // `snapshot` then treats the branch as one that needs a choice.
        for id in dangling { result[id] = Commit(id: id, parents: [], snapshot: nil) }
        return result
    }

    static func requireDownloaded(_ file: URL) throws {
        guard try startDownloadIfNeeded(file) else { throw CloudSyncError.downloading }
    }

    /// True when the file's content is on this device; otherwise asks iCloud
    /// for it and returns false.
    static func startDownloadIfNeeded(_ file: URL) throws -> Bool {
        let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current else { return true }
        try FileManager.default.startDownloadingUbiquitousItem(at: file)
        return false
    }

    func heads(_ commits: [String: Commit]) -> [String] {
        let parents = Set(commits.values.flatMap(\.parents))
        return commits.keys.filter { !parents.contains($0) }.sorted()
    }

    func snapshot(_ commits: [String: Commit]) throws -> AppSnapshot? {
        let ids = heads(commits)
        guard let first = ids.first else {
            if !commits.isEmpty { throw CloudSyncError.conflict }
            return nil
        }
        guard var merged = commits[first]?.snapshot else { throw CloudSyncError.conflict }
        let firstAncestors = try ancestors(first, commits: commits)
        var common = firstAncestors
        for id in ids.dropFirst() {
            let other = try ancestors(id, commits: commits)
            // Branches with nothing in common that reach a record whose
            // payload and links were cut away (`prune`, then `compact`) are
            // not two devices' first syncs but a device offline across a
            // compaction. Bootstrapping could resurrect deletions.
            if common.isDisjoint(with: other),
               firstAncestors.union(other).contains(where: { commits[$0]?.snapshot == nil && commits[$0]?.parents.isEmpty == true }) {
                throw CloudSyncError.conflict
            }
            common.formIntersection(other)
            // A common ancestor closest to the heads is a shared baseline.
            let closest = closestAncestors(in: common, commits: commits)
            guard closest.count <= 1 else { throw CloudSyncError.conflict }
            guard let remote = commits[id]?.snapshot else { throw CloudSyncError.conflict }
            let base = closest.first.flatMap { commits[$0]?.snapshot }
            // A pruned baseline is not a first sync. Never bootstrap-merge it:
            // doing so could resurrect deleted nodes from a long-offline device.
            if !closest.isEmpty && base == nil { throw CloudSyncError.conflict }
            merged = try CloudSnapshotMerge.merge(local: merged, remote: remote, base: base)
        }
        return merged
    }

    /// `common` is an intersection of ancestor sets, so it is closed under
    /// ancestry: anything in it that is an older ancestor of another member
    /// is also the parent of some member. The closest ones are therefore the
    /// members no member names as a parent — one pass over the parent links
    /// instead of an ancestor walk per pair, which was cubic in the history.
    private func closestAncestors(in common: Set<String>, commits: [String: Commit]) -> [String] {
        let parentsInCommon = Set(common.flatMap { commits[$0]?.parents ?? [] })
        return common.filter { !parentsInCommon.contains($0) }.sorted()
    }

    /// Baselines the current heads merge against; pruning them would turn a
    /// mergeable pair of edits into a conflict.
    private func mergeBases(of ids: [String], commits: [String: Commit]) -> Set<String> {
        guard let first = ids.first, var common = try? ancestors(first, commits: commits) else { return [] }
        var bases = Set<String>()
        for id in ids.dropFirst() {
            guard let other = try? ancestors(id, commits: commits) else { return bases }
            common.formIntersection(other)
            bases.formUnion(closestAncestors(in: common, commits: commits))
        }
        return bases
    }

    /// Every record reachable from `id`, itself included. Throws on a missing
    /// record or a cycle.
    ///
    /// Iterative on purpose. The history grows by one record per sync and
    /// pruning keeps every id and parent link, so a recursive walk took one
    /// stack frame per sync and overflowed a cooperative thread's 512 KB stack
    /// at about 420 records: the app crashed seconds after every launch
    /// (device crash logs, 2026-10-07).
    func ancestors(_ id: String, commits: [String: Commit]) throws -> Set<String> {
        guard commits[id] != nil else { throw CloudSyncError.conflict }
        var result: Set<String> = [id]
        // Records on the current path; reaching one again is a cycle.
        var onPath: Set<String> = [id]
        var stack: [(id: String, nextParent: Int)] = [(id, 0)]
        while let top = stack.last {
            let parents = commits[top.id]?.parents ?? []
            guard top.nextParent < parents.count else {
                onPath.remove(top.id)
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].nextParent += 1
            let parent = parents[top.nextParent]
            guard commits[parent] != nil, !onPath.contains(parent) else { throw CloudSyncError.conflict }
            // Already walked from another branch, without finding a cycle.
            guard result.insert(parent).inserted else { continue }
            onPath.insert(parent)
            stack.append((parent, 0))
        }
        return result
    }

    func append(_ snapshot: AppSnapshot, parents: [String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = Commit(id: UUID().uuidString, parents: parents, snapshot: snapshot)
        try write(record, extension: "json")
    }

    /// Remove configuration payloads, retaining only IDs and parent links.
    /// Mark-before-delete makes interrupted cleanup and reordered cloud delivery safe.
    func prune() throws {
        let records = try commits()
        let liveHeads = Set(heads(records))
        let full = records.values.filter { $0.snapshot != nil }.sorted { lhs, rhs in
            let ld = lhs.snapshot?.updatedAt ?? .distantPast
            let rd = rhs.snapshot?.updatedAt ?? .distantPast
            return ld == rd ? lhs.id < rhs.id : ld > rd
        }
        // Unresolved concurrent branches must never be silently discarded.
        guard liveHeads.count <= Self.retentionLimit else { throw CloudSyncError.conflict }
        var keep = liveHeads.union(mergeBases(of: heads(records), commits: records)
            .filter { records[$0]?.snapshot != nil })
        // Among older versions keep only ones that differ in what the user
        // decided; copies that differ only in refresh status are one version.
        var keptSignatures = Set(records.values.filter { keep.contains($0.id) }
            .compactMap { $0.snapshot.flatMap(CloudSnapshotMerge.signature) })
        for record in full where keep.count < Self.retentionLimit && !keep.contains(record.id) {
            if let snapshot = record.snapshot, let signature = CloudSnapshotMerge.signature(snapshot) {
                guard keptSignatures.insert(signature).inserted else { continue }
            }
            keep.insert(record.id)
        }
        for record in full where !keep.contains(record.id) {
            try write(Commit(id: record.id, parents: record.parents, snapshot: nil), extension: "pruned")
        }
        let pruned = try commits().values.filter { $0.snapshot == nil }
        for record in pruned {
            let url = directory.appendingPathComponent(record.id + ".json")
            var error: NSError?
            var deletionError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { target in
                do {
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                } catch { deletionError = error }
            }
            if let error { throw error }
            if let deletionError { throw deletionError }
        }
        // Housekeeping: the version is already written, and a compaction
        // that cannot finish now (list still downloading) runs next time.
        try? compact()
    }

    /// History size at which `compact` runs, and the generations it keeps
    /// beyond the oldest retained version.
    static let compactionThreshold = 60
    static let compactionSlack = 20
    /// Ids `compact` deleted, newest last; older ones are forgotten.
    static let compactedIDLimit = 5000
    private var compactedURL: URL { directory.appendingPathComponent("compacted.txt") }

    /// Deletes pruning markers far behind every retained version.
    ///
    /// `prune` keeps each record's id and parent links so heads stay heads,
    /// which used to mean one more file per sync forever: 518 files by
    /// 2026-11, each to be downloaded before a sync could read the history,
    /// and iCloud evicts them again. Records closer to a head than the
    /// oldest retained version plus `compactionSlack` stay; older ones go.
    /// Order matters for devices reading mid-way: deleted ids are recorded
    /// first (see `commits`), then the records left on the edge drop their
    /// links to them, so a reader — this build or an older one — never
    /// sees a parent that is neither present nor known to be deleted.
    func compact() throws {
        let records = try commits()
        guard records.count > Self.compactionThreshold else { return }
        var depth: [String: Int] = [:]
        var queue = heads(records)
        for id in queue { depth[id] = 0 }
        var index = 0
        while index < queue.count {
            let id = queue[index]; index += 1
            for parent in records[id]?.parents ?? [] where depth[parent] == nil && records[parent] != nil {
                depth[parent] = depth[id]! + 1
                queue.append(parent)
            }
        }
        let retained = records.values.filter { $0.snapshot != nil }.compactMap { depth[$0.id] }.max() ?? 0
        let limit = retained + Self.compactionSlack
        let removed = Set(records.keys.filter { (depth[$0] ?? .max) > limit })
        guard !removed.isEmpty else { return }

        // Throws while the list is still downloading: rewriting it from
        // nothing would forget ids an offline device may still name.
        var known = try compactedIDs()
        var lines = (try? String(contentsOf: compactedURL, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        for id in removed.sorted() where known.insert(id).inserted { lines.append(id) }
        try writeData(Data(lines.suffix(Self.compactedIDLimit).joined(separator: "\n").utf8), to: compactedURL)

        for record in records.values where !removed.contains(record.id) && record.parents.contains(where: removed.contains) {
            // Only markers sit at the edge: every full version is shallower.
            let trimmed = Commit(id: record.id, parents: record.parents.filter { !removed.contains($0) }, snapshot: record.snapshot)
            try write(trimmed, extension: record.snapshot == nil ? "pruned" : "json")
        }
        for id in removed {
            for suffix in ["pruned", "json"] {
                let url = directory.appendingPathComponent(id + "." + suffix)
                var error: NSError?
                var deletionError: Error?
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { target in
                    do {
                        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    } catch { deletionError = error }
                }
                if let error { throw error }
                if let deletionError { throw deletionError }
            }
        }
    }

    /// Ids deleted by `compact`, read only when a parent is missing.
    private func compactedIDs() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: compactedURL.path) else {
            let placeholder = directory.appendingPathComponent(".compacted.txt.icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try FileManager.default.startDownloadingUbiquitousItem(at: compactedURL)
                throw CloudSyncError.downloading
            }
            return []
        }
        try Self.requireDownloaded(compactedURL)
        let text = try String(contentsOf: compactedURL, encoding: .utf8)
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    private func write(_ record: Commit, extension suffix: String) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try writeData(try encoder.encode(record), to: directory.appendingPathComponent(record.id + "." + suffix))
    }

    private func writeData(_ data: Data, to target: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &coordinationError) { url in
            do { try data.write(to: url, options: [.atomic, .completeFileProtection]) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}

/// Parsed journal records, reused across reads.
///
/// Every record file is written once under a unique id — pruning writes a
/// separate `.pruned` marker rather than rewriting — so a file with the same
/// path, date and size has the same content. The one rewrite, `compact`
/// dropping parent links, makes the file shorter and so changes its stamp.
/// A sync used to list and fully decode the whole journal four or five times (download, commit, prune),
/// including ten complete snapshots and every pruning marker, and asked iCloud
/// for each file's download status: about 1.5 s of CPU per sync on device
/// (2026-09-27). Only new files are read now.
final class CloudCommitCache: @unchecked Sendable {
    struct Stamp: Equatable {
        let modifiedAt: Date?
        let size: Int?

        init(_ url: URL) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            modifiedAt = values?.contentModificationDate
            size = values?.fileSize
        }
    }

    static let shared = CloudCommitCache()

    private let lock = NSLock()
    private var entries: [String: (stamp: Stamp, commit: CloudSnapshotJournal.Commit)] = [:]

    func commit(at path: String, stamp: Stamp) -> CloudSnapshotJournal.Commit? {
        guard stamp.modifiedAt != nil, stamp.size != nil else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[path], entry.stamp == stamp else { return nil }
        return entry.commit
    }

    func store(_ commit: CloudSnapshotJournal.Commit, at path: String, stamp: Stamp) {
        guard stamp.modifiedAt != nil, stamp.size != nil else { return }
        lock.lock(); defer { lock.unlock() }
        entries[path] = (stamp, commit)
    }

    /// Forgets deleted files so the cache cannot grow past the journal.
    func retain(only paths: Set<String>, in directory: String) {
        lock.lock(); defer { lock.unlock() }
        entries = entries.filter { !$0.key.hasPrefix(directory) || paths.contains($0.key) }
    }
}
