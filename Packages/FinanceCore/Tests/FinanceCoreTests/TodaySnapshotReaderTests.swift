import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct TodaySnapshotReaderTests {
    @Test func scopedReaderKeepsOldBalancesAndSeesCommittedUpdates() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Euro")
        let other = Account(name: "Dollari", currency: "USD")
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 1_000)
        let foreign = Conto(name: "Estero", type: .checking, initialBalance: 0)
        cash.account = book
        foreign.account = other
        context.insert(book)
        context.insert(other)
        context.insert(cash)
        context.insert(foreign)
        let now = Date()
        let old = Transaction(amount: 50, type: .expense,
                              date: Calendar.current.date(byAdding: .year, value: -2, to: now)!)
        old.setFromConto(cash)
        let transfer = Transaction(amount: 100, type: .transfer, date: now.addingTimeInterval(-60))
        transfer.setFromConto(foreign)
        transfer.setToConto(cash)
        transfer.destinationAmount = 90
        let unrelated = Transaction(amount: 700, type: .expense, date: now)
        unrelated.setFromConto(foreign)
        for transaction in [old, transfer, unrelated] { context.insert(transaction) }
        try context.save()
        let reader = TodaySnapshotReader()
        let first = try await reader.load(container: container, accountID: book.id, showAllAccounts: false, now: now)
        #expect(first.entries.count == 2)
        #expect(first.direction.liquidBalance == 1_040)
        #expect(first.contoIDs == [cash.id])
        #expect(!first.hasMixedCurrencies)

        old.amount = 80
        try context.save()
        let refreshed = try await reader.load(container: container, accountID: book.id, showAllAccounts: false, now: now)
        #expect(refreshed.direction.liquidBalance == 1_010)
        let all = try await reader.load(container: container, accountID: nil, showAllAccounts: true, now: now)
        #expect(all.hasMixedCurrencies)
        #expect(all.entries.count == 3)
    }

    @Test func budgetsIncludeArchivedContiAndExpandedCategories() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Libro")
        let archived = Conto(name: "Chiuso", type: .checking, initialBalance: 0)
        archived.isActive = false
        archived.account = book
        let category = Category(name: "Spesa")
        category.account = book
        let child = Category(name: "Dettaglio", parentCategoryId: category.id)
        child.account = book
        let budget = Budget(name: "Limite", amount: 100, period: .monthly)
        budget.account = book
        budget.categories = [category]
        let now = Date()
        let transaction = Transaction(amount: 40, type: .expense, date: now)
        transaction.setFromConto(archived)
        transaction.category = child
        transaction.categoryId = child.id
        context.insert(book)
        context.insert(archived)
        context.insert(category)
        context.insert(child)
        context.insert(budget)
        context.insert(transaction)
        try context.save()
        let value = try await TodaySnapshotReader().load(container: container, accountID: book.id,
                                                        showAllAccounts: false, now: now)
        #expect(value.entries.isEmpty)
        #expect(value.budgets.first?.spent == 40)
        #expect(value.budgets.first?.remaining == 60)
        #expect(value.refreshContoIDs.contains(archived.id))
        let all = try await TodaySnapshotReader().load(container: container, accountID: book.id,
                                                      showAllAccounts: true, now: now)
        #expect(all.budgets.first?.spent == 40)
    }

    @Test func cancellationDoesNotReturnAStaleSnapshot() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let reader = TodaySnapshotReader()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.load(container: container, accountID: nil, showAllAccounts: true)
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled refresh must not produce a snapshot")
        } catch is CancellationError {}
    }
}
