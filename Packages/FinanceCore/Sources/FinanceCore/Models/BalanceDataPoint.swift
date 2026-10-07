import Foundation

/// A single data point in a balance history chart
public struct BalanceDataPoint: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let balance: Decimal

    public init(id: UUID = UUID(), date: Date, balance: Decimal) {
        self.id = id
        self.date = date
        self.balance = balance
    }
}
