import Foundation

public enum WidgetBalancePeriod: String, Codable, CaseIterable, Sendable {
    case week = "week", month = "month", quarter = "quarter", year = "year"

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        SpendingAnalysisPeriod(rawValue: rawValue)!.interval(containing: date, calendar: calendar)
    }
}

public struct WidgetBalanceSnapshot: Codable, Equatable, Sendable {
    public let period: WidgetBalancePeriod
    public let interval: DateInterval
    public let recordedAt: Date
    public let series: [AccountBalanceSeries]
    public let plannedMovements: [WidgetBalancePlannedMovement]?
    public let scheduledFlowGroups: [WidgetBalanceFlowGroup]?
    public init(period: WidgetBalancePeriod, interval: DateInterval, recordedAt: Date, series: [AccountBalanceSeries],
                plannedMovements: [WidgetBalancePlannedMovement]? = nil, scheduledFlowGroups: [WidgetBalanceFlowGroup]? = nil) {
        self.period = period; self.interval = interval; self.recordedAt = recordedAt; self.series = series
        self.plannedMovements = plannedMovements
        self.scheduledFlowGroups = scheduledFlowGroups
    }

    public var recordedTotal: Decimal { series.reduce(0) { $0 + $1.balance(at: recordedAt) } }
    public var projectedTotal: Decimal { series.reduce(0) { $0 + $1.balance(at: interval.end) } }

    public func selecting(accountIDs: Set<UUID>) -> Self {
        guard !accountIDs.isEmpty else { return self }
        return Self(period: period, interval: interval, recordedAt: recordedAt,
                    series: series.filter { accountIDs.contains($0.id) },
                    plannedMovements: plannedMovements?.filter { $0.involves(accountIDs: accountIDs) },
                    scheduledFlowGroups: scheduledFlowGroups?.filter { $0.movement.involves(accountIDs: accountIDs) })
    }

    public var scheduledFlows: WidgetBalanceScheduledFlows? {
        guard let values = scheduledFlowGroups?.map(\.movement) ?? plannedMovements else { return nil }
        let ids = Set(series.map(\.id))
        var incoming: Decimal = 0
        var outgoing: Decimal = 0
        for movement in values {
            guard let delta = movement.netChange(accountIDs: ids) else {
                return WidgetBalanceScheduledFlows(incoming: nil, outgoing: nil)
            }
            if delta > 0 { incoming += delta }
            else { outgoing -= delta }
        }
        return WidgetBalanceScheduledFlows(incoming: incoming, outgoing: outgoing)
    }

    public var scheduledMovementCount: Int? {
        if let groups = scheduledFlowGroups { return groups.reduce(0) { $0 + $1.count } }
        return plannedMovements?.count
    }

    /// Sum at every account's change date so transfers cancel and no movement is lost.
    public var totalPoints: [BalanceDataPoint] {
        guard !series.isEmpty else { return [] }
        let dates = Set(series.flatMap { $0.points.map(\.date) } + [interval.start, recordedAt])
        return totalBalances(at: dates.filter { $0 >= interval.start && $0 <= recordedAt })
    }

    public var totalProjected: [BalanceDataPoint] {
        guard series.contains(where: { !$0.projected.isEmpty }) else { return [] }
        let dates = Set(series.flatMap { $0.projected.map(\.date) } + [recordedAt, interval.end])
        return totalBalances(at: dates.filter { $0 >= recordedAt && $0 <= interval.end })
    }

    public func minimumProjectedDailyBalance(calendar: Calendar = .current) -> BalanceDataPoint? {
        let future = totalProjected.filter { $0.date > recordedAt }
        let closing = Dictionary(grouping: future) {
            calendar.startOfDay(for: min($0.date, interval.end.addingTimeInterval(-1)))
        }.values.compactMap { $0.last }.sorted { $0.date < $1.date }
        return closing.min { $0.balance < $1.balance }
    }

    private func totalBalances(at dates: [Date]) -> [BalanceDataPoint] {
        dates.sorted().map { date in
            BalanceDataPoint(date: date, balance: series.reduce(0) { $0 + $1.balance(at: date) })
        }
    }

