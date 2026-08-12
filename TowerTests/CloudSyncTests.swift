import XCTest
@testable import Tower

/// The rule that decides which device's copy survives.
///
/// Split out of `CloudSyncStore` so it can be tested without an iCloud account
/// — and because a merge rule nobody can test is a merge rule nobody trusts.
final class CloudSyncTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    func testNewerSnapshotWins() {
        XCTAssertEqual(CloudSyncResolution.resolve(local: earlier, remote: later), .takeRemote)
        XCTAssertEqual(CloudSyncResolution.resolve(local: later, remote: earlier), .keepLocal)
    }

    /// Equal timestamps keep what is already on the device: pulling would
    /// replace a snapshot with an identical one and cost a write for nothing.
    func testATieKeepsTheLocalCopy() {
        XCTAssertEqual(CloudSyncResolution.resolve(local: later, remote: later), .keepLocal)
    }

    /// Snapshots written before sync existed carry no date. Such a snapshot
    /// cannot have been the newer edit made on another device — sync did not
    /// exist when it was written — so it loses to any dated one.
    func testAnUndatedSnapshotLosesToADatedOne() {
        XCTAssertEqual(CloudSyncResolution.resolve(local: nil, remote: later), .takeRemote)
    }

    /// Nothing in iCloud yet is not a reason to wipe the device.
    func testMissingRemoteNeverReplacesLocal() {
        XCTAssertEqual(CloudSyncResolution.resolve(local: later, remote: nil), .keepLocal)
        XCTAssertEqual(CloudSyncResolution.resolve(local: nil, remote: nil), .keepLocal)
    }

    /// The switch is per-device and must not travel inside the thing being
    /// synced, or one device would decide where another device's data may go.
    func testTheSyncSwitchIsNotPartOfTheSnapshot() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(
            String(data: try encoder.encode(AppSnapshot(
                subscriptions: [], nodes: [], selectedPresetID: "x", selectedTarget: .surge
            )), encoding: .utf8)
        )

        XCTAssertFalse(json.contains("iCloud"), json)
        XCTAssertFalse(json.contains("icloud"), json)
    }

    func testSnapshotCarriesTheTimestampSyncNeeds() throws {
        let snapshot = AppSnapshot(
            subscriptions: [], nodes: [], selectedPresetID: "x", selectedTarget: .surge,
            updatedAt: later
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let round = try decoder.decode(AppSnapshot.self, from: try encoder.encode(snapshot))
        XCTAssertEqual(round.updatedAt, later)
    }

    /// Every snapshot written before this feature has no `updatedAt` key at
    /// all. Decoding has to keep working or sync would cost users their data.
    func testOlderSnapshotsWithoutTheKeyStillDecode() throws {
        let json = """
        {"subscriptions":[],"nodes":[],"selectedPresetID":"x","selectedTarget":"surge"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.updatedAt)
    }
}

/// A pull that happens on its own must never surprise the user with a toast,
/// and must never lose an edit they just made.
final class CloudSyncTriggerTests: XCTestCase {
    /// Automatic pulls pass no `showResult`, so the default has to be silent.
    /// Returning to the foreground several times a minute is normal use; a
    /// message each time would train people to ignore the ones that matter.
    func testAutomaticSyncIsSilentByDefault() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tower/AppModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("func synchronizeWithCloud(showResult: Bool = false)"),
            "自动拉取默认必须静默"
        )
    }

    /// Both the launch pull and the foreground pull have to exist, or an upload
    /// that already happened never reaches the other device and "sync" means
    /// opening Settings and pressing a button. Automatic refresh rides the same
    /// two triggers, so it is pinned here too.
    ///
    /// Checks that the calls are present, not how the block is laid out — an
    /// earlier version asserted the exact source line and broke the moment a
    /// second call joined it, which says nothing about whether sync works.
    func testLaunchAndForegroundBothTriggerTheOpenWork() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tower/TowerApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".task(id: hasSeenWelcome)"), source)
        XCTAssertTrue(source.contains("onChange(of: scenePhase)"), source)
        XCTAssertTrue(source.contains("phase == .active"), source)
        XCTAssertEqual(
            occurrences(of: "guard hasSeenWelcome else { return }", in: source),
            2,
            "欢迎页关闭前，启动任务和前台任务都不能在遮罩下面联网：\n\(source)"
        )
        // Two call sites each: the launch task and the foreground change.
        XCTAssertEqual(occurrences(of: "synchronizeWithCloud()", in: source), 2, source)
        XCTAssertEqual(occurrences(of: "refreshOnOpenIfEnabled()", in: source), 2, source)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// An edit made locally after the remote copy was written must survive a
    /// foreground pull. This is the case that would silently eat someone's
    /// work, so it is pinned rather than left to the general ordering test.
    func testAFreshLocalEditIsNotOverwrittenByAnOlderRemote() {
        let remoteWritten = Date(timeIntervalSince1970: 1_000)
        let localEditedAfter = Date(timeIntervalSince1970: 1_001)

        XCTAssertEqual(
            CloudSyncResolution.resolve(local: localEditedAfter, remote: remoteWritten),
            .keepLocal
        )
    }
}
