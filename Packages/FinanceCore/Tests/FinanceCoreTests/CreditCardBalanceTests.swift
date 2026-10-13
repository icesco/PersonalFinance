import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct CreditCardBalanceTests {
    private func card(balance: Decimal, limit: Decimal? = 7500) -> Conto {
        Conto(name: "Blu", type: .credit, initialBalance: balance, creditLimit: limit)
    }

    @Test func postedAndPendingChargesConsumeCreditExactlyOnce() {
        let conto = card(balance: Decimal(string: "-349.61")!)
        let pending = Transaction(amount: Decimal(string: "17.13")!, type: .expense, date: .now.addingTimeInterval(-60))
        conto.outgoingTransactions = [pending]
        #expect(conto.balance == Decimal(string: "-366.74"))
        #expect(conto.creditOutstandingBalance == Decimal(string: "366.74"))
        #expect(conto.creditLimitRemaining == Decimal(string: "7133.26"))
        #expect(conto.displayBalance == Decimal(string: "7133.26"))
    }

    @Test func paymentsAndRefundsRestoreCreditWithoutResettingAtStatementClose() {
        let conto = card(balance: -1000)
        let previousCycleExpense = Transaction(amount: 150, type: .expense, date: .now.addingTimeInterval(-60 * 86400))
        let payment = Transaction(amount: 600, type: .transfer, date: .now.addingTimeInterval(-60))
        let refund = Transaction(amount: 50, type: .income, date: .now.addingTimeInterval(-60))
        conto.outgoingTransactions = [previousCycleExpense]
        conto.incomingTransactions = [payment, refund]
        conto.statementClosingDay = 1
        #expect(conto.balance == -500 && conto.creditOutstandingBalance == 500)
        #expect(conto.creditLimitRemaining == 7000)
        conto.statementClosingDay = 28
        #expect(conto.creditLimitRemaining == 7000)
        #expect(abs((conto.creditLimitUsageRatio ?? 0) - 500.0 / 7500) < 0.000001)
    }

    @Test func futureExpensesDoNotConsumeCredit() {
        let conto = card(balance: -100)
        conto.outgoingTransactions = [Transaction(amount: 500, type: .expense, date: .now.addingTimeInterval(86400))]
        #expect(conto.creditLimitRemaining == 7400 && conto.creditOutstandingBalance == 100)
    }

    @Test func overLimitAndPositiveCreditBalanceAreExplicit() {
        let overdrawn = card(balance: -8000)
        #expect(overdrawn.creditLimitRemaining == 0 && overdrawn.creditOutstandingBalance == 8000)
        #expect((overdrawn.creditLimitUsageRatio ?? 0) > 1)
        let prepaid = card(balance: 100)
        #expect(prepaid.creditLimitRemaining == 7600 && prepaid.creditOutstandingBalance == 0)
        #expect(prepaid.creditLimitUsageRatio == 0)
    }

    @Test func missingLimitDoesNotInventAvailabilityOrChangeBankBalances() {
        let noLimit = card(balance: -75, limit: nil)
        #expect(noLimit.creditLimitRemaining == nil && noLimit.displayBalance == 75)
        let invalidLimit = card(balance: -75, limit: 0)
        #expect(invalidLimit.creditLimitRemaining == nil)
        let checking = Conto(name: "Banca", type: .checking, initialBalance: -75, creditLimit: 1000)
        #expect(checking.displayBalance == -75 && checking.creditLimitRemaining == nil)
    }
}
