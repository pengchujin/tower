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
        for file in files {
            if file.pathExtension == "icloud" {
                let name = file.deletingPathExtension().lastPathComponent
                let target = directory.appendingPathComponent(name.hasPrefix(".") ? String(name.dropFirst()) : name)
                try FileManager.default.startDownloadingUbiquitousItem(at: target)
                throw CloudSyncError.downloading
            }
            guard ["json", "pruned"].contains(file.pathExtension) else { continue }
            let stamp = CloudCommitCache.Stamp(file)
            listed.insert(file.path)
            let commit: Commit
            if let cached = CloudCommitCache.shared.commit(at: file.path, stamp: stamp) {
                commit = cached
            } else {
                try Self.requireDownloaded(file)
                commit = try decoder.decode(Commit.self, from: Data(contentsOf: file))
                guard UUID(uuidString: commit.id) != nil, file.deletingPathExtension().lastPathComponent == commit.id else { throw CloudSyncError.conflict }
                CloudCommitCache.shared.store(commit, at: file.path, stamp: stamp)
            }
            // A pruning marker wins if iCloud delivers an old full file again.
            if file.pathExtension == "pruned" || result[commit.id] == nil {
                result[commit.id] = commit
            }
        }
        CloudCommitCache.shared.retain(only: listed, in: directory.path)
        // Missing parents may simply still be travelling through iCloud.
        guard result.values.allSatisfy({ $0.parents.allSatisfy { result[$0] != nil } }) else { throw CloudSyncError.downloading }
        return result
    }

    static func requireDownloaded(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
            throw CloudSyncError.downloading
        }
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
        var common = try ancestors(first, commits: commits)
        for id in ids.dropFirst() {
            common.formIntersection(try ancestors(id, commits: commits))
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
    }

    private func write(_ record: Commit, extension suffix: String) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let target = directory.appendingPathComponent(record.id + "." + suffix)
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
/// path, date and size has the same content. A sync used to list and fully
/// decode the whole journal four or five times (download, commit, prune),
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
