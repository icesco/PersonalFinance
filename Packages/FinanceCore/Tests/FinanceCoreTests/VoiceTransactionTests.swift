import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor struct VoiceTransactionTests {
    @Test func omittedDateUsesExactCurrentMomentAndExplicitDateIsStrict() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let now = Date(timeIntervalSince1970: 1_791_623_145)
        #expect(VoiceTransactionDraft.resolvedDate("", wasSpecified: false, now: now, calendar: calendar) == now)
        #expect(VoiceTransactionDraft.resolvedDate("2026-02-30", wasSpecified: true, now: now, calendar: calendar) == nil)
        #expect(VoiceTransactionDraft.resolvedDate("", wasSpecified: true, now: now, calendar: calendar) == nil)
        let date = try #require(VoiceTransactionDraft.resolvedDate("2026-10-09", wasSpecified: true, now: now, calendar: calendar))
        #expect(calendar.component(.day, from: date) == 9)
        #expect(calendar.component(.month, from: date) == 10)
    }

    @Test func listSavesIncomeAndRepeatedExpensesOnceAndPlansFuture() throws {
        let (store, conto) = try ledger()
        let now = Date().addingTimeInterval(-60)
        let drafts = [
            VoiceTransactionDraft(amount: "1800", currency: "EUR", type: .income, note: "Stipendio", date: now, contoID: conto.id),
            VoiceTransactionDraft(amount: "3", type: .expense, note: "Bar", date: now, contoID: conto.id),
            VoiceTransactionDraft(amount: "3", type: .expense, note: "Bar", date: now, contoID: conto.id),
            VoiceTransactionDraft(amount: "5", type: .expense, note: "Supermercato", date: now.addingTimeInterval(86_400), contoID: conto.id)
        ]
        let ids = try VoiceTransactionApproval.approve(drafts, in: store)
        #expect(ids.count == 4)
        #expect(try VoiceTransactionApproval.approve(drafts, in: store) == ids)
        let context = ModelContext(store)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 4)
        #expect(transactions.filter { $0.transactionDescription == "Bar" }.count == 2)
        let freshConto = try #require(context.fetch(FetchDescriptor<Conto>()).first)
        #expect(freshConto.balance == 2294)
    }

    @Test func invalidLastRowRollsBackWholeList() throws {
        let (store, conto) = try ledger()
        let valid = VoiceTransactionDraft(amount: "3", type: .expense, contoID: conto.id)
        let invalid = VoiceTransactionDraft(amount: "5", type: .expense)
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([valid, invalid], in: store) }
        let context = ModelContext(store)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try context.fetch(FetchDescriptor<Conto>()).first?.balance == 500)
    }

    @Test func approvesOneWhileOtherDraftsRemainUnresolvedThenApprovesTheRest() throws {
        let (store, conto) = try ledger()
        let now = Date().addingTimeInterval(-60)
        let first = VoiceTransactionDraft(amount: "3", type: .expense, note: "Bar", date: now, contoID: conto.id)
        var second = VoiceTransactionDraft(amount: "5", type: .expense, note: "Supermercato", date: now)
        let firstIDs = try VoiceTransactionApproval.approve([first], in: store)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([second], in: store) }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<Transaction>()) == 1)
        second.contoID = conto.id
        let secondIDs = try VoiceTransactionApproval.approve([second], in: store)
        #expect(firstIDs != secondIDs)
        #expect(try VoiceTransactionApproval.approve([first, second], in: store) == firstIDs + secondIDs)
        let context = ModelContext(store)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try context.fetch(FetchDescriptor<Conto>()).first?.balance == 492)
    }

    @Test func rejectsUnresolvedDatesCurrencyMismatchAndWrongCategory() throws {
        let (store, conto) = try ledger()
        var draft = VoiceTransactionDraft(amount: "12,50", currency: "USD", type: .expense, contoID: conto.id)
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([draft], in: store) }
        draft.currency = "EUR"; draft.dateNeedsReview = true
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([draft], in: store) }
        draft.dateNeedsReview = false; draft.categoryID = UUID()
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([draft], in: store) }
        draft.categoryID = nil; draft.type = nil
        #expect(throws: (any Error).self) { try VoiceTransactionApproval.approve([draft], in: store) }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    private func ledger() throws -> (ModelContainer, Conto) {
        let store = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 500)
        conto.account = book; book.conti = [conto]
        store.mainContext.insert(book)
        try store.mainContext.save()
        return (store, conto)
    }
}
