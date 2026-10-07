import Foundation

public struct FinanceCalendarEvent: Identifiable, Sendable {
    public enum Kind: Sendable { case recorded, planned, recurrence }
    public let id: String
    public let transactionID: UUID
    public let date: Date
    public let amount: Decimal?
    public let type: TransactionType
    public let title: String
    public let kind: Kind
}

/// Calendar browsing never creates transactions. Materialized and skipped occurrences are suppressed.
@MainActor
public enum FinanceCalendarEvents {
    public static func build(transactions: [Transaction], resolutions: [RecurrenceResolution],
                             contoIDs: Set<UUID>, interval: DateInterval, now: Date = Date()) -> [FinanceCalendarEvent] {
        var seen: Set<UUID> = []
        let scoped = transactions.filter {
            seen.insert($0.id).inserted &&
            (($0.fromContoId.map(contoIDs.contains) ?? false) || ($0.toContoId.map(contoIDs.contains) ?? false))
        }
        let resolved = Set(resolutions.map(\.key)).union(scoped.compactMap { row -> String? in
            guard let source = row.recurrenceSourceID else { return nil }
            return row.externalID.hasPrefix("recurrence:") ? row.externalID : RecurrenceResolution.key(sourceID: source, date: row.date)
        })
        var events: [FinanceCalendarEvent] = []
        for row in scoped where row.type != .transfer {
            let title = row.transactionDescription ?? row.category?.name ?? "Movimento"
            let amount = row.amount.flatMap { $0.isNaN ? nil : $0 }
            if row.date >= interval.start && row.date < interval.end {
                events.append(.init(id: row.id.uuidString, transactionID: row.id, date: row.date,
                    amount: amount, type: row.type, title: title, kind: row.date <= now ? .recorded : .planned))
            }
            if row.isRecurring == true {
                for date in RecurrenceOccurrenceService.pendingDates(source: row, interval: interval, resolvedKeys: resolved) {
                    events.append(.init(id: RecurrenceResolution.key(sourceID: row.id, date: date), transactionID: row.id,
                        date: date, amount: amount, type: row.type, title: title, kind: .recurrence))
                }
            }
        }
        return events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
