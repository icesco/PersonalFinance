import Foundation
import SwiftData

/// Service for calculating account statistics on-demand using optimized DB queries
public class StatisticsService {

    // MARK: - Calculate Statistics On-Demand

    /// Calculate statistics for an account for a specific period
    /// Returns computed results - nothing is persisted to database
    @MainActor
    public static func calculateStatistics(
        for account: Account,
        period: StatisticsPeriod = .currentMonth,
        in context: ModelContext
    ) throws -> AccountStatisticsResult {
        let transactions = try getTransactionsForPeriod(account: account, period: period, in: context)

        // Separate by type
        let incomeTransactions = transactions.filter { $0.type == .income }
        let expenseTransactions = transactions.filter { $0.type == .expense }
        let transferTransactions = transactions.filter { $0.type == .transfer }

        // Calculate totals
        let totalIncome = incomeTransactions.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        let totalExpenses = expenseTransactions.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

        // Calculate top categories
        let topExpenses = calculateTopCategories(from: expenseTransactions, in: context)
        let topIncome = calculateTopCategories(from: incomeTransactions, in: context)

        return AccountStatisticsResult(
            accountId: account.id,
            period: period,
            totalBalance: account.totalBalance,
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            transactionCount: transactions.count,
            incomeTransactionCount: incomeTransactions.count,
            expenseTransactionCount: expenseTransactions.count,
            transferTransactionCount: transferTransactions.count,
            topExpenseCategories: topExpenses,
            topIncomeCategories: topIncome
        )
    }

    /// Calculate current month statistics
    @MainActor
    public static func currentMonthStatistics(
        for account: Account,
        in context: ModelContext
    ) throws -> AccountStatisticsResult {
        return try calculateStatistics(for: account, period: .currentMonth, in: context)
    }

    /// Calculate current year statistics
    @MainActor
    public static func currentYearStatistics(
        for account: Account,
        in context: ModelContext
    ) throws -> AccountStatisticsResult {
        return try calculateStatistics(for: account, period: .currentYear, in: context)
    }

    // MARK: - Quick Totals (Optimized for Dashboard)

