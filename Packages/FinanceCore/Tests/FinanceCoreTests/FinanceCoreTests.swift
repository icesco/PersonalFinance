import Testing
import Foundation
import SwiftData
@testable import FinanceCore

struct FinanceCoreTests {
    
    @Test func accountCreation() async throws {
        let account = Account(name: "Test Account", currency: "EUR")
        #expect(account.name == "Test Account")
        #expect(account.currency == "EUR")
        #expect(account.isActive == true)
        #expect(account.totalBalance == 0)
    }
    
    @Test func contoCreation() async throws {
        let conto = Conto(name: "Test Conto", type: .checking, initialBalance: 1000)
        #expect(conto.name == "Test Conto")
        #expect(conto.type == .checking)
        #expect(conto.initialBalance == 1000)
        #expect(conto.balance == 1000)
    }
    
    @Test func transactionCreation() async throws {
        let transaction = Transaction(
            amount: 100,
            type: .expense,
            transactionDescription: "Test expense"
        )
        #expect(transaction.amount == 100)
        #expect(transaction.type == .expense)
        #expect(transaction.displayAmount == -100)
        #expect(transaction.transactionDescription == "Test expense")
    }
    
    @Test func categoryCreation() async throws {
        let category = Category(name: "Food", type: .expense, color: "#FF0000")
        #expect(category.name == "Food")
        #expect(category.type == .expense)
        #expect(category.color == "#FF0000")
        #expect(category.isSubcategory == false)
    }
    
    @Test func budgetCreation() async throws {
        let budget = Budget(
            name: "Monthly Food Budget",
            amount: 500,
            period: .monthly,
            alertThreshold: 0.8
        )
        #expect(budget.name == "Monthly Food Budget")
        #expect(budget.amount == 500)
        #expect(budget.period == .monthly)
        #expect(budget.alertThreshold == 0.8)
        #expect(budget.currentSpent == 0)
        #expect(budget.remainingAmount == 500)
        #expect(budget.categories.isEmpty)
        #expect(budget.includeRecurringTransactions == true)
        
        // Test dynamic period calculation
        let (start, end) = budget.currentPeriodRange
        #expect(start <= Date())
        #expect(end >= Date())
    }
    
    @Test func recurringTransactionCreation() async throws {
        let transaction = Transaction(
            amount: 1200,
            type: .income,
            transactionDescription: "Monthly salary",
            isRecurring: true,
            recurrenceFrequency: .monthly
        )
        #expect(transaction.amount == 1200)
        #expect(transaction.isRecurring == true)
        #expect(transaction.recurrenceFrequency == .monthly)
        #expect(transaction.isRecurrenceActive() == true)
        #expect(transaction.nextRecurrenceDate() != nil)
    }
    
    @Test func recurrenceFrequencyDisplayNames() async throws {
        #expect(RecurrenceFrequency.daily.displayName == "Giornaliera")
        #expect(RecurrenceFrequency.weekly.displayName == "Settimanale")
        #expect(RecurrenceFrequency.monthly.displayName == "Mensile")
        #expect(RecurrenceFrequency.yearly.displayName == "Annuale")
    }
    
    @Test func transferCreation() async throws {
        let fromConto = Conto(name: "Checking", type: .checking, initialBalance: 1000)
        let toConto = Conto(name: "Savings", type: .savings, initialBalance: 500)
        
        let (outgoing, incoming) = Transaction.createTransfer(
            amount: 200,
            fromConto: fromConto,
            toConto: toConto,
            transactionDescription: "Transfer to savings"
        )
        
        #expect(outgoing.amount == 200)
        #expect(incoming.amount == 200)
        #expect(outgoing.type == .transfer)
        #expect(incoming.type == .transfer)
        #expect(outgoing.fromConto === fromConto)
        #expect(incoming.toConto === toConto)
        #expect(outgoing.transferLinks.count == 1)
        #expect(incoming.transferLinks.count == 1)
    }
}