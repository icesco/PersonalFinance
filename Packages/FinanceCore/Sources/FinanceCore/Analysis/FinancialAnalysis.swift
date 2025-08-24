import Foundation

public struct FinancialAnalysis {
    public let totalIncome: Decimal
    public let totalExpenses: Decimal
    public let totalSavings: Decimal
    public let categories: [CategoryAnalysis]
    public let rule502010: Rule502010Analysis
    public let period: AnalysisPeriod
    
    public init(
        totalIncome: Decimal,
        totalExpenses: Decimal,
        totalSavings: Decimal,
        categories: [CategoryAnalysis],
        rule502010: Rule502010Analysis,
        period: AnalysisPeriod
    ) {
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.totalSavings = totalSavings
        self.categories = categories
        self.rule502010 = rule502010
        self.period = period
    }
    
    public var netIncome: Decimal {
        totalIncome - totalExpenses
    }
    
    public var savingsRate: Double {
        guard totalIncome > 0 else { return 0 }
        return Double(truncating: totalSavings as NSDecimalNumber) / Double(truncating: totalIncome as NSDecimalNumber) * 100
    }
}

public struct CategoryAnalysis {
    public let category: Category
    public let amount: Decimal
    public let percentage: Double
    public let transactionCount: Int
    public let trend: TrendDirection
    
    public init(
        category: Category,
        amount: Decimal,
        percentage: Double,
        transactionCount: Int,
        trend: TrendDirection
    ) {
        self.category = category
        self.amount = amount
        self.percentage = percentage
        self.transactionCount = transactionCount
        self.trend = trend
    }
}

public enum TrendDirection: String, CaseIterable {
    case up = "up"
    case down = "down"
    case stable = "stable"
    
    public var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .stable: return "minus"
        }
    }
    
    public var displayName: String {
        switch self {
        case .up: return "In crescita"
        case .down: return "In diminuzione"
        case .stable: return "Stabile"
        }
    }
}

public enum AnalysisPeriod: String, CaseIterable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"
    
    public var displayName: String {
        switch self {
        case .week: return "Questa Settimana"
        case .month: return "Questo Mese"
        case .quarter: return "Questo Trimestre"
        case .year: return "Quest'Anno"
        }
    }
    
    public var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .week:
            let start = calendar.startOfWeek(for: now)
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)
        case .month:
            let start = calendar.startOfMonth(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .quarter:
            let start = calendar.startOfQuarter(for: now)
            let end = calendar.date(byAdding: .month, value: 3, to: start)!
            return (start, end)
        case .year:
            let start = calendar.startOfYear(for: now)
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }
}

public struct Rule502010Analysis {
    public let necessities: Decimal // 50%
    public let wants: Decimal // 30%
    public let savings: Decimal // 20%
    public let totalIncome: Decimal
    
    public init(necessities: Decimal, wants: Decimal, savings: Decimal, totalIncome: Decimal) {
        self.necessities = necessities
        self.wants = wants
        self.savings = savings
        self.totalIncome = totalIncome
    }
    
    public var necessitiesPercentage: Double {
        guard totalIncome > 0 else { return 0 }
        return Double(truncating: necessities as NSDecimalNumber) / Double(truncating: totalIncome as NSDecimalNumber) * 100
    }
    
    public var wantsPercentage: Double {
        guard totalIncome > 0 else { return 0 }
        return Double(truncating: wants as NSDecimalNumber) / Double(truncating: totalIncome as NSDecimalNumber) * 100
    }
    
    public var savingsPercentage: Double {
        guard totalIncome > 0 else { return 0 }
        return Double(truncating: savings as NSDecimalNumber) / Double(truncating: totalIncome as NSDecimalNumber) * 100
    }
    
    public var idealNecessities: Decimal {
        totalIncome * 0.5
    }
    
    public var idealWants: Decimal {
        totalIncome * 0.3
    }
    
    public var idealSavings: Decimal {
        totalIncome * 0.2
    }
    
    public var necessitiesStatus: BudgetStatus {
        let percentage = necessitiesPercentage
        if percentage <= 50 { return .onTrack }
        if percentage <= 60 { return .warning }
        return .overBudget
    }
    
    public var wantsStatus: BudgetStatus {
        let percentage = wantsPercentage
        if percentage <= 30 { return .onTrack }
        if percentage <= 40 { return .warning }
        return .overBudget
    }
    
    public var savingsStatus: BudgetStatus {
        let percentage = savingsPercentage
        if percentage >= 20 { return .onTrack }
        if percentage >= 10 { return .warning }
        return .overBudget
    }
}

public enum BudgetStatus {
    case onTrack
    case warning
    case overBudget
    
    public var color: String {
        switch self {
        case .onTrack: return "#34C759"
        case .warning: return "#FF9500"
        case .overBudget: return "#FF3B30"
        }
    }
    
    public var displayName: String {
        switch self {
        case .onTrack: return "In linea"
        case .warning: return "Attenzione"
        case .overBudget: return "Fuori budget"
        }
    }
}

// MARK: - Calendar Extensions

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
    
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
    
    func startOfQuarter(for date: Date) -> Date {
        let month = component(.month, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        var components = dateComponents([.year], from: date)
        components.month = quarterStartMonth
        components.day = 1
        return self.date(from: components) ?? date
    }
    
    func startOfYear(for date: Date) -> Date {
        let components = dateComponents([.year], from: date)
        return self.date(from: components) ?? date
    }
}