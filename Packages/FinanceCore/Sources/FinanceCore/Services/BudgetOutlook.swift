import Foundation

public struct BudgetOutlook {
    /// Includes today, even on the final day of the period.
    public let daysRemaining: Int
    /// Budget margin per remaining calendar day, after all recorded commitments.
    public let dailyAllowance: Decimal
    /// Variable spending pace from completed days, plus recorded recurring entries.
    /// Nil until at least one complete calendar day is available.
    public let projectedTotal: Decimal?

    public static func calculate(for budget: Budget, transactions: [Transaction], now: Date = Date(),
                                 calendar: Calendar = .current) -> BudgetOutlook {
        guard let interval = budget.period?.interval(containing: now, calendar: calendar) else {
            return BudgetOutlook(daysRemaining: 0, dailyAllowance: 0, projectedTotal: nil)
        }
        let today = calendar.startOfDay(for: now)
        let completedDays = max(0, calendar.dateComponents([.day], from: interval.start, to: today).day ?? 0)
        let remainingDays = max(1, calendar.dateComponents([.day], from: today, to: interval.end).day ?? 1)
        let entries = RecordedBudgetSpending.entries(for: budget, transactions: transactions,
                                                     start: interval.start, end: interval.end)
        let recorded = entries.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        let margin = max(0, (budget.amount ?? 0) - recorded)
        guard completedDays > 0 else {
            return BudgetOutlook(daysRemaining: remainingDays,
                                 dailyAllowance: margin / Decimal(remainingDays), projectedTotal: nil)
        }
        let recurring = entries.filter { $0.isRecurring == true || $0.recurrenceSourceID != nil }.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        let completedVariable = entries.filter { $0.isRecurring != true && $0.recurrenceSourceID == nil && $0.date < today }
            .reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        let variablePace = max(0, completedVariable) * Decimal(completedDays + remainingDays) / Decimal(completedDays)
        // Future ledger entries set a floor, not a rate to extrapolate again.
        let projection = max(recorded, recurring + variablePace)
        return BudgetOutlook(daysRemaining: remainingDays, dailyAllowance: margin / Decimal(remainingDays),
                             projectedTotal: projection)
    }
}

extension Budget {
    public func spendingOutlook(now: Date = Date(), calendar: Calendar = .current) -> BudgetOutlook {
        BudgetOutlook.calculate(for: self, transactions: (categories ?? []).flatMap { $0.transactions ?? [] },
                                now: now, calendar: calendar)
    }
}
