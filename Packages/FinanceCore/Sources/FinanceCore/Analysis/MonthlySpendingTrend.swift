import Foundation

/// Daily cumulative recorded expenses, aligned by day of month and local clock time.
public struct MonthlySpendingTrend: Sendable {
    public struct Point: Sendable, Identifiable {
        public let day: Int
        public let amount: Decimal
        public var id: Int { day }
    }
    public let current: [Point]
    public let previous: [Point]
    public let daysInMonth: Int
    public let hasPreviousExpenses: Bool
    public let hasInvalidAmounts: Bool
    public let isInProgress: Bool

    public static func calculate(transactions: [DirectionTransaction], anchor: Date,
                                 now: Date = Date(), calendar: Calendar = .current) -> Self {
        let month = calendar.dateInterval(of: .month, for: anchor)!
        let priorStart = calendar.date(byAdding: .month, value: -1, to: month.start)!
        let prior = calendar.dateInterval(of: .month, for: priorStart)!
        let days = calendar.range(of: .day, in: .month, for: anchor)!.count
        let priorDays = calendar.range(of: .day, in: .month, for: priorStart)!.count
        let inProgress = now < month.end
        let lastDay = now < month.start ? 0 : inProgress ? calendar.component(.day, from: now) : days
        let expenses = transactions.filter { $0.type == .expense && $0.date <= now }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
        func cutoff(_ interval: DateInterval, day: Int, final: Bool) -> Date {
            let start = calendar.date(byAdding: .day, value: day - 1, to: interval.start)!
            if final && inProgress {
                return min(calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                    second: clock.second ?? 0, of: start) ?? start, interval.end)
            }
            return min(calendar.date(byAdding: .day, value: 1, to: start)!, interval.end)
        }
        func series(_ interval: DateInterval, count: Int) -> ([Point], Bool, Bool) {
            guard count > 0 else { return ([], false, false) }
            let end = cutoff(interval, day: count, final: count == lastDay)
            let isCurrent = interval.start == month.start
            let rows = expenses.filter {
                $0.date >= interval.start && $0.date < interval.end &&
                ($0.date < end || (isCurrent && inProgress && $0.date == end))
            }
            var invalid = false
            var total = Decimal.zero
            var index = 0
            let sorted = rows.sorted { $0.date < $1.date }
            let points = (1...count).map { day -> Point in
                let end = cutoff(interval, day: day, final: day == lastDay)
                while index < sorted.count && (sorted[index].date < end || (isCurrent && inProgress && day == lastDay && sorted[index].date == end)) {
                    let row = sorted[index]
                    if row.hasValidAmount && !row.amount.isNaN { total += row.amount }
                    else { invalid = true }
                    index += 1
                }
                return Point(day: day, amount: total)
            }
            return (points, !rows.isEmpty, invalid)
        }
        let current = series(month, count: lastDay)
        let previous = series(prior, count: inProgress ? min(lastDay, priorDays) : priorDays)
        return Self(current: current.0, previous: previous.0, daysInMonth: days,
                    hasPreviousExpenses: previous.1, hasInvalidAmounts: current.2 || previous.2,
                    isInProgress: inProgress)
    }
}
