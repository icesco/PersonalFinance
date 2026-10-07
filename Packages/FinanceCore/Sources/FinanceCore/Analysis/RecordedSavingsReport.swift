import Foundation

/// Cash-flow residual from recorded income and expenses, not an account balance
/// or proof of money set aside. Callers must supply one consistent currency/scope.
public struct RecordedSavingsReport: Sendable {
    public let income: Decimal
    public let expenses: Decimal
    public let hasInvalidAmounts: Bool
    public var remainder: Decimal { income - expenses }

    /// A fraction, for percent formatting. Negative rates are intentional.
    public var savingsRate: Decimal? {
        guard !hasInvalidAmounts else { return nil }
        return Self.rate(income: income, expenses: expenses)
    }

    public static func rate(income: Decimal, expenses: Decimal) -> Decimal? {
        guard !income.isNaN, !expenses.isNaN, income > 0 else { return nil }
        let rate = (income - expenses) / income
        return rate.isNaN ? nil : rate
    }

    public static func calculate(transactions: [DirectionTransaction], interval: DateInterval,
                                 now: Date = Date()) -> Self {
        var income: Decimal = 0
        var expenses: Decimal = 0
        var invalid = false
        for entry in transactions where entry.date >= interval.start && entry.date < interval.end && entry.date <= now {
            guard entry.type != .transfer else { continue }
            guard entry.hasValidAmount, !entry.amount.isNaN else {
                invalid = true
                continue
            }
            switch entry.type {
            case .income: income += entry.amount
            case .expense: expenses += entry.amount
            case .transfer: break
            }
        }
        return Self(income: income, expenses: expenses,
                    hasInvalidAmounts: invalid || income.isNaN || expenses.isNaN)
    }
}
