import Foundation
import SwiftData

public enum BudgetPeriod: String, CaseIterable, Codable {
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case yearly = "yearly"
    
    public var displayName: String {
        switch self {
        case .weekly: return "Settimanale"
        case .monthly: return "Mensile"
        case .quarterly: return "Trimestrale"
        case .yearly: return "Annuale"
        }
    }
    
    public var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        case .quarterly: return 90
        case .yearly: return 365
        }
    }
}

@Model
public final class Budget {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var amount: Decimal?
    public var period: BudgetPeriod?
    public var isActive: Bool?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var alertThreshold: Double? // Percentage (0.0 - 1.0)
    public var includeRecurringTransactions: Bool?  // Include transazioni ricorrenti pianificate
    
    public var account: Account?

    /// Direct many-to-many relationship with Category (no junction table needed)
    public var categories: [Category]?

    public init(
        name: String,
        amount: Decimal,
        period: BudgetPeriod,
        alertThreshold: Double = 0.8,
        includeRecurringTransactions: Bool = true
    ) {
        self.name = name
        self.amount = amount
        self.period = period
        self.alertThreshold = max(0.0, min(1.0, alertThreshold))
        self.includeRecurringTransactions = includeRecurringTransactions
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.categories = []
    }
    
    /// Current calendar period, with an exclusive end.
    public var currentPeriodRange: (start: Date, end: Date) {
        let now = Date()
        guard let interval = period?.interval(containing: now) else { return (now, now) }
        return (interval.start, interval.end)
    }

    /// Previous complete calendar period, including its entire final day.
    public var previousPeriodRange: (start: Date, end: Date) {
        let start = currentPeriodRange.start
        guard let interval = period?.interval(containing: start.addingTimeInterval(-1)) else {
            return (start, start)
        }
        return (interval.start, interval.end)
    }

    // MARK: - Computed Properties (use optimized methods with ModelContext when possible)

    /// Current spent amount - loads all transactions in memory
    /// Prefer `getCurrentSpent(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use getCurrentSpent(in:) for optimized DB queries")
    public var currentSpent: Decimal {
        calculateSpentInMemory(for: currentPeriodRange)
    }

    /// Previous period spent - loads all transactions in memory
    /// Prefer `getPreviousPeriodSpent(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use getPreviousPeriodSpent(in:) for optimized DB queries")
    public var previousPeriodSpent: Decimal {
        calculateSpentInMemory(for: previousPeriodRange)
    }

    /// Calculate spent in memory (inefficient, prefer BudgetService methods)
    private func calculateSpentInMemory(for period: (start: Date, end: Date)) -> Decimal {
        RecordedBudgetSpending.total(
            for: self, transactions: (categories ?? []).flatMap { $0.transactions ?? [] },
            start: period.start, end: period.end
        )
    }

    /// Add a category to this budget
    public func addCategory(_ category: Category) {
        if categories == nil {
            categories = []
        }
        if !(categories?.contains(where: { $0.id == category.id }) ?? false) {
            categories?.append(category)
        }
    }

    /// Remove a category from this budget
    public func removeCategory(_ category: Category) {
        categories?.removeAll { $0.id == category.id }
    }
    
    /// Remaining amount - uses in-memory calculation
    /// Prefer `getRemainingAmount(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use getRemainingAmount(in:) for optimized DB queries")
    public var remainingAmount: Decimal {
        guard let budgetAmount = amount else { return 0 }
        return budgetAmount - calculateSpentInMemory(for: currentPeriodRange)
    }

    /// Spent percentage - uses in-memory calculation
    /// Prefer `getSpentPercentage(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use getSpentPercentage(in:) for optimized DB queries")
    public var spentPercentage: Double {
        guard let budgetAmount = amount, budgetAmount > 0 else { return 0 }
        let spent = calculateSpentInMemory(for: currentPeriodRange)
        return NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: budgetAmount).doubleValue
    }

    /// Check if over budget - uses in-memory calculation
    /// Prefer `isOverBudget(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use isOverBudget(in:) for optimized DB queries")
    public var isOverBudget: Bool {
        guard let budgetAmount = amount else { return false }
        return calculateSpentInMemory(for: currentPeriodRange) > budgetAmount
    }

    /// Check if should alert - uses in-memory calculation
    /// Prefer `shouldAlert(in:)` for optimized DB queries
    @available(*, deprecated, message: "Use shouldAlert(in:) for optimized DB queries")
    public var shouldAlert: Bool {
        guard let threshold = alertThreshold else { return false }
        return spentPercentage >= threshold
    }
    
    // Giorni rimanenti nel periodo corrente
    public var daysRemaining: Int {
        spendingOutlook().daysRemaining
    }
    
    // Percentuale del periodo trascorso
    public var periodProgressPercentage: Double {
        let (start, end) = currentPeriodRange
        let now = Date()
        
        let totalDuration = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        
        return min(1.0, max(0.0, elapsed / totalDuration))
    }
    
    /// Daily suggested spending - uses in-memory calculation
    @available(*, deprecated, message: "Use BudgetService for optimized calculations")
    public var dailySuggestedSpending: Decimal {
        spendingOutlook().dailyAllowance
    }

    /// Get spent for a custom period with an exclusive end - uses in-memory calculation
    @available(*, deprecated, message: "Use BudgetService.calculateSpent(for:period:in:) instead")
    public func getSpent(for customPeriod: (start: Date, end: Date)) -> Decimal {
        calculateSpentInMemory(for: customPeriod)
    }

    /// Change from previous period - uses in-memory calculation
    @available(*, deprecated, message: "Use BudgetService for optimized calculations")
    public var changeFromPreviousPeriod: Double {
        let previous = calculateSpentInMemory(for: previousPeriodRange)
        guard previous > 0 else { return 0 }

        let current = calculateSpentInMemory(for: currentPeriodRange)
        let difference = current - previous
        return NSDecimalNumber(decimal: difference).doubleValue /
               NSDecimalNumber(decimal: previous).doubleValue
    }
}
