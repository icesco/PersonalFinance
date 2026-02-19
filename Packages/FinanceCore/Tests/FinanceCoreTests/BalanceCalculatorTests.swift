import Testing
import Foundation
@testable import FinanceCore

// MARK: - Test Helpers

private let contoA = UUID()
private let contoB = UUID()
private let contoC = UUID()

private func tx(
    _ amount: Decimal,
    _ type: TransactionType,
    _ date: Date,
    from: UUID? = nil,
    to: UUID? = nil
) -> TransactionSnapshot {
    TransactionSnapshot(
        amount: amount,
        type: type,
        date: date,
        fromContoId: from,
        toContoId: to
    )
}

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var components = DateComponents()
    components.year = y
    components.month = m
    components.day = d
    components.hour = 12
    return Calendar.current.date(from: components)!
}

private let defaultContiIDs: Set<UUID> = [contoA, contoB]

// MARK: - Group 1: netChange

@Suite("netChange")
struct NetChangeTests {

    @Test("Income to conto in set adds amount")
    func incomeToContoInSet() {
        let t = tx(500, .income, date(2025, 1, 15), to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 500)
    }

    @Test("Income to external conto returns 0")
    func incomeToExternalConto() {
        let t = tx(500, .income, date(2025, 1, 15), to: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Expense from conto in set subtracts amount")
    func expenseFromContoInSet() {
        let t = tx(200, .expense, date(2025, 1, 15), from: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == -200)
    }

    @Test("Expense from external conto returns 0")
    func expenseFromExternalConto() {
        let t = tx(200, .expense, date(2025, 1, 15), from: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Transfer out (from set to external) subtracts amount")
    func transferOut() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoA, to: contoC)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == -300)
    }

    @Test("Transfer in (from external to set) adds amount")
    func transferIn() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoC, to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 300)
    }

    @Test("Transfer internal (both in set) cancels out to 0")
    func transferInternal() {
        let t = tx(300, .transfer, date(2025, 1, 15), from: contoA, to: contoB)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Transfer external (neither in set) returns 0")
    func transferExternal() {
        let externalA = UUID()
        let externalB = UUID()
        let t = tx(300, .transfer, date(2025, 1, 15), from: externalA, to: externalB)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }

    @Test("Zero amount returns 0")
    func zeroAmount() {
        let t = tx(0, .income, date(2025, 1, 15), to: contoA)
        #expect(BalanceCalculator.netChange(for: t, contiIDs: defaultContiIDs) == 0)
    }
}

// MARK: - Group 2: totalBalance

@Suite("totalBalance")
struct TotalBalanceTests {

    @Test("Empty array returns 0")
    func emptyArray() {
        #expect(BalanceCalculator.totalBalance(contiBalances: []) == 0)
    }

    @Test("Single value")
    func singleValue() {
        #expect(BalanceCalculator.totalBalance(contiBalances: [1000]) == 1000)
    }

    @Test("Multiple values sum correctly")
    func multipleValues() {
        #expect(BalanceCalculator.totalBalance(contiBalances: [1000, 5000, -500]) == 5500)
    }

    @Test("All negative values")
    func allNegative() {
        #expect(BalanceCalculator.totalBalance(contiBalances: [-100, -200, -50]) == -350)
    }
}

// MARK: - Group 3: absoluteChange & percentageChange

@Suite("absoluteChange and percentageChange")
struct ChangeTests {

    @Test("Positive change")
    func positiveChange() {
        #expect(BalanceCalculator.absoluteChange(current: 1500, periodStart: 1000) == 500)
    }

    @Test("Negative change")
    func negativeChange() {
        #expect(BalanceCalculator.absoluteChange(current: 800, periodStart: 1000) == -200)
    }

    @Test("Zero change")
    func zeroChange() {
        #expect(BalanceCalculator.absoluteChange(current: 1000, periodStart: 1000) == 0)
    }

    @Test("Percentage positive")
    func percentagePositive() {
        let result = BalanceCalculator.percentageChange(current: 1100, periodStart: 1000)
        #expect(abs(result - 10.0) < 0.01)
    }

    @Test("Percentage from zero returns 0")
    func percentageFromZero() {
        #expect(BalanceCalculator.percentageChange(current: 100, periodStart: 0) == 0)
    }

    @Test("Percentage from negative uses abs start")
    func percentageFromNegative() {
        // -100 -> -50: change is +50, percentage is 50/100 = 50%
        let result = BalanceCalculator.percentageChange(current: -50, periodStart: -100)
        #expect(abs(result - 50.0) < 0.01)
    }

