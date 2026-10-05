import Foundation

/// Recorded spending only. Both intervals are half-open; future entries are excluded.
public struct RecordedSpendingReport: Sendable {
    public let expenses: Decimal
    public let recurring: Decimal
    public let variable: Decimal
    public let previousExpenses: Decimal
    public let categories: [CategoryOutflow]
    public let increases: [CategoryIncrease]

    public var chartOutflows: [CategoryOutflow] {
        let remainder = categories.dropFirst(5).reduce(Decimal.zero) { $0 + $1.amount }
        return Array(categories.prefix(5)) + (remainder > 0 ? [CategoryOutflow(name: "Restanti categorie", amount: remainder)] : [])
    }

    public static func calculate(transactions: [DirectionTransaction], interval: DateInterval,
                                 previous: DateInterval, now: Date = Date()) -> Self {
        let expenses = transactions.filter { $0.type == .expense && $0.date <= now }
        let current = expenses.filter { $0.date >= interval.start && $0.date < interval.end }
        let prior = expenses.filter { $0.date >= previous.start && $0.date < previous.end }
        struct Key: Hashable { let id: UUID?; let fallback: String }
        func key(_ transaction: DirectionTransaction) -> Key {
            Key(id: transaction.categoryID, fallback: transaction.categoryID == nil ? transaction.categoryName : "")
        }
        let grouped = Dictionary(grouping: current, by: key)
        let previousGroups = Dictionary(grouping: prior, by: key)
        let categories: [CategoryOutflow] = grouped.map { key, entries -> CategoryOutflow in
            CategoryOutflow(categoryID: key.id, name: entries.last?.categoryName ?? "Da classificare",
                            amount: entries.reduce(Decimal.zero) { $0 + $1.amount })
        }.sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
        let increases = categories.compactMap { category -> CategoryIncrease? in
            let old = previousGroups[Key(id: category.categoryID, fallback: category.categoryID == nil ? category.name : "")]?
                .reduce(Decimal.zero) { $0 + $1.amount } ?? 0
            guard category.amount > old else { return nil }
            return CategoryIncrease(name: category.name, current: category.amount, previous: old, increase: category.amount - old)
        }.sorted { $0.increase > $1.increase }
        return Self(expenses: current.reduce(Decimal.zero) { $0 + $1.amount },
                    recurring: current.filter(\.isRecurring).reduce(Decimal.zero) { $0 + $1.amount },
                    variable: current.filter { !$0.isRecurring }.reduce(Decimal.zero) { $0 + $1.amount },
                    previousExpenses: prior.reduce(Decimal.zero) { $0 + $1.amount }, categories: categories,
                    increases: Array(increases.prefix(3)))
    }
}
