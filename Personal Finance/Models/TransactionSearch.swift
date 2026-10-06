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
