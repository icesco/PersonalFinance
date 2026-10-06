import Foundation
import Testing
import UserNotifications
import FinanceCore
@testable import Personal_Finance

@MainActor
struct RecurrenceReminderTests {
    @Test func reminderTapWaitsForUnlockAndEditorThenShowsAllBooks() throws {
        let keys = ["selectedAccountID", "selectedContoID", "showAllAccounts", "showAllConti"]
        let saved = keys.map { (key: $0, value: UserDefaults.standard.object(forKey: $0)) }
        defer { for item in saved { UserDefaults.standard.set(item.value, forKey: item.key) } }
        let inbox = FinanceShortcutInbox()
        let state = AppStateManager()
        state.showAllAccounts = false
        state.selectTab(.dashboard)
        let router = ReminderNotificationRouter()
        router.receive(identifier: "forgia.recurrence.123", action: UNNotificationDefaultActionIdentifier, inbox: inbox)
        inbox.deliver(to: state, canAccessContent: false)
        #expect(inbox.pending == .reminderPlanning)
        #expect(state.selectedTab == .dashboard)
        state.presentQuickTransaction()
        inbox.deliver(to: state)
        #expect(inbox.pending == .reminderPlanning)
        state.dismissQuickTransaction()
        inbox.deliver(to: state)
        #expect(inbox.pending == nil)
        #expect(state.selectedTab == .planning)
        #expect(state.showAllAccounts)
    }

    @Test func reminderDismissalAndForeignNotificationsDoNotNavigateOrReplaceDraft() throws {
        let inbox = FinanceShortcutInbox()
        let router = ReminderNotificationRouter()
        router.receive(identifier: "forgia.recurrence.123", action: UNNotificationDismissActionIdentifier, inbox: inbox)
        router.receive(identifier: "another.notification", action: UNNotificationDefaultActionIdentifier, inbox: inbox)
        #expect(inbox.pending == nil)
        let draft = FinanceShortcutRequest.expense(amount: "10", description: "Bozza")
        try inbox.submit(draft)
        router.receive(identifier: "forgia.recurrence.123", action: UNNotificationDefaultActionIdentifier, inbox: inbox)
        #expect(inbox.pending == draft)
        #expect(inbox.errorMessage != nil)
    }

    @MainActor final class Center: RecurrenceNotificationCenter {
        var authorized = true
        var requests: [UNNotificationRequest] = []
        var onRead: (() -> Void)?
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { authorized }
        func pendingNotificationRequests() async -> [UNNotificationRequest] {
            let action = onRead; onRead = nil; action?()
            return requests
        }
        func removePendingNotificationRequests(withIdentifiers ids: [String]) { requests.removeAll { ids.contains($0.identifier) } }
        func deliveredNotifications() async -> [UNNotification] { [] }
        func removeDeliveredNotifications(withIdentifiers: [String]) { }
        func isAuthorized() async -> Bool { authorized }
        func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
    }

    @Test func disableRemovesOnlyOwnedReminders() async {
        let name = "reminder-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = Center()
        center.requests = [UNNotificationRequest(identifier: "another-feature", content: UNMutableNotificationContent(), trigger: nil)]
        let service = RecurrenceReminders(defaults: defaults, center: center)
        await service.setEnabled(true)
        service.update(RecurringReminderPlanner.plan(occurrences: [Date().addingTimeInterval(172800)], hour: 9, minute: 0, daysBefore: 0))
        await service.waitForPendingUpdates()
        #expect(center.requests.count == 2)
        await service.setEnabled(false)
        await service.waitForPendingUpdates()
        #expect(center.requests.map(\.identifier) == ["another-feature"])
        #expect(!defaults.bool(forKey: "reminders.enabled"))
    }

    @Test func deniedPermissionDoesNotEnableAndLatestRevisionWins() async {
        let name = "reminder-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let center = Center()
        center.authorized = false
        let service = RecurrenceReminders(defaults: defaults, center: center)
        await service.setEnabled(true)
        #expect(!service.enabled)
        center.authorized = true
        await service.setEnabled(true)
        await service.waitForPendingUpdates()
        let earlier = RecurringReminderPlanner.plan(occurrences: [Date().addingTimeInterval(172800)], hour: 9, minute: 0, daysBefore: 0)
        let later = RecurringReminderPlanner.plan(occurrences: [Date().addingTimeInterval(345600)], hour: 10, minute: 0, daysBefore: 0)
        center.onRead = { service.update(later) }
        service.update(earlier)
        await service.waitForPendingUpdates()
        #expect(center.requests.map(\.identifier) == later.map(\.identifier))
    }

    @Test func clockAdvanceDuringReconciliationDoesNotRescheduleExpiredDates() async throws {
        let name = "reminder-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "reminders.enabled")
        let center = Center()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let plans = RecurringReminderPlanner.plan(
            occurrences: [now.addingTimeInterval(172800), now.addingTimeInterval(345600)],
            hour: 9, minute: 0, daysBefore: 0, now: now
        )
        let first = try #require(plans.first)
        let last = try #require(plans.last)
        let service = RecurrenceReminders(defaults: defaults, center: center, now: { now })
        center.onRead = { now = first.fireDate }
        service.update(plans)
        await service.waitForPendingUpdates()
        #expect(center.requests.map(\.identifier) == [last.identifier])
        #expect(service.status == "1 promemoria programmati su questo dispositivo.")

        now = last.fireDate.addingTimeInterval(1)
        service.update(plans)
        await service.waitForPendingUpdates()
        #expect(center.requests.isEmpty)
        #expect(service.status == "0 promemoria programmati su questo dispositivo.")
    }
}
