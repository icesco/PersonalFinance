import Foundation
import Testing
@testable import FinanceCore

struct RecurrenceScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    @Test func monthEndReturnsToOriginalDay() {
        let anchor = date(2025, 1, 31)
        let dates = RecurrenceSchedule.dates(anchor: anchor, frequency: .monthly, after: anchor,
                                             through: date(2025, 4, 30), calendar: calendar)
        #expect(dates == [date(2025, 2, 28), date(2025, 3, 31), date(2025, 4, 30)])
    }
    @Test func leapDayAndInclusiveEnd() {
        let anchor = date(2024, 2, 29)
        #expect(RecurrenceSchedule.next(anchor: anchor, frequency: .yearly, after: date(2027, 3, 1), calendar: calendar) == date(2028, 2, 29))
        #expect(RecurrenceSchedule.next(anchor: anchor, frequency: .yearly, after: anchor, ending: date(2025, 2, 28), calendar: calendar) == date(2025, 2, 28))
        #expect(RecurrenceSchedule.next(anchor: anchor, frequency: .yearly, after: date(2025, 2, 28), ending: date(2025, 2, 28), calendar: calendar) == nil)
    }
    @Test func dailyKeepsWallClockAcrossDST() {
        let dates = RecurrenceSchedule.dates(anchor: date(2026, 3, 28), frequency: .daily,
                                             after: date(2026, 3, 28), through: date(2026, 3, 30), calendar: calendar)
        #expect(dates == [date(2026, 3, 29), date(2026, 3, 30)])
    }
    @Test func selectedEndDayIsInclusiveAcrossDaylightSavingChanges() throws {
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25), (10, 5, 24)] {
            let lastDay = date(2026, month, day)
            let anchor = calendar.date(byAdding: .day, value: -1, to: lastDay)!
            let end = try #require(RecurrenceSchedule.inclusiveEnd(anchor: anchor, lastDay: lastDay, calendar: calendar))
            let interval = try #require(calendar.dateInterval(of: .day, for: lastDay))
            #expect(interval.duration == Double(hours * 3600))
            #expect(end >= lastDay)
            #expect(end < interval.end)
            #expect(end == interval.end.addingTimeInterval(-0.001))
            #expect(calendar.isDate(end, inSameDayAs: lastDay))
            let display = Date.FormatStyle(date: .numeric, time: .omitted, locale: Locale(identifier: "it_IT"),
                                           calendar: calendar, timeZone: calendar.timeZone)
            #expect(end.formatted(display) == lastDay.formatted(display))
            let followingDay = calendar.date(byAdding: .day, value: 1, to: lastDay)!
            #expect(RecurrenceSchedule.dates(anchor: anchor, frequency: .daily, after: anchor,
                                             through: followingDay, ending: end, calendar: calendar) == [lastDay])
        }
    }

    @Test func endDayMayEqualAnchorDayButCannotPrecedeIt() {
        let anchor = date(2026, 10, 5)
        #expect(RecurrenceSchedule.inclusiveEnd(anchor: anchor, lastDay: calendar.startOfDay(for: anchor), calendar: calendar) != nil)
        #expect(RecurrenceSchedule.inclusiveEnd(anchor: anchor, lastDay: date(2026, 10, 4), calendar: calendar) == nil)
    }

}
