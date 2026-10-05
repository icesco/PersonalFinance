import Foundation

/// Pure balance calculations shared by the ledger history and its chart.
/// All functions are static, take value types, and return value types — no SwiftData dependency.
public struct BalanceCalculator: Sendable {

    // MARK: - Net Change

    /// Calculate the net balance change of a single transaction relative to a set of conto IDs.
    ///
    /// - Income to a conto in the set: +amount
    /// - Expense from a conto in the set: -amount
    /// - Transfer out (from set, to external): -amount
    /// - Transfer in (from external, to set): +amount
    /// - Transfer internal (both in set): 0 (cancels out)
    /// - Transfer external (neither in set): 0
    public static func netChange(for transaction: TransactionSnapshot, contiIDs: Set<UUID>) -> Decimal {
        let amount = transaction.amount
        switch transaction.type {
        case .income:
            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                return amount
            }
            return 0
        case .expense:
            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                return -amount
            }
            return 0
        case .transfer:
            if let from = transaction.fromContoId, let to = transaction.toContoId, contiIDs.contains(from), contiIDs.contains(to) { return 0 }
            var change: Decimal = 0
            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                change -= amount
            }
            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                change += transaction.destinationAmount ?? amount
            }
            return change
        }
    }

    // MARK: - Chart Y Domain

    /// Calculate the Y-axis domain for a chart with 10% padding.
    /// Positive-only data won't go below 0. Single-value data gets ±50 range.
    public static func chartYDomain(dataPoints: [BalanceDataPoint]) -> ClosedRange<Decimal> {
        guard !dataPoints.isEmpty else { return 0...100 }

        let values = dataPoints.map(\.balance)
        let minValue = values.min()!
        let maxValue = values.max()!

        if minValue == maxValue {
            return (minValue - 50)...(maxValue + 50)
        }

        let range = maxValue - minValue
        let padding = range * Decimal(string: "0.1")!

        let lowerBound = minValue >= 0 ? max(0, minValue - padding) : minValue - padding
        let upperBound = maxValue + padding

        return lowerBound...upperBound
    }

}
