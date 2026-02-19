//
//  UnifiedWidgetModels.swift
//  Personal Finance
//
//  Data models used by unified dashboard widget sections.
//

import SwiftUI
import FinanceCore

// MARK: - Budget Snapshot

struct BudgetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let spent: Decimal
    let limit: Decimal
    let percentage: Double
    let daysRemaining: Int

    var barColor: Color {
        if percentage >= 1.0 { return .red }
        if percentage >= 0.8 { return .orange }
        return .green
    }
}

// MARK: - Financial Health Result

struct FinancialHealthResult {
    let score: Double
    let savingsPoints: Double
    let budgetPoints: Double
    let incomePoints: Double
    let spendingPoints: Double

    var label: String {
        switch score {
        case 80...: return "Ottimo"
        case 60..<80: return "Buono"
        case 40..<60: return "Sufficiente"
        default: return "Critico"
        }
    }

    var color: Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }

    static var empty: FinancialHealthResult {
        FinancialHealthResult(score: 0, savingsPoints: 0, budgetPoints: 0, incomePoints: 0, spendingPoints: 0)
    }
}

// MARK: - Spending Anomaly

enum AnomalySeverity {
    case low, medium, high

    var color: Color {
        switch self {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct SpendingAnomaly: Identifiable {
    let id = UUID()
    let categoryName: String
    let categoryColor: String
    let icon: String
    let amount: Decimal
    let average: Decimal
    let deviationPercent: Double
    let severity: AnomalySeverity

    var title: String { categoryName }
    var detail: String {
        "Media: \(average.currencyFormatted)/mese"
    }
}

// MARK: - Category Trend Data

struct CategoryTrendData: Identifiable {
    let id = UUID()
    let name: String
    let color: String
    let icon: String
    let monthlyAmounts: [Decimal]
    let currentMonth: Decimal
    let isIncreasing: Bool
}

// MARK: - Cash Flow Week

struct CashFlowWeek: Identifiable {
    let id = UUID()
    let label: String
    let projectedIncome: Decimal
    let projectedExpenses: Decimal
}

// MARK: - Weekday Spending

struct WeekdaySpending: Identifiable {
    let weekday: Int
    let label: String
    let fullName: String
    let amount: Decimal
    var id: Int { weekday }
}

// MARK: - Monthly Income Expense

struct MonthlyIncomeExpense: Identifiable {
    let id = UUID()
    let label: String
    let income: Decimal
    let expenses: Decimal
}

// MARK: - Payee Data

struct PayeeData: Identifiable {
    let id = UUID()
    let name: String
    let totalAmount: Decimal
    let transactionCount: Int
}

// MARK: - Savings Goal Data

struct SavingsGoalData {
    let monthlyTarget: Decimal
    let currentSavings: Decimal
    let progressPercent: Double
    let remaining: Decimal
    let daysRemaining: Int
    let projectedEndOfMonth: Decimal
    let onTrack: Bool

    static var empty: SavingsGoalData {
        SavingsGoalData(monthlyTarget: 0, currentSavings: 0, progressPercent: 0,
                        remaining: 0, daysRemaining: 0, projectedEndOfMonth: 0, onTrack: false)
    }
}
