import XCTest
@testable import Tower

final class CloudSnapshotMergeTests: XCTestCase {
    private func fixture() -> AppSnapshot {
        AppSnapshot(subscriptions: [], nodes: [ProxyNode(kind: .trojan, name: "A", server: "example.invalid", port: 443, password: "fixture", rawURI: "")], selectedPresetID: "default", selectedTarget: .surge, configurationName: "Original", updatedAt: Date(timeIntervalSince1970: 1000))
    }

    func testOfflineSettingsEditPreservesRemoteNodesAndRules() throws {
        let base = fixture()
        var local = base; local.configurationName = "Offline edit"
        var remote = base
        remote.nodes.append(ProxyNode(kind: .trojan, name: "B", server: "example.invalid", port: 443, password: "fixture", rawURI: ""))
        let merged = try CloudSnapshotMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(merged.nodes.count, 2)
        XCTAssertEqual(merged.configurationName, "Offline edit")
    }

    func testIntentionalDeletionIsNotResurrected() throws {
        let base = fixture()
        var local = base; local.nodes = []
        var remote = base; remote.configurationName = "Other device"
        let merged = try CloudSnapshotMerge.merge(local: local, remote: remote, base: base)
        XCTAssertTrue(merged.nodes.isEmpty)
        XCTAssertEqual(merged.configurationName, "Other device")
    }

    func testDeleteVersusEditAndConcurrentCredentialsRequireChoice() {
        let base = fixture()
        var deleted = base; deleted.nodes = []
        var remote = base; remote.nodes[0].password = "remote"
        XCTAssertThrowsError(try CloudSnapshotMerge.merge(local: deleted, remote: remote, base: base))
        var local = base; local.nodes[0].password = "local"
        XCTAssertThrowsError(try CloudSnapshotMerge.merge(local: local, remote: remote, base: base))
    }

    func testConcurrentRefreshDeduplicatesNodesAndPreservesExclusionAndCountry() throws {
        let source = SubscriptionSource(name: "Fixture", urlString: "https://example.invalid/sub")
        var base = fixture(); base.subscriptions = [source]; base.nodes[0].sourceID = source.id
        var local = base, remote = base
        local.nodes = [ProxyNode(sourceID: source.id, kind: .trojan, name: "A", server: "example.invalid", port: 443, password: "fixture", rawURI: "")]
        remote.nodes = [ProxyNode(sourceID: source.id, kind: .trojan, name: "A", server: "example.invalid", port: 443, password: "fixture", rawURI: "")]
        local.excludedNodeIDs = [local.nodes[0].id]
        remote.nodes[0].countryOverride = "JP"
        local.subscriptions[0].lastUpdatedAt = Date(timeIntervalSince1970: 2000)
        remote.subscriptions[0].lastUpdatedAt = Date(timeIntervalSince1970: 3000)
        local.resolvedHostCountryCodeUpdatedAt = ["example.invalid": Date(timeIntervalSince1970: 2000)]
        remote.resolvedHostCountryCodeUpdatedAt = ["example.invalid": Date(timeIntervalSince1970: 3000)]
        let merged = try CloudSnapshotMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(merged.nodes.count, 1)
        XCTAssertEqual(merged.excludedNodeIDs, [merged.nodes[0].id])
        XCTAssertEqual(merged.nodes[0].countryOverride, "JP")
        XCTAssertEqual(merged.subscriptions[0].lastUpdatedAt, Date(timeIntervalSince1970: 3000))
    }

    func testRemoteRefreshRenamePreservesConcurrentLocalExclusion() throws {
        let source = SubscriptionSource(name: "Fixture", urlString: "https://example.invalid/sub")
        var base = fixture(); base.subscriptions = [source]; base.nodes[0].sourceID = source.id
        var local = base, remote = base
        local.excludedNodeIDs = [local.nodes[0].id]
        remote.nodes = [ProxyNode(sourceID: source.id, kind: .trojan, name: "New remark", server: "example.invalid", port: 443, password: "fixture", rawURI: "updated-remark")]

        for (left, right) in [(local, remote), (remote, local)] {
            let merged = try CloudSnapshotMerge.merge(local: left, remote: right, base: base)
            XCTAssertEqual(merged.nodes.count, 1)
            XCTAssertEqual(merged.nodes[0].name, "New remark")
            XCTAssertEqual(merged.excludedNodeIDs, [merged.nodes[0].id])
        }
    }

