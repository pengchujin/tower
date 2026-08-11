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
