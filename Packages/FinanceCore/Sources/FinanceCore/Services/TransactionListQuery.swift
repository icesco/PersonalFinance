import Foundation
import SwiftData

/// Filters for the transaction list, evaluated entirely by the store so pages
/// can be fetched with `fetchLimit`/`fetchOffset` instead of loading a whole period.
public struct TransactionListQuery: Equatable, Sendable {
    public var interval: DateInterval
    public var contoIDs: Set<UUID>
    public var type: TransactionType?
    public var categoryIDs: Set<UUID>

    public init(interval: DateInterval, contoIDs: Set<UUID>, type: TransactionType? = nil, categoryIDs: Set<UUID> = []) {
        self.interval = interval
        self.contoIDs = contoIDs
        self.type = type
        self.categoryIDs = categoryIDs
    }

    public var predicate: Predicate<Transaction> {
        let start = interval.start
        let end = interval.end
        let contoIDs = Array(contoIDs)
        let anyType = type == nil
        let typeRaw = type?.rawValue ?? ""
        let categoryIDs = Array(categoryIDs)
        let anyCategory = categoryIDs.isEmpty
        return #Predicate<Transaction> { transaction in
            transaction.date >= start && transaction.date < end
                && (transaction.fromContoId.flatMap { contoIDs.contains($0) } == true
                    || transaction.toContoId.flatMap { contoIDs.contains($0) } == true)
                && (anyType || transaction.typeRaw == typeRaw)
                && (anyCategory || transaction.categoryId.flatMap { categoryIDs.contains($0) } == true)
        }
    }

    /// Newest first; `externalID` breaks ties so pages never overlap or skip rows.
    public func pageDescriptor(offset: Int, limit: Int) -> FetchDescriptor<Transaction> {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.externalID)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return descriptor
    }

    @MainActor
    public func fetchPage(in context: ModelContext, offset: Int, limit: Int) throws -> [Transaction] {
        guard !contoIDs.isEmpty, limit > 0 else { return [] }
        return try context.fetch(pageDescriptor(offset: offset, limit: limit))
    }

    /// Count and totals for the whole period, reading only the amount and type columns.
    @MainActor
    public func summary(in context: ModelContext) throws -> TransactionListSummary {
        guard !contoIDs.isEmpty else { return TransactionListSummary() }
        var descriptor = FetchDescriptor<Transaction>(predicate: predicate)
        descriptor.propertiesToFetch = [\.amount, \.typeRaw]
        var summary = TransactionListSummary()
        for transaction in try context.fetch(descriptor) {
            summary.count += 1
            switch transaction.type {
            case .income: summary.income += transaction.amount ?? 0
            case .expense: summary.expenses += transaction.amount ?? 0
            case .transfer: break
            }
        }
        return summary
    }
}

public struct TransactionListSummary: Equatable, Sendable {
    public var count = 0
    public var income: Decimal = 0
    public var expenses: Decimal = 0

    public init(count: Int = 0, income: Decimal = 0, expenses: Decimal = 0) {
        self.count = count
        self.income = income
        self.expenses = expenses
    }

    public var balance: Decimal { income - expenses }
}
