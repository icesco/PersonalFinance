import Foundation
import Testing
@testable import FinanceCore

struct RecordedSavingsReportTests {
    private func entry(_ time: TimeInterval, _ amount: Decimal, _ type: TransactionType,
                       recurring: Bool = false, valid: Bool = true) -> DirectionTransaction {
        .init(date: Date(timeIntervalSince1970: time), amount: amount, type: type,
              categoryID: nil, categoryName: "", isRecurring: recurring, hasValidAmount: valid)
    }

    private func report(_ entries: [DirectionTransaction], now: TimeInterval = 30) -> RecordedSavingsReport {
        .calculate(transactions: entries,
                   interval: DateInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 30)),
                   now: Date(timeIntervalSince1970: now))
    }

    @Test func recordsOnlyWithinHalfOpenPeriodAndUntilNow() {
        let value = report([entry(9, 900, .income), entry(10, 2000, .income),
                            entry(11, 1500, .expense, recurring: true), entry(15, 500, .transfer),
                            entry(21, 800, .income), entry(30, 500, .expense)], now: 20)
        #expect(value.income == 2000)
        #expect(value.expenses == 1500)
        #expect(value.remainder == 500)
        #expect(value.savingsRate == Decimal(string: "0.25"))
    }

    @Test func noIncomeIsUnavailableEvenWithExpensesOrTransfers() {
        #expect(report([]).savingsRate == nil)
        #expect(report([entry(10, 400, .expense), entry(11, 2000, .transfer)]).savingsRate == nil)
        #expect(RecordedSavingsReport.rate(income: -1, expenses: 50) == nil)
    }

    @Test func zeroNegativeAndFullSavingsRemainDistinct() {
        #expect(RecordedSavingsReport.rate(income: 2000, expenses: 2000) == 0)
        #expect(RecordedSavingsReport.rate(income: 2000, expenses: 2500) == Decimal(string: "-0.25"))
        #expect(RecordedSavingsReport.rate(income: 2000, expenses: 0) == 1)
    }

    @Test func aggregationUsesTotalsNotMeanOfRates() {
        let value = report([entry(10, 1000, .income), entry(11, 1000, .expense),
                            entry(20, 3000, .income), entry(21, 1500, .expense)])
        #expect(value.savingsRate == Decimal(string: "0.375"))
    }

    @Test func signedExpenseCorrectionsReduceSpendingWithoutAddingIncome() {
        let value = report([entry(10, 2000, .income), entry(11, 1500, .expense), entry(12, -100, .expense)])
        #expect(value.income == 2000)
        #expect(value.expenses == 1400)
        #expect(value.savingsRate == Decimal(string: "0.3"))
    }

    @Test func invalidRecordedAmountsSuppressRateButUnrelatedEntriesDoNot() {
        #expect(report([entry(10, 2000, .income), entry(11, 0, .expense, valid: false)]).hasInvalidAmounts)
        #expect(report([entry(10, 2000, .income), entry(11, .nan, .expense)]).savingsRate == nil)
        let value = report([entry(10, 2000, .income), entry(11, .nan, .transfer), entry(21, .nan, .expense)], now: 20)
        #expect(!value.hasInvalidAmounts)
        #expect(value.savingsRate == 1)
    }

    @Test func legacyStatisticsUsePercentageAndUnavailableState() {
        func statistics(_ income: Decimal, _ expenses: Decimal) -> AccountStatisticsResult {
            .init(accountId: UUID(), period: .allTime, totalBalance: 9000,
                  totalIncome: income, totalExpenses: expenses, transactionCount: 0,
                  incomeTransactionCount: 0, expenseTransactionCount: 0, transferTransactionCount: 0)
        }
        #expect(statistics(2000, 1500).savingsRate == 25)
        #expect(statistics(2000, 2500).savingsRate == -25)
        #expect(statistics(0, 400).savingsRate == nil)
    }

    @MainActor @Test func scopedInputsDeduplicateAndPreserveMissingAmounts() {
        let cash = Conto(name: "Banca", type: .checking)
        let other = Conto(name: "Altro libro", type: .checking)
        let income = Transaction(amount: 2000, type: .income, date: Date(timeIntervalSince1970: 10))
        income.setToConto(cash)
        let expense = Transaction(amount: 1500, type: .expense, date: Date(timeIntervalSince1970: 11))
        expense.setFromConto(cash)
        let unrelated = Transaction(amount: 900, type: .expense, date: Date(timeIntervalSince1970: 11))
        unrelated.setFromConto(other)
        let now = Date(timeIntervalSince1970: 20)
        func inputs() -> SpendingDirectionInputs {
            .build(conti: [cash], transactions: [income, expense, expense, unrelated],
                   resolutions: [], now: now, horizon: Date(timeIntervalSince1970: 30))
        }
        #expect(report(inputs().transactions).savingsRate == Decimal(string: "0.25"))
        expense.amount = nil
        #expect(report(inputs().transactions).savingsRate == nil)
        #expect(report(inputs().transactions).hasInvalidAmounts)
    }
}
