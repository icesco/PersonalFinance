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
    public var date: Date = Date()
    public var createdAt: Date?
    public var updatedAt: Date?
    public var transactionDescription: String?
    public var notes: String?
    public var isRecurring: Bool?
    public var recurrenceFrequency: RecurrenceFrequency?
    public var recurrenceEndDate: Date?

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
    public var fromConto: Conto? {
        didSet { fromContoId = fromConto?.id }
    }

    /// Destination account for income/transfer transactions
    public var toConto: Conto? {
        didSet { toContoId = toConto?.id }
    }

    /// Transaction category
    public var category: Category? {
        didSet { categoryId = category?.id }
    }
    
    // For transfers, we track both sides
    @Relationship(deleteRule: .cascade, inverse: \TransferLink.transaction)
    public var transferLinks: [TransferLink]?
    
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
        self.transferLinks = []
    }
    
    public var displayAmount: Decimal {
        guard let transactionAmount = amount else { return 0 }

        switch type {
        case .expense:
            return -transactionAmount
        case .income, .transfer:
            return transactionAmount
        }
    }
    
    public var isTransfer: Bool {
        type == .transfer
    }
    
    // Calcola la prossima data di ricorrenza
    public func nextRecurrenceDate() -> Date? {
        guard isRecurring == true,
              let frequency = recurrenceFrequency else { return nil }

        let calendar = Calendar.current
        let component = frequency.calendarComponent
        let value = frequency.componentValue

        return calendar.date(byAdding: component, value: value, to: date)
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
        guard isRecurring == true,
              let frequency = recurrenceFrequency else { return [] }

        var dates: [Date] = []
        let calendar = Calendar.current
        var currentDate = date
        
        let actualEndDate = recurrenceEndDate?.compare(endDate) == .orderedAscending ? 
                           recurrenceEndDate! : endDate
        
        while currentDate <= actualEndDate {
            if let nextDate = calendar.date(
                byAdding: frequency.calendarComponent,
                value: frequency.componentValue,
                to: currentDate
            ) {
                if nextDate <= actualEndDate {
                    dates.append(nextDate)
                }
                currentDate = nextDate
            } else {
                break
            }
        }
        
        return dates
    }
    
    public static func createTransfer(
        amount: Decimal,
        fromConto: Conto,
        toConto: Conto,
        date: Date = Date(),
        transactionDescription: String? = nil,
        notes: String? = nil
    ) -> (outgoing: Transaction, incoming: Transaction) {
        
        let outgoing = Transaction(
            amount: amount,
            type: .transfer,
            date: date,
            transactionDescription: transactionDescription,
            notes: notes
        )
        outgoing.fromConto = fromConto
        
        let incoming = Transaction(
            amount: amount,
            type: .transfer,
            date: date,
            transactionDescription: transactionDescription,
            notes: notes
        )
        incoming.toConto = toConto
        
        let outgoingLink = TransferLink(outgoingTransaction: outgoing, incomingTransaction: incoming)
        let incomingLink = TransferLink(outgoingTransaction: incoming, incomingTransaction: outgoing)
        outgoing.transferLinks?.append(outgoingLink)
        incoming.transferLinks?.append(incomingLink)
        
        return (outgoing, incoming)
    }
}

@Model
public final class TransferLink {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var createdAt: Date?
    
    public var transaction: Transaction?
    public var linkedTransactionId: UUID = UUID()
    
    public init(outgoingTransaction: Transaction, incomingTransaction: Transaction) {
        // id, externalID, linkedTransactionId now have default values
        self.createdAt = Date()
        self.transaction = outgoingTransaction
        self.linkedTransactionId = incomingTransaction.id
    }
}
    
