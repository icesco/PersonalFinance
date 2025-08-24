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
    
    // Relazione many-to-many tramite modello intermedio
    @Relationship(deleteRule: .cascade, inverse: \BudgetCategory.budget)
    public var budgetCategories: [BudgetCategory]?
    
    public init(
        name: String,
        amount: Decimal,
        period: BudgetPeriod,
        alertThreshold: Double = 0.8,
        includeRecurringTransactions: Bool = true
    ) {
        // id and externalID now have default values
        self.name = name
        self.amount = amount
        self.period = period
        self.alertThreshold = max(0.0, min(1.0, alertThreshold))
        self.includeRecurringTransactions = includeRecurringTransactions
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.budgetCategories = []
    }
    
    public var categories: [Category] {
        (budgetCategories ?? []).compactMap { $0.category }
    }
    
    // Calcola dinamicamente il periodo corrente basato su Date()
    public var currentPeriodRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        guard let budgetPeriod = period else {
            return (now, now) // Return current date if no period is set
        }
        
        switch budgetPeriod {
        case .weekly:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? now
            return (startOfWeek, endOfWeek)
            
        case .monthly:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end.addingTimeInterval(-1) ?? now
            return (startOfMonth, endOfMonth)
            
        case .quarterly:
            let quarter = calendar.component(.quarter, from: now)
            let year = calendar.component(.year, from: now)
            let startMonth = (quarter - 1) * 3 + 1
            var components = DateComponents()
            components.year = year
            components.month = startMonth
            components.day = 1
            let startOfQuarter = calendar.date(from: components) ?? now
            let endOfQuarter = calendar.date(byAdding: .month, value: 3, to: startOfQuarter)?.addingTimeInterval(-1) ?? now
            return (startOfQuarter, endOfQuarter)
            
        case .yearly:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            let endOfYear = calendar.dateInterval(of: .year, for: now)?.end.addingTimeInterval(-1) ?? now
            return (startOfYear, endOfYear)
        }
    }
    
    // Calcola il periodo precedente per confronti
    public var previousPeriodRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let (currentStart, _) = currentPeriodRange
        
        guard let budgetPeriod = period else {
            return (currentStart, currentStart) // Return current start if no period is set
        }
        
        switch budgetPeriod {
        case .weekly:
            let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: 6, to: previousStart) ?? currentStart
            return (previousStart, previousEnd)
            
        case .monthly:
            let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            return (previousStart, previousEnd)
            
        case .quarterly:
            let previousStart = calendar.date(byAdding: .month, value: -3, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            return (previousStart, previousEnd)
            
        case .yearly:
            let previousStart = calendar.date(byAdding: .year, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart
            return (previousStart, previousEnd)
        }
    }
    
    // Spesa corrente per il periodo attuale
    public var currentSpent: Decimal {
        calculateSpent(for: currentPeriodRange)
    }
    
    // Spesa del periodo precedente per confronto
    public var previousPeriodSpent: Decimal {
        calculateSpent(for: previousPeriodRange)
    }
    
    // Calcola la spesa per un periodo specifico
    private func calculateSpent(for period: (start: Date, end: Date)) -> Decimal {
        let categoriesList = categories
        guard !categoriesList.isEmpty else { return 0 }
        
        var totalSpent: Decimal = 0
        
        // Transazioni effettive nel periodo
        let actualTransactions = categoriesList.flatMap { category in
            (category.transactions ?? []).filter { transaction in
                (transaction.date ?? Date.distantPast) >= period.start &&
                (transaction.date ?? Date.distantPast) <= period.end &&
                transaction.type == .expense
            }
        }
        totalSpent += actualTransactions.reduce(0) { $0 + ($1.amount ?? 0) }
        
        // Se abilitato, includi transazioni ricorrenti pianificate
        if includeRecurringTransactions == true {
            let recurringTransactions = categoriesList.flatMap { category in
                (category.transactions ?? []).filter { transaction in
                    transaction.isRecurring == true &&
                    transaction.type == .expense &&
                    transaction.isRecurrenceActive()
                }
            }
            
            // Calcola le occorrenze delle transazioni ricorrenti nel periodo
            for transaction in recurringTransactions {
                let occurrences = transaction.generateRecurrenceDates(until: period.end)
                    .filter { $0 >= period.start && $0 <= period.end }
                totalSpent += Decimal(occurrences.count) * (transaction.amount ?? 0)
            }
        }
        
        return totalSpent
    }
    
    public func addCategory(_ category: Category) {
        let budgetCategory = BudgetCategory(budget: self, category: category)
        if budgetCategories == nil {
            budgetCategories = []
        }
        budgetCategories?.append(budgetCategory)
    }
    
    public func removeCategory(_ category: Category) {
        budgetCategories?.removeAll { $0.category?.id == category.id }
    }
    
    public var remainingAmount: Decimal {
        guard let budgetAmount = amount else { return 0 }
        return budgetAmount - currentSpent
    }
    
    public var spentPercentage: Double {
        guard let budgetAmount = amount, budgetAmount > 0 else { return 0 }
        return NSDecimalNumber(decimal: currentSpent).doubleValue / NSDecimalNumber(decimal: budgetAmount).doubleValue
    }
    
    public var isOverBudget: Bool {
        guard let budgetAmount = amount else { return false }
        return currentSpent > budgetAmount
    }
    
    public var shouldAlert: Bool {
        guard let threshold = alertThreshold else { return false }
        return spentPercentage >= threshold
    }
    
    // Giorni rimanenti nel periodo corrente
    public var daysRemaining: Int {
        let calendar = Calendar.current
        let now = Date()
        let (_, endDate) = currentPeriodRange
        
        if now > endDate {
            return 0
        }
        
        return calendar.dateComponents([.day], from: now, to: endDate).day ?? 0
    }
    
    // Percentuale del periodo trascorso
    public var periodProgressPercentage: Double {
        let (start, end) = currentPeriodRange
        let now = Date()
        
        let totalDuration = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        
        return min(1.0, max(0.0, elapsed / totalDuration))
    }
    
    // Spesa media giornaliera consigliata per rimanere nel budget
    public var dailySuggestedSpending: Decimal {
        guard daysRemaining > 0 else { return 0 }
        return remainingAmount / Decimal(daysRemaining)
    }
    
    // Calcola la spesa per un periodo specifico custom
    public func getSpent(for customPeriod: (start: Date, end: Date)) -> Decimal {
        calculateSpent(for: customPeriod)
    }
    
    // Proiezione di spesa se si continua al ritmo attuale
    public var projectedSpending: Decimal {
        let progressPercentage = periodProgressPercentage
        guard progressPercentage > 0 else { return 0 }
        
        return currentSpent / Decimal(progressPercentage)
    }
    
    // Percentuale di variazione rispetto al periodo precedente
    public var changeFromPreviousPeriod: Double {
        guard previousPeriodSpent > 0 else { return 0 }
        
        let difference = currentSpent - previousPeriodSpent
        return NSDecimalNumber(decimal: difference).doubleValue / 
               NSDecimalNumber(decimal: previousPeriodSpent).doubleValue
    }
}
