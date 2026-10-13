import Foundation
import SwiftData
import CryptoKit

@MainActor
public enum FormiCLITransactionService {
    public struct Row: Codable, Sendable {
        public let transactionID: UUID
        public let externalID: String
        public let date: String
        public let timestamp: Date
        public let type: String
        public let amount: String?
        public let currency: String?
        public let destinationAmount: String?
        public let destinationCurrency: String?
        public let fromAccountID: UUID?
        public let toAccountID: UUID?
        public let fromAccountName: String?
        public let toAccountName: String?
        public let fromBookID: UUID?
        public let toBookID: UUID?
        public let categoryID: UUID?
        public let description: String?
        public let notes: String?
        public let originalAmount: String?
        public let originalCurrency: String?
        public let recurrence: FormiCLIRecurrence?
        public let recurrenceSourceID: UUID?
        public let planned: Bool
    }

    public struct Page: Codable, Sendable {
        public let transactions: [Row]
        public let total: Int
        public let offset: Int
        public let nextOffset: Int?
        public let revision: String
        public let timeZone: String
    }

    public static func read(_ request: FormiCLIRequest, container: ModelContainer,
                            calendar: Calendar = .current, now: Date = Date()) throws -> Page {
        guard request.version == 3, request.command == "transactions", !request.commit,
              !request.allowDuplicates, request.movements.isEmpty, request.accountSplit == nil, request.categoryMutation == nil,
              request.includeArchived != true, let query = request.transactionQuery,
              (1...500).contains(query.limit), query.offset >= 0 else {
            throw FormiCLIService.Failure("Richiesta di lettura transazioni non valida.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        func date(_ value: String) throws -> Date {
            guard let parsed = formatter.date(from: value), formatter.string(from: parsed) == value else {
                throw FormiCLIService.Failure("Data non valida: usa YYYY-MM-DD nel fuso orario di Formi.")
            }
            return parsed
        }
        let start = try query.from.map(date) ?? .distantPast
        let lastDay = try query.to.map(date)
        if let lastDay, start > lastDay {
            throw FormiCLIService.Failure("--from deve precedere o coincidere con --to.")
        }
        // Calendar addition includes the full final day across daylight-saving changes.
        let end = lastDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let bookID = request.bookID {
            guard try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == bookID })).first != nil else {
                throw FormiCLIService.Failure("Libro non trovato.")
            }
        }
        if let accountID = query.accountID {
            let account = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == accountID })).first
            guard let account, request.bookID == nil || account.account?.id == request.bookID else {
                throw FormiCLIService.Failure("Conto non trovato nel libro richiesto.")
            }
        }
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                      sortBy: [SortDescriptor(\.date)])
        func decimal(_ value: Decimal?) -> String? { value.map { NSDecimalNumber(decimal: $0).stringValue } }
        let rows = try context.fetch(descriptor).filter { transaction in
            let source = transaction.fromConto
            let destination = transaction.toConto
            return (query.includePlanned || transaction.date <= now)
                && (request.bookID == nil || source?.account?.id == request.bookID || destination?.account?.id == request.bookID)
                && (query.accountID == nil || source?.id == query.accountID || destination?.id == query.accountID)
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }.map { transaction in
            Row(transactionID: transaction.id, externalID: transaction.externalID,
                date: formatter.string(from: transaction.date), timestamp: transaction.date,
                type: transaction.typeRaw, amount: decimal(transaction.amount),
                currency: (transaction.fromConto ?? transaction.toConto)?.account?.currency,
                destinationAmount: decimal(transaction.destinationAmount),
                destinationCurrency: transaction.toConto?.account?.currency,
                fromAccountID: transaction.fromConto?.id, toAccountID: transaction.toConto?.id,
                fromAccountName: transaction.fromConto?.name, toAccountName: transaction.toConto?.name,
                fromBookID: transaction.fromConto?.account?.id, toBookID: transaction.toConto?.account?.id,
                categoryID: transaction.category?.id ?? transaction.categoryId,
                description: transaction.transactionDescription, notes: transaction.notes,
                originalAmount: decimal(transaction.originalAmount), originalCurrency: transaction.originalCurrency,
                recurrence: transaction.isRecurring == true ? transaction.recurrenceFrequency.map {
                    FormiCLIRecurrence(frequency: $0.rawValue,
                        endDate: transaction.recurrenceEndDate.map { formatter.string(from: $0) })
                } : nil, recurrenceSourceID: transaction.recurrenceSourceID, planned: transaction.date > now)
        }
        let revision = SHA256.hash(data: try FormiCLIWire.encoder().encode(rows)).map { String(format: "%02x", $0) }.joined()
        guard query.revision == nil || query.revision == revision else {
            throw FormiCLIService.Failure("Lo storico è cambiato. Riparti da --offset 0 e usa la nuova revision.")
        }
        guard query.offset <= rows.count else {
            throw FormiCLIService.Failure("--offset supera il totale delle transazioni.")
        }
        let pageEnd = query.offset + min(query.limit, rows.count - query.offset)
        let page = Page(transactions: Array(rows[query.offset..<pageEnd]), total: rows.count, offset: query.offset,
                        nextOffset: pageEnd < rows.count ? pageEnd : nil, revision: revision,
                        timeZone: calendar.timeZone.identifier)
        guard try FormiCLIWire.encoder().encode(page).count < FormiCLIWire.maxBytes - 2048 else {
            throw FormiCLIService.Failure("Risposta troppo grande: riduci --limit o restringi il periodo.")
        }
        return page
    }
}
