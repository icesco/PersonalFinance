import Foundation
import SwiftData

public enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"     // Ogni due settimane
    case monthly = "monthly"
    case quarterly = "quarterly"   // Ogni tre mesi
    case semiannually = "semiannually" // Ogni sei mesi
    case yearly = "yearly"
    
    public var displayName: String {
        switch self {
        case .daily: return "Giornaliera"
        case .weekly: return "Settimanale"
        case .biweekly: return "Ogni 2 settimane"
        case .monthly: return "Mensile"
        case .quarterly: return "Trimestrale"
        case .semiannually: return "Semestrale"
        case .yearly: return "Annuale"
        }
    }
    
    public var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .biweekly: return .weekOfYear
        case .monthly: return .month
        case .quarterly: return .month
        case .semiannually: return .month
        case .yearly: return .year
        }
    }
    
    /// Average occurrences per year, used to compare series of different frequencies.
    public var occurrencesPerYear: Decimal {
        switch self {
        case .daily: return 365
        case .weekly: return 52
        case .biweekly: return 26
        case .monthly: return 12
        case .quarterly: return 4
        case .semiannually: return 2
        case .yearly: return 1
        }
    }

    /// Average monthly amount of a series repeating `amount` at this frequency.
    public func monthlyEquivalent(of amount: Decimal) -> Decimal {
        amount * occurrencesPerYear / 12
    }

    public var componentValue: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 1
        case .biweekly: return 2
        case .monthly: return 1
        case .quarterly: return 3
        case .semiannually: return 6
        case .yearly: return 1
        }
    }
}

public enum TransactionType: String, CaseIterable, Codable, Sendable {
    case income = "income"
    case expense = "expense"
    case transfer = "transfer"
    
    public var displayName: String {
        switch self {
        case .income: return "Entrata"
        case .expense: return "Spesa"
        case .transfer: return "Trasferimento"
        }
    }
    
