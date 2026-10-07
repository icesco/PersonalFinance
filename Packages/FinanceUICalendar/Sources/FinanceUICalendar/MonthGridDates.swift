import Foundation

func monthGridDates(containing date: Date, calendar: Calendar) -> [Date] {
    guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
    let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
    guard let start = calendar.date(byAdding: .day, value: -leading, to: month.start) else { return [] }
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
}
