import Foundation
import SwiftData

/// Service for optimized budget calculations using indexed DB queries
public class BudgetService {

    /// Calculate spent amount for a budget in a specific period using optimized DB queries
    /// - Parameters:
    ///   - budget: The budget to calculate for
    ///   - period: The date range (start, end)
    ///   - context: ModelContext for database queries
    /// The end date is exclusive. Relationship fallbacks support legacy ledger entries.
    /// - Returns: Total spent amount for the budget's categories in the period
    @MainActor
    public static func calculateSpent(
        for budget: Budget,
        period: (start: Date, end: Date),
        in context: ModelContext
    ) throws -> Decimal {
        let start = period.start
        let end = period.end
        let expenseType = TransactionType.expense.rawValue
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.typeRaw == expenseType
        })
        return RecordedBudgetSpending.total(
            for: budget, transactions: try context.fetch(descriptor), start: start, end: end
        )
    }

    /// Calculate current period spent for a budget
    @MainActor
    public static func currentSpent(
        for budget: Budget,
        in context: ModelContext
    ) throws -> Decimal {
        return try calculateSpent(for: budget, period: budget.currentPeriodRange, in: context)
    }

    /// Calculate previous period spent for comparison
    @MainActor
    public static func previousPeriodSpent(
        for budget: Budget,
        in context: ModelContext
    ) throws -> Decimal {
        return try calculateSpent(for: budget, period: budget.previousPeriodRange, in: context)
    }

}

// MARK: - Budget Extension for convenient access

extension Budget {
    /// Get current spent using optimized DB query (requires ModelContext)
    @MainActor
    public func getCurrentSpent(in context: ModelContext) throws -> Decimal {
        return try BudgetService.currentSpent(for: self, in: context)
    }

    /// Get previous period spent using optimized DB query (requires ModelContext)
    @MainActor
    public func getPreviousPeriodSpent(in context: ModelContext) throws -> Decimal {
        return try BudgetService.previousPeriodSpent(for: self, in: context)
    }

    /// Get remaining amount using optimized DB query (requires ModelContext)
    @MainActor
    public func getRemainingAmount(in context: ModelContext) throws -> Decimal {
        guard let budgetAmount = amount else { return 0 }
        return budgetAmount - (try getCurrentSpent(in: context))
    }

    /// Get spent percentage using optimized DB query (requires ModelContext)
    @MainActor
    public func getSpentPercentage(in context: ModelContext) throws -> Double {
        guard let budgetAmount = amount, budgetAmount > 0 else { return 0 }
        let spent = try getCurrentSpent(in: context)
        return NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: budgetAmount).doubleValue
    }

    /// Check if over budget using optimized DB query (requires ModelContext)
    @MainActor
    public func isOverBudget(in context: ModelContext) throws -> Bool {
        guard let budgetAmount = amount else { return false }
        return try getCurrentSpent(in: context) > budgetAmount
    }

    /// Check if should alert using optimized DB query (requires ModelContext)
    @MainActor
    public func shouldAlert(in context: ModelContext) throws -> Bool {
        guard let threshold = alertThreshold else { return false }
        return try getSpentPercentage(in: context) >= threshold
    }
}
