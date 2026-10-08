import Foundation
import SwiftData
import CryptoKit

/// The app owns every write. A batch validates completely before one atomic save.
@MainActor
public enum FormiCLIService {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        public init(_ message: String) { self.message = message }
    }
    public struct Row: Codable, Sendable {
        public let requestID: UUID
        public let transactionID: UUID?
        public let account: String
        public let category: String?
        public let amount: String
        public let currency: String
        public let date: String
        public let type: String
        public let description: String?
        public let alreadyRecorded: Bool
        public let possibleDuplicate: Bool
    }
    public struct Result: Codable, Sendable {
        public let saved: Bool
        public let movements: [Row]
    }
    private struct Validated {
        let input: FormiCLIMovement
        let conto: Conto
        let category: Category?
        let amount: Decimal
        let date: Date
        let type: TransactionType
        let digest: Data
        let receipt: RemoteExpenseReceipt?
        let duplicate: Bool
    }

    public static func execute(_ request: FormiCLIRequest, container: ModelContainer,
                               calendar: Calendar = .current) throws -> Result {
        guard request.version == 1, request.categoryMutation == nil, ["add", "import", "preview"].contains(request.command),
              !request.movements.isEmpty, request.movements.count <= 500,
              request.command != "add" || request.movements.count == 1,
              request.command != "preview" || !request.commit else {
            throw Failure("Richiesta non valida: usa da 1 a 500 movimenti (uno per add).")
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let conti = try context.fetch(FetchDescriptor<Conto>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let shared = Set(try context.fetch(FetchDescriptor<SharedBookMembership>()).map(\.localBookID))
        var validated: [Validated] = []
        var ids: Set<UUID> = []
        for (index, input) in request.movements.enumerated() {
            do {
                guard ids.insert(input.requestID).inserted else { throw Failure("requestID ripetuto nel lotto.") }
                guard let type = TransactionType(rawValue: input.type), type != .transfer else {
                    throw Failure("Il tipo deve essere expense o income.")
                }
                guard let conto = conti.first(where: { $0.id == input.accountID && $0.isActive == true }),
                      let book = conto.account, book.isActive == true,
                      request.bookID == nil || request.bookID == book.id else {
                    throw Failure("Conto o libro non disponibile.")
                }
                guard !shared.contains(book.id) else { throw Failure("La CLI supporta per ora solo libri personali.") }
                guard book.currency == input.currency else { throw Failure("La valuta non corrisponde al libro.") }
                guard input.amount.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                      input.amount.filter(\.isNumber).count <= 38,
                      let amount = Decimal(string: input.amount, locale: Locale(identifier: "en_US_POSIX")),
                      amount > 0, !amount.isNaN,
                      let rounded = try? CurrencyConversion.convert(amount, rate: 1, currency: input.currency),
                      rounded == amount else { throw Failure("Importo positivo non valido o precisione errata.") }
                let date = try parseDate(input.date, calendar: calendar)
                guard (input.description?.count ?? 0) <= 2_000 else { throw Failure("Descrizione troppo lunga.") }
                var category: Category?
                if let id = input.categoryID {
                    guard let found = categories.first(where: { $0.id == id && $0.isActive == true }),
                          found.account?.id == book.id, found.fits(type) else {
                        throw Failure("Categoria non disponibile o incompatibile con il conto e il tipo.")
                    }
                    category = found
                }
                let digest = Data(SHA256.hash(data: try FormiCLIWire.encoder().encode(input)))
                let id = input.requestID
                let receipt = try context.fetch(FetchDescriptor<RemoteExpenseReceipt>(
                    predicate: #Predicate { $0.requestID == id })).first
                if let receipt {
                    guard receipt.requestDigest == digest, receipt.transactionID != nil else {
                        throw Failure("requestID già utilizzato con dati diversi.")
                    }
                }
                let day = calendar.startOfDay(for: date)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
                // Bound duplicate candidates by day; relationship fallbacks cover legacy rows.
                let candidates = try context.fetch(FetchDescriptor<Transaction>(
                    predicate: #Predicate { $0.date >= day && $0.date < nextDay }))
                let duplicate = receipt == nil && (candidates.contains {
                    $0.type == type && $0.amount == amount &&
                    (type == .expense ? ($0.fromContoId ?? $0.fromConto?.id) : ($0.toContoId ?? $0.toConto?.id)) == conto.id &&
                    ($0.transactionDescription ?? "") == (input.description ?? "")
                } || validated.contains {
                    $0.receipt == nil && $0.conto.id == conto.id && $0.type == type && $0.amount == amount &&
                    calendar.isDate($0.date, inSameDayAs: date) &&
                    ($0.input.description ?? "") == (input.description ?? "")
                })
                if request.commit && duplicate && !request.allowDuplicates {
                    throw Failure("Possibile duplicato. Verifica l'anteprima; usa --allow-duplicates solo se voluto.")
                }
                validated.append(Validated(input: input, conto: conto, category: category, amount: amount,
                    date: date, type: type, digest: digest, receipt: receipt, duplicate: duplicate))
            } catch {
                throw Failure("Movimento \(index + 1): \(error.localizedDescription)")
            }
        }
        var rows: [Row] = []
        for item in validated {
            var transactionID = item.receipt?.transactionID
            if request.commit && item.receipt == nil {
                let transaction = Transaction(amount: item.amount, type: item.type, date: item.date,
                                              transactionDescription: item.input.description)
                transaction.externalID = "formi-cli:\(item.input.requestID.uuidString)"
                if item.type == .expense { transaction.setFromConto(item.conto) }
                else { transaction.setToConto(item.conto) }
                transaction.setCategory(item.category)
                context.insert(transaction)
                context.insert(RemoteExpenseReceipt(requestID: item.input.requestID, transactionID: transaction.id,
                    requestDigest: item.digest, createdAt: Date()))
                transactionID = transaction.id
            }
            rows.append(Row(requestID: item.input.requestID, transactionID: transactionID,
                account: item.conto.name ?? "Conto", category: item.category?.name,
                amount: item.input.amount, currency: item.input.currency, date: item.input.date,
                type: item.input.type, description: item.input.description,
                alreadyRecorded: item.receipt != nil, possibleDuplicate: item.duplicate))
        }
        if request.commit {
            do { try context.save() }
            catch { context.rollback(); throw error }
        }
        return Result(saved: request.commit, movements: rows)
    }

    private static func parseDate(_ value: String, calendar: Calendar) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw Failure("Data non valida: usa YYYY-MM-DD nel fuso orario di Formi.")
        }
        return date
    }
}
