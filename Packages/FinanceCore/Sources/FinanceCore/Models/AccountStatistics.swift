import Foundation
import SwiftData

@Model
public final class AccountStatistics {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    
    // Time period for these statistics
    public var year: Int?
    public var month: Int?
    public var week: Int? // Week of year
    public var day: Date? // For daily statistics
    
    // Core statistics
    public var totalBalance: Decimal?
    public var totalIncome: Decimal?
    public var totalExpenses: Decimal?
    public var netIncome: Decimal? // Income - Expenses
    
    // Monthly breakdown (for current month)
    public var monthlyIncome: Decimal?
    public var monthlyExpenses: Decimal?
    public var monthlySavings: Decimal?
    
    // Transaction counts
    public var transactionCount: Int?
    public var incomeTransactionCount: Int?
    public var expenseTransactionCount: Int?
    public var transferTransactionCount: Int?
    
    // Category breakdown (top 5 categories by spending)
    public var topExpenseCategories: String? // JSON string of [CategoryID: Amount]
    public var topIncomeCategories: String? // JSON string of [CategoryID: Amount]
    
    // Metadata
    public var calculatedAt: Date?
    public var lastTransactionDate: Date?
    public var createdAt: Date?
    public var updatedAt: Date?
    
    // Relationships
    public var account: Account?
    
    public init(
        account: Account,
        year: Int? = nil,
        month: Int? = nil,
        week: Int? = nil,
        day: Date? = nil
    ) {
        self.account = account
        self.year = year
        self.month = month
        self.week = week
        self.day = day
        
        // Initialize with zero values
        self.totalBalance = 0
        self.totalIncome = 0
        self.totalExpenses = 0
        self.netIncome = 0
        self.monthlyIncome = 0
        self.monthlyExpenses = 0
        self.monthlySavings = 0
        self.transactionCount = 0
        self.incomeTransactionCount = 0
        self.expenseTransactionCount = 0
        self.transferTransactionCount = 0
        
        self.createdAt = Date()
        self.updatedAt = Date()
        self.calculatedAt = Date()
    }
    
    // MARK: - Helper Methods
    
    /// Returns true if these statistics represent current month
    public var isCurrentMonth: Bool {
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        return year == currentYear && month == currentMonth && week == nil && day == nil
    }
    
    /// Returns true if these statistics represent current week
    public var isCurrentWeek: Bool {
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.yearForWeekOfYear, from: now)
        let currentWeek = calendar.component(.weekOfYear, from: now)
        
        return year == currentYear && week == currentWeek && month == nil && day == nil
    }
    
    /// Returns true if these statistics represent today
    public var isToday: Bool {
        guard let day = day else { return false }
        return Calendar.current.isDate(day, inSameDayAs: Date())
    }
    
    /// Parse top categories from JSON string
    public func getTopExpenseCategories() -> [String: Decimal] {
        guard let json = topExpenseCategories,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }
        
        return dict.mapValues { Decimal($0) }
    }
    
    /// Parse top income categories from JSON string
    public func getTopIncomeCategories() -> [String: Decimal] {
        guard let json = topIncomeCategories,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }
        
        return dict.mapValues { Decimal($0) }
    }
    
    /// Set top expense categories from dictionary
    public func setTopExpenseCategories(_ categories: [String: Decimal]) {
        let dict = categories.mapValues { NSDecimalNumber(decimal: $0).doubleValue }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            topExpenseCategories = json
        }
    }
    
    /// Set top income categories from dictionary
    public func setTopIncomeCategories(_ categories: [String: Decimal]) {
        let dict = categories.mapValues { NSDecimalNumber(decimal: $0).doubleValue }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            topIncomeCategories = json
        }
    }
}

// MARK: - Statistics Type Enum

public enum StatisticsPeriod {
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
    
    /// Create AccountStatistics for this period
    public func createStatistics(for account: Account) -> AccountStatistics {
        switch self {
        case .daily(let date):
            return AccountStatistics(account: account, day: date)
        case .weekly(let year, let week):
            return AccountStatistics(account: account, year: year, week: week)
        case .monthly(let year, let month):
            return AccountStatistics(account: account, year: year, month: month)
        case .yearly(let year):
            return AccountStatistics(account: account, year: year)
        case .allTime:
            return AccountStatistics(account: account)
        }
    }
}