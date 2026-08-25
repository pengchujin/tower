import XCTest
@testable import Tower

/// Reset promises one thing on screen — "only this device" — and the snapshot
/// it writes has to keep that promise the next time sync runs.
final class ResetCloudSafetyTests: XCTestCase {
    @MainActor
    func testReenablingSyncAfterResetRestoresTheRemoteCopyInsteadOfErasingIt() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-cloud-\(UUID().uuidString).json")
        let remoteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-remote-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: remoteURL)
        }

        let wasEnabled = CloudSyncPreference.isEnabled()
        defer { CloudSyncPreference.setEnabled(wasEnabled) }
        CloudSyncPreference.setEnabled(true)

        // Another device uploaded a real snapshot an hour ago.
        let remote = AppSnapshot(
            subscriptions: [
                SubscriptionSource(name: "另一台设备的订阅", urlString: "https://a.example/x")
            ],
            nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge,
            updatedAt: Date.now.addingTimeInterval(-3600)
        )
        let cloud = CloudSyncStore(fileURL: remoteURL)
        try await cloud.upload(remote)

        let model = AppModel(
            persistence: PersistenceStore(fileURL: stateURL),
            cloudSync: cloud,
            arguments: []
        )
        model.subscriptions = [
            SubscriptionSource(name: "本机订阅", urlString: "https://b.example/y")
        ]

        await model.resetAllConfiguration()
        XCTAssertFalse(model.iCloudSyncEnabled)

        // Turning sync back on is how someone asks for their data back. It used
        // to upload the emptiness over the other device instead.
        await model.setICloudSyncEnabled(true)

        let after = try await cloud.download()
        XCTAssertEqual(after?.subscriptions.count, 1, "远端副本被本机的空快照覆盖了")
        XCTAssertEqual(model.subscriptions.first?.name, "另一台设备的订阅")
    }

    /// The file on disk has to carry the same old timestamp, or the next launch
    /// applies it, stamps `lastLocalEditAt` with "now" and loses the remote
    /// copy one launch later instead of immediately.
    @MainActor
    func testTheResetSnapshotIsPersistedWithoutClaimingToBeTheNewestEdit() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-stamp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let persistence = PersistenceStore(fileURL: stateURL)
        let model = AppModel(persistence: persistence, arguments: [])
        model.subscriptions = [
            SubscriptionSource(name: "本机订阅", urlString: "https://b.example/y")
        ]

        await model.resetAllConfiguration()

        let saved = try XCTUnwrap(persistence.load())
        XCTAssertEqual(saved.updatedAt, AppModel.resetSnapshotDate)
        XCTAssertEqual(
            CloudSyncResolution.resolve(local: saved.updatedAt, remote: Date.now.addingTimeInterval(-86_400)),
            .takeRemote
        )
    }

    /// An ordinary edit after a reset is a real edit and must win again.
    @MainActor
    func testAnEditAfterResetIsStampedNormally() async throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-edit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let persistence = PersistenceStore(fileURL: stateURL)
        let model = AppModel(persistence: persistence, arguments: [])
        await model.resetAllConfiguration()
        model.setConfigurationName("重置之后改的名字")

        let saved = try XCTUnwrap(persistence.load())
        let updatedAt = try XCTUnwrap(saved.updatedAt)
        XCTAssertGreaterThan(updatedAt, Date.now.addingTimeInterval(-60))
    }

    /// Reset should leave the rule cache as empty as a fresh install, including
    /// lists whose scheme was deleted long ago and can no longer be named.
    @MainActor
    func testResetEmptiesTheRuleCacheEvenForListsNothingReferences() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let downloadStore = RuleDownloadStore(folderURL: rootURL.appendingPathComponent("rules"))
        let orphan = try XCTUnwrap(URL(string: "https://rules.example/orphan.list"))
        try downloadStore.store("DOMAIN,orphan.example", for: orphan)

        let model = AppModel(
            persistence: PersistenceStore(fileURL: rootURL.appendingPathComponent("state.json")),
            downloadStore: downloadStore,
            arguments: []
        )

        await model.resetAllConfiguration()

        XCTAssertFalse(downloadStore.hasCachedRules(for: orphan))
    }
}

/// Every byte count Tower parses comes from the provider, and `Int64(Double)`
/// traps rather than saturating.
final class SubscriptionUsageOverflowTests: XCTestCase {
    func testAnAbsurdHeaderQuotaIsClampedInsteadOfCrashing() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(header: "upload=1e30; download=0; total=99999999999999999999")
        )

        XCTAssertEqual(usage.totalBytes, .max)
        XCTAssertEqual(usage.uploadBytes, .max)
    }

    func testAnAbsurdStatusLineQuotaIsClampedInsteadOfCrashing() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(statusLine: "STATUS=↑:1GB,↓:2GB,TOT:99999999999999999999GB")
        )

        XCTAssertEqual(usage.totalBytes, .max)
    }

    /// The card reads this one while drawing, so a trap here crashed the app on
    /// the subscription list rather than during a refresh.
    func testAnAbsurdRemainingNoticeIsClampedInsteadOfCrashing() {
        var usage = SubscriptionUsage()
        usage.notices = ["剩余流量：99999999999999999999 GB"]

        XCTAssertEqual(usage.displayRemainingBytes, .max)
    }

    func testOrdinaryQuotasStillParseExactly() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(header: "upload=1073741824; download=0; total=10737418240")
        )

        XCTAssertEqual(usage.totalBytes, 10_737_418_240)
        XCTAssertEqual(usage.remainingBytes, 9_663_676_416)
    }

    func testANegativeQuotaBecomesZeroRatherThanTrapping() throws {
        let usage = try XCTUnwrap(SubscriptionUsage.parse(header: "total=-1e30"))

        XCTAssertEqual(usage.totalBytes, 0)
    }

    /// Two clamped halves must not overflow their own sum, and the remainder
    /// subtraction after them must not overflow either.
    func testClampedHalvesDoNotOverflowTheDerivedTotals() throws {
        let usage = try XCTUnwrap(
            SubscriptionUsage.parse(
                header: "upload=1e30; download=1e30; total=1e30"
            )
        )

        XCTAssertEqual(usage.usedBytes, .max)
        XCTAssertEqual(usage.remainingBytes, 0)
        XCTAssertEqual(usage.usedFraction, 1)
    }
}
