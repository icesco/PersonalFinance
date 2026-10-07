import Foundation
import Testing
@testable import Personal_Finance

@MainActor
struct TransactionTimeframeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func quarterAndSemesterAlignToCalendarBoundaries() {
        let reference = date(2026, 11, 19)
        #expect(TransactionTimeframe.quarter.interval(containing: reference, calendar: calendar)
                == DateInterval(start: date(2026, 10, 1), end: date(2027, 1, 1)))
        #expect(TransactionTimeframe.halfYear.interval(containing: reference, calendar: calendar)
                == DateInterval(start: date(2026, 7, 1), end: date(2027, 1, 1)))
        #expect(TransactionTimeframe.quarter.interval(containing: date(2026, 4, 1), calendar: calendar).start
                == date(2026, 4, 1))
    }

    @Test func subtitleExplainsWhatThePeriodCovers() {
        let reference = date(2026, 11, 19)
        #expect(TransactionTimeframe.quarter.subtitle(containing: reference, calendar: calendar) == "Ottobre – Dicembre")
        #expect(TransactionTimeframe.halfYear.subtitle(containing: date(2026, 2, 3), calendar: calendar) == "Gennaio – Giugno")
        #expect(TransactionTimeframe.week.subtitle(containing: date(2026, 10, 6), calendar: calendar) == "Settimana 41")
        #expect(TransactionTimeframe.month.subtitle(containing: reference, calendar: calendar) == nil)
        #expect(TransactionTimeframe.year.subtitle(containing: reference, calendar: calendar) == nil)
    }

    @Test func navigationCrossesYearsWithoutSkippingPeriods() {
        #expect(TransactionTimeframe.quarter.moving(date(2026, 1, 31), by: -1, calendar: calendar)
                == date(2025, 10, 1))
        #expect(TransactionTimeframe.halfYear.moving(date(2026, 12, 31), by: 1, calendar: calendar)
                == date(2027, 1, 1))
        #expect(TransactionTimeframe.month.moving(date(2024, 1, 31), by: 1, calendar: calendar)
                == date(2024, 2, 1))
    }

    @Test func leapMonthIncludesFebruary29() {
        let range = TransactionTimeframe.month.interval(containing: date(2024, 2, 29), calendar: calendar)
        #expect(range.start == date(2024, 2, 1))
        #expect(range.end == date(2024, 3, 1))
        #expect(calendar.dateComponents([.day], from: range.start, to: range.end).day == 29)
    }

    @Test func weekRespectsFirstWeekdayAndDaylightSaving() {
        let range = TransactionTimeframe.week.interval(containing: date(2026, 3, 29), calendar: calendar)
        #expect(range.start == date(2026, 3, 23))
        #expect(range.end == date(2026, 3, 30))
        #expect(range.duration == 7 * 24 * 60 * 60 - 3600)
        #expect(TransactionTimeframe.week.moving(date(2026, 3, 29), by: 1, calendar: calendar) == range.end)
    }
}
