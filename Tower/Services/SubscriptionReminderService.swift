import Foundation
import UserNotifications

struct SubscriptionReminderPlan: Equatable, Sendable {
    let identifier: String
    let sourceName: String
    let title: String
    let body: String
    let fireDate: Date
    let expiryDate: Date
}

enum SubscriptionExpiryStatus: Equatable, Sendable {
    case upcoming(days: Int)
    case expired(days: Int)
}

struct SubscriptionExpiryEntry: Identifiable, Equatable, Sendable {
    let identifier: String
    let sourceName: String
    let expiryDate: Date

    var id: String { identifier }

    func status(
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> SubscriptionExpiryStatus {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiryDate)
        let difference = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        if expiryDate >= now {
            return .upcoming(days: max(difference, 1))
        }
        return .expired(days: max(abs(difference), 1))
    }
}

enum SubscriptionReminderPlanner {
    static let identifierPrefix = "tower.renewal."

    static func plans(
        for sources: [SubscriptionSource],
        now: Date = .now
    ) -> [SubscriptionReminderPlan] {
        sources.compactMap { source in
            guard let expiry = source.usage?.expiresAt else { return nil }
            let fireDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: expiry)
                ?? expiry.addingTimeInterval(-86_400)
            guard fireDate > now else { return nil }
            return SubscriptionReminderPlan(
                identifier: identifierPrefix + source.id.uuidString,
                sourceName: source.name,
                title: String(localized: "\(source.name) 到期还剩 1 天"),
                body: String(localized: "订阅到期还剩 1 天，请及时续费。"),
                fireDate: fireDate,
                expiryDate: expiry
            )
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    static func expiryEntries(
        for sources: [SubscriptionSource],
        now: Date = .now
    ) -> [SubscriptionExpiryEntry] {
        sources.compactMap { source in
            guard let expiryDate = source.usage?.expiresAt else { return nil }
            return SubscriptionExpiryEntry(
                identifier: "\(identifierPrefix)\(source.id.uuidString)",
                sourceName: source.name,
                expiryDate: expiryDate
            )
        }
        .sorted { lhs, rhs in
            let lhsExpired = lhs.expiryDate < now
            let rhsExpired = rhs.expiryDate < now
            if lhsExpired != rhsExpired { return !lhsExpired }
            return lhsExpired
                ? lhs.expiryDate > rhs.expiryDate
                : lhs.expiryDate < rhs.expiryDate
        }
    }

    static func remainingDayCount(
        until expiry: Date,
        from now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiry)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }
}

@MainActor
protocol SubscriptionReminderScheduling: AnyObject {
    func requestAuthorization() async throws -> Bool
    func replaceReminders(with plans: [SubscriptionReminderPlan]) async throws
    func removeReminders() async
}

@MainActor
final class SubscriptionReminderScheduler: SubscriptionReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func replaceReminders(with plans: [SubscriptionReminderPlan]) async throws {
        await removeReminders()
        let calendar = Calendar.autoupdatingCurrent

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "tower-renewal"

            let components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: plan.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(
                UNNotificationRequest(
                    identifier: plan.identifier,
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    func removeReminders() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(SubscriptionReminderPlanner.identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
