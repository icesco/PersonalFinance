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
    @Test func verificationPersistsAndOnlyPastFinancialChangesInvalidateIt() throws {
        let (container, id) = try fixture()
        let originalContext = ModelContext(container)
        let before = try #require(originalContext.fetch(FetchDescriptor<Conto>()).first)
        #expect(BalanceReconciliation.needsVerification(for: before))
        try BalanceReconciliation.apply(contoID: id, enteredBalance: "200", container: container, now: now)
        let context = ModelContext(container)
        let conto = try #require(context.fetch(FetchDescriptor<Conto>()).first)
        #expect(conto.balanceVerifiedAt == now)
        #expect(!BalanceReconciliation.needsVerification(for: conto))
        let later = Transaction(amount: 10, type: .expense, date: now.addingTimeInterval(3600))
        later.setFromConto(conto)
        context.insert(later)
        try context.save()
        #expect(!BalanceReconciliation.needsVerification(for: conto))
        let historical = try #require(conto.allTransactions.first { $0.date < now })
        historical.transactionDescription = "A clearer note"
        #expect(!BalanceReconciliation.needsVerification(for: conto))
        historical.amount = 25
        #expect(BalanceReconciliation.needsVerification(for: conto))
        historical.amount = 20
        #expect(!BalanceReconciliation.needsVerification(for: conto))
        conto.initialBalance = 181
        #expect(BalanceReconciliation.needsVerification(for: conto))
        conto.initialBalance = 180
        let backdated = Transaction(amount: 5, type: .expense, date: now.addingTimeInterval(-3600))
        backdated.setFromConto(conto)
        context.insert(backdated)
        try context.save()
        #expect(BalanceReconciliation.needsVerification(for: conto))
    }

    @Test func verificationSurvivesSharedBookImportWithNewLocalIDs() throws {
        let (source, id) = try fixture()
        try BalanceReconciliation.apply(contoID: id, enteredBalance: "200", container: source, now: now)
        let conto = try #require(ModelContext(source).fetch(FetchDescriptor<Conto>()).first)
        let book = try #require(conto.account)
        let snapshot = try SharedBookExporter.export(bookID: book.id, container: source)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        _ = try SharedBookImporter.apply(scope: SharedBookScope(ownerName: "test-owner", bookID: book.id),
            records: snapshot.records, assets: snapshot.assets, container: target)
        let imported = try #require(ModelContext(target).fetch(FetchDescriptor<Conto>()).first)
        #expect(imported.id != id)
        #expect(imported.balanceVerifiedAt == now)
        #expect(!BalanceReconciliation.needsVerification(for: imported))
    }

    @Test func archivedAndInvestmentAccountsDoNotRequestVerification() {
        let conto = Conto(name: "Investments", type: .investment)
        #expect(!BalanceReconciliation.needsVerification(for: conto))
        conto.type = .checking
        #expect(BalanceReconciliation.needsVerification(for: conto))
        conto.isActive = false
        #expect(!BalanceReconciliation.needsVerification(for: conto))
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
