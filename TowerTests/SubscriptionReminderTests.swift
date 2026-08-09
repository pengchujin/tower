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
