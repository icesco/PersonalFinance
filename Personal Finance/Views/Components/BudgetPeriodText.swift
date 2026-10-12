import Foundation
import FinanceCore

enum BudgetPeriodText {
    private static let locale = Locale(identifier: "it_IT")

    static func range(_ interval: DateInterval) -> String {
        guard interval.end > interval.start else { return "Periodo non impostato" }
        let end = interval.end.addingTimeInterval(-1)
        let startText = interval.start.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        let endText = end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        return "\(startText) – \(endText)"
    }

    static func title(for period: BudgetPeriod?, interval: DateInterval) -> String {
        switch period {
        case .monthly:
            return interval.start.formatted(.dateTime.month(.wide).year().locale(locale)).localizedCapitalized
        case .quarterly:
            let quarter = (Calendar.current.component(.month, from: interval.start) - 1) / 3 + 1
            return "\(quarter)° trimestre \(interval.start.formatted(.dateTime.year().locale(locale)))"
        case .yearly:
            return interval.start.formatted(.dateTime.year().locale(locale))
        case .weekly:
            return range(interval)
        case nil:
            return "Periodo non impostato"
        }
    }

    static func frequency(for period: BudgetPeriod?) -> String {
        switch period {
        case .weekly: "ogni settimana"
        case .monthly: "ogni mese"
        case .quarterly: "ogni trimestre"
        case .yearly: "ogni anno"
        case nil: "per il periodo del budget"
        }
    }
}
