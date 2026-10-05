import Foundation
import CryptoKit
import SwiftData

/// All calls execute on the phone's main actor. No network or financial write
/// occurs during preview; a save and its retry receipt share one context save.
@MainActor
public enum RemoteExpenseService {
    public enum Failure: Error, Equatable {
        case invalidAmount, invalidSelection, currencyChanged, invalidDate, invalidNote
        case confirmationExpired, confirmationChanged, requestIDReused
    }

    public static func preview(_ input: RemoteExpenseInput, container: ModelContainer,
                               now: Date = Date(), calendar: Calendar = .current) throws -> RemoteExpenseQuote {
        try quote(input, context: ModelContext(container), now: now, calendar: calendar)
    }

    public static func save(_ input: RemoteExpenseInput, confirmation: RemoteExpenseQuote,
                            container: ModelContainer, now: Date = Date(),
                            calendar: Calendar = .current) throws -> RemoteExpenseSaveResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let requestID = input.requestID
        let receipts = try context.fetch(FetchDescriptor<RemoteExpenseReceipt>(
            predicate: #Predicate { $0.requestID == requestID }))
        if let receipt = receipts.first {
            guard receipt.requestDigest == (try digest(input)),
                  let transactionID = receipt.transactionID else { throw Failure.requestIDReused }
            return RemoteExpenseSaveResult(transactionID: transactionID, alreadyRecorded: true)
        }
        guard confirmation.input == input else { throw Failure.confirmationChanged }
        guard now >= confirmation.issuedAt, now.timeIntervalSince(confirmation.issuedAt) <= 300 else {
            throw Failure.confirmationExpired
        }
        let current = try quote(input, context: context, now: now, calendar: calendar)
        guard current.budgets == confirmation.budgets,
              current.bookName == confirmation.bookName,
              current.contoName == confirmation.contoName,
              current.categoryName == confirmation.categoryName else { throw Failure.confirmationChanged }
        let (book, conto, category) = try selection(input, context: context)
        guard book.currency == input.currency else { throw Failure.currencyChanged }
        let transaction = Transaction(amount: input.amount, type: .expense, date: input.date,
                                      transactionDescription: input.note)
        transaction.externalID = "watch:\(input.requestID.uuidString)"
        transaction.setFromConto(conto)
        transaction.setCategory(category)
        context.insert(transaction)
        context.insert(RemoteExpenseReceipt(requestID: requestID, transactionID: transaction.id,
            requestDigest: try digest(input), createdAt: now))
        do { try context.save() }
        catch { context.rollback(); throw error }
        return RemoteExpenseSaveResult(transactionID: transaction.id, alreadyRecorded: false)
    }

    private static func digest(_ input: RemoteExpenseInput) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Data(SHA256.hash(data: try encoder.encode(input)))
    }

    private static func selection(_ input: RemoteExpenseInput, context: ModelContext) throws -> (Account, Conto, Category) {
        let id = input.bookID
        guard let book = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first,
              book.isActive == true,
              let conto = book.conti?.first(where: { $0.id == input.contoID && $0.isActive == true }),
              let category = book.categories?.first(where: { $0.id == input.categoryID && $0.isActive == true }) else {
            throw Failure.invalidSelection
        }
        return (book, conto, category)
    }

    private static func quote(_ input: RemoteExpenseInput, context: ModelContext,
                              now: Date, calendar: Calendar) throws -> RemoteExpenseQuote {
        guard input.amount > 0, !input.amount.isNaN,
              let rounded = try? CurrencyConversion.convert(input.amount, rate: 1, currency: input.currency),
              rounded == input.amount else { throw Failure.invalidAmount }
        guard input.note.count <= 200 else { throw Failure.invalidNote }
        guard input.date.timeIntervalSince1970.isFinite,
              abs(input.date.timeIntervalSince(now)) <= 86400 else { throw Failure.invalidDate }
        let (book, conto, category) = try selection(input, context: context)
        guard book.currency == input.currency else { throw Failure.currencyChanged }
        let previews = BudgetService.previewExpense(amount: input.amount, categoryID: input.categoryID,
            accountID: input.bookID, date: input.date,
            budgets: try context.fetch(FetchDescriptor<Budget>()),
            transactions: try context.fetch(FetchDescriptor<Transaction>()), calendar: calendar)
        return RemoteExpenseQuote(input: input, issuedAt: now,
            bookName: book.name ?? "Libro", contoName: conto.name ?? "Conto",
            categoryName: category.name ?? "Categoria", budgets: previews.map {
                RemoteExpenseBudget(id: $0.id, name: $0.name, limit: $0.limit, spent: $0.spent,
                                    remaining: $0.remaining, threshold: $0.threshold, period: $0.period)
            })
    }
}
