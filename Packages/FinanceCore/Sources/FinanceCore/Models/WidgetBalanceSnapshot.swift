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
    public init(period: WidgetBalancePeriod, interval: DateInterval, recordedAt: Date, series: [AccountBalanceSeries]) {
        self.period = period; self.interval = interval; self.recordedAt = recordedAt; self.series = series
    }

    public var recordedTotal: Decimal { series.reduce(0) { $0 + $1.balance(at: recordedAt) } }
    public var projectedTotal: Decimal { series.reduce(0) { $0 + $1.balance(at: interval.end) } }

    @MainActor
    public static func make(period: WidgetBalancePeriod, conti: [Conto], transactions: [Transaction],
                            resolutions: [RecurrenceResolution], now: Date, calendar: Calendar = .current) -> Self {
        let interval = period.interval(containing: now, calendar: calendar)
        let values = AccountBalanceSeries.make(conti: conti, selectedIDs: Set(conti.map(\.id)), transactions: transactions,
                                               resolutions: resolutions, interval: interval, now: now)
        let compact = values.map { value in
            AccountBalanceSeries(id: value.id, name: value.name, colorHex: value.colorHex,
                                 points: dailyClosing(value.points, calendar: calendar),
                                 projected: dailyClosing(value.projected, calendar: calendar))
        }
        return Self(period: period, interval: interval, recordedAt: now, series: compact)
    }

    /// Widgets have no intraday selection: retain daily closing balances and both boundaries.
    private static func dailyClosing(_ points: [BalanceDataPoint], calendar: Calendar) -> [BalanceDataPoint] {
        guard let first = points.first, let last = points.last else { return [] }
        var closing: [Date: BalanceDataPoint] = [:]
        for point in points { closing[calendar.startOfDay(for: point.date)] = point }
        var dates = Dictionary(uniqueKeysWithValues: closing.values.map { ($0.date, $0) })
        dates[first.date] = first; dates[last.date] = last
        var result: [BalanceDataPoint] = []
        for point in dates.values.sorted(by: { $0.date < $1.date }) {
            if result.last?.balance != point.balance || point.date == last.date { result.append(point) }
        }
        return result
    }
}