    /// The caller must own all supplied models on its executor.
    public static func make(period: WidgetBalancePeriod, conti: [Conto], transactions: [Transaction],
                            resolutions: [RecurrenceResolution], now: Date, calendar: Calendar = .current,
                            ledgerSnapshots: [UUID: LedgerCacheSnapshot]? = nil) -> Self {
        let interval = period.interval(containing: now, calendar: calendar)
        let values = AccountBalanceSeries.make(conti: conti, selectedIDs: Set(conti.map(\.id)), transactions: transactions,
                                               resolutions: resolutions, interval: interval, now: now,
                                               ledgerSnapshots: ledgerSnapshots, calendar: calendar)
        let compact = values.map { value in
            AccountBalanceSeries(id: value.id, name: value.name, colorHex: value.colorHex,
                                 points: dailyClosing(value.points, calendar: calendar),
                                 projected: dailyClosing(value.projected, calendar: calendar, retainUnchanged: true))
        }
        let ids = Set(compact.map(\.id))
        let sources = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let planned = ProjectedBalanceHistory.plannedTransactions(transactions: transactions, resolutions: resolutions,
            now: now, through: interval.end)
        var seen = Set<String>()
        let movements = planned.compactMap { value -> WidgetBalancePlannedMovement? in
            guard let source = sources[value.id] else { return nil }
            let key = RecurrenceResolution.key(sourceID: value.id, date: value.date)
            guard seen.insert(key).inserted else { return nil }
            let description = source.transactionDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = description.flatMap { $0.isEmpty ? nil : $0 } ?? source.category?.name ?? ""
            let movement = WidgetBalancePlannedMovement(id: key, date: value.date, title: title,
                amount: source.amount.flatMap { $0.isNaN ? nil : $0 }, type: value.type,
                fromAccountID: value.fromContoId, toAccountID: value.toContoId,
                destinationAmount: value.destinationAmount, categoryIcon: source.category?.icon,
                categoryColor: source.category?.color)
            return movement.involves(accountIDs: ids) ? movement : nil
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        // Three rows per account retain the next three for any selection, without duplicating a year's titles.
        let visibleIDs = Set(ids.flatMap { id in movements.filter { $0.involves(accountIDs: [id]) }.prefix(3).map(\.id) })
        let grouped = Dictionary(grouping: movements) {
            let sourceNegative = $0.amount.map { $0 < 0 } ?? false
            let destinationNegative = ($0.destinationAmount ?? $0.amount).map { $0 < 0 } ?? false
            return "\($0.type.rawValue):\($0.fromAccountID?.uuidString ?? ""):\($0.toAccountID?.uuidString ?? ""):\(sourceNegative):\(destinationNegative)"
        }
        let groups = grouped.keys.sorted().compactMap { key -> WidgetBalanceFlowGroup? in
            guard let rows = grouped[key], let first = rows.first else { return nil }
            let known = rows.allSatisfy { $0.amount != nil && $0.amount?.isNaN != true && $0.destinationAmount?.isNaN != true }
            let total: Decimal? = known ? rows.reduce(0) { $0 + ($1.amount ?? 0) } : nil
            let destination: Decimal? = first.type == .transfer && known
                ? rows.reduce(0) { $0 + ($1.destinationAmount ?? $1.amount ?? 0) } : nil
            let movement = WidgetBalancePlannedMovement(id: key, date: now, title: "", amount: total,
                type: first.type, fromAccountID: first.fromAccountID, toAccountID: first.toAccountID, destinationAmount: destination)
            return WidgetBalanceFlowGroup(movement: movement, count: rows.count)
        }
        return Self(period: period, interval: interval, recordedAt: now, series: compact,
                    plannedMovements: movements.filter { visibleIDs.contains($0.id) }, scheduledFlowGroups: groups)
    }

    /// Widgets have no intraday selection: retain daily closing balances and both boundaries.
    private static func dailyClosing(_ points: [BalanceDataPoint], calendar: Calendar, retainUnchanged: Bool = false) -> [BalanceDataPoint] {
        guard let first = points.first, let last = points.last else { return [] }
        var closing: [Date: BalanceDataPoint] = [:]
        for point in points { closing[calendar.startOfDay(for: point.date)] = point }
        var dates = Dictionary(uniqueKeysWithValues: closing.values.map { ($0.date, $0) })
        dates[first.date] = first; dates[last.date] = last
        var result: [BalanceDataPoint] = []
        for point in dates.values.sorted(by: { $0.date < $1.date }) {
            if retainUnchanged || result.last?.balance != point.balance || point.date == last.date { result.append(point) }
        }
        return result
    }
}
