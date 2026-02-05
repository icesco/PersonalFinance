import Foundation
import SwiftData

public enum ContoType: String, CaseIterable, Codable {
    case checking = "checking"
    case savings = "savings"
    case credit = "credit"
    case investment = "investment"
    case cash = "cash"
    case other = "other"
    
    public var displayName: String {
        switch self {
        case .checking: return "Conto Corrente"
        case .savings: return "Conto Risparmio"
        case .credit: return "Carta di Credito"
        case .investment: return "Investimenti"
        case .cash: return "Contanti"
        case .other: return "Altro"
        }
    }
    
    public var icon: String {
        switch self {
        case .checking: return "creditcard"
        case .savings: return "banknote"
        case .credit: return "creditcard.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .cash: return "dollarsign.circle"
        case .other: return "questionmark.circle"
        }
    }
}

@Model
public final class Conto {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var type: ContoType?
    public var initialBalance: Decimal?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isActive: Bool?
    public var contoDescription: String?
    public var color: String?
    
    public var account: Account?
    
    @Relationship(deleteRule: .cascade, inverse: \Transaction.fromConto)
    public var outgoingTransactions: [Transaction]?
    
    @Relationship(deleteRule: .cascade, inverse: \Transaction.toConto)
    public var incomingTransactions: [Transaction]?
    
    public init(
        name: String,
        type: ContoType,
        initialBalance: Decimal = 0,
        contoDescription: String? = nil,
        color: String? = nil
    ) {
        // id and externalID now have default values
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.contoDescription = contoDescription
        self.color = color
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.outgoingTransactions = []
        self.incomingTransactions = []
    }
    
    public var balance: Decimal {
        // Only sum transactions of the correct type to prevent incorrect balance calculations
        let incoming = (incomingTransactions ?? []).reduce(0) { sum, transaction in
            // Only income and incoming transfers should add to balance
            guard transaction.type == .income || transaction.type == .transfer else { return sum }
            return sum + (transaction.amount ?? 0)
        }

        let outgoing = (outgoingTransactions ?? []).reduce(0) { sum, transaction in
            // Only expenses and outgoing transfers should subtract from balance
            guard transaction.type == .expense || transaction.type == .transfer else { return sum }
            return sum + (transaction.amount ?? 0)
        }

        return (initialBalance ?? 0) + incoming - outgoing
    }
    
    public var allTransactions: [Transaction] {
        let incoming = incomingTransactions ?? []
        let outgoing = outgoingTransactions ?? []
        return (incoming + outgoing).sorted { $0.date > $1.date }
    }
}