    func testRemoteRefreshRenamePreservesConcurrentReinclusion() throws {
        let source = SubscriptionSource(name: "Fixture", urlString: "https://example.invalid/sub")
        var base = fixture(); base.subscriptions = [source]; base.nodes[0].sourceID = source.id
        base.excludedNodeIDs = [base.nodes[0].id]
        var local = base, remote = base
        local.excludedNodeIDs = []
        remote.nodes = [ProxyNode(sourceID: source.id, kind: .trojan, name: "New remark", server: "example.invalid", port: 443, password: "fixture", rawURI: "")]
        remote.excludedNodeIDs = [remote.nodes[0].id]
        for (left, right) in [(local, remote), (remote, local)] {
            let merged = try CloudSnapshotMerge.merge(local: left, remote: right, base: base)
            XCTAssertEqual(merged.nodes.count, 1)
            XCTAssertEqual(merged.nodes[0].name, "New remark")
            XCTAssertTrue(merged.excludedNodeIDs?.isEmpty == true)
        }
    }

    func testRenameDoesNotConflateAmbiguousRoutes() throws {
        let source = SubscriptionSource(name: "Fixture", urlString: "https://example.invalid/sub")
        var base = fixture(); base.subscriptions = [source]; base.nodes[0].sourceID = source.id
        base.nodes.append(ProxyNode(sourceID: source.id, kind: .trojan, name: "Other route", server: "example.invalid", port: 443, password: "fixture", rawURI: ""))
        var local = base, remote = base
        local.excludedNodeIDs = [local.nodes[0].id]
        remote.nodes = [ProxyNode(sourceID: source.id, kind: .trojan, name: "Renamed route", server: "example.invalid", port: 443, password: "fixture", rawURI: "")]
        let merged = try CloudSnapshotMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(merged.nodes.count, 1)
        XCTAssertFalse(merged.excludedNodeIDs?.contains(merged.nodes[0].id) == true)
    }

