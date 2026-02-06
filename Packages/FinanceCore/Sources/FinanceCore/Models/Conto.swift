import Foundation
import SwiftData

public enum ContoType: String, CaseIterable, Codable {
    case checking = "checking"
    case savings = "savings"
    case credit = "credit"
    case investment = "investment"
    case cash = "cash"
    case other = "other"
    
    public var displayName: String {
        switch self {
        case .checking: return "Conto Corrente"
        case .savings: return "Conto Risparmio"
        case .credit: return "Carta di Credito"
        case .investment: return "Investimenti"
        case .cash: return "Contanti"
        case .other: return "Altro"
        }
    }
    
    public var icon: String {
        switch self {
        case .checking: return "creditcard"
        case .savings: return "banknote"
        case .credit: return "creditcard.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .cash: return "dollarsign.circle"
        case .other: return "questionmark.circle"
        }
    }
}

@Model
public final class Conto {
    public var id: UUID = UUID()
    public var externalID: String = UUID().uuidString
    public var name: String?
    public var type: ContoType?
    public var initialBalance: Decimal?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isActive: Bool?
    public var contoDescription: String?
    public var color: String?
    
    // Carta di Credito
    public var creditLimit: Decimal?
    public var statementClosingDay: Int?
    public var paymentDueDay: Int?

    // Investimenti
    public var annualInterestRate: Decimal?

    // Risparmio
    public var savingsGoal: Decimal?

    public var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.fromConto)
    public var outgoingTransactions: [Transaction]?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.toConto)
    public var incomingTransactions: [Transaction]?

    public init(
        name: String,
        type: ContoType,
        initialBalance: Decimal = 0,
        contoDescription: String? = nil,
        color: String? = nil,
        creditLimit: Decimal? = nil,
        statementClosingDay: Int? = nil,
        paymentDueDay: Int? = nil,
        annualInterestRate: Decimal? = nil,
        savingsGoal: Decimal? = nil
    ) {
        // id and externalID now have default values
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.contoDescription = contoDescription
        self.color = color
        self.creditLimit = creditLimit
        self.statementClosingDay = statementClosingDay
        self.paymentDueDay = paymentDueDay
        self.annualInterestRate = annualInterestRate
        self.savingsGoal = savingsGoal
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = true
        self.outgoingTransactions = []
        self.incomingTransactions = []
    }
    
    public var balance: Decimal {
        // Only sum transactions of the correct type to prevent incorrect balance calculations
        let incoming = (incomingTransactions ?? []).reduce(Decimal(0)) { sum, transaction in
            // Only income and incoming transfers should add to balance
            guard transaction.type == .income || transaction.type == .transfer else { return sum }
            return sum + (transaction.amount ?? Decimal(0))
        }

        let outgoing = (outgoingTransactions ?? []).reduce(Decimal(0)) { sum, transaction in
            // Only expenses and outgoing transfers should subtract from balance
            guard transaction.type == .expense || transaction.type == .transfer else { return sum }
            return sum + (transaction.amount ?? Decimal(0))
        }

        return (initialBalance ?? 0) + incoming - outgoing
    }

    /// For credit cards with a plafond, returns available credit (creditLimit − billing period spending).
    /// For all other account types, returns the standard balance.
    public var displayBalance: Decimal {
        if type == .credit, let remaining = creditLimitRemaining {
            return remaining
        }
        return balance
    }

    public var allTransactions: [Transaction] {
        let incoming = incomingTransactions ?? []
        let outgoing = outgoingTransactions ?? []
        return (incoming + outgoing).sorted { $0.date > $1.date }
    }

    // MARK: - Credit Card Computed Properties

    /// Start of the current billing period based on statementClosingDay.
    /// The billing cycle runs from the day after the last closing to the next closing day.
    /// Falls back to calendar month start if no closing day is set.
    private var billingPeriodStart: Date {
        let calendar = Calendar.current
        let now = Date()

        guard let closingDay = statementClosingDay else {
            // No closing day — use calendar month start
            let components = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: components) ?? now
        }

        let currentDay = calendar.component(.day, from: now)
        var components = calendar.dateComponents([.year, .month], from: now)

        if currentDay <= closingDay {
            // Still in cycle whose closing is this month — period started after LAST month's closing
            let month = components.month ?? 1
            if month == 1 {
                components.year = (components.year ?? 2026) - 1
                components.month = 12
            } else {
                components.month = month - 1
            }
        }
        // Period started the day after the previous closing
        components.day = closingDay
        guard let closingDate = calendar.date(from: components) else { return now }
        return calendar.date(byAdding: .day, value: 1, to: closingDate) ?? now
    }

    /// Total expenses in the current billing period.
    /// Uses statementClosingDay to determine period boundaries when set,
    /// otherwise falls back to the calendar month.
    public var currentMonthSpending: Decimal {
        let periodStart = billingPeriodStart

        return (outgoingTransactions ?? [])
            .filter { $0.type == .expense && $0.date >= periodStart }
            .reduce(Decimal(0)) { $0 + ($1.amount ?? Decimal(0)) }
    }

    /// Ratio of current billing period spending to credit limit (nil if no credit limit set)
    public var creditLimitUsageRatio: Double? {
        guard let limit = creditLimit, limit > 0 else { return nil }
        return NSDecimalNumber(decimal: currentMonthSpending / limit).doubleValue
    }

    /// Remaining credit available (nil if no credit limit set)
    public var creditLimitRemaining: Decimal? {
        guard let limit = creditLimit else { return nil }
        return limit - currentMonthSpending
    }

    /// Next statement closing date based on statementClosingDay
    public var nextStatementClosingDate: Date? {
        guard let day = statementClosingDay else { return nil }
        return Self.nextDateForDay(day)
    }

    /// Next payment due date based on paymentDueDay.
    /// When paymentDueDay < statementClosingDay the payment falls in the month
    /// after the statement closing (e.g. closing 25, payment 10 → payment is the 10th
    /// of the following month).
    /// The independent `nextDateForDay` logic is correct here because it always returns
    /// the chronologically next occurrence of the given day.
    public var nextPaymentDueDate: Date? {
        guard let day = paymentDueDay else { return nil }
        return Self.nextDateForDay(day)
    }

    // MARK: - Investment Computed Properties

    /// Projected annual return based on current balance and interest rate
    public var projectedAnnualReturn: Decimal? {
        guard let rate = annualInterestRate else { return nil }
        return balance * rate / Decimal(100)
    }

    // MARK: - Savings Computed Properties

    /// Progress toward savings goal as a ratio (nil if no goal set)
    public var savingsGoalProgress: Double? {
        guard let goal = savingsGoal, goal > 0 else { return nil }
        return NSDecimalNumber(decimal: balance / goal).doubleValue
    }

    /// Amount remaining to reach savings goal (nil if no goal set, 0 if exceeded)
    public var savingsGoalRemaining: Decimal? {
        guard let goal = savingsGoal else { return nil }
        let remaining = goal - balance
        return remaining > 0 ? remaining : Decimal(0)
    }

    // MARK: - Helpers

    private static func nextDateForDay(_ day: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let currentComponents = calendar.dateComponents([.year, .month, .day], from: now)

        var target = DateComponents()
        target.year = currentComponents.year
        target.month = currentComponents.month
        target.day = day

        if let date = calendar.date(from: target), date >= now {
            return date
        }

        // Move to next month
        target.month = (currentComponents.month ?? 1) + 1
        if target.month! > 12 {
            target.month = 1
            target.year = (currentComponents.year ?? 2026) + 1
        }
        return calendar.date(from: target) ?? now
    }
}
