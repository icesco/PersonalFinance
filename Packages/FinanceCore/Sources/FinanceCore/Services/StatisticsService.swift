import Foundation
import SwiftData

public class StatisticsService {
    
    // MARK: - Calculate Statistics
    
    /// Calculate and update statistics for an account for a specific period
    @MainActor
    public static func updateStatistics(
        for account: Account,
        period: StatisticsPeriod = .monthly(year: Calendar.current.component(.year, from: Date()),
                                          month: Calendar.current.component(.month, from: Date())),
        in context: ModelContext
    ) async throws {
        
        // Find existing statistics or create new
        let existingStats = try findExistingStatistics(for: account, period: period, in: context)
        let statistics = existingStats ?? period.createStatistics(for: account)
        
        // Calculate all the values
        try await calculateStatistics(statistics, for: account, period: period, in: context)
        
        // Save or update
        if existingStats == nil {
            context.insert(statistics)
        }
        
        try context.save()
    }
    
    /// Get current month statistics for an account
    @MainActor
    public static func getCurrentMonthStatistics(
        for account: Account,
        in context: ModelContext
    ) throws -> AccountStatistics? {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        
        let period = StatisticsPeriod.monthly(year: year, month: month)
        return try findExistingStatistics(for: account, period: period, in: context)
    }
    
    /// Get or create current month statistics for an account
    @MainActor
    public static func getOrCreateCurrentMonthStatistics(
        for account: Account,
        in context: ModelContext
    ) async throws -> AccountStatistics {
        if let existing = try getCurrentMonthStatistics(for: account, in: context) {
            return existing
        }
        
        // Create and calculate new statistics
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let period = StatisticsPeriod.monthly(year: year, month: month)
        
        let statistics = period.createStatistics(for: account)
        try await calculateStatistics(statistics, for: account, period: period, in: context)
        
        context.insert(statistics)
        try context.save()
        
        return statistics
    }
    
    // MARK: - Private Helper Methods
    
    @MainActor
    private static func findExistingStatistics(
        for account: Account,
        period: StatisticsPeriod,
        in context: ModelContext
    ) throws -> AccountStatistics? {
        
        let predicate: Predicate<AccountStatistics>
        
        switch period {
        case .daily(let date):
            let accountId = account.id
            let startOfDay = Calendar.current.startOfDay(for: date)
            predicate = #Predicate { stats in
                stats.account?.id == accountId &&
                stats.day == startOfDay
            }
            
        case .weekly(let year, let week):
            let accountId = account.id
            predicate = #Predicate { stats in
                stats.account?.id == accountId &&
                stats.year == year &&
                stats.week == week
            }
            
