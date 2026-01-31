import Foundation
import SwiftData

/// Service for optimized budget calculations using indexed DB queries
public class BudgetService {

    /// Calculate spent amount for a budget in a specific period using optimized DB queries
    /// - Parameters:
    ///   - budget: The budget to calculate for
    ///   - period: The date range (start, end)
    ///   - context: ModelContext for database queries
    /// - Returns: Total spent amount for the budget's categories in the period
    @MainActor
    public static func calculateSpent(
        for budget: Budget,
        period: (start: Date, end: Date),
        in context: ModelContext
    ) throws -> Decimal {
        let categoryIds = (budget.categories ?? []).map { $0.id }
        guard !categoryIds.isEmpty else { return 0 }

        var totalSpent: Decimal = 0

        // Query transactions using indexed fields (categoryId, date, typeRaw)
        // This is much more efficient than loading via relationships
        for categoryId in categoryIds {
            let start = period.start
            let end = period.end
            let expenseType = TransactionType.expense.rawValue

            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { transaction in
                    transaction.categoryId == categoryId &&
                    transaction.date >= start &&
                    transaction.date <= end &&
                    transaction.typeRaw == expenseType
                }
            )

            let transactions = try context.fetch(descriptor)
            totalSpent += transactions.reduce(0) { $0 + ($1.amount ?? 0) }
        }

        // Include recurring transactions if enabled
        if budget.includeRecurringTransactions == true {
            totalSpent += try calculateRecurringSpent(
                categoryIds: categoryIds,
                period: period,
                in: context
            )
        }

        return totalSpent
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

    // MARK: - Private Helpers

    @MainActor
    private static func calculateRecurringSpent(
        categoryIds: [UUID],
        period: (start: Date, end: Date),
        in context: ModelContext
    ) throws -> Decimal {
        var recurringTotal: Decimal = 0

        for categoryId in categoryIds {
            let expenseType = TransactionType.expense.rawValue

            // Fetch recurring expense transactions for this category
            let descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { transaction in
                    transaction.categoryId == categoryId &&
                    transaction.typeRaw == expenseType &&
                    transaction.isRecurring == true
                }
            )

            let recurringTransactions = try context.fetch(descriptor)

            // Calculate projected occurrences in the period
            for transaction in recurringTransactions where transaction.isRecurrenceActive() {
                let occurrences = transaction.generateRecurrenceDates(until: period.end)
                    .filter { $0 >= period.start && $0 <= period.end }
                recurringTotal += Decimal(occurrences.count) * (transaction.amount ?? 0)
            }
        }

        return recurringTotal
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
