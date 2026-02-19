import Foundation

/// Lightweight, immutable snapshot of a Transaction for pure calculations.
/// Decouples business logic from SwiftData model objects.
public struct TransactionSnapshot: Sendable {
    public let id: UUID
    public let amount: Decimal
    public let type: TransactionType
    public let date: Date
    public let fromContoId: UUID?
    public let toContoId: UUID?

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        type: TransactionType,
        date: Date,
        fromContoId: UUID? = nil,
        toContoId: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.date = date
        self.fromContoId = fromContoId
        self.toContoId = toContoId
    }
}

extension TransactionSnapshot {
    /// Create a snapshot from a SwiftData Transaction model object
    public init(from transaction: Transaction) {
        self.id = transaction.id
        self.amount = transaction.amount ?? 0
        self.type = transaction.type
        self.date = transaction.date
        self.fromContoId = transaction.fromContoId
        self.toContoId = transaction.toContoId
    }
}

/// Input representation of an Account (Libro) for pure calculations
public struct AccountInput: Sendable {
    public let id: UUID
    public let name: String
    public let contiIDs: Set<UUID>
    public let initialBalance: Decimal
    public let colorIndex: Int

    public init(id: UUID, name: String, contiIDs: Set<UUID>, initialBalance: Decimal, colorIndex: Int) {
        self.id = id
        self.name = name
        self.contiIDs = contiIDs
        self.initialBalance = initialBalance
        self.colorIndex = colorIndex
    }
}

/// Input representation of a Conto for pure calculations
public struct ContoInput: Sendable {
    public let id: UUID
    public let name: String
    public let initialBalance: Decimal
    public let colorIndex: Int

    public init(id: UUID, name: String, initialBalance: Decimal, colorIndex: Int) {
        self.id = id
        self.name = name
        self.initialBalance = initialBalance
        self.colorIndex = colorIndex
    }
}
