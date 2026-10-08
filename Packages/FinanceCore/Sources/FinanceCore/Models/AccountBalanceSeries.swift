import Foundation

public struct AccountBalanceSeries: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let points: [BalanceDataPoint]
    public let projected: [BalanceDataPoint]
    public var savingsCapital: [BalanceDataPoint]?
    public var savingsValue: [BalanceDataPoint]?

    public func savingsAmount(at date: Date, estimated: Bool) -> Decimal? {
        let values = estimated ? savingsValue : savingsCapital
        return values?.last { $0.date <= date }?.balance
    }

    public init(id: UUID, name: String, colorHex: String, points: [BalanceDataPoint], projected: [BalanceDataPoint]) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.points = points; self.projected = projected
    }

    public func balance(at date: Date) -> Decimal {
        let history = date > (points.last?.date ?? date) && !projected.isEmpty ? projected : points
        return history.last { $0.date <= date }?.balance ?? history.first?.balance ?? 0
    }

    /// The caller must own all supplied models on its executor.
    public static func make(conti: [Conto], selectedIDs: Set<UUID>,
                     transactions: [Transaction], resolutions: [RecurrenceResolution], interval: DateInterval, now: Date = Date(),
                     ledgerSnapshots: [UUID: LedgerCacheSnapshot]? = nil, calendar: Calendar = .current) -> [Self] {
        let snapshots = transactions.map {
            TransactionSnapshot(id: $0.id, amount: $0.amount ?? 0, type: $0.type, date: $0.date,
                                fromContoId: $0.fromContoId ?? $0.fromConto?.id,
                                toContoId: $0.toContoId ?? $0.toConto?.id, destinationAmount: $0.destinationAmount,
                                categoryID: $0.categoryId ?? $0.category?.id)
        }
        let planned = ProjectedBalanceHistory.plannedTransactions(transactions: transactions, resolutions: resolutions,
                                                                  now: now, through: interval.end)
        let selected = conti.filter { selectedIDs.contains($0.id) }
        let ledger = ledgerSnapshots ?? (try? LedgerCache.prepare(conti: selected, transactions: snapshots, now: now).snapshots)
        let histories = Dictionary(uniqueKeysWithValues: selected.map { conto in
            (conto.id, ledger?[conto.id]?.points(interval: interval, now: now, transactions: snapshots, calendar: calendar)
                ?? RecordedBalanceHistory.points(transactions: snapshots, contiIDs: [conto.id],
                    initialBalance: conto.initialBalance ?? 0, interval: interval, now: now))
        })
        // Account identity colours remain the same in the app and widget snapshots.
        let ordered = conti.sorted { $0.id.uuidString < $1.id.uuidString }
        return ordered.compactMap { conto in
            guard selectedIDs.contains(conto.id), let points = histories[conto.id], !points.isEmpty else { return nil }
            var result = Self(id: conto.id, name: conto.name ?? "Conto",
                        colorHex: conto.displayColorHex, points: points,
                        projected: ProjectedBalanceHistory.points(planned: planned, contoID: conto.id,
                            openingBalance: points.last!.balance, interval: interval, now: now))
            if conto.type == .savings {
                var dates = Set(points.map(\.date))
                var day = Calendar.current.startOfDay(for: interval.start)
                while day < min(interval.end, now) {
                    if day >= interval.start { dates.insert(day) }
                    day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                }
                let movements = conto.savingsMovements(transactions: transactions)
                let rates = conto.savingsRates
                let start = rates.first?.effectiveDate ?? conto.createdAt ?? now
                let values = dates.sorted().map { date in
                    (date, SavingsValuation.value(initialBalance: conto.initialBalance ?? 0,
                        start: start, rates: rates, movements: movements, at: date))
                }
                result.savingsCapital = values.map { BalanceDataPoint(date: $0.0, balance: $0.1.capital) }
                result.savingsValue = values.map { BalanceDataPoint(date: $0.0, balance: $0.1.estimatedValue) }
            }
            return result
        }.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
    }
}
