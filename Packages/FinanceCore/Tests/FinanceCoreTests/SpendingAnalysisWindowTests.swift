import Foundation
import Testing
@testable import FinanceCore

struct SpendingAnalysisWindowTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Rome")!
        result.firstWeekday = 2
        result.minimumDaysInFirstWeek = 4
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func customDatesAreInclusiveAndPreviousDaysSurviveDST() throws {
        let range = try #require(SpendingAnalysisWindow(start: date(2026, 3, 28, 8), endInclusive: date(2026, 3, 30, 18), now: date(2026, 4, 1), calendar: calendar))
        #expect(range.interval.start == date(2026, 3, 28))
        #expect(range.interval.end == date(2026, 3, 31))
        #expect(range.previous.start == date(2026, 3, 25))
        #expect(range.previous.end == date(2026, 3, 28))
        #expect(range.interval.duration != range.previous.duration)
    }

    @Test func customCurrentRangeComparesElapsedLocalTimeAndRejectsReversedDates() throws {
        let range = try #require(SpendingAnalysisWindow(start: date(2026, 3, 28), endInclusive: date(2026, 3, 30), now: date(2026, 3, 29, 12), calendar: calendar))
        #expect(range.previous.end == date(2026, 3, 26, 12))
        let single = try #require(SpendingAnalysisWindow(start: date(2026, 10, 5), endInclusive: date(2026, 10, 5), now: date(2026, 10, 6), calendar: calendar))
        #expect(single.interval.end == date(2026, 10, 6))
        #expect(single.previous.start == date(2026, 10, 4))
        #expect(single.previous.end == date(2026, 10, 5))
        #expect(SpendingAnalysisWindow(start: date(2026, 10, 6), endInclusive: date(2026, 10, 5), calendar: calendar) == nil)
    }

    @Test func weeklyComparisonKeepsWallClockAcrossDaylightSaving() {
        let now = date(2026, 3, 29, 12)
        let result = SpendingAnalysisWindow(period: .week, anchor: now, now: now, calendar: calendar)
        #expect(result.interval.start == date(2026, 3, 23))
        #expect(result.interval.end == date(2026, 3, 30))
        #expect(result.previous.start == date(2026, 3, 16))
        #expect(result.previous.end == date(2026, 3, 22, 12))
    }

    @Test func quarterNavigationAndElapsedComparisonUseCalendarMonths() {
        let now = date(2026, 5, 5, 10)
        let result = SpendingAnalysisWindow(period: .quarter, anchor: now, now: now, calendar: calendar)
        #expect(result.interval.start == date(2026, 4, 1))
        #expect(result.interval.end == date(2026, 7, 1))
        #expect(result.previous.start == date(2026, 1, 1))
        #expect(result.previous.end == date(2026, 2, 5, 10))
        #expect(SpendingAnalysisPeriod.quarter.moving(result.interval.start, by: -1, calendar: calendar) == date(2026, 1, 1))
    }

    @Test func fullPastPeriodsAndShorterPreviousMonthsAreBounded() {
        let march = SpendingAnalysisWindow(period: .month, anchor: date(2026, 3, 31), now: date(2026, 3, 31, 12), calendar: calendar)
        #expect(march.previous.start == date(2026, 2, 1))
        #expect(march.previous.end == date(2026, 3, 1))
        let past = SpendingAnalysisWindow(period: .year, anchor: date(2024, 9, 1), now: date(2026, 1, 1), calendar: calendar)
        #expect(past.previous.start == date(2023, 1, 1))
        #expect(past.previous.end == date(2024, 1, 1))
        let future = SpendingAnalysisWindow(period: .week, anchor: date(2027, 1, 5), now: date(2026, 1, 1), calendar: calendar)
        #expect(future.previous.duration == 0)
    }
}
