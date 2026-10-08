import Foundation

/// Value-only schedule published by the app; the widget never opens the model store.
public struct WidgetUpcomingTransaction: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let title: String
    public let amount: Decimal?
    public let type: TransactionType
    /// Optional so older schedules still decode. Uses the directly assigned category, including subcategories.
    public let categoryIcon: String?
    public let categoryColor: String?

    public init(id: String, date: Date, title: String, amount: Decimal?, type: TransactionType,
                categoryIcon: String? = nil, categoryColor: String? = nil) {
        self.id = id; self.date = date; self.title = title; self.amount = amount; self.type = type
        self.categoryIcon = categoryIcon; self.categoryColor = categoryColor
    }
}

public struct WidgetUpcomingSnapshot: Codable, Equatable, Sendable {
    /// Complete recurrence window; a more distant next occurrence and all future one-off entries are also included.
    public let coverageEnd: Date
    public let transactions: [WidgetUpcomingTransaction]

    public init(coverageEnd: Date, transactions: [WidgetUpcomingTransaction]) {
        self.coverageEnd = coverageEnd; self.transactions = transactions
    }

    public func upcoming(at date: Date) -> [WidgetUpcomingTransaction] {
        transactions.filter { $0.date > date }
    }

    /// Models must belong to the calling executor, just like FinanceWidgetBuilder's inputs.
    static func build(transactions: [Transaction], resolutions: [RecurrenceResolution],
                      contoIDs: Set<UUID>, now: Date, calendar: Calendar) -> Self {
        let end = calendar.date(byAdding: .day, value: 90, to: now) ?? now
        let resolved = Set(resolutions.map(\.key)).union(transactions.compactMap { row -> String? in
            guard let source = row.recurrenceSourceID else { return nil }
            return RecurrenceResolution.key(sourceID: source, date: row.date)
        })
        var seen: Set<String> = []
        var values: [WidgetUpcomingTransaction] = []
        for row in transactions where row.type != .transfer {
            let contoID = row.type == .income ? row.toContoId ?? row.toConto?.id : row.fromContoId ?? row.fromConto?.id
            guard let contoID, contoIDs.contains(contoID) else { continue }
            let title = row.transactionDescription.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? row.category?.name ?? ""
            let amount = row.amount.flatMap { $0.isNaN ? nil : $0 }
            func append(id: String, date: Date) {
                guard date > now, seen.insert(id).inserted else { return }
                values.append(.init(id: id, date: date, title: title, amount: amount, type: row.type,
                                    categoryIcon: row.category?.icon,
                                    categoryColor: row.category.map { $0.color ?? CategoryPalette.fallback }))
            }
            // A future seed is a single planned transaction, not a generated occurrence.
            append(id: row.id.uuidString, date: row.date)
            guard row.isRecurring == true, row.recurrenceSourceID == nil else { continue }
            let reference = max(now, row.date)
            var occurrenceDates = row.recurrenceDates(after: reference, through: end)
            // An annual bill must remain the next expense even outside the calendar window.
            var cursor = max(reference, end.addingTimeInterval(-0.001))
            while let next = row.nextRecurrenceDate(after: cursor) {
                let key = RecurrenceResolution.key(sourceID: row.id, date: next)
                if !resolved.contains(key) { occurrenceDates.append(next); break }
                cursor = next
            }
            for date in occurrenceDates {
                let key = RecurrenceResolution.key(sourceID: row.id, date: date)
                if !resolved.contains(key) { append(id: key, date: date) }
            }
        }
        values.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        return Self(coverageEnd: end, transactions: values)
    }
}

/// The next expense day for compact widgets, falling back to income when there are no expenses.
public struct WidgetUpcomingDaySummary: Equatable, Sendable {
    public let date: Date
    public let type: TransactionType
    public let daysUntilDue: Int
    public let transactions: [WidgetUpcomingTransaction]

    /// Never present a partial sum as the day's total when an amount is unknown.
    public var total: Decimal? {
        guard transactions.allSatisfy({ $0.amount != nil && $0.amount?.isNaN == false }) else { return nil }
        return transactions.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    public var categoryRepresentatives: [WidgetUpcomingTransaction] {
        var seen: Set<String> = []
        return transactions.filter {
            seen.insert("\($0.categoryIcon ?? $0.type.icon)|\($0.categoryColor ?? "")").inserted
        }
    }

    public static func next(in transactions: [WidgetUpcomingTransaction], at now: Date,
                            calendar: Calendar = .current) -> Self? {
        let upcoming = transactions.filter { $0.date > now && $0.type != .transfer }
        let expenses = upcoming.filter { $0.type == .expense }
        let candidates = expenses.isEmpty ? upcoming.filter { $0.type == .income } : expenses
        let sorted = candidates.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        guard let first = sorted.first else { return nil }
        let rows = sorted.filter { calendar.isDate($0.date, inSameDayAs: first.date) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: first.date)).day ?? 0
        return Self(date: first.date, type: first.type, daysUntilDue: days, transactions: rows)
    }
}
