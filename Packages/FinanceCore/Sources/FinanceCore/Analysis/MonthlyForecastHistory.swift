import Foundation

public struct MonthlyForecastHistoryExclusion: Identifiable, Sendable, Equatable {
    public enum Reason: String, CaseIterable, Sendable {
        case recurringPayment, mixedCategory, sporadic

        public var explanation: LocalizedStringResource {
            switch self {
            case .recurringPayment: "Pagamenti compatibili con una ricorrente già prevista"
            case .mixedCategory: "Categorie usate anche per entrate o apporti: da verificare"
            case .sporadic: "Spese senza una frequenza sufficiente nello storico"
            }
        }
    }
    public let reason: Reason
    public let events: [FinanceCalendarEvent]
    public var id: String { reason.rawValue }
}

enum MonthlyForecastHistory {
    static func categoryKey(_ row: Transaction) -> String {
        row.categoryId?.uuidString ?? row.category?.id.uuidString ?? "uncategorized"
    }

    /// Only affects the estimate. A resemblance never resolves an occurrence or changes the ledger.
    static func recurringPayments(history: [Transaction], sources: [Transaction], calendar: Calendar) -> Set<UUID> {
        var excluded: Set<UUID> = []
        let historyByCategory = Dictionary(grouping: history, by: categoryKey)
        for source in sources.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let frequency = source.recurrenceFrequency, let amount = source.amount,
                  categoryKey(source) != "uncategorized" else { continue }
            let tolerance = frequency == .daily ? 0 : [.weekly, .biweekly].contains(frequency) ? 1 : 3
            let component = frequency.calendarComponent
            let step = frequency.componentValue
            let candidates = (historyByCategory[categoryKey(source)] ?? []).compactMap { row -> (row: Transaction, slot: Date, distance: Int)? in
                guard !excluded.contains(row.id), row.amount == amount,
                      categoryKey(row) == categoryKey(source) else { return nil }
                let distance = calendar.dateComponents([component], from: source.date, to: row.date).value(for: component) ?? 0
                let ordinal = distance / step
                let slots = ((ordinal - 1)...(ordinal + 1)).compactMap {
                    calendar.date(byAdding: component, value: $0 * step, to: source.date)
                }
                let ranked = slots.map { slot in
                    (slot, abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: slot),
                                                       to: calendar.startOfDay(for: row.date)).day ?? Int.max))
                }.sorted { $0.1 < $1.1 }
                guard let closest = ranked.first, closest.1 <= tolerance else { return nil }
                return (row, calendar.startOfDay(for: closest.0), closest.1)
            }.sorted {
                $0.distance == $1.distance ? $0.row.id.uuidString < $1.row.id.uuidString : $0.distance < $1.distance
            }
            var slots: Set<Date> = []
            let matches = candidates.filter { slots.insert($0.slot).inserted }
            let months = Set(matches.map { calendar.dateInterval(of: .month, for: $0.row.date)!.start })
            if months.count >= 2 { excluded.formUnion(matches.map { $0.row.id }) }
        }
        return excluded
    }
}
