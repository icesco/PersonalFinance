import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct BudgetOutlookTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func fixture() -> (Budget, Conto, FinanceCore.Category) {
        let book = Account(name: "Book")
        let conto = Conto(name: "Conto", type: .checking)
        conto.account = book; book.conti = [conto]
        let category = Category(name: "Food")
        category.account = book
        let budget = Budget(name: "Budget", amount: 1000, period: .monthly)
        budget.account = book; budget.categories = [category]
        return (budget, conto, category)
    }
    private func entry(_ amount: Decimal, on date: Date, conto: Conto, category: FinanceCore.Category,
                       recurring: Bool = false, occurrence: Bool = false) -> Transaction {
        let value = Transaction(amount: amount, type: .expense, date: date, isRecurring: recurring)
        value.setCategory(category); value.setFromConto(conto)
        if occurrence { value.recurrenceSourceID = UUID() }
        return value
    }

    @Test func futureEntriesSetAFloorWithoutBeingExtrapolated() {
        let (budget, conto, category) = fixture()
        let future = entry(400, on: date(25), conto: conto, category: category)
        let report = BudgetOutlook.calculate(for: budget, transactions: [future], now: date(11), calendar: calendar)
        #expect(report.projectedTotal == 400)
        #expect(report.daysRemaining == 21)
        #expect(report.dailyAllowance == Decimal(600) / 21)
    }

    @Test func variablePaceDoesNotMultiplyRecurringTemplatesOrRecordedOccurrences() {
        let (budget, conto, category) = fixture()
        let variable = entry(100, on: date(5), conto: conto, category: category)
        let fixed = entry(200, on: date(2), conto: conto, category: category, recurring: true)
        let occurrence = entry(50, on: date(3), conto: conto, category: category, occurrence: true)
        let future = entry(60, on: date(28), conto: conto, category: category)
        let report = BudgetOutlook.calculate(for: budget, transactions: [variable, fixed, occurrence, future],
                                             now: date(11), calendar: calendar)
        #expect(report.projectedTotal == 560) // 100 / 10 * 31 + 200 + 50
        #expect(report.dailyAllowance == Decimal(590) / 21)
    }

    @Test func firstDayHasNoRateAndDoesNotClaimZeroForecast() {
        let (budget, conto, category) = fixture()
        let today = entry(100, on: date(1, hour: 8), conto: conto, category: category)
        let report = BudgetOutlook.calculate(for: budget, transactions: [today], now: date(1), calendar: calendar)
        #expect(report.projectedTotal == nil)
        #expect(report.daysRemaining == 31)
        #expect(report.dailyAllowance == Decimal(900) / 31)
    }

    @Test func finalDayAndDaylightSavingUseCalendarDaysAndNeverSuggestNegativeSpending() {
        let (budget, conto, category) = fixture()
        let excess = entry(1200, on: date(1), conto: conto, category: category)
        let last = BudgetOutlook.calculate(for: budget, transactions: [excess], now: date(31, hour: 23), calendar: calendar)
        #expect(last.daysRemaining == 1)
        #expect(last.dailyAllowance == 0)
        let autumn = BudgetOutlook.calculate(for: budget, transactions: [], now: date(25), calendar: calendar)
        #expect(autumn.daysRemaining == 7)
        let spring = BudgetOutlook.calculate(for: budget, transactions: [], now: date(29, month: 3), calendar: calendar)
        #expect(spring.daysRemaining == 3)
    }
}
