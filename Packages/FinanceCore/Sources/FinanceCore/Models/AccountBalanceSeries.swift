import Foundation

struct BalanceSeriesInputs {
    let snapshots: [TransactionSnapshot]
    let planned: [TransactionSnapshot]

    init(transactions: [Transaction], resolutions: [RecurrenceResolution], now: Date, through end: Date) {
        snapshots = transactions.map(TransactionSnapshot.init(from:))
        planned = ProjectedBalanceHistory.plannedTransactions(transactions: transactions, resolutions: resolutions,
            now: now, through: end)
    }
}

public struct AccountBalanceSeries: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let points: [BalanceDataPoint]
    public let projected: [BalanceDataPoint]
    public var savingsCapital: [BalanceDataPoint]?
    public var savingsValue: [BalanceDataPoint]?

    public func savingsAmount(at date: Date, estimated: Bool) -> Decimal? {
        guard let values = estimated ? savingsValue : savingsCapital else { return nil }
        return values.balanceIndex(at: date).map { values[$0].balance }
    }

    public init(id: UUID, name: String, colorHex: String, points: [BalanceDataPoint], projected: [BalanceDataPoint]) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.points = points; self.projected = projected
    }

    public func balance(at date: Date) -> Decimal {
        let history = date > (points.last?.date ?? date) && !projected.isEmpty ? projected : points
        return history.balanceIndex(at: date).map { history[$0].balance } ?? history.first?.balance ?? 0
    }

    /// The caller must own all supplied models on its executor.
    public static func make(conti: [Conto], selectedIDs: Set<UUID>,
                     transactions: [Transaction], resolutions: [RecurrenceResolution], interval: DateInterval, now: Date = Date(),
                     ledgerSnapshots: [UUID: LedgerCacheSnapshot]? = nil, calendar: Calendar = .current,
                     includeSavingsValuation: Bool = true) -> [Self] {
        make(conti: conti, selectedIDs: selectedIDs, transactions: transactions, interval: interval, now: now,
            ledgerSnapshots: ledgerSnapshots, calendar: calendar, includeSavingsValuation: includeSavingsValuation,
            inputs: BalanceSeriesInputs(transactions: transactions, resolutions: resolutions, now: now, through: interval.end))
    }

    static func make(conti: [Conto], selectedIDs: Set<UUID>, transactions: [Transaction],
                     interval: DateInterval, now: Date, ledgerSnapshots: [UUID: LedgerCacheSnapshot]?,
                     calendar: Calendar, includeSavingsValuation: Bool, inputs: BalanceSeriesInputs) -> [Self] {
        let snapshots = inputs.snapshots
        let planned = inputs.planned
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
            if includeSavingsValuation && conto.type == .savings {
                var dates = Set(points.map(\.date))
                var day = Calendar.current.startOfDay(for: interval.start)
                while day < min(interval.end, now) {
                    if day >= interval.start { dates.insert(day) }
                    day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                }
                let movements = conto.savingsMovements(transactions: transactions)
                let rates = conto.savingsRates
                let start = rates.first?.effectiveDate ?? conto.createdAt ?? now
                let sampleDates = dates.sorted()
                let samples = SavingsValuation.values(initialBalance: conto.initialBalance ?? 0,
                    start: start, rates: rates, movements: movements, at: sampleDates)
                let values = Array(zip(sampleDates, samples))
                result.savingsCapital = values.map { BalanceDataPoint(date: $0.0, balance: $0.1.capital) }
                result.savingsValue = values.map { BalanceDataPoint(date: $0.0, balance: $0.1.estimatedValue) }
            }
            return result
        }.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
    }
}

extension Array where Element == BalanceDataPoint {
    /// Upper bound retains the last point when multiple changes share a timestamp.
    func balanceIndex(at date: Date) -> Int? {
        var lower = 0, upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if self[middle].date <= date { lower = middle + 1 }
            else { upper = middle }
        }
        return lower == 0 ? nil : lower - 1
    }
}
