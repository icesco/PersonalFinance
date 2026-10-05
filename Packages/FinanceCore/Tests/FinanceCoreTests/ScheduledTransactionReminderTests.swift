import Foundation
import Testing
@testable import FinanceCore

struct ScheduledTransactionReminderTests {
    @Test func futureEntriesAreBoundedAndDoNotDuplicateResolvedRecurrences() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(86_400)
        let book = Account(name: "Prova")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = book
        func expense(_ date: Date) -> Transaction {
            let value = Transaction(amount: 10, type: .expense, date: date)
            value.setFromConto(conto)
            return value
        }
        let single = expense(future)
        let generated = expense(future)
        generated.recurrenceSourceID = UUID()
        let startingSeries = expense(future)
        startingSeries.isRecurring = true
        let dates = ScheduledTransactionReminders.dates(
            transactions: [single, single, generated, startingSeries, expense(now), expense(future.addingTimeInterval(1))],
            now: now, through: future)
        #expect(dates == [future, future])
    }

    @Test func inactiveBooksOrAccountsAndMissingOwnershipAreExcluded() {
        let now = Date()
        let date = now.addingTimeInterval(86_400)
        let book = Account(name: "Prova")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = book
        let income = Transaction(amount: 100, type: .income, date: date)
        income.setToConto(conto)
        #expect(ScheduledTransactionReminders.dates(transactions: [income], now: now, through: date) == [date])
        conto.isActive = false
        #expect(ScheduledTransactionReminders.dates(transactions: [income], now: now, through: date).isEmpty)
        conto.isActive = true
        book.isActive = false
        #expect(ScheduledTransactionReminders.dates(transactions: [income], now: now, through: date).isEmpty)
        book.isActive = true
        income.setToConto(nil)
        #expect(ScheduledTransactionReminders.dates(transactions: [income], now: now, through: date).isEmpty)
    }
}