    @Test("Negative to positive change")
    func negativeToPositive() {
        // -500 -> 500: change is 1000, abs(-500) = 500, percentage is 200%
        let result = BalanceCalculator.percentageChange(current: 500, periodStart: -500)
        #expect(abs(result - 200.0) < 0.01)
    }

    @Test("Percentage negative change")
    func percentageNegative() {
        let result = BalanceCalculator.percentageChange(current: 900, periodStart: 1000)
        #expect(abs(result - (-10.0)) < 0.01)
    }
}

// MARK: - Group 4: chartYDomain

@Suite("chartYDomain")
struct ChartYDomainTests {

    @Test("No data returns 0...100")
    func noData() {
        let domain = BalanceCalculator.chartYDomain(dataPoints: [])
        #expect(domain == 0...100)
    }

    @Test("Single point gets ±50 range")
    func singlePoint() {
        let points = [BalanceDataPoint(date: date(2025, 1, 1), balance: 1000)]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        #expect(domain == 950...1050)
    }

    @Test("Range with 10% padding")
    func rangeWithPadding() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 2000)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 1000, padding 100. Lower: max(0, 1000-100) = 900, Upper: 2000+100 = 2100
        #expect(domain.lowerBound == 900)
        #expect(domain.upperBound == 2100)
    }

    @Test("Negative values")
    func negativeValues() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: -500),
            BalanceDataPoint(date: date(2025, 2, 1), balance: -100)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 400, padding 40. Lower: -500-40 = -540, Upper: -100+40 = -60
        #expect(domain.lowerBound == -540)
        #expect(domain.upperBound == -60)
    }

    @Test("Mixed positive and negative")
    func mixedValues() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: -200),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 800)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 1000, padding 100. Lower: -200-100 = -300 (negative, so no clamping), Upper: 800+100 = 900
        #expect(domain.lowerBound == -300)
        #expect(domain.upperBound == 900)
    }

    @Test("Positive lower bound clamped to 0")
    func positiveLowerBoundClampedToZero() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 50),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 150)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        // Range 100, padding 10. Lower: max(0, 50-10) = 40, Upper: 150+10 = 160
        #expect(domain.lowerBound == 40)
        #expect(domain.upperBound == 160)
    }

    @Test("Equal points get ±50 range")
    func equalPoints() {
        let points = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 500),
            BalanceDataPoint(date: date(2025, 2, 1), balance: 500)
        ]
        let domain = BalanceCalculator.chartYDomain(dataPoints: points)
        #expect(domain == 450...550)
    }
}

// MARK: - Group 5: periodStartBalance (BUG FIX TESTS)

@Suite("periodStartBalance")
struct PeriodStartBalanceTests {

    let periodStart = date(2025, 1, 1)
    let now = date(2025, 1, 31)

    @Test("No transactions returns current total")
    func noTransactions() {
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 5000, transactions: [], contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        #expect(result == 5000)
    }

    @Test("Solo income")
    func soloIncome() {
        let transactions = [tx(1000, .income, date(2025, 1, 15), to: contoA)]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 6000, transactions: transactions, contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        // 6000 - 1000 = 5000
        #expect(result == 5000)
    }

    @Test("Solo expense")
    func soloExpense() {
        let transactions = [tx(500, .expense, date(2025, 1, 10), from: contoA)]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 4500, transactions: transactions, contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        // 4500 - (-500) = 5000
        #expect(result == 5000)
    }

    @Test("Mixed income and expense")
    func mixedIncomeAndExpense() {
        let transactions = [
            tx(1000, .income, date(2025, 1, 5), to: contoA),
            tx(300, .expense, date(2025, 1, 10), from: contoA)
        ]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 5700, transactions: transactions, contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        // net = 1000 - 300 = 700; start = 5700 - 700 = 5000
        #expect(result == 5000)
    }

    @Test("Transfer out correctly subtracts (BUG FIX)")
    func transferOut() {
        let transactions = [tx(400, .transfer, date(2025, 1, 20), from: contoA, to: contoC)]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 4600, transactions: transactions, contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        // net = -400 (transfer out); start = 4600 - (-400) = 5000
        #expect(result == 5000)
    }