    public var icon: String {
        switch self {
        case .income: return "arrow.down.circle.fill"
        case .expense: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}

@Model
public final class Transaction {
    // Indexes for fast queries - using denormalized fields for DB-level filtering
    #Index<Transaction>([\.date], [\.typeRaw], [\.fromContoId], [\.toContoId], [\.categoryId])

    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var amount: Decimal?
    /// Amount credited by a cross-currency transfer; nil retains legacy same-currency behavior.
    public var destinationAmount: Decimal?
    /// An actual interest credit is income, but is not a savings contribution.
    public var isSavingsInterest: Bool?
    public var date: Date = Date()
    public var createdAt: Date?
    public var updatedAt: Date?
    public var transactionDescription: String?
    public var notes: String?
    public var originalAmount: Decimal?
    public var originalCurrency: String?
    public var exchangeRate: Decimal?
    public var exchangeRateDate: String?
    public var exchangeRateSource: String?
    public var placeName: String?
    public var latitude: Double?
    public var longitude: Double?
    public var locationAccuracy: Double?
    public var isRecurring: Bool?
    public var recurrenceFrequency: RecurrenceFrequency?
    public var recurrenceEndDate: Date?
    /// Set on a realized occurrence; it must not generate another recurring series.
    public var recurrenceSourceID: UUID?

    // MARK: - Denormalized fields for indexing (keep in sync with relationships)

    /// Raw string value of type for indexing (use `type` property for access)
    public var typeRaw: String = TransactionType.expense.rawValue

    /// Denormalized fromConto ID for indexed queries
    public var fromContoId: UUID?

    /// Denormalized toConto ID for indexed queries
    public var toContoId: UUID?

    /// Denormalized category ID for indexed queries
    public var categoryId: UUID?

    // MARK: - Computed property for type (synced with typeRaw)

    /// Transaction type (automatically syncs with typeRaw for indexing)
    public var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Relationships

    /// Source account for expense/transfer transactions
    public var fromConto: Conto?

    /// Destination account for income/transfer transactions
    public var toConto: Conto?

    /// Transaction category
    public var category: Category?

    @Relationship(deleteRule: .cascade, inverse: \TransactionAttachment.transaction)
    public var attachments: [TransactionAttachment]?

    // MARK: - Relationship Setters (use these to keep denormalized IDs in sync)

    /// Set the source conto and sync the denormalized ID
    public func setFromConto(_ conto: Conto?) {
        self.fromConto = conto
        self.fromContoId = conto?.id
    }

    /// Set the destination conto and sync the denormalized ID
    public func setToConto(_ conto: Conto?) {
        self.toConto = conto
        self.toContoId = conto?.id
    }

    /// Set the category and sync the denormalized ID
    public func setCategory(_ category: Category?) {
        self.category = category
        self.categoryId = category?.id
    }

    public init(
        amount: Decimal,
        type: TransactionType,
        date: Date = Date(),
        transactionDescription: String? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        recurrenceFrequency: RecurrenceFrequency? = nil,
        recurrenceEndDate: Date? = nil
    ) {
        // id and externalID now have default values
        self.amount = amount
        self.type = type
        self.date = date
        self.transactionDescription = transactionDescription
        self.notes = notes
        self.isRecurring = isRecurring
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceEndDate = recurrenceEndDate
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Display amount (negative for expenses, positive for income)
    /// For transfers, use `displayAmount(for:)` to get the correct sign based on perspective
    public var displayAmount: Decimal {
        guard let transactionAmount = amount else { return 0 }

        switch type {
        case .expense:
            return -transactionAmount
        case .income:
            return transactionAmount
        case .transfer:
            // Default: show as positive, use displayAmount(for:) for perspective
            return transactionAmount
        }
    }

    /// Display amount from the perspective of a specific conto
    /// - Parameter contoId: The conto ID to calculate the amount for
    /// - Returns: Negative if money leaves this conto, positive if money enters
    public func displayAmount(for contoId: UUID) -> Decimal {
        guard let transactionAmount = amount else { return 0 }

        switch type {
        case .expense:
            return -transactionAmount
        case .income:
            return transactionAmount
        case .transfer:
            if fromContoId == contoId {
                return -transactionAmount  // Money leaving this conto
            } else if toContoId == contoId {
                return destinationAmount ?? transactionAmount   // Money entering this conto
            }
            return transactionAmount
        }
    }

    public var isTransfer: Bool {
        type == .transfer
    }
    
    // Calcola la prossima data di ricorrenza
    public func nextRecurrenceDate(after referenceDate: Date = Date()) -> Date? {
        guard isRecurring == true,
              let frequency = recurrenceFrequency else { return nil }

        return RecurrenceSchedule.next(anchor: date, frequency: frequency, after: referenceDate, ending: recurrenceEndDate)
    }

    /// Scheduled occurrences after the reference date, without changing recorded transactions.
    public func recurrenceDates(after referenceDate: Date, through endDate: Date) -> [Date] {
        guard isRecurring == true, let frequency = recurrenceFrequency else { return [] }
        return RecurrenceSchedule.dates(anchor: date, frequency: frequency, after: referenceDate,
                                        through: endDate, ending: recurrenceEndDate)
    }

    // Verifica se la ricorrenza è ancora attiva
    public func isRecurrenceActive() -> Bool {
        guard isRecurring == true else { return false }
        
        if let endDate = recurrenceEndDate {
            return Date() <= endDate
        }
        
        return true // Ricorrenza infinita se non c'è end date
    }
    
    // Genera tutte le date di ricorrenza fino a una data specifica
    public func generateRecurrenceDates(until endDate: Date) -> [Date] {
        recurrenceDates(after: date, through: endDate)
    }
    
    /// Create a transfer transaction between two conti
    /// - Returns: A single Transaction with both fromConto and toConto set
    public static func createTransfer(
        amount: Decimal,
        fromConto: Conto,
        toConto: Conto,
        date: Date = Date(),
        transactionDescription: String? = nil,
        notes: String? = nil
    ) -> Transaction {
        let transfer = Transaction(
            amount: amount,
            type: .transfer,
            date: date,
            transactionDescription: transactionDescription,
            notes: notes
        )
        transfer.setFromConto(fromConto)
        transfer.setToConto(toConto)
        return transfer
    }
}
