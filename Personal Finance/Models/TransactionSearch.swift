import Foundation

enum TransactionSearch {
    static func matches(query: String, fields: [String?], amount: Decimal) -> Bool {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace).map { token in
            let value = String(token)
            if value.range(of: "^-?[0-9]+([.][0-9]+)?$", options: .regularExpression) != nil,
               let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) {
                return NSDecimalNumber(decimal: decimal).stringValue
            }
            return value
        }
        guard !terms.isEmpty else { return true }
        let amountText = NSDecimalNumber(decimal: amount).stringValue
        let text = normalized((fields.compactMap { $0 } + [amountText]).joined(separator: " "))
        return terms.allSatisfy { text.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .replacingOccurrences(of: ",", with: ".")
    }
}

/// Finestra temporale della ricerca: per default copre tutte le date del libro.
enum TransactionSearchPeriod: CaseIterable {
    case all, last30Days, last3Months, thisYear, lastYear

    var displayName: String {
        switch self {
        case .all: "Sempre"
        case .last30Days: "Ultimi 30 giorni"
        case .last3Months: "Ultimi 3 mesi"
        case .thisYear: "Quest’anno"
        case .lastYear: "Anno scorso"
        }
    }

    /// Half-open range; `nil` means no date bound. Rolling windows end at the start of tomorrow.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        switch self {
        case .all:
            return nil
        case .last30Days:
            return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: startOfTomorrow)!, end: startOfTomorrow)
        case .last3Months:
            return DateInterval(start: calendar.date(byAdding: .month, value: -3, to: startOfTomorrow)!, end: startOfTomorrow)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .lastYear:
            return calendar.dateInterval(of: .year, for: calendar.date(byAdding: .year, value: -1, to: now)!)
        }
    }
}

enum TransactionSearchSort: CaseIterable {
    case newest, oldest, highestAmount, lowestAmount

    var displayName: String {
        switch self {
        case .newest: "Più recenti"
        case .oldest: "Meno recenti"
        case .highestAmount: "Importo più alto"
        case .lowestAmount: "Importo più basso"
        }
    }

    var groupsByMonth: Bool { self == .newest || self == .oldest }
}
