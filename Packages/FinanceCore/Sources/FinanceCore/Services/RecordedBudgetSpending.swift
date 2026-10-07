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