    /// Get just income/expense totals for a period (faster than full statistics)
    @MainActor
    public static func getTotals(
        for account: Account,
        period: StatisticsPeriod = .currentMonth,
        in context: ModelContext
    ) throws -> (income: Decimal, expenses: Decimal) {
        guard let conti = account.conti else { return (0, 0) }
        let dateRange = period.dateRange

        var totalIncome: Decimal = 0
        var totalExpenses: Decimal = 0

        let incomeType = TransactionType.income.rawValue
        let expenseType = TransactionType.expense.rawValue

        for conto in conti {
            let contoId = conto.id

            if let start = dateRange.start, let end = dateRange.end {
                // Income: transactions where this conto is toConto
                let incomeDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toContoId == contoId &&
                        transaction.typeRaw == incomeType &&
                        transaction.date >= start &&
                        transaction.date < end
                    }
                )
                totalIncome += try context.fetch(incomeDescriptor).reduce(0) { $0 + ($1.amount ?? 0) }

                // Expenses: transactions where this conto is fromConto
                let expenseDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromContoId == contoId &&
                        transaction.typeRaw == expenseType &&
                        transaction.date >= start &&
                        transaction.date < end
                    }
                )
                totalExpenses += try context.fetch(expenseDescriptor).reduce(0) { $0 + ($1.amount ?? 0) }
            } else {
                // All time
                let incomeDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toContoId == contoId &&
                        transaction.typeRaw == incomeType
                    }
                )
                totalIncome += try context.fetch(incomeDescriptor).reduce(0) { $0 + ($1.amount ?? 0) }

                let expenseDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromContoId == contoId &&
                        transaction.typeRaw == expenseType
                    }
                )
                totalExpenses += try context.fetch(expenseDescriptor).reduce(0) { $0 + ($1.amount ?? 0) }
            }
        }

        return (totalIncome, totalExpenses)
    }

    // MARK: - Private Helpers

    @MainActor
    private static func getTransactionsForPeriod(
        account: Account,
        period: StatisticsPeriod,
        in context: ModelContext
    ) throws -> [Transaction] {
        guard let conti = account.conti else { return [] }

        var allTransactions: [Transaction] = []
        let dateRange = period.dateRange

        // Fetch transactions for each conto using indexed fields
        for conto in conti {
            let contoId = conto.id

            if let start = dateRange.start, let end = dateRange.end {
                // With date filter
                let fromDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromContoId == contoId &&
                        transaction.date >= start &&
                        transaction.date < end
                    }
                )
                let toDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toContoId == contoId &&
                        transaction.date >= start &&
                        transaction.date < end
                    }
                )

                allTransactions.append(contentsOf: try context.fetch(fromDescriptor))
                allTransactions.append(contentsOf: try context.fetch(toDescriptor))
            } else {
                // No date filter (all time)
                let fromDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromContoId == contoId
                    }
                )
                let toDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toContoId == contoId
                    }
                )

                allTransactions.append(contentsOf: try context.fetch(fromDescriptor))
                allTransactions.append(contentsOf: try context.fetch(toDescriptor))
            }
        }

        // Remove duplicates (transfers could appear in both from and to)
        var seen = Set<UUID>()
        return allTransactions.filter { transaction in
            if seen.contains(transaction.id) {
                return false
            }
            seen.insert(transaction.id)
            return true
        }
    }

    @MainActor
    private static func calculateTopCategories(
        from transactions: [Transaction],
        in context: ModelContext
    ) -> [CategoryAmount] {
        // Group by category
        var amountsByCategory: [UUID: Decimal] = [:]

        for transaction in transactions {
            guard let categoryId = transaction.categoryId,
                  let amount = transaction.amount else { continue }
            amountsByCategory[categoryId, default: 0] += amount
        }

        // Sort by amount and take top 5
        let sortedCategories = amountsByCategory.sorted { $0.value > $1.value }.prefix(5)

        // Fetch category details
        var results: [CategoryAmount] = []
        for (categoryId, amount) in sortedCategories {
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.id == categoryId }
            )
            if let category = try? context.fetch(descriptor).first {
                results.append(CategoryAmount(
                    id: categoryId,
                    name: category.name ?? "Unknown",
                    amount: amount,
                    color: category.color
                ))
            }
        }

        return results
    }

    // MARK: - Deprecated Methods (For Backwards Compatibility)

    /// Deprecated: Statistics are now calculated on-demand, no need to update
    @available(*, deprecated, message: "Statistics are now calculated on-demand. This method does nothing.")
    @MainActor
    public static func updateStatistics(
        for account: Account,
        period: StatisticsPeriod = .currentMonth,
        in context: ModelContext
    ) async throws {
        // No-op: statistics are now calculated on-demand
    }

    /// Deprecated: Statistics are now calculated on-demand, no need to update
    @available(*, deprecated, message: "Statistics are now calculated on-demand. This method does nothing.")
    @MainActor
    public static func updateAllAccountStatistics(
        for period: StatisticsPeriod = .currentMonth,
        in context: ModelContext
    ) async throws {
        // No-op: statistics are now calculated on-demand
    }

    /// Deprecated: Statistics are now calculated on-demand, no need to clean
    @available(*, deprecated, message: "Statistics are no longer persisted. This method does nothing.")
    @MainActor
    public static func cleanOldStatistics(in context: ModelContext) throws {
        // No-op: statistics are no longer persisted
    }
}

// MARK: - Account Extension

extension Account {
    /// Get current month statistics (calculated on-demand)
    @MainActor
    public func getCurrentMonthStatistics(in context: ModelContext) throws -> AccountStatisticsResult {
        return try StatisticsService.currentMonthStatistics(for: self, in: context)
    }

    /// Get statistics for a specific period (calculated on-demand)
    @MainActor
    public func getStatistics(for period: StatisticsPeriod, in context: ModelContext) throws -> AccountStatisticsResult {
        return try StatisticsService.calculateStatistics(for: self, period: period, in: context)
    }

    /// Get quick totals for dashboard (optimized query)
    @MainActor
    public func getTotals(for period: StatisticsPeriod = .currentMonth, in context: ModelContext) throws -> (income: Decimal, expenses: Decimal) {
        return try StatisticsService.getTotals(for: self, period: period, in: context)
    }
}
