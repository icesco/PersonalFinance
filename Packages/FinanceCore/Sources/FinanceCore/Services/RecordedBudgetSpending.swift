import Foundation

/// Common ledger rules for budget screens, persisted queries and expense previews.
/// The end of the period is exclusive; scheduled entries already in the ledger count once.
enum RecordedBudgetSpending {
    static func total(for budget: Budget, transactions: [Transaction], start: Date, end: Date,
                      excludingTransactionID: UUID? = nil) -> Decimal {
        entries(for: budget, transactions: transactions, start: start, end: end,
                excludingTransactionID: excludingTransactionID)
            .reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
    }

    static func entries(for budget: Budget, transactions: [Transaction], start: Date, end: Date,
                        excludingTransactionID: UUID? = nil) -> [Transaction] {
        let categoryIDs = budget.coveredCategoryIDs
        let contoIDs = Set((budget.account?.conti ?? []).map(\.id))
        guard !categoryIDs.isEmpty, !contoIDs.isEmpty, start < end else { return [] }
        var visited = Set<ObjectIdentifier>()
        return transactions.filter { transaction in
            guard visited.insert(ObjectIdentifier(transaction)).inserted,
                  transaction.id != excludingTransactionID,
                  transaction.type == .expense,
                  transaction.date >= start, transaction.date < end,
                  (transaction.categoryId ?? transaction.category?.id).map(categoryIDs.contains) == true,
                  (transaction.fromContoId ?? transaction.fromConto?.id).map(contoIDs.contains) == true
            else { return false }
            return true
        }
    }
}

extension Budget {
    /// The ledger expenses contributing to the period total, including recorded future entries.
    public func recordedExpenses(for period: (start: Date, end: Date),
                                 transactions: [Transaction]) -> [Transaction] {
        RecordedBudgetSpending.entries(for: self, transactions: transactions,
                                       start: period.start, end: period.end)
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}

extension BudgetService {
    /// Overlapping budgets share ledger entries; an all-budget list must count each expense once.
    public static func recordedExpenses(for budgets: [Budget], period: (start: Date, end: Date),
                                        transactions: [Transaction]) -> [Transaction] {
        var visited = Set<ObjectIdentifier>()
        return budgets.flatMap { $0.recordedExpenses(for: period, transactions: transactions) }
            .filter { visited.insert(ObjectIdentifier($0)).inserted }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}
