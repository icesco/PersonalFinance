import Foundation

/// A single data point in a balance history chart
public struct BalanceDataPoint: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let balance: Decimal

    public init(id: UUID = UUID(), date: Date, balance: Decimal) {
        self.id = id
        self.date = date
        self.balance = balance
    }
}

/// A balance data point associated with a specific account or conto, for multi-line charts.
/// Uses `colorIndex` instead of SwiftUI `Color` to keep FinanceCore free of SwiftUI.
public struct AccountBalanceDataPoint: Identifiable, Sendable {
    public let id: UUID
    public let accountId: UUID
    public let accountName: String
    public let date: Date
    public let balance: Decimal
    public let colorIndex: Int

    public init(
        id: UUID = UUID(),
        accountId: UUID,
        accountName: String,
        date: Date,
        balance: Decimal,
        colorIndex: Int
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.date = date
        self.balance = balance
        self.colorIndex = colorIndex
    }
}
