import Foundation

/// Lightweight, immutable snapshot of a Transaction for pure calculations.
/// Decouples business logic from SwiftData model objects.
public struct TransactionSnapshot: Sendable, Codable, Equatable {
    public let id: UUID
    public let amount: Decimal
    public let destinationAmount: Decimal?
    public let type: TransactionType
    public let date: Date
    public let fromContoId: UUID?
    public let toContoId: UUID?
    public let categoryID: UUID?

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        type: TransactionType,
        date: Date,
        fromContoId: UUID? = nil,
        toContoId: UUID? = nil,
        destinationAmount: Decimal? = nil,
        categoryID: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.destinationAmount = destinationAmount
        self.type = type
        self.date = date
        self.fromContoId = fromContoId
        self.toContoId = toContoId
        self.categoryID = categoryID
    }
}

extension TransactionSnapshot {
    /// Create a snapshot from a SwiftData Transaction model object
    public init(from transaction: Transaction) {
        self.id = transaction.id
        self.amount = transaction.amount ?? 0
        self.destinationAmount = transaction.destinationAmount
        self.type = transaction.type
        self.date = transaction.date
        self.fromContoId = transaction.fromContoId ?? transaction.fromConto?.id
        self.toContoId = transaction.toContoId ?? transaction.toConto?.id
        self.categoryID = transaction.categoryId ?? transaction.category?.id
    }
}
