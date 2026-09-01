import XCTest
@testable import Tower

@MainActor
final class SubscriptionReminderTests: XCTestCase {
    func testPlansReminderExactlyOneDayBeforeExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let source = SubscriptionSource(
            name: "云帆机场",
            urlString: "https://airport.example/private?token=secret",
            usage: SubscriptionUsage(expiresAt: expiry)
        )

        let plans = SubscriptionReminderPlanner.plans(
            for: [source],
            now: expiry.addingTimeInterval(-7 * 86_400)
        )

        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plan.fireDate, expiry.addingTimeInterval(-86_400))
        XCTAssertEqual(plan.identifier, "tower.renewal.\(source.id.uuidString)")
        XCTAssertEqual(plan.title, "云帆机场 到期还剩 1 天")
        XCTAssertEqual(plan.expiryDate, expiry)
        XCTAssertTrue(plan.body.contains("续费"))
        XCTAssertFalse(plan.body.contains("secret"))
        XCTAssertFalse(plan.body.contains("airport.example"))
    }

    func testRemainingDaysUsesCalendarDaysInsteadOfTomorrowWording() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = calendar.date(byAdding: .day, value: 6, to: now)!

        XCTAssertEqual(
            SubscriptionReminderPlanner.remainingDayCount(
                until: expiry,
                from: now,
                calendar: calendar
            ),
            6
        )
    }

    func testSkipsSourcesWithoutAFutureReminderDate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let noExpiry = SubscriptionSource(name: "未提供到期", urlString: "https://a.example")
        let tooLate = SubscriptionSource(
            name: "已经不足一天",
            urlString: "https://b.example",
            usage: SubscriptionUsage(expiresAt: now.addingTimeInterval(3_600))
        )
        let expired = SubscriptionSource(
            name: "已到期",
            urlString: "https://c.example",
            usage: SubscriptionUsage(expiresAt: now.addingTimeInterval(-1))
        )

        XCTAssertTrue(
            SubscriptionReminderPlanner.plans(for: [noExpiry, tooLate, expired], now: now).isEmpty
        )

        let entries = SubscriptionReminderPlanner.expiryEntries(
            for: [noExpiry, tooLate, expired],
            now: now
        )
        XCTAssertEqual(entries.map(\.sourceName), ["已经不足一天", "已到期"])
        XCTAssertEqual(entries[0].status(at: now), .upcoming(days: 1))
        XCTAssertEqual(entries[1].status(at: now), .expired(days: 1))
    }

    func testDisabledSubscriptionStillReceivesRenewalReminder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = SubscriptionSource(
            name: "暂时停用的机场",
            urlString: "https://example.com/sub",
            isEnabled: false,
            usage: SubscriptionUsage(expiresAt: now.addingTimeInterval(172_800))
        )

        XCTAssertEqual(SubscriptionReminderPlanner.plans(for: [source], now: now).count, 1)
    }

    func testAppModelPersistsPreferenceOnlyAfterAuthorization() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reminder-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let scheduler = ReminderSchedulerSpy(isAuthorized: true)
        let model = AppModel(
            persistence: store,
            reminderScheduler: scheduler,
            arguments: []
        )

        await model.setRenewalRemindersEnabled(true)

        XCTAssertTrue(model.renewalRemindersEnabled)
        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertEqual(scheduler.replacementCount, 1)
        XCTAssertEqual(try store.load()?.renewalRemindersEnabled, true)

        await model.setRenewalRemindersEnabled(false)
        XCTAssertFalse(model.renewalRemindersEnabled)
        XCTAssertEqual(scheduler.removalCount, 1)
        XCTAssertEqual(try store.load()?.renewalRemindersEnabled, false)
    }

    func testAppModelKeepsReminderOffWhenPermissionIsDenied() async {
        let scheduler = ReminderSchedulerSpy(isAuthorized: false)
        let model = AppModel(
            persistence: PersistenceStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tower-reminder-denied-\(UUID().uuidString).json")
            ),
            reminderScheduler: scheduler,
            arguments: []
        )

        await model.setRenewalRemindersEnabled(true)

        XCTAssertFalse(model.renewalRemindersEnabled)
        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertEqual(scheduler.replacementCount, 0)
    }

    func testResetAllConfigurationRestoresLocalDefaultsAndRemovesCachedRules() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-reset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let persistence = PersistenceStore(fileURL: rootURL.appendingPathComponent("state.json"))
        let downloadStore = RuleDownloadStore(folderURL: rootURL.appendingPathComponent("rules"))
        let scheduler = ReminderSchedulerSpy(isAuthorized: true)
        let remoteRuleURL = try XCTUnwrap(URL(string: "https://rules.example/private.list"))
        try downloadStore.store("DOMAIN,example.com", for: remoteRuleURL)

        let source = SubscriptionSource(
            name: "待重置订阅",
            urlString: "https://subscription.example/private"
        )
        let node = ProxyNode(
            sourceID: source.id,
            kind: .shadowsocks,
            name: "待重置节点",
            server: "node.example",
            port: 443,
            rawURI: "ss://private"
        )
        let scheme = RuleScheme(
            id: "reset-test-scheme",
            name: "待重置规则",
            summary: "test",
            groups: [],
            rulesets: [RuleSchemeRuleset(groupName: "代理", resource: .remote(remoteRuleURL))]
        )

        let originalCloudPreference = CloudSyncPreference.isEnabled()
        CloudSyncPreference.setEnabled(true)
        defer { CloudSyncPreference.setEnabled(originalCloudPreference) }

        let model = AppModel(
            persistence: persistence,
            downloadStore: downloadStore,
            reminderScheduler: scheduler,
            arguments: []
        )
        model.subscriptions = [source]
        model.nodes = [node]
        model.selectedPresetID = scheme.id
        model.selectedTarget = .quanx
        model.selectedTab = .export
        model.importedSchemes = [scheme]
        model.selectedRuleGroups[scheme.id] = ["代理"]
        model.ruleSchemeCustomizations[scheme.id] = RuleSchemeCustomization(schemeID: scheme.id)
        model.ruleGroupEmojisEnabled[scheme.id] = false
        model.excludedNodeIDs = [node.id]
        model.localRuleSets = [LocalRuleSet(name: "本机规则", rulesText: "DOMAIN,example.com")]
        model.customRuleFlows = [
            CustomRuleFlow(
                schemeID: scheme.id,
                name: "自定义规则",
                policyName: "代理",
                rulesText: "DOMAIN,example.com"
            )
        ]
        model.excludedKinds[.quanx] = [.vless]
        model.renewalRemindersEnabled = true
        model.clientOrder = Array(ClientTarget.allCases.reversed())
        model.lanSharingOrderIndex = 0
        model.appendSubscriptionNameToNodes = true
        model.filterSubscriptionInfoNodes = true
        model.autoRefreshOnOpen = true
        model.configurationName = "自定义名称"
        model.setPreferRuleSets(true)
        model.exportContentModes[.quanx] = .nodesOnly
        model.nodeLatencies[node.id] = .success(milliseconds: 42, method: .tcp)
        model.latencyTestingNodeIDs = [node.id]
        model.selectedLatencyTestMode = .tcp

        await model.resetAllConfiguration()

        XCTAssertTrue(model.subscriptions.isEmpty)
        XCTAssertTrue(model.nodes.isEmpty)
        XCTAssertEqual(model.selectedPresetID, AppModel.defaultRuleSchemeID)
        XCTAssertEqual(model.selectedTarget, .surge)
        XCTAssertEqual(model.selectedTab, .subscriptions)
        XCTAssertTrue(model.importedSchemes.isEmpty)
        XCTAssertTrue(model.selectedRuleGroups.isEmpty)
        XCTAssertTrue(model.ruleSchemeCustomizations.isEmpty)
        XCTAssertTrue(model.ruleGroupEmojisEnabled.isEmpty)
        XCTAssertTrue(model.excludedNodeIDs.isEmpty)
        XCTAssertTrue(model.localRuleSets.isEmpty)
        XCTAssertTrue(model.customRuleFlows.isEmpty)
        XCTAssertTrue(model.excludedKinds.isEmpty)
        XCTAssertFalse(model.renewalRemindersEnabled)
        XCTAssertEqual(model.clientOrder, ClientTargetOrder.defaultOrder)
        XCTAssertEqual(model.lanSharingOrderIndex, ExportDestinationOrder.defaultLANSharingIndex)
        XCTAssertEqual(model.exportDestinationOrder[3], .lanSharing)
        XCTAssertFalse(model.appendSubscriptionNameToNodes)
        XCTAssertFalse(model.filterSubscriptionInfoNodes)
        XCTAssertFalse(model.autoRefreshOnOpen)
        XCTAssertEqual(model.configurationName, TowerBrand.localizedName)
        XCTAssertFalse(model.preferRuleSets)
        XCTAssertTrue(model.exportContentModes.isEmpty)
        XCTAssertTrue(model.nodeLatencies.isEmpty)
        XCTAssertTrue(model.latencyTestingNodeIDs.isEmpty)
        XCTAssertEqual(model.selectedLatencyTestMode, .automatic)
        XCTAssertFalse(model.iCloudSyncEnabled)
        XCTAssertFalse(downloadStore.hasCachedRules(for: remoteRuleURL))
        XCTAssertEqual(scheduler.removalCount, 1)
        XCTAssertEqual(model.toast?.text, "所有配置已重置")
        XCTAssertEqual(model.toast?.tone, .success)

        let saved = try XCTUnwrap(persistence.load())
        XCTAssertTrue(saved.subscriptions.isEmpty)
        XCTAssertTrue(saved.nodes.isEmpty)
        XCTAssertEqual(saved.selectedPresetID, AppModel.defaultRuleSchemeID)
        XCTAssertEqual(saved.selectedTarget, .surge)
        XCTAssertEqual(saved.importedSchemes ?? [], [])
        XCTAssertEqual(saved.configurationName, TowerBrand.localizedName)
        XCTAssertEqual(saved.preferRuleSets, false)
        XCTAssertEqual(saved.renewalRemindersEnabled, false)
        XCTAssertEqual(saved.lanSharingOrderIndex, ExportDestinationOrder.defaultLANSharingIndex)

        let reloaded = AppModel(
            persistence: persistence,
            downloadStore: downloadStore,
            reminderScheduler: scheduler,
            arguments: []
        )
        XCTAssertEqual(reloaded.exportDestinationOrder[3], .lanSharing)
    }
}

@MainActor
private final class ReminderSchedulerSpy: SubscriptionReminderScheduling {
    let isAuthorized: Bool
    var authorizationRequestCount = 0
    var replacementCount = 0
    var removalCount = 0
    var plans: [SubscriptionReminderPlan] = []

    init(isAuthorized: Bool) {
        self.isAuthorized = isAuthorized
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return isAuthorized
    }

    func replaceReminders(with plans: [SubscriptionReminderPlan]) async throws {
        replacementCount += 1
        self.plans = plans
    }

    func removeReminders() async {
        removalCount += 1
        plans = []
    }
}
