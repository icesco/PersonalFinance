import Foundation
import SwiftData

@MainActor
public enum RecurrenceOccurrenceService {
    public enum Failure: Error { case invalidOccurrence, missingAccount, alreadySkipped }

    /// Records a scheduled occurrence once in the local store. The original entry is never modified.
    public static func record(source: Transaction, scheduledDate: Date, context: ModelContext) throws -> Transaction {
        try validate(source, date: scheduledDate)
        let key = RecurrenceResolution.key(sourceID: source.id, date: scheduledDate)
        if let existing = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.externalID == key })).first {
            return existing
        }
        let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>(predicate: #Predicate { $0.key == key }))
        guard resolutions.isEmpty else { throw Failure.alreadySkipped }
        guard source.type == .income ? source.toConto != nil : source.fromConto != nil,
              source.type != .transfer || source.toConto != nil else { throw Failure.missingAccount }
        let transaction = Transaction(amount: source.amount ?? 0, type: source.type, date: scheduledDate,
                                      transactionDescription: source.transactionDescription, notes: source.notes)
        transaction.destinationAmount = source.destinationAmount
        transaction.originalAmount = source.originalAmount
        transaction.originalCurrency = source.originalCurrency
        transaction.exchangeRate = source.exchangeRate
        transaction.exchangeRateDate = source.exchangeRateDate
        transaction.exchangeRateSource = source.exchangeRateSource
        transaction.externalID = key
        transaction.recurrenceSourceID = source.id
        transaction.setFromConto(source.fromConto)
        transaction.setToConto(source.toConto)
        transaction.setCategory(source.category)
        let resolution = RecurrenceResolution(sourceID: source.id, scheduledDate: scheduledDate, transactionID: transaction.id)
        context.insert(transaction)
        context.insert(resolution)
        do { try context.save() }
        catch {
            context.delete(transaction)
            context.delete(resolution)
            throw error
        }
        return transaction
    }

    public static func skip(source: Transaction, scheduledDate: Date, context: ModelContext) throws {
        try validate(source, date: scheduledDate)
        let key = RecurrenceResolution.key(sourceID: source.id, date: scheduledDate)
        guard try context.fetch(FetchDescriptor<RecurrenceResolution>(predicate: #Predicate { $0.key == key })).isEmpty else { return }
        guard try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.externalID == key })).isEmpty else { return }
        let resolution = RecurrenceResolution(sourceID: source.id, scheduledDate: scheduledDate, isSkipped: true)
        context.insert(resolution)
        do { try context.save() }
        catch { context.delete(resolution); throw error }
    }

    private static func validate(_ source: Transaction, date: Date) throws {
        guard date > source.date, source.isRecurring == true, (source.amount ?? 0) > 0,
              source.nextRecurrenceDate(after: date.addingTimeInterval(-0.001)) == date else {
            throw Failure.invalidOccurrence
        }
    }
}
