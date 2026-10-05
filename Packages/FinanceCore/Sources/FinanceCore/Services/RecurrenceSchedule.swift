import Foundation

/// Each occurrence is anchored to the original date, preserving month-end and leap-day intent.
public enum RecurrenceSchedule {
    /// Converts a date-only choice to an inclusive cutoff in the user's calendar.
    /// Rejects an end day before the anchor, including when the start date is edited.
    public static func inclusiveEnd(anchor: Date, lastDay: Date, calendar: Calendar = .current) -> Date? {
        guard calendar.startOfDay(for: lastDay) >= calendar.startOfDay(for: anchor),
              let interval = calendar.dateInterval(of: .day, for: lastDay) else { return nil }
        // Use millisecond precision so Foundation formatting does not round into the following day.
        return interval.end.addingTimeInterval(-0.001)
    }

    public static func next(anchor: Date, frequency: RecurrenceFrequency, after reference: Date,
                            ending: Date? = nil, calendar: Calendar = .current) -> Date? {
        let step = frequency.componentValue
        let component = frequency.calendarComponent
        let distance = calendar.dateComponents([component], from: anchor, to: reference).value(for: component) ?? 0
        var ordinal = max(0, distance / step)
        while let date = calendar.date(byAdding: component, value: ordinal * step, to: anchor) {
            if let ending, date > ending { return nil }
            if date > reference { return date }
            ordinal += 1
        }
        return nil
    }

    public static func dates(anchor: Date, frequency: RecurrenceFrequency, after reference: Date,
                             through horizon: Date, ending: Date? = nil, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = reference
        while let date = next(anchor: anchor, frequency: frequency, after: cursor, ending: ending, calendar: calendar),
              date <= horizon {
            result.append(date)
            cursor = date
        }
        return result
    }
}