    @Test("Transfer in correctly adds (BUG FIX)")
    func transferIn() {
        let transactions = [tx(600, .transfer, date(2025, 1, 20), from: contoC, to: contoA)]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 5600, transactions: transactions, contiIDs: [contoA],
            periodStart: periodStart, now: now
        )
        // net = +600 (transfer in); start = 5600 - 600 = 5000
        #expect(result == 5000)
    }

    @Test("Internal transfer cancels out")
    func internalTransfer() {
        let transactions = [tx(200, .transfer, date(2025, 1, 20), from: contoA, to: contoB)]
        let result = BalanceCalculator.periodStartBalance(
            currentTotal: 5000, transactions: transactions, contiIDs: [contoA, contoB],
            periodStart: periodStart, now: now
        )
        // net = 0 (internal); start = 5000
        #expect(result == 5000)
    }
}

// MARK: - Group 6: monthlyTotals

@Suite("monthlyTotals")
struct MonthlyTotalsTests {

    let start = date(2025, 1, 1)
    let end = date(2025, 2, 1)

    @Test("No transactions returns zero")
    func noTransactions() {
        let (income, expenses) = BalanceCalculator.monthlyTotals(
            transactions: [], contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 0)
        #expect(expenses == 0)
    }

    @Test("Solo income")
    func soloIncome() {
        let transactions = [tx(3000, .income, date(2025, 1, 15), to: contoA)]
        let (income, expenses) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 3000)
        #expect(expenses == 0)
    }

    @Test("Solo expense")
    func soloExpense() {
        let transactions = [tx(500, .expense, date(2025, 1, 20), from: contoA)]
        let (income, expenses) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 0)
        #expect(expenses == 500)
    }

    @Test("Mixed income and expense")
    func mixed() {
        let transactions = [
            tx(3000, .income, date(2025, 1, 5), to: contoA),
            tx(500, .expense, date(2025, 1, 10), from: contoA),
            tx(200, .expense, date(2025, 1, 15), from: contoA)
        ]
        let (income, expenses) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 3000)
        #expect(expenses == 700)
    }

    @Test("Filters by contiIDs")
    func filtersByContiIDs() {
        let transactions = [
            tx(1000, .income, date(2025, 1, 5), to: contoA),
            tx(2000, .income, date(2025, 1, 10), to: contoC) // external
        ]
        let (income, _) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 1000) // Only contoA's income
    }

    @Test("Filters by date range")
    func filtersByDate() {
        let transactions = [
            tx(1000, .income, date(2025, 1, 15), to: contoA),
            tx(2000, .income, date(2025, 2, 15), to: contoA) // outside range
        ]
        let (income, _) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 1000)
    }

    @Test("Transfers are excluded from income/expenses")
    func transfersExcluded() {
        let transactions = [tx(500, .transfer, date(2025, 1, 15), from: contoA, to: contoC)]
        let (income, expenses) = BalanceCalculator.monthlyTotals(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(income == 0)
        #expect(expenses == 0)
    }
}

// MARK: - Group 7: balanceHistory

@Suite("balanceHistory")
struct BalanceHistoryTests {

    let calendar = Calendar.current

    @Test("No transactions returns single start point")
    func noTransactions() {
        let result = BalanceCalculator.balanceHistory(
            transactions: [],
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        #expect(result.count >= 1)
        #expect(result.first?.balance == 1000)
    }

    @Test("Single income adds to balance")
    func singleIncome() {
        let transactions = [tx(500, .income, date(2025, 1, 15), to: contoA)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        // Should have at least start point + transaction day point
        #expect(result.count >= 2)
        #expect(result.first?.balance == 1000)
        // Find the point after the income
        let afterIncome = result.filter { $0.date >= date(2025, 1, 15) }
        #expect(afterIncome.first?.balance == 1500)
    }

    @Test("Single expense subtracts from balance")
    func singleExpense() {
        let transactions = [tx(300, .expense, date(2025, 1, 10), from: contoA)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        let afterExpense = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 1, 10)) }
        #expect(afterExpense.first?.balance == 700)
    }

    @Test("Multiple transactions same day collapsed")
    func sameDayCollapsed() {
        let transactions = [
            tx(500, .income, date(2025, 1, 15), to: contoA),
            tx(200, .expense, date(2025, 1, 15), from: contoA)
        ]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        // Only one point for Jan 15 (net +300)
        let jan15Points = result.filter { calendar.isDate($0.date, inSameDayAs: date(2025, 1, 15)) }
        #expect(jan15Points.count == 1)
        #expect(jan15Points.first?.balance == 1300)
    }

    @Test("Internal transfer maintains balance")
    func internalTransfer() {
        let transactions = [tx(500, .transfer, date(2025, 1, 15), from: contoA, to: contoB)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA, contoB],
            initialBalance: 2000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        // Internal transfer nets to 0
        let jan15Points = result.filter { calendar.isDate($0.date, inSameDayAs: date(2025, 1, 15)) }
        #expect(jan15Points.first?.balance == 2000)
    }

