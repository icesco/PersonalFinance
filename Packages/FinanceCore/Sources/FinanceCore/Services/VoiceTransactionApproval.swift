import Foundation
import SwiftData

/// Editable proposals remain values, outside SwiftData, until the whole list is approved.
public struct VoiceTransactionDraft: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var amount: String
    public var currency: String
    public var type: TransactionType?
    public var note: String
    public var date: Date
    public var dateNeedsReview: Bool
    public var contoID: UUID?
    public var categoryID: UUID?
    public var suggestedCategory: String

    public init(id: UUID = UUID(), amount: String = "", currency: String = "", type: TransactionType? = nil,
                note: String = "", date: Date = Date(), dateNeedsReview: Bool = false,
                contoID: UUID? = nil, categoryID: UUID? = nil, suggestedCategory: String = "") {
        self.id = id; self.amount = amount; self.currency = currency; self.type = type
        self.note = note; self.date = date; self.dateNeedsReview = dateNeedsReview
        self.contoID = contoID; self.categoryID = categoryID
        self.suggestedCategory = suggestedCategory
    }

    /// Strict calendar parsing prevents a malformed explicit date silently becoming today.
    public static func resolvedDate(_ isoDay: String, wasSpecified: Bool, now: Date, calendar: Calendar = .current) -> Date? {
        guard wasSpecified else { return now }
        let parts = isoDay.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
}

@MainActor public enum VoiceTransactionApproval {
    public enum Failure: LocalizedError {
        case invalidList, invalidRow(Int)
        public var errorDescription: String? {
            switch self {
            case .invalidList: "L’elenco deve contenere da 1 a 20 movimenti distinti."
            case .invalidRow(let row): "Controlla importo, valuta, tipo, data e conto del movimento \(row)."
            }
        }
    }

    /// A dedicated context makes validation and save atomic without touching unrelated edits.
    @discardableResult public static func approve(_ drafts: [VoiceTransactionDraft], in container: ModelContainer) throws -> [UUID] {
        guard (1...20).contains(drafts.count), Set(drafts.map(\.id)).count == drafts.count else { throw Failure.invalidList }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var result: [UUID] = []
        do {
            for (index, draft) in drafts.enumerated() {
                let externalID = "voice:\(draft.id.uuidString)"
                // Retrying an approved list must not add the same movements again.
                if let existing = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.externalID == externalID })).first {
                    result.append(existing.id); continue
                }
                guard let amount = CaptureTextParser.decimal(draft.amount), amount > 0,
                      let type = draft.type, type != .transfer,
                      !draft.dateNeedsReview, draft.date.timeIntervalSince1970.isFinite,
                      let contoID = draft.contoID,
                      let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
                      conto.isActive == true, let book = conto.account, book.isActive == true,
                      draft.currency.isEmpty || draft.currency == book.currency,
                      let currency = book.currency,
                      (try? CurrencyConversion.convert(amount, rate: 1, currency: currency)) == amount else {
                    throw Failure.invalidRow(index + 1)
                }
                var category: Category?
                if let categoryID = draft.categoryID {
                    category = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryID })).first
                    guard category?.isActive == true, category?.account?.id == book.id, category?.fits(type) == true else {
                        throw Failure.invalidRow(index + 1)
                    }
                }
                let transaction = Transaction(amount: amount, type: type, date: draft.date,
                    transactionDescription: String(draft.note.prefix(500)))
                transaction.externalID = externalID
                if type == .expense { transaction.setFromConto(conto) } else { transaction.setToConto(conto) }
                transaction.setCategory(category)
                context.insert(transaction)
                result.append(transaction.id)
            }
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
