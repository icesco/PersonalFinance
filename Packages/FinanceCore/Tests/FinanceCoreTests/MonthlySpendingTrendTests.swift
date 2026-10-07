import Foundation
import Testing
@testable import FinanceCore

struct MonthlySpendingTrendTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }
    private func expense(_ date: Date, _ amount: Decimal, type: TransactionType = .expense, valid: Bool = true) -> DirectionTransaction {
        .init(date: date, amount: amount, type: type, categoryID: nil, categoryName: "Casa", isRecurring: false, hasValidAmount: valid)
    }

    @Test func sameLocalClockAcrossDSTAndFutureExclusion() {
        let now = date(10, 27, 12)
        let report = MonthlySpendingTrend.calculate(transactions: [
            expense(date(10, 1), 10), expense(now, 5), expense(date(10, 27, 13), 100),
            expense(date(9, 27, 11), 20), expense(date(9, 27, 12), 300), expense(date(9, 27, 13), 200),
            expense(date(10, 2), 1000, type: .transfer), expense(date(10, 2), 1000, type: .income)
        ], anchor: now, now: now, calendar: calendar)
        #expect(report.current.count == 27)
        #expect(report.current.last?.amount == 15)
        #expect(report.previous.last?.amount == 20)
        #expect(report.daysInMonth == 31)
    }

    @Test func shorterPreviousMonthStopsWithoutInventingDays() {
        let now = date(3, 31, 12)
        let report = MonthlySpendingTrend.calculate(transactions: [expense(date(2, 28, 23), 30)],
            anchor: now, now: now, calendar: calendar)
        #expect(report.current.count == 31)
        #expect(report.previous.count == 28)
        #expect(report.previous.last?.amount == 30)
    }

    @Test func completedMonthUsesWholePreviousMonthAndHalfOpenBoundary() {
        let report = MonthlySpendingTrend.calculate(transactions: [
            expense(date(3, 31, 23), 10), expense(date(4, 1), 100), expense(date(2, 28, 23), 20)
        ], anchor: date(3, 1), now: date(5, 1), calendar: calendar)
        #expect(report.current.last?.amount == 10)
        #expect(report.previous.last?.amount == 20)
        #expect(!report.isInProgress)
    }

    @Test func completedShortMonthIncludesPreviousMonthsLastDay() {
        let report = MonthlySpendingTrend.calculate(transactions: [expense(date(3, 31, 23), 40)],
            anchor: date(4, 1), now: date(5, 1), calendar: calendar)
        #expect(report.current.count == 30)
        #expect(report.previous.count == 31)
        #expect(report.previous.last?.amount == 40)
    }

    @Test func futureAndInvalidDataDoNotBecomePositiveInsights() {
        let future = MonthlySpendingTrend.calculate(transactions: [], anchor: date(11, 1), now: date(10, 7), calendar: calendar)
        #expect(future.current.isEmpty)
        #expect(!future.hasPreviousExpenses)
        let invalid = MonthlySpendingTrend.calculate(transactions: [expense(date(10, 1), 10, valid: false)],
            anchor: date(10, 1), now: date(10, 7), calendar: calendar)
        #expect(invalid.hasInvalidAmounts)
    }
}