    @Test("Transfer out reduces balance")
    func transferOut() {
        let transactions = [tx(300, .transfer, date(2025, 1, 15), from: contoA, to: contoC)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        let afterTransfer = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 1, 15)) }
        #expect(afterTransfer.first?.balance == 700)
    }

    @Test("Transfer in increases balance")
    func transferIn() {
        let transactions = [tx(300, .transfer, date(2025, 1, 15), from: contoC, to: contoA)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        let afterTransfer = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 1, 15)) }
        #expect(afterTransfer.first?.balance == 1300)
    }

    @Test("Pre-period transactions incorporated in initial balance")
    func prePeriodTransactions() {
        let transactions = [
            tx(500, .income, date(2024, 12, 15), to: contoA), // before period
            tx(200, .expense, date(2025, 1, 10), from: contoA) // in period
        ]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        // Initial: 1000 + 500 (pre-period income) = 1500
        #expect(result.first?.balance == 1500)
        // After expense: 1500 - 200 = 1300
        let afterExpense = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 1, 10)) }
        #expect(afterExpense.first?.balance == 1300)
    }

    @Test("Chronological order maintained")
    func chronologicalOrder() {
        let transactions = [
            tx(100, .income, date(2025, 1, 20), to: contoA),
            tx(200, .income, date(2025, 1, 5), to: contoA),
            tx(300, .income, date(2025, 1, 10), to: contoA)
        ]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        for i in 1..<result.count {
            #expect(result[i].date >= result[i - 1].date)
        }
    }

    @Test("Invalid range returns empty")
    func invalidRange() {
        let result = BalanceCalculator.balanceHistory(
            transactions: [],
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 2, 1),
            periodEnd: date(2025, 1, 1)
        )
        #expect(result.isEmpty)
    }

    @Test("Future transactions included in period")
    func futureTransactions() {
        let transactions = [tx(500, .income, date(2025, 1, 28), to: contoA)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        let lastBalance = result.last?.balance
        #expect(lastBalance == 1500)
    }

    @Test("Negative balances handled correctly")
    func negativeBalances() {
        let transactions = [tx(1500, .expense, date(2025, 1, 15), from: contoA)]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 1000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 1, 31)
        )
        let afterExpense = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 1, 15)) }
        #expect(afterExpense.first?.balance == -500)
    }

    @Test("3 month period with sparse transactions")
    func threeMonthPeriod() {
        let transactions = [
            tx(1000, .income, date(2025, 1, 15), to: contoA),
            tx(500, .expense, date(2025, 3, 10), from: contoA)
        ]
        let result = BalanceCalculator.balanceHistory(
            transactions: transactions,
            contiIDs: [contoA],
            initialBalance: 2000,
            periodStart: date(2025, 1, 1),
            periodEnd: date(2025, 3, 31)
        )
        // Should have points spanning the full period
        #expect(result.first?.date == date(2025, 1, 1))
        #expect(result.count >= 3)

        // Final balance: 2000 + 1000 - 500 = 2500
        let lastTxPoint = result.filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: date(2025, 3, 10)) }
        #expect(lastTxPoint.first?.balance == 2500)
    }
}

// MARK: - Group 8: splitBalanceHistory

@Suite("splitBalanceHistory")
struct SplitBalanceHistoryTests {

    let calendar = Calendar.current

    @Test("Everything in the past")
    func allPast() {
        let pastDate = date(2024, 6, 15)
        let today = date(2025, 1, 15)
        let history = [
            BalanceDataPoint(date: date(2024, 6, 1), balance: 1000),
            BalanceDataPoint(date: pastDate, balance: 1200)
        ]
        let (past, future) = BalanceCalculator.splitBalanceHistory(
            history: history, today: today, period: .oneMonth,
            selectedMonth: date(2024, 6, 1)
        )
        #expect(past.count == 2)
        // Month end (June 30, 2024) is before today (Jan 15, 2025), so no future points
        #expect(future.isEmpty)
    }

