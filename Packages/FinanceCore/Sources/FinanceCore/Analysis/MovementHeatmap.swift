import Foundation
import SwiftData

public enum MovementHeatmapMode: String, CaseIterable, Sendable {
    case expense, income, net

    public func value(in totals: MovementHeatmapTotals) -> Decimal? {
        switch self {
        case .expense: totals.expenses
        case .income: totals.income
        case .net: totals.net
        }
    }

    /// Fixed monetary bands preserve the meaning of colour when switching accounts.
    public func level(in totals: MovementHeatmapTotals) -> Int {
        guard let value = value(in: totals), value != 0 else { return 0 }
        switch abs(value) {
        case ...25: return 1
        case ...100: return 2
        case ...500: return 3
        default: return 4
        }
    }
}

public struct MovementHeatmapEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let type: TransactionType
    public let amount: Decimal?
    public let title: String?
    public let accountName: String?
    public let destinationName: String?
}

public struct MovementHeatmapTotals: Sendable, Equatable {
    public let income: Decimal?
    public let expenses: Decimal?
    public var net: Decimal? {
        guard let income, let expenses else { return nil }
        return income - expenses
    }

    init(entries: [MovementHeatmapEntry]) {
        func sum(_ type: TransactionType) -> Decimal? {
            var total: Decimal = 0
            for entry in entries where entry.type == type {
                guard let amount = entry.amount, !amount.isNaN else { return nil }
                total += amount
            }
            return total
        }
        income = sum(.income)
        expenses = sum(.expense)
    }
}

public struct MovementHeatmapDay: Identifiable, Sendable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let entries: [MovementHeatmapEntry]
    public let totals: MovementHeatmapTotals
    public let isFuture: Bool
    public var isEmpty: Bool { entries.isEmpty }
    public var onlyTransfers: Bool { !isEmpty && entries.allSatisfy { $0.type == .transfer } }
    public var hasBalancedActivity: Bool {
        !onlyTransfers && !isEmpty && totals.income != 0 && totals.net == 0
    }
}

public struct MovementHeatmapMonth: Sendable {
    public let interval: DateInterval
    public let days: [MovementHeatmapDay]
    public let totals: MovementHeatmapTotals
    public let generatedAt: Date
    public var isEmpty: Bool { days.allSatisfy(\.isEmpty) }

    /// Own the supplied models on the calling executor. Only detached values escape.
    public static func build(transactions: [Transaction], contoIDs: Set<UUID>, month: Date,
                             now: Date = Date(), calendar: Calendar = .current) -> Self {
        let interval = calendar.dateInterval(of: .month, for: month)!
        var seen = Set<UUID>()
        let entries: [MovementHeatmapEntry] = transactions.compactMap { row in
            guard row.date >= interval.start, row.date < interval.end, row.date <= now,
                  seen.insert(row.id).inserted else { return nil }
            let from = row.fromContoId ?? row.fromConto?.id
            let to = row.toContoId ?? row.toConto?.id
            let includesFrom = from.map(contoIDs.contains) == true
            let includesTo = to.map(contoIDs.contains) == true
            switch row.type {
            case .expense: guard includesFrom else { return nil }
            case .income: guard includesTo else { return nil }
            case .transfer: guard includesFrom || includesTo else { return nil }
            }
            let rawAmount = row.type == .transfer && !includesFrom ? row.destinationAmount ?? row.amount : row.amount
            let amount = rawAmount.flatMap { $0.isNaN ? nil : $0 }
            let account = row.type == .income ? row.toConto?.name : (includesFrom ? row.fromConto?.name : nil)
            return MovementHeatmapEntry(id: row.id, date: row.date, type: row.type, amount: amount,
                title: row.transactionDescription?.isEmpty == false ? row.transactionDescription : row.category?.name,
                accountName: account, destinationName: row.type == .transfer && includesTo ? row.toConto?.name : nil)
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        var days: [MovementHeatmapDay] = []
        var date = interval.start
        while date < interval.end {
            let rows = grouped[date] ?? []
            days.append(.init(date: date, entries: rows, totals: .init(entries: rows),
                              isFuture: date > calendar.startOfDay(for: now)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return .init(interval: interval, days: days, totals: .init(entries: entries), generatedAt: now)
    }
}

public actor MovementHeatmapReader {
    public init() {}

    public func load(container: ModelContainer, contoIDs: Set<UUID>, currency: String, month: Date,
                     now: Date = Date(), calendar: Calendar = .current) throws -> MovementHeatmapMonth {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try Self.read(in: context, contoIDs: contoIDs, currency: currency, month: month, now: now, calendar: calendar)
    }

    nonisolated public static func read(in context: ModelContext, contoIDs: Set<UUID>, currency: String, month: Date,
                                       now: Date = Date(), calendar: Calendar = .current) throws -> MovementHeatmapMonth {
        try Task.checkCancellation()
        let requested = Array(contoIDs)
        let accounts = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { requested.contains($0.id) }))
        let ids = Set(accounts.filter { ($0.account?.currency ?? "EUR") == currency }.map(\.id))
        guard !ids.isEmpty else { return .build(transactions: [], contoIDs: [], month: month, now: now, calendar: calendar) }
        let interval = calendar.dateInterval(of: .month, for: month)!
        let start = interval.start, end = interval.end
        // Date-bounded reads also include legacy movements whose query IDs are missing.
        var query = FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.date >= start && $0.date < end && $0.date <= now
        })
        query.relationshipKeyPathsForPrefetching = [\.category, \.fromConto, \.toConto]
        let rows = try context.fetch(query)
        try Task.checkCancellation()
        return .build(transactions: rows, contoIDs: ids, month: month, now: now, calendar: calendar)
    }
}
