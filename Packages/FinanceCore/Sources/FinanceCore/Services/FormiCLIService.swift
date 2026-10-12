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
        public let accountID: UUID
        public let toAccountID: UUID?
        public let toAccount: String?
        public let account: String
        public let category: String?
        public let amount: String
        public let currency: String
        public let date: String
        public let type: String
        public let description: String?
        public let recurrence: FormiCLIRecurrence?
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
        let destination: Conto?
        let category: Category?
        let amount: Decimal
        let date: Date
        let type: TransactionType
        let frequency: RecurrenceFrequency?
        let endDate: Date?
        let digest: Data
        let receipt: RemoteExpenseReceipt?
        let duplicate: Bool
    }

    public static func execute(_ request: FormiCLIRequest, container: ModelContainer,
                               calendar: Calendar = .current) throws -> Result {
        guard request.transactionQuery == nil, [1, 2, 4].contains(request.version),
              request.version == 4 || request.movements.allSatisfy({ $0.type != "transfer" && $0.toAccountID == nil }),
              request.version != 1 || request.movements.allSatisfy({ $0.recurrence == nil }), request.categoryMutation == nil, ["add", "import", "preview"].contains(request.command),
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
        let series: [Transaction] = request.movements.contains(where: { $0.recurrence != nil })
            ? try context.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.isRecurring == true && $0.recurrenceSourceID == nil }))
            : []
        var validated: [Validated] = []
        var ids: Set<UUID> = []
        for (index, input) in request.movements.enumerated() {
            do {
                guard ids.insert(input.requestID).inserted else { throw Failure("requestID ripetuto nel lotto.") }
                guard let type = TransactionType(rawValue: input.type) else {
                    throw Failure("Il tipo deve essere expense, income o transfer.")
                }
                guard let conto = conti.first(where: { $0.id == input.accountID && $0.isActive == true }),
                      let book = conto.account, book.isActive == true,
                      request.bookID == nil || request.bookID == book.id else {
                    throw Failure("Conto o libro non disponibile.")
                }
                guard !shared.contains(book.id) else { throw Failure("La CLI supporta per ora solo libri personali.") }
                guard book.currency == input.currency else { throw Failure("La valuta non corrisponde al libro.") }
                var destination: Conto?
                if type == .transfer {
                    guard request.version == 4, input.recurrence == nil,
                          let destinationID = input.toAccountID, destinationID != conto.id,
                          let found = conti.first(where: { $0.id == destinationID && $0.isActive == true }),
                          let destinationBook = found.account, destinationBook.isActive == true else {
                        throw Failure("Trasferimento non valido: scegli due conti diversi e attivi, senza ricorrenza.")
                    }
                    guard !shared.contains(destinationBook.id) else {
                        throw Failure("Il conto di arrivo deve appartenere a un libro personale.")
                    }
                    guard destinationBook.currency == input.currency else {
                        throw Failure("I trasferimenti CLI richiedono la stessa valuta nei due libri.")
                    }
                    destination = found
                } else if input.toAccountID != nil {
                    throw Failure("toAccountID è consentito soltanto per i trasferimenti.")
                }
                guard input.amount.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                      input.amount.filter(\.isNumber).count <= 38,
                      let amount = Decimal(string: input.amount, locale: Locale(identifier: "en_US_POSIX")),
                      amount > 0, !amount.isNaN,
                      let rounded = try? CurrencyConversion.convert(amount, rate: 1, currency: input.currency),
                      rounded == amount else { throw Failure("Importo positivo non valido o precisione errata.") }
                let date = try parseDate(input.date, calendar: calendar)
                var frequency: RecurrenceFrequency?
                var endDate: Date?
                if let recurrence = input.recurrence {
                    guard let parsed = RecurrenceFrequency(rawValue: recurrence.frequency) else {
                        throw Failure("Frequenza non valida: daily, weekly, biweekly, monthly, quarterly, semiannually o yearly.")
                    }
                    frequency = parsed
                    if let value = recurrence.endDate {
                        let lastDay = try parseDate(value, calendar: calendar)
                        guard let end = RecurrenceSchedule.inclusiveEnd(anchor: date, lastDay: lastDay, calendar: calendar) else {
                            throw Failure("La data di fine della ricorrenza precede la data iniziale.")
                        }
                        endDate = end
                    }
                }
                guard (input.description?.count ?? 0) <= 2_000 else { throw Failure("Descrizione troppo lunga.") }
                var category: Category?
                if let id = input.categoryID {
                    guard let found = categories.first(where: { $0.id == id && $0.isActive == true }),
                          found.account?.id == book.id, (type == .transfer || found.fits(type)) else {
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
                // Compare schedules as well as recorded rows: descriptions/categories may differ after migration.
                let recurringDuplicate = frequency.map { cadence in
                    series.contains { candidate in
                        candidate.type == type && candidate.amount == amount && candidate.recurrenceFrequency == cadence &&
                        (type == .expense ? (candidate.fromContoId ?? candidate.fromConto?.id) :
                            (candidate.toContoId ?? candidate.toConto?.id)) == conto.id &&
                        schedulesOverlap(candidate.date, ending: candidate.recurrenceEndDate,
                                         date, ending: endDate, frequency: cadence, calendar: calendar)
                    } || validated.contains { candidate in
                        candidate.receipt == nil && candidate.frequency == cadence && candidate.type == type &&
                        candidate.amount == amount && candidate.conto.id == conto.id &&
                        schedulesOverlap(candidate.date, ending: candidate.endDate,
                                         date, ending: endDate, frequency: cadence, calendar: calendar)
                    }
                } ?? false
                let duplicate = receipt == nil && (recurringDuplicate || candidates.contains { candidate in
                    guard candidate.type == type, candidate.amount == amount else { return false }
                    if type == .transfer {
                        return (candidate.fromContoId ?? candidate.fromConto?.id) == conto.id
                            && (candidate.toContoId ?? candidate.toConto?.id) == destination?.id
                    }
                    return (type == .expense ? (candidate.fromContoId ?? candidate.fromConto?.id) :
                        (candidate.toContoId ?? candidate.toConto?.id)) == conto.id
                        && (candidate.transactionDescription ?? "") == (input.description ?? "")
                } || validated.contains { candidate in
                    guard candidate.receipt == nil, candidate.conto.id == conto.id, candidate.type == type,
                          candidate.amount == amount, calendar.isDate(candidate.date, inSameDayAs: date) else { return false }
                    if type == .transfer { return candidate.destination?.id == destination?.id }
                    return (candidate.input.description ?? "") == (input.description ?? "")
                })
                if request.commit && duplicate && !request.allowDuplicates {
                    throw Failure("Possibile duplicato. Verifica l'anteprima; usa --allow-duplicates solo se voluto.")
                }
                validated.append(Validated(input: input, conto: conto, destination: destination, category: category, amount: amount,
                    date: date, type: type, frequency: frequency, endDate: endDate, digest: digest, receipt: receipt, duplicate: duplicate))
            } catch {
                throw Failure("Movimento \(index + 1): \(error.localizedDescription)")
            }
        }
        var rows: [Row] = []
        for item in validated {
            var transactionID = item.receipt?.transactionID
            if request.commit && item.receipt == nil {
                let transaction = Transaction(amount: item.amount, type: item.type, date: item.date,
                                              transactionDescription: item.input.description,
                                              isRecurring: item.frequency != nil,
                                              recurrenceFrequency: item.frequency, recurrenceEndDate: item.endDate)
                transaction.externalID = "formi-cli:\(item.input.requestID.uuidString)"
                if item.type == .transfer {
                    transaction.setFromConto(item.conto)
                    transaction.setToConto(item.destination)
                } else if item.type == .expense { transaction.setFromConto(item.conto) }
                else { transaction.setToConto(item.conto) }
                transaction.setCategory(item.category)
                context.insert(transaction)
                context.insert(RemoteExpenseReceipt(requestID: item.input.requestID, transactionID: transaction.id,
                    requestDigest: item.digest, createdAt: Date()))
                transactionID = transaction.id
            }
            rows.append(Row(requestID: item.input.requestID, transactionID: transactionID,
                accountID: item.conto.id, toAccountID: item.destination?.id, toAccount: item.destination?.name,
                account: item.conto.name ?? "Conto", category: item.category?.name,
                amount: item.input.amount, currency: item.input.currency, date: item.input.date,
                type: item.input.type, description: item.input.description,
                recurrence: item.input.recurrence, alreadyRecorded: item.receipt != nil, possibleDuplicate: item.duplicate))
        }
        if request.commit {
            do { try context.save() }
            catch { context.rollback(); throw error }
        }
        return Result(saved: request.commit, movements: rows)
    }

    private static func schedulesOverlap(_ first: Date, ending firstEnd: Date?,
                                         _ second: Date, ending secondEnd: Date?,
                                         frequency: RecurrenceFrequency, calendar: Calendar) -> Bool {
        let later = max(first, second)
        if let firstEnd, firstEnd < later { return false }
        if let secondEnd, secondEnd < later { return false }
        let earlier = min(first, second)
        guard let occurrence = RecurrenceSchedule.next(anchor: earlier, frequency: frequency,
            after: calendar.startOfDay(for: later).addingTimeInterval(-1), calendar: calendar) else { return false }
        return calendar.isDate(occurrence, inSameDayAs: later)
    }

    public struct RecurringRow: Codable, Sendable {
        public let transactionID: UUID
        public let accountID: UUID
        public let categoryID: UUID?
        public let amount: String
        public let type: String
        public let description: String?
        public let date: String
        public let recurrence: FormiCLIRecurrence
        public let nextDate: String?
    }

    public static func recurrences(_ request: FormiCLIRequest, container: ModelContainer,
                                   calendar: Calendar = .current, now: Date = Date()) throws -> [RecurringRow] {
        guard request.version == 2, request.command == "recurrences", !request.commit,
              request.movements.isEmpty, request.categoryMutation == nil, request.transactionQuery == nil else {
            throw Failure("Richiesta di lettura ricorrenze non valida.")
        }
        let context = ModelContext(container)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.isRecurring == true && $0.recurrenceSourceID == nil },
            sortBy: [SortDescriptor(\.date)] )).compactMap { transaction in
            let account = transaction.type == .expense ? transaction.fromConto : transaction.toConto
            guard transaction.type != .transfer, let account, let book = account.account,
                  account.isActive == true, book.isActive == true,
                  request.bookID == nil || request.bookID == book.id,
                  let frequency = transaction.recurrenceFrequency, let amount = transaction.amount else { return nil }
            return RecurringRow(transactionID: transaction.id, accountID: account.id,
                categoryID: transaction.categoryId ?? transaction.category?.id,
                amount: NSDecimalNumber(decimal: amount).stringValue, type: transaction.type.rawValue,
                description: transaction.transactionDescription, date: formatter.string(from: transaction.date),
                recurrence: .init(frequency: frequency.rawValue,
                    endDate: transaction.recurrenceEndDate.map { formatter.string(from: $0) }),
                nextDate: RecurrenceSchedule.next(anchor: transaction.date, frequency: frequency, after: now,
                    ending: transaction.recurrenceEndDate, calendar: calendar).map { formatter.string(from: $0) })
        }
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
