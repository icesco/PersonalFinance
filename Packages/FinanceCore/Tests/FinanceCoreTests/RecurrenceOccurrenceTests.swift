import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct RecurrenceOccurrenceTests {
    func fixture() throws -> (ModelContainer, Transaction, Date) {
        let container = try FinanceCoreModule.createModelContainer(inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Test")
        let conto = Conto(name: "Conto", type: .checking, initialBalance: 1000)
        conto.account = book
        let source = Transaction(amount: 25, type: .expense, date: Date(timeIntervalSince1970: 1_700_000_000),
                                 transactionDescription: "Abbonamento", isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(conto)
        context.insert(book)
        context.insert(conto)
        context.insert(source)
        try context.save()
        return (container, source, source.nextRecurrenceDate(after: source.date)!)
    }

    @Test func recordsOnceAndPreservesSeriesAcrossContexts() throws {
        let (container, source, due) = try fixture()
        let first = try RecurrenceOccurrenceService.record(source: source, scheduledDate: due, context: container.mainContext)
        let second = try RecurrenceOccurrenceService.record(source: source, scheduledDate: due, context: container.mainContext)
        #expect(first.id == second.id)
        #expect(first.isRecurring == false)
        #expect(first.recurrenceSourceID == source.id)
        #expect(source.isRecurring == true)
        let other = ModelContext(container)
        let id = source.id
        let reloaded = try #require(other.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })).first)
        let third = try RecurrenceOccurrenceService.record(source: reloaded, scheduledDate: due, context: other)
        #expect(third.id == first.id)
        #expect(try other.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try other.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 1)
        #expect(first.fromContoId == source.fromContoId)
    }

    @Test func skippingDoesNotCreateExpense() throws {
        let (container, source, due) = try fixture()
        try RecurrenceOccurrenceService.skip(source: source, scheduledDate: due, context: container.mainContext)
        try RecurrenceOccurrenceService.skip(source: source, scheduledDate: due, context: container.mainContext)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 1)
        #expect(throws: RecurrenceOccurrenceService.Failure.alreadySkipped) {
            try RecurrenceOccurrenceService.record(source: source, scheduledDate: due, context: container.mainContext)
        }
    }

    @Test func rejectsSeedAndUnscheduledDates() throws {
        let (container, source, due) = try fixture()
        for date in [source.date, due.addingTimeInterval(60)] {
            #expect(throws: RecurrenceOccurrenceService.Failure.invalidOccurrence) {
                try RecurrenceOccurrenceService.record(source: source, scheduledDate: date, context: container.mainContext)
            }
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }
}