        case .monthly(let year, let month):
            let accountId = account.id
            predicate = #Predicate { stats in
                stats.account?.id == accountId &&
                stats.year == year &&
                stats.month == month
            }
            
        case .yearly(let year):
            let accountId = account.id
            predicate = #Predicate { stats in
                stats.account?.id == accountId &&
                stats.year == year &&
                stats.month == nil &&
                stats.week == nil
            }
            
        case .allTime:
            let accountId = account.id
            predicate = #Predicate { stats in
                stats.account?.id == accountId &&
                stats.year == nil
            }
        }
        
        let descriptor = FetchDescriptor<AccountStatistics>(predicate: predicate)
        let results = try context.fetch(descriptor)
        return results.first
    }
    
    @MainActor
    private static func calculateStatistics(
        _ statistics: AccountStatistics,
        for account: Account,
        period: StatisticsPeriod,
        in context: ModelContext
    ) async throws {
        
        // Get all transactions for the account in the period
        let transactions = try getTransactionsForPeriod(account: account, period: period, in: context)
        
        // Calculate basic statistics
        statistics.transactionCount = transactions.count
        statistics.totalBalance = account.totalBalance
        
        // Separate by type
        let incomeTransactions = transactions.filter { $0.type == .income }
        let expenseTransactions = transactions.filter { $0.type == .expense }
        let transferTransactions = transactions.filter { $0.type == .transfer }
        
        statistics.incomeTransactionCount = incomeTransactions.count
        statistics.expenseTransactionCount = expenseTransactions.count
        statistics.transferTransactionCount = transferTransactions.count
        
        // Calculate totals
        statistics.totalIncome = incomeTransactions.reduce(0) { $0 + ($1.amount ?? 0) }
        statistics.totalExpenses = expenseTransactions.reduce(0) { $0 + ($1.amount ?? 0) }
        statistics.netIncome = (statistics.totalIncome ?? 0) - (statistics.totalExpenses ?? 0)
        
        // For monthly statistics, also calculate monthly values
        if case .monthly = period {
            statistics.monthlyIncome = statistics.totalIncome
            statistics.monthlyExpenses = statistics.totalExpenses
            statistics.monthlySavings = statistics.netIncome
        }
        
        // Calculate top categories
        try calculateTopCategories(statistics, transactions: transactions)
        
        // Update metadata
        statistics.calculatedAt = Date()
        statistics.updatedAt = Date()
        statistics.lastTransactionDate = transactions.compactMap { $0.date }.max()
    }
    
    private static func getTransactionsForPeriod(
        account: Account,
        period: StatisticsPeriod,
        in context: ModelContext
    ) throws -> [Transaction] {

        let dateRange = getDateRange(for: period)
        guard let conti = account.conti else { return [] }

        var allTransactions: [Transaction] = []

        // Fetch transactions separately for each conto to avoid OR predicate issues
        // This is more efficient than fetching all transactions and filtering in-memory
        for conto in conti {
            let contoId = conto.id

            if let start = dateRange.start, let end = dateRange.end {
                // Query with both conto and date filters at DB level
                let fromDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromConto?.id == contoId
                    }
                )
                let toDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toConto?.id == contoId
                    }
                )

                let fromTransactions = try context.fetch(fromDescriptor)
                let toTransactions = try context.fetch(toDescriptor)

                // Filter by date in-memory (single optional chain is fast)
                allTransactions.append(contentsOf: fromTransactions.filter {
                    if let date = $0.date {
                        return date >= start && date < end
                    }
                    return false
                })
                allTransactions.append(contentsOf: toTransactions.filter {
                    if let date = $0.date {
                        return date >= start && date < end
                    }
                    return false
                })
            } else {
                // No date filter - fetch all for this conto
                let fromDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.fromConto?.id == contoId
                    }
                )
                let toDescriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.toConto?.id == contoId
                    }
                )

                allTransactions.append(contentsOf: try context.fetch(fromDescriptor))
                allTransactions.append(contentsOf: try context.fetch(toDescriptor))
            }
        }

        // Remove duplicates (a transfer could appear in both from and to)
        let uniqueTransactions = Array(Set(allTransactions.map { $0.id }))
            .compactMap { id in allTransactions.first { $0.id == id } }

        return uniqueTransactions
    }
    
    private static func getDateRange(for period: StatisticsPeriod) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        
        switch period {
        case .daily(let date):
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            return (startOfDay, endOfDay)
            
        case .weekly(let year, let week):
            let dateComponents = DateComponents(weekOfYear: week, yearForWeekOfYear: year)
            guard let startOfWeek = calendar.date(from: dateComponents) else { return (nil, nil) }
            let endOfWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek)
            return (startOfWeek, endOfWeek)
            
        case .monthly(let year, let month):
            let dateComponents = DateComponents(year: year, month: month)
            guard let startOfMonth = calendar.date(from: dateComponents) else { return (nil, nil) }
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)
            return (startOfMonth, endOfMonth)
            
        case .yearly(let year):
            let dateComponents = DateComponents(year: year)
            guard let startOfYear = calendar.date(from: dateComponents) else { return (nil, nil) }
            let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear)
            return (startOfYear, endOfYear)
            
        case .allTime:
            return (nil, nil)
        }
    }
    
    private static func calculateTopCategories(
        _ statistics: AccountStatistics,
        transactions: [Transaction]
    ) throws {
        // Group expenses by category
        var expensesByCategory: [String: Decimal] = [:]
        var incomeByCategory: [String: Decimal] = [:]
        
        for transaction in transactions {
            guard let categoryId = transaction.category?.id.uuidString,
                  let amount = transaction.amount else { continue }
            
            switch transaction.type {
            case .expense:
                expensesByCategory[categoryId, default: 0] += amount
            case .income:
                incomeByCategory[categoryId, default: 0] += amount
            case .transfer:
                continue // Skip transfers for category analysis
            default:
                continue
            }
        }
        
        // Get top 5 categories for each type
        let topExpensesArray = Array(expensesByCategory.sorted { $0.value > $1.value }.prefix(5))
        let topExpenses = Dictionary(topExpensesArray, uniquingKeysWith: { first, _ in first })

        let topIncomeArray = Array(incomeByCategory.sorted { $0.value > $1.value }.prefix(5))
        let topIncome = Dictionary(topIncomeArray, uniquingKeysWith: { first, _ in first })
        
        // Store as JSON
        statistics.setTopExpenseCategories(topExpenses)
        statistics.setTopIncomeCategories(topIncome)
    }
    
    // MARK: - Batch Operations
    
    /// Update statistics for all accounts
    @MainActor
    public static func updateAllAccountStatistics(
        for period: StatisticsPeriod = .monthly(year: Calendar.current.component(.year, from: Date()),
                                              month: Calendar.current.component(.month, from: Date())),
        in context: ModelContext
    ) async throws {
        
        // Get all active accounts
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { account in account.isActive == true }
        )
        let accounts = try context.fetch(descriptor)
        
        // Update statistics for each account
        for account in accounts {
            try await updateStatistics(for: account, period: period, in: context)
        }
    }
    
    /// Clean old statistics (keep only last 12 months of monthly stats, 4 weeks of weekly stats, etc.)
    @MainActor
    public static func cleanOldStatistics(in context: ModelContext) throws {
        let calendar = Calendar.current
        let now = Date()
        
        // Delete monthly statistics older than 12 months
        if let cutoffDate = calendar.date(byAdding: .month, value: -12, to: now) {
            let cutoffYear = calendar.component(.year, from: cutoffDate)
            let cutoffMonth = calendar.component(.month, from: cutoffDate)
            
            let predicate = #Predicate<AccountStatistics> { stats in
                stats.month != nil &&
                ((stats.year! < cutoffYear) || 
                 (stats.year! == cutoffYear && stats.month! < cutoffMonth))
            }
            
            let descriptor = FetchDescriptor<AccountStatistics>(predicate: predicate)
            let oldStats = try context.fetch(descriptor)
            
            for stat in oldStats {
                context.delete(stat)
            }
        }
        
        try context.save()
    }
}

// MARK: - Extensions

extension Account {
    /// Get current month statistics (cached)
    @MainActor
    public func getCurrentMonthStatistics(in context: ModelContext) throws -> AccountStatistics? {
        return try StatisticsService.getCurrentMonthStatistics(for: self, in: context)
    }

    /// Get or create current month statistics
    @MainActor
    public func getOrCreateCurrentMonthStatistics(in context: ModelContext) async throws -> AccountStatistics {
        return try await StatisticsService.getOrCreateCurrentMonthStatistics(for: self, in: context)
    }
}