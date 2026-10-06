import Foundation
import Testing
@testable import Personal_Finance

@MainActor
struct TransactionSearchTests {
    @Test func matchesWordsAcrossDescriptionNotesCategoryAndAccount() {
        let fields: [String?] = ["Caffè", "Con Anna", "Bar", "Conto corrente", nil]
        #expect(TransactionSearch.matches(query: "  CAFFE   anna corrente ", fields: fields, amount: 12.5))
        #expect(!TransactionSearch.matches(query: "caffe marco", fields: fields, amount: 12.5))
    }

    @Test func amountSupportsCommaAndPoint() {
        #expect(TransactionSearch.matches(query: "12,50", fields: [], amount: 12.5))
        #expect(TransactionSearch.matches(query: "12.50", fields: [], amount: 12.5))
        #expect(!TransactionSearch.matches(query: "19,5", fields: [], amount: 12.5))
    }

    @Test func emptyWhitespaceDoesNotExcludeTransactions() {
        #expect(TransactionSearch.matches(query: " \n ", fields: [nil], amount: 0))
    }
}

struct TransactionSearchPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func allHasNoBound() {
        #expect(TransactionSearchPeriod.all.interval(now: date(2026, 10, 6), calendar: calendar) == nil)
    }

    @Test func rollingWindowsIncludeTodayAndStopAtTomorrow() throws {
        let now = date(2026, 10, 6)
        let range = try #require(TransactionSearchPeriod.last30Days.interval(now: now, calendar: calendar))
        #expect(range.end == date(2026, 10, 7, hour: 0))
        #expect(range.start == date(2026, 9, 7, hour: 0))
        let quarter = try #require(TransactionSearchPeriod.last3Months.interval(now: now, calendar: calendar))
        #expect(quarter.start == date(2026, 7, 7, hour: 0))
    }

    @Test func calendarYears() throws {
        let now = date(2026, 10, 6)
        let thisYear = try #require(TransactionSearchPeriod.thisYear.interval(now: now, calendar: calendar))
        #expect(thisYear.start == date(2026, 1, 1, hour: 0))
        #expect(thisYear.end == date(2027, 1, 1, hour: 0))
        let lastYear = try #require(TransactionSearchPeriod.lastYear.interval(now: now, calendar: calendar))
        #expect(lastYear.start == date(2025, 1, 1, hour: 0))
        #expect(lastYear.end == date(2026, 1, 1, hour: 0))
    }
}
