import Foundation
import Testing
@testable import FinanceCore

struct RecurringReminderPlannerTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }
    @Test func groupsByDayAndDoesNotBackdate() {
        let plans = RecurringReminderPlanner.plan(occurrences: [date(28, 12), date(29, 10), date(29, 18), date(30, 12)],
            hour: 9, minute: 0, daysBefore: 0, now: date(28, 10), calendar: calendar)
        #expect(plans.map(\.fireDate) == [date(29, 9), date(30, 9)])
        #expect(plans.map(\.count) == [2, 1])
        #expect(Set(plans.map(\.identifier)).count == 2)
    }
    @Test func previousDayHonorsCalendarAcrossDST() {
        let plans = RecurringReminderPlanner.plan(occurrences: [date(29, 12), date(30, 12)],
            hour: 9, minute: 0, daysBefore: 1, now: date(28, 8), calendar: calendar)
        #expect(plans.map(\.fireDate) == [date(28, 9), date(29, 9)])
    }
    @Test func rejectsInvalidPreferences() {
        #expect(RecurringReminderPlanner.plan(occurrences: [date(29, 12)], hour: 24, minute: 0, daysBefore: 0).isEmpty)
        #expect(RecurringReminderPlanner.plan(occurrences: [date(29, 12)], hour: 9, minute: 0, daysBefore: -1).isEmpty)
    }
}
