import Foundation

/// Value-only messages also compiled by the Watch app, without SwiftData.
public struct RemoteExpenseInput: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let bookID: UUID
    public let contoID: UUID
    public let categoryID: UUID
    public let amount: Decimal
    public let currency: String
    public let date: Date
    public let note: String

    public init(requestID: UUID, bookID: UUID, contoID: UUID, categoryID: UUID,
                amount: Decimal, currency: String, date: Date, note: String) {
        self.requestID = requestID; self.bookID = bookID; self.contoID = contoID
        self.categoryID = categoryID; self.amount = amount; self.currency = currency
        self.date = date; self.note = note
    }
}

public struct RemoteExpenseBudget: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let limit: Decimal
    public let spent: Decimal
    public let remaining: Decimal
    public let threshold: Double
    public let period: DateInterval
}

public struct RemoteExpenseQuote: Codable, Equatable, Sendable {
    public let input: RemoteExpenseInput
    public let issuedAt: Date
    public let bookName: String
    public let contoName: String
    public let categoryName: String
    public let budgets: [RemoteExpenseBudget]
}

public struct RemoteExpenseSaveResult: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let alreadyRecorded: Bool
}