    @Test("With future data in 1M mode")
    func withFuture1M() {
        let today = date(2025, 1, 15)
        let history = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 1, 10), balance: 1200),
            BalanceDataPoint(date: date(2025, 1, 20), balance: 1500)
        ]
        let (past, future) = BalanceCalculator.splitBalanceHistory(
            history: history, today: today, period: .oneMonth,
            selectedMonth: date(2025, 1, 1)
        )
        #expect(!past.isEmpty)
        #expect(!future.isEmpty)
        // Future should start with today's balance connection point
        #expect(future.first?.balance == past.last?.balance)
    }

    @Test("Non-1M period returns empty future")
    func non1MEmptyFuture() {
        let today = date(2025, 1, 15)
        let history = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 1, 20), balance: 1500)
        ]
        let (_, future) = BalanceCalculator.splitBalanceHistory(
            history: history, today: today, period: .threeMonths,
            selectedMonth: date(2025, 1, 1)
        )
        #expect(future.isEmpty)
    }

    @Test("Future connects to last past point")
    func futureConnectsToLastPast() {
        let today = date(2025, 1, 15)
        let history = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 1, 10), balance: 1200),
            BalanceDataPoint(date: date(2025, 1, 25), balance: 1800)
        ]
        let (past, future) = BalanceCalculator.splitBalanceHistory(
            history: history, today: today, period: .oneMonth,
            selectedMonth: date(2025, 1, 1)
        )
        // Future first point should have past's last balance
        if let lastPast = past.last, let firstFuture = future.first {
            #expect(firstFuture.balance == lastPast.balance)
        }
    }

    @Test("No future transactions creates flat projection")
    func flatProjection() {
        let today = date(2025, 1, 15)
        let history = [
            BalanceDataPoint(date: date(2025, 1, 1), balance: 1000),
            BalanceDataPoint(date: date(2025, 1, 10), balance: 1200)
        ]
        let (_, future) = BalanceCalculator.splitBalanceHistory(
            history: history, today: today, period: .oneMonth,
            selectedMonth: date(2025, 1, 1)
        )
        // Should have connection point + end of month projection, both at 1200
        #expect(future.count >= 2)
        #expect(future.first?.balance == 1200)
        #expect(future.last?.balance == 1200)
    }
}

// MARK: - Group 9: contiChanges

@Suite("contiChanges")
struct ContiChangesTests {

    let start = date(2025, 1, 1)
    let end = date(2025, 2, 1)

    @Test("No transactions returns zeros")
    func noTransactions() {
        let result = BalanceCalculator.contiChanges(
            transactions: [], contiIDs: [contoA, contoB], start: start, end: end
        )
        #expect(result[contoA] == 0)
        #expect(result[contoB] == 0)
    }

    @Test("Income adds to conto")
    func incomeAdds() {
        let transactions = [tx(1000, .income, date(2025, 1, 15), to: contoA)]
        let result = BalanceCalculator.contiChanges(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(result[contoA] == 1000)
    }

    @Test("Expense subtracts from conto")
    func expenseSubtracts() {
        let transactions = [tx(300, .expense, date(2025, 1, 15), from: contoA)]
        let result = BalanceCalculator.contiChanges(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(result[contoA] == -300)
    }

    @Test("Transfer A to B affects both conti")
    func transferAffectsBoth() {
        let transactions = [tx(500, .transfer, date(2025, 1, 15), from: contoA, to: contoB)]
        let result = BalanceCalculator.contiChanges(
            transactions: transactions, contiIDs: [contoA, contoB], start: start, end: end
        )
        #expect(result[contoA] == -500)
        #expect(result[contoB] == 500)
    }

    @Test("Multiple transactions accumulate")
    func multipleTransactions() {
        let transactions = [
            tx(3000, .income, date(2025, 1, 5), to: contoA),
            tx(500, .expense, date(2025, 1, 10), from: contoA),
            tx(200, .expense, date(2025, 1, 20), from: contoA)
        ]
        let result = BalanceCalculator.contiChanges(
            transactions: transactions, contiIDs: [contoA], start: start, end: end
        )
        #expect(result[contoA] == 2300) // 3000 - 500 - 200
    }
}

// MARK: - Group 10: formatCompactCurrency

@Suite("formatCompactCurrency")
struct FormatCompactCurrencyTests {

    @Test("Millions format")
    func millions() {
        #expect(BalanceCalculator.formatCompactCurrency(1_500_000) == "1.5M €")
    }

    @Test("Thousands format")
    func thousands() {
        #expect(BalanceCalculator.formatCompactCurrency(5000) == "5K €")
    }

    @Test("Small values format")
    func smallValues() {
        #expect(BalanceCalculator.formatCompactCurrency(42) == "42 €")
    }

    @Test("Negative millions")
    func negativeMillions() {
        #expect(BalanceCalculator.formatCompactCurrency(-2_500_000) == "-2.5M €")
    }

    @Test("Zero")
    func zero() {
        #expect(BalanceCalculator.formatCompactCurrency(0) == "0 €")
    }
}
