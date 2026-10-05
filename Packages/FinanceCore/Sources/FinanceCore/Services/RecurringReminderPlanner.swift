import Foundation

public struct DailyRecurrenceReminder: Hashable, Sendable {
    public let fireDate: Date
    public let count: Int
    public var identifier: String { "forgia.recurrence.\(Int(fireDate.timeIntervalSince1970))" }
}

public enum RecurringReminderPlanner {
    /// One discreet digest per day. Dates at or before now are never scheduled retroactively.
    public static func plan(occurrences: [Date], hour: Int, minute: Int, daysBefore: Int,
                            now: Date = Date(), calendar: Calendar = .current) -> [DailyRecurrenceReminder] {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...1).contains(daysBefore) else { return [] }
        var counts: [Date: Int] = [:]
        for date in occurrences {
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: date),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > now else { continue }
            counts[fire, default: 0] += 1
        }
        return counts.map { DailyRecurrenceReminder(fireDate: $0.key, count: $0.value) }
            .sorted { $0.fireDate < $1.fireDate }
    }
}

/// Scheduled entries are already recorded, so reminders do not create or count
/// them again. Generated recurrence instances have already been resolved by the user.
public enum ScheduledTransactionReminders {
    public static func dates(transactions: [Transaction], now: Date, through end: Date) -> [Date] {
        var seen: Set<UUID> = []
        return transactions.compactMap { transaction in
            guard seen.insert(transaction.id).inserted,
                  transaction.date > now, transaction.date <= end,
                  transaction.recurrenceSourceID == nil else { return nil }
            let conto = transaction.type == .income ? transaction.toConto : transaction.fromConto
            guard conto?.isActive == true, conto?.account?.isActive == true else { return nil }
            return transaction.date
        }
    }
}
