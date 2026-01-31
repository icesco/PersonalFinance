import Foundation
import SwiftData

// MARK: - Statistics Result (Computed On-Demand, Not Persisted)

/// Statistics calculated on-demand from transactions - NOT persisted to database
/// This replaces the old @Model AccountStatistics to avoid storage overhead
public struct AccountStatisticsResult: Sendable {
    public let accountId: UUID
    public let period: StatisticsPeriod

    // Core statistics
    public let totalBalance: Decimal
    public let totalIncome: Decimal
    public let totalExpenses: Decimal
    public let netIncome: Decimal

    // Transaction counts
    public let transactionCount: Int
    public let incomeTransactionCount: Int
    public let expenseTransactionCount: Int
    public let transferTransactionCount: Int

    // Category breakdown (top 5)
    public let topExpenseCategories: [CategoryAmount]
    public let topIncomeCategories: [CategoryAmount]

    // Metadata
    public let calculatedAt: Date

    public init(
        accountId: UUID,
        period: StatisticsPeriod,
        totalBalance: Decimal,
        totalIncome: Decimal,
        totalExpenses: Decimal,
        transactionCount: Int,
        incomeTransactionCount: Int,
        expenseTransactionCount: Int,
        transferTransactionCount: Int,
        topExpenseCategories: [CategoryAmount] = [],
        topIncomeCategories: [CategoryAmount] = []
    ) {
        self.accountId = accountId
        self.period = period
        self.totalBalance = totalBalance
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.netIncome = totalIncome - totalExpenses
        self.transactionCount = transactionCount
        self.incomeTransactionCount = incomeTransactionCount
        self.expenseTransactionCount = expenseTransactionCount
        self.transferTransactionCount = transferTransactionCount
        self.topExpenseCategories = topExpenseCategories
        self.topIncomeCategories = topIncomeCategories
        self.calculatedAt = Date()
    }

    /// Savings rate as percentage (0-100)
    public var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: netIncome).doubleValue /
               NSDecimalNumber(decimal: totalIncome).doubleValue * 100
    }
}

/// Category with amount for statistics breakdown
public struct CategoryAmount: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let amount: Decimal
    public let color: String?

    public init(id: UUID, name: String, amount: Decimal, color: String? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.color = color
    }
}

// MARK: - Statistics Period

public enum StatisticsPeriod: Sendable {
    case daily(Date)
    case weekly(year: Int, week: Int)
    case monthly(year: Int, month: Int)
    case yearly(Int)
    case allTime

    public var displayName: String {
        switch self {
        case .daily(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        case .weekly(let year, let week):
            return "Settimana \(week), \(year)"
        case .monthly(let year, let month):
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            let calendar = Calendar.current
            if let date = calendar.date(from: DateComponents(year: year, month: month)) {
                return formatter.string(from: date)
            }
            return "Mese \(month), \(year)"
        case .yearly(let year):
            return "\(year)"
        case .allTime:
            return "Tutti i periodi"
        }
    }

    /// Get date range for this period
    public var dateRange: (start: Date?, end: Date?) {
        let calendar = Calendar.current

        switch self {
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

    /// Current month period
    public static var currentMonth: StatisticsPeriod {
        let now = Date()
        let calendar = Calendar.current
        return .monthly(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    /// Current year period
    public static var currentYear: StatisticsPeriod {
        let now = Date()
        let calendar = Calendar.current
        return .yearly(calendar.component(.year, from: now))
    }
}