    func testRecoveryResolutionRetainsConflictingVersions() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CloudSyncStore(fileURL: dir.appendingPathComponent("state.json"))
        let base = fixture()
        try await store.upload(base)
        var edited = base; edited.nodes[0].password = "edited"
        try await store.commit(edited, replacing: base)
        try await store.resolveConflict(with: base)
        let current = try await store.download()
        XCTAssertEqual(current?.nodes[0].password, "fixture")
        let copies = try await store.recoveryCopies()
        // The original and the resolution are the same version; only one is kept.
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.contains { $0.snapshot.nodes[0].password == "edited" })
        XCTAssertTrue(copies.contains { $0.snapshot.nodes[0].password == "fixture" })
    }

    func testConcurrentJournalBranchesMergeWithoutLosingEitherWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = CloudSnapshotJournal(directory: dir)
        let base = fixture()
        try journal.append(base, parents: [])
        let parents = journal.heads(try journal.commits())
        var left = base; left.configurationName = "Left"
        var right = base; right.nodes[0].name = "Right"
        try journal.append(left, parents: parents)
        try journal.append(right, parents: parents)
        let records = try journal.commits()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(journal.heads(records).count, 2)
        let merged = try XCTUnwrap(journal.snapshot(records))
        XCTAssertEqual(merged.configurationName, "Left")
        XCTAssertEqual(merged.nodes[0].name, "Right")
    }

    func testCloudCompareAndCommitRejectsStaleReadAndRetainsHistory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CloudSyncStore(fileURL: dir.appendingPathComponent("state.json"))
        let base = fixture()
        try await store.upload(base)
        var fresh = base; fresh.nodes[0].name = "New"
        try await store.commit(fresh, replacing: base)
        do {
            try await store.commit(base, replacing: base)
            XCTFail("Stale writer must not commit")
        } catch CloudSyncError.conflict { }
        let current = try await store.download()
        XCTAssertEqual(current?.nodes[0].name, "New")
        let copies = try await store.recoveryCopies()
        XCTAssertEqual(copies.count, 2)
    }

    func testMissingParentBlocksIncompleteCloudHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = CloudSnapshotJournal(directory: dir)
        try journal.append(fixture(), parents: [UUID().uuidString])
        XCTAssertThrowsError(try journal.commits()) { error in
            guard case CloudSyncError.downloading = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    /// Pruning keeps every record's id and parent link, so the history only
    /// grows. A recursive ancestor walk overflowed the 512 KB stack of the
    /// cooperative thread that syncs at about 420 records and crashed the app
    /// on every launch; run the merge on a stack that size with far more.
    func testLongPrunedHistoryMergesOnASmallStack() throws {
        typealias Commit = CloudSnapshotJournal.Commit
        let journal = CloudSnapshotJournal(directory: FileManager.default.temporaryDirectory)
        var records: [String: Commit] = [:]
        var previous: [String] = []
        for _ in 0..<5_000 {
            let id = UUID().uuidString
            records[id] = Commit(id: id, parents: previous, snapshot: nil)
            previous = [id]
        }
        let base = fixture()
        let baseID = UUID().uuidString
        records[baseID] = Commit(id: baseID, parents: previous, snapshot: base)
        var left = base; left.configurationName = "Left"
        var right = base; right.nodes[0].name = "Right"
        for snapshot in [left, right] {
            let id = UUID().uuidString
            records[id] = Commit(id: id, parents: [baseID], snapshot: snapshot)
        }

        var merged: AppSnapshot?
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            do { merged = try journal.snapshot(records) } catch { failure = error }
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
        XCTAssertNil(failure)
        XCTAssertEqual(merged?.configurationName, "Left")
        XCTAssertEqual(merged?.nodes.first?.name, "Right")
    }

    func testCyclicHistoryIsAConflict() {
        typealias Commit = CloudSnapshotJournal.Commit
        let journal = CloudSnapshotJournal(directory: FileManager.default.temporaryDirectory)
        let (a, b, head) = (UUID().uuidString, UUID().uuidString, UUID().uuidString)
        let records: [String: Commit] = [
            a: Commit(id: a, parents: [b], snapshot: nil),
            b: Commit(id: b, parents: [a], snapshot: nil),
            head: Commit(id: head, parents: [a], snapshot: fixture()),
        ]
        XCTAssertThrowsError(try journal.ancestors(head, commits: records)) { error in
            guard case CloudSyncError.conflict = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testAncestorsVisitSharedHistoryOnce() throws {
        typealias Commit = CloudSnapshotJournal.Commit
        let journal = CloudSnapshotJournal(directory: FileManager.default.temporaryDirectory)
        let (root, left, right, head) = (UUID().uuidString, UUID().uuidString, UUID().uuidString, UUID().uuidString)
        let records: [String: Commit] = [
            root: Commit(id: root, parents: [], snapshot: nil),
            left: Commit(id: left, parents: [root], snapshot: nil),
            right: Commit(id: right, parents: [root], snapshot: nil),
            head: Commit(id: head, parents: [left, right], snapshot: fixture()),
        ]
        XCTAssertEqual(try journal.ancestors(head, commits: records), [root, left, right, head])
    }

    // Issue #49: a Set encodes in hash order, which differs per decode, so an
    // unchanged snapshot with several deleted groups looked like a conflict.
    private func withRemovedGroups(_ names: Set<String>) -> AppSnapshot {
        var snapshot = fixture()
        snapshot.ruleSchemeCustomizations = ["scheme": RuleSchemeCustomization(schemeID: "scheme", removedGroupNames: names)]
        return snapshot
    }

    private func roundTrip(_ snapshot: AppSnapshot) throws -> AppSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: CloudSnapshotMerge.data(snapshot))
    }

    func testRemovedGroupNamesEncodeInStableOrder() throws {
        let names = Set((1...10).map { "Group \($0)" })
        let original = withRemovedGroups(names)
        let data = try CloudSnapshotMerge.data(original)
        for _ in 0..<30 {
            let copy = try roundTrip(original)
            XCTAssertEqual(try CloudSnapshotMerge.data(copy), data)
            XCTAssertTrue(CloudSnapshotMerge.equal(copy, original))
            XCTAssertTrue(CloudSnapshotMerge.sameContent(copy, original))
        }
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let customization = (object["ruleSchemeCustomizations"] as! [String: Any])["scheme"] as! [String: Any]
        XCTAssertEqual(customization["removedGroupNames"] as? [String], names.sorted())
    }

    func testUnchangedRemovedGroupNamesMergeWithoutConflict() throws {
        let snapshot = withRemovedGroups(Set((1...10).map { "Group \($0)" }))
        for _ in 0..<20 {
            let merged = try CloudSnapshotMerge.merge(local: try roundTrip(snapshot), remote: try roundTrip(snapshot), base: try roundTrip(snapshot))
            XCTAssertEqual(merged.ruleSchemeCustomizations?["scheme"]?.removedGroupNames, snapshot.ruleSchemeCustomizations?["scheme"]?.removedGroupNames)
        }
    }

    func testRemovedGroupNamesMergeAsSet() throws {
        let base = withRemovedGroups(["A", "B"])
        let local = withRemovedGroups(["A", "B", "C"])   // deleted C here
        let remote = withRemovedGroups(["B", "D"])       // restored A, deleted D there
        let merged = try CloudSnapshotMerge.merge(local: local, remote: remote, base: base)
        XCTAssertEqual(merged.ruleSchemeCustomizations?["scheme"]?.removedGroupNames, ["B", "C", "D"])
        let first = try CloudSnapshotMerge.merge(local: local, remote: remote, base: nil)
        XCTAssertEqual(first.ruleSchemeCustomizations?["scheme"]?.removedGroupNames, ["A", "B", "C", "D"])
    }

    // 2026-11: pruning markers were never deleted, so a history of 518 files
    // had to be downloaded in full before every sync ("尚未下载完成").
    private func syncedHistory(_ count: Int, in dir: URL) throws -> (CloudSnapshotJournal, [String]) {
        let journal = CloudSnapshotJournal(directory: dir)
        var heads: [String] = []
        for index in 0..<count {
            var snapshot = fixture(); snapshot.configurationName = "Version \(index)"
            snapshot.updatedAt = Date(timeIntervalSince1970: 1000 + Double(index))
            try journal.append(snapshot, parents: journal.heads(try journal.commits()))
            try journal.prune()
            heads.append(contentsOf: journal.heads(try journal.commits()))
        }
        return (journal, heads)
    }

    func testCompactionKeepsTheHistoryBounded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (journal, _) = try syncedHistory(90, in: dir)
        let records = try journal.commits()
        XCTAssertLessThanOrEqual(records.count, CloudSnapshotJournal.compactionThreshold)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") || $0.hasSuffix(".pruned") }
        XCTAssertLessThanOrEqual(files.count, CloudSnapshotJournal.compactionThreshold)
        // Every remaining link resolves without help from the deleted list,
        // so a build without compaction reads this history too.
        XCTAssertTrue(records.values.allSatisfy { $0.parents.allSatisfy { records[$0] != nil } })
        XCTAssertEqual(journal.heads(records).count, 1)
        XCTAssertEqual(try journal.snapshot(records)?.configurationName, "Version 89")
        XCTAssertEqual(records.values.filter { $0.snapshot != nil }.count, CloudSnapshotJournal.retentionLimit)
    }

    func testDeviceOfflineAcrossCompactionStillSyncs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (journal, heads) = try syncedHistory(90, in: dir)
        let stale = heads[0]
        XCTAssertNil(try journal.commits()[stale])
        // The offline device names the head it last saw, long since deleted.
        var offline = fixture(); offline.configurationName = "Offline"
        try journal.append(offline, parents: [stale])
        // Readable, not "still downloading" forever…
        let records = try journal.commits()
        XCTAssertEqual(journal.heads(records).count, 2)
        // …and, like a branch from a pruned version, a choice for the user.
        XCTAssertThrowsError(try journal.snapshot(records)) { XCTAssertEqual($0 as? CloudSyncError, .conflict) }
        // Choosing one, as recovery does, joins the branches again.
        try journal.append(offline, parents: journal.heads(records))
        XCTAssertEqual(try journal.snapshot(try journal.commits())?.configurationName, "Offline")
    }

    func testUnknownMissingParentIsStillInTransit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (journal, _) = try syncedHistory(3, in: dir)
        try journal.append(fixture(), parents: [UUID().uuidString])
        XCTAssertThrowsError(try journal.commits()) { XCTAssertEqual($0 as? CloudSyncError, .downloading) }
    }
}
