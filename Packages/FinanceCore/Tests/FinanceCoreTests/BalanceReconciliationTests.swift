import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct BalanceReconciliationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture(recent: Bool = true) throws -> (ModelContainer, UUID) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Demo", currency: "EUR")
        let conto = Conto(name: "Conto", type: .checking, initialBalance: 100)
        conto.account = book; book.conti = [conto]
        container.mainContext.insert(book)
        let income = Transaction(amount: 20, type: .income, date: now.addingTimeInterval(recent ? -86_400 : -10 * 86_400))
        income.setToConto(conto)
        let future = Transaction(amount: 50, type: .expense, date: now.addingTimeInterval(86_400))
        future.setFromConto(conto)
        container.mainContext.insert(income); container.mainContext.insert(future)
        try container.mainContext.save()
        return (container, conto.id)
    }
    @Test func alignsTodayWithoutCompensatingFutureExpenseOrAddingTransactions() throws {
        let (container, id) = try fixture()
        try BalanceReconciliation.apply(contoID: id, enteredBalance: "200,00", container: container, now: now)
        let context = ModelContext(container)
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first)
        #expect(conto.initialBalance == 180)
        #expect(BalanceReconciliation.status(for: conto, now: now).balance == 200)
        #expect(BalanceReconciliation.status(for: conto, now: now.addingTimeInterval(2 * 86_400)).balance == 150)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }
    @Test func futureMovementDoesNotMakeAnOldLedgerRecent() throws {
        let (container, id) = try fixture(recent: false)
        #expect(throws: BalanceReconciliation.Failure.staleMovements) {
            try BalanceReconciliation.apply(contoID: id, enteredBalance: "200", container: container, now: now)
        }
        let conto = try #require(ModelContext(container).fetch(FetchDescriptor<Conto>()).first)
        #expect(conto.initialBalance == 100)
        #expect(!BalanceReconciliation.status(for: conto, now: now).canReconcile)
    }
    @Test func invalidInputNeverChangesOpeningBalanceAndNegativeBalancesAreSupported() throws {
        let (container, id) = try fixture()
        for invalid in ["12abc", "", "1.234,56", "1,234"] {
            #expect(throws: BalanceReconciliation.Failure.invalidAmount) {
                try BalanceReconciliation.apply(contoID: id, enteredBalance: invalid, container: container, now: now)
            }
        }
        #expect(try ModelContext(container).fetch(FetchDescriptor<Conto>()).first?.initialBalance == 100)
        try BalanceReconciliation.apply(contoID: id, enteredBalance: "-25,50", container: container, now: now)
        let conto = try #require(ModelContext(container).fetch(FetchDescriptor<Conto>()).first)
        #expect(BalanceReconciliation.status(for: conto, now: now).balance == Decimal(string: "-25.50"))
    }
}
