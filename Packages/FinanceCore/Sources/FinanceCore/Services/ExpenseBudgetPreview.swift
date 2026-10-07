import Foundation

public struct ExpenseBudgetPreview: Identifiable {
    public enum Status { case withinLimit, approachingLimit, atLimit, overLimit }
    public let id: UUID
    public let name: String
    public let limit: Decimal
    public let spent: Decimal
    public let proposedAmount: Decimal
    public let threshold: Double
    public let period: DateInterval

    public var remaining: Decimal { limit - spent - proposedAmount }
    public var status: Status {
        if remaining < 0 { return .overLimit }
        if remaining == 0 { return .atLimit }
        if limit > 0, spent + proposedAmount >= limit * Decimal(threshold) { return .approachingLimit }
        return .withinLimit
    }
}

extension BudgetPeriod {
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .weekly: calendar.dateInterval(of: .weekOfYear, for: date)
        case .monthly: calendar.dateInterval(of: .month, for: date)
        case .quarterly: calendar.dateInterval(of: .quarter, for: date)
        case .yearly: calendar.dateInterval(of: .year, for: date)
        }
    }
}

extension BudgetService {
    /// Preview a new or edited expense without saving it. Exclude the original ID
    /// when editing so the proposed amount replaces it. Includes every category in each matching
    /// budget and only recorded entries, never additional projected recurrence occurrences.
    @MainActor
    public static func previewExpense(
        amount: Decimal, categoryID: UUID, accountID: UUID,
        date: Date, budgets: [Budget], transactions: [Transaction],
        calendar: Calendar = .current, excludingTransactionID: UUID? = nil
    ) -> [ExpenseBudgetPreview] {
        guard amount > 0 else { return [] }
        return budgets.compactMap { budget -> ExpenseBudgetPreview? in
            guard budget.isActive == true, budget.account?.id == accountID,
                  let limit = budget.amount, limit >= 0,
                  let interval = budget.period?.interval(containing: date, calendar: calendar) else { return nil }
            guard budget.coveredCategoryIDs.contains(categoryID) else { return nil }
            let spent = RecordedBudgetSpending.total(
                for: budget, transactions: transactions, start: interval.start, end: interval.end,
                excludingTransactionID: excludingTransactionID
            )
            return ExpenseBudgetPreview(
                id: budget.id, name: budget.name ?? "Budget", limit: limit,
                spent: spent, proposedAmount: amount,
                threshold: min(1, max(0, budget.alertThreshold ?? 0.8)), period: interval
            )
        }.sorted {
            if $0.remaining == $1.remaining { return $0.id.uuidString < $1.id.uuidString }
            return $0.remaining < $1.remaining
        }
    }
}
