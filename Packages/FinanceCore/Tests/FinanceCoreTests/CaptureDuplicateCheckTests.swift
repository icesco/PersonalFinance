import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor struct CaptureDuplicateCheckTests {
    private let day = Date(timeIntervalSince1970: 1_750_000_000)

    private func ledger() throws -> (ModelContainer, Conto) {
        let store = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 500)
        conto.account = book
        book.conti = [conto]
        store.mainContext.insert(book)
        try store.mainContext.save()
        return (store, conto)
    }

    private func movement(_ store: ModelContainer, _ conto: Conto, date: Date, recurring: Bool = false) throws -> Transaction {
        let transaction = Transaction(amount: 25, type: .expense, date: date, transactionDescription: "Abbonamento",
            isRecurring: recurring, recurrenceFrequency: recurring ? .monthly : nil)
        transaction.setFromConto(conto)
        store.mainContext.insert(transaction)
        try store.mainContext.save()
        return transaction
    }

    private func matches(_ store: ModelContainer, _ conto: Conto, date: Date, type: TransactionType = .expense) throws -> [CaptureDuplicateMatch] {
        try CaptureDuplicateCheck.matches(captureID: UUID(), contoID: conto.id, amount: 25, type: type,
            date: date, in: store.mainContext)
    }

    @Test func recordedMatchesDoNotDependOnDescriptionAndRespectAccountAndDirection() throws {
        let (store, conto) = try ledger()
        let transaction = try movement(store, conto, date: day)
        transaction.transactionDescription = nil
        let other = Conto(name: "Altro", type: .checking, initialBalance: 100)
        other.account = conto.account
        store.mainContext.insert(other)
        try store.mainContext.save()
        #expect(try matches(store, conto, date: day).count == 1)
        #expect(try matches(store, other, date: day).isEmpty)
        #expect(try matches(store, conto, date: day, type: .income).isEmpty)
        #expect(try matches(store, conto, date: day.addingTimeInterval(86400 * 4)).isEmpty)
    }

    @Test func oldSeedDetectsUnrecordedRecurringOccurrence() throws {
        let (store, conto) = try ledger()
        let source = try movement(store, conto, date: day, recurring: true)
        let due = try #require(source.nextRecurrenceDate(after: day))
        let result = try matches(store, conto, date: due)
        #expect(result.count == 1)
        #expect(result.first?.isRecurring == true)
        #expect(result.first?.id == RecurrenceResolution.key(sourceID: source.id, date: due))
        #expect(try matches(store, conto, date: due.addingTimeInterval(86400 * 8)).isEmpty)
    }

    @Test func skippedAndEndedRecurrencesAreNotFlagged() throws {
        let (store, conto) = try ledger()
        let source = try movement(store, conto, date: day, recurring: true)
        let due = try #require(source.nextRecurrenceDate(after: day))
        try RecurrenceOccurrenceService.skip(source: source, scheduledDate: due, context: store.mainContext)
        #expect(try matches(store, conto, date: due).isEmpty)
        source.recurrenceEndDate = day
        try store.mainContext.save()
        let later = Calendar.current.date(byAdding: .month, value: 2, to: day)!
        #expect(try matches(store, conto, date: later).isEmpty)
    }

    @Test func materializedOccurrenceAppearsOnceAsRecorded() throws {
        let (store, conto) = try ledger()
        let source = try movement(store, conto, date: day, recurring: true)
        let due = try #require(source.nextRecurrenceDate(after: day))
        _ = try RecurrenceOccurrenceService.record(source: source, scheduledDate: due, context: store.mainContext)
        let result = try matches(store, conto, date: due)
        #expect(result.count == 1)
        #expect(result.first?.isRecurring == false)
    }

    @Test func approvalRequiresReviewAndRejectsNewMatchesAfterReview() throws {
        let (store, conto) = try ledger()
        _ = try movement(store, conto, date: day)
        let reviewedIDs = Set(try matches(store, conto, date: day).map(\.id))
        let input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, amount: 25,
            currency: "EUR", date: day, note: "Descrizione diversa", paymentConfirmed: true)
        #expect(throws: CaptureApproval.Failure.possibleDuplicate) {
            try CaptureApproval.approve(input, in: store)
        }
        _ = try movement(store, conto, date: day)
        #expect(throws: CaptureApproval.Failure.possibleDuplicate) {
            try CaptureApproval.approve(input, in: store, reviewedDuplicateIDs: reviewedIDs)
        }
        let allIDs = Set(try matches(store, conto, date: day).map(\.id))
        let id = try CaptureApproval.approve(input, in: store, reviewedDuplicateIDs: allIDs)
        #expect(try CaptureApproval.approve(input, in: store) == id)
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<Transaction>()) == 3)
    }

    @Test func recurringMatchBlocksApprovalUntilExplicitlyReviewed() throws {
        let (store, conto) = try ledger()
        let source = try movement(store, conto, date: day, recurring: true)
        let due = try #require(source.nextRecurrenceDate(after: day))
        let input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, amount: 25,
            currency: "EUR", date: due, paymentConfirmed: true)
        #expect(throws: CaptureApproval.Failure.possibleDuplicate) {
            try CaptureApproval.approve(input, in: store)
        }
        #expect(try ModelContext(store).fetchCount(FetchDescriptor<Transaction>()) == 1)
    }
}
