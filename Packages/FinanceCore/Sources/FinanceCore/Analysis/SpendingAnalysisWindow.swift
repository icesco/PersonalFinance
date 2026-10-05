import Foundation

public enum SpendingAnalysisPeriod: String, CaseIterable, Sendable {
    case week, month, quarter, year

    public var displayName: String {
        switch self {
        case .week: "Settimana"
        case .month: "Mese"
        case .quarter: "Trimestre"
        case .year: "Anno"
        }
    }

    private var intervalComponent: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: intervalComponent, for: date)!
    }

    public func moving(_ date: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = self == .quarter ? .month : intervalComponent
        return calendar.date(byAdding: component, value: offset * (self == .quarter ? 3 : 1), to: date) ?? date
    }
}

/// Calendar-aligned windows. A current period compares equal elapsed calendar
/// components, preserving local clock time across daylight-saving transitions.
public struct SpendingAnalysisWindow: Sendable {
    public let interval: DateInterval
    public let previous: DateInterval

    /// User-facing end dates are inclusive; persistence/query boundaries stay
    /// half-open. Previous custom ranges have the same number of calendar days.
    public init?(start: Date, endInclusive: Date, now: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: endInclusive)
        guard finalDay >= start,
              let end = calendar.date(byAdding: .day, value: 1, to: finalDay),
              let days = calendar.dateComponents([.day], from: start, to: end).day,
              days > 0,
              let previousStart = calendar.date(byAdding: .day, value: -days, to: start) else { return nil }
        interval = DateInterval(start: start, end: end)
        if now >= end {
            previous = DateInterval(start: previousStart, end: start)
        } else if now <= start {
            previous = DateInterval(start: previousStart, duration: 0)
        } else {
            let elapsedDays = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
            let comparisonDay = calendar.date(byAdding: .day, value: elapsedDays, to: previousStart) ?? previousStart
            let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
            let comparisonEnd = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                               second: clock.second ?? 0, of: comparisonDay) ?? start
            previous = DateInterval(start: previousStart, end: min(comparisonEnd, start))
        }
    }

    public init(period: SpendingAnalysisPeriod, anchor: Date, now: Date = Date(), calendar: Calendar = .current) {
        interval = period.interval(containing: anchor, calendar: calendar)
        let previousStart = period.moving(interval.start, by: -1, calendar: calendar)
        let fullPrevious = period.interval(containing: previousStart, calendar: calendar)
        if now >= interval.end {
            previous = fullPrevious
        } else if now <= interval.start {
            previous = DateInterval(start: fullPrevious.start, duration: 0)
        } else {
            let components: Set<Calendar.Component> = period == .year || period == .quarter
                ? [.month, .day] : [.day]
            let elapsed = calendar.dateComponents(components, from: interval.start, to: calendar.startOfDay(for: now))
            let comparisonDay = calendar.date(byAdding: elapsed, to: fullPrevious.start) ?? fullPrevious.end
            let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
            let end = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
                                    second: clock.second ?? 0, of: comparisonDay) ?? fullPrevious.end
            previous = DateInterval(start: fullPrevious.start, end: min(end, fullPrevious.end))
        }
    }
}
