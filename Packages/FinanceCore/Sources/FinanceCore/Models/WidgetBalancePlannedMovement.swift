import Foundation

public struct WidgetBalancePlannedMovement: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let title: String
    public let amount: Decimal?
    public let type: TransactionType
    public let fromAccountID: UUID?
    public let toAccountID: UUID?
    public let destinationAmount: Decimal?
    public let categoryIcon: String?
    public let categoryColor: String?

    public init(id: String, date: Date, title: String, amount: Decimal?, type: TransactionType,
                fromAccountID: UUID? = nil, toAccountID: UUID? = nil, destinationAmount: Decimal? = nil,
                categoryIcon: String? = nil, categoryColor: String? = nil) {
        self.id = id; self.date = date; self.title = title; self.amount = amount; self.type = type
        self.fromAccountID = fromAccountID; self.toAccountID = toAccountID
        self.destinationAmount = destinationAmount; self.categoryIcon = categoryIcon; self.categoryColor = categoryColor
    }

    public func involves(accountIDs: Set<UUID>) -> Bool {
        switch type {
        case .income: toAccountID.map(accountIDs.contains) ?? false
        case .expense: fromAccountID.map(accountIDs.contains) ?? false
        case .transfer: (fromAccountID.map(accountIDs.contains) ?? false) || (toAccountID.map(accountIDs.contains) ?? false)
        }
    }

    public func isInternalTransfer(accountIDs: Set<UUID>) -> Bool {
        type == .transfer && (fromAccountID.map(accountIDs.contains) ?? false) && (toAccountID.map(accountIDs.contains) ?? false)
    }

    public func netChange(accountIDs: Set<UUID>) -> Decimal? {
        guard involves(accountIDs: accountIDs), !isInternalTransfer(accountIDs: accountIDs) else { return 0 }
        guard let amount, !amount.isNaN, destinationAmount?.isNaN != true else { return nil }
        return BalanceCalculator.netChange(for: TransactionSnapshot(amount: amount, type: type, date: date,
            fromContoId: fromAccountID, toContoId: toAccountID, destinationAmount: destinationAmount), contiIDs: accountIDs)
    }
}

public struct WidgetBalanceScheduledFlows: Equatable, Sendable {
    public let incoming: Decimal?
    public let outgoing: Decimal?
}

public struct WidgetBalanceFlowGroup: Codable, Equatable, Sendable {
    public let movement: WidgetBalancePlannedMovement
    public let count: Int
}
