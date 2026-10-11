import Foundation

public struct MarginScenario: Sendable, Equatable {
    public enum Outcome: Sendable { case remaining, exhausted, shortfall }
    public let remaining: Decimal
    public var outcome: Outcome { remaining > 0 ? .remaining : remaining == 0 ? .exhausted : .shortfall }

    public init?(margin: Decimal, expense: Decimal, currency: String = "EUR") {
        guard !margin.isNaN, !expense.isNaN, expense >= 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        var originalMargin = margin
        var originalExpense = expense
        var roundedMargin = Decimal()
        var roundedExpense = Decimal()
        // Compare the amounts the user sees, including currencies with zero or three minor digits.
        NSDecimalRound(&roundedMargin, &originalMargin, formatter.maximumFractionDigits, .bankers)
        NSDecimalRound(&roundedExpense, &originalExpense, formatter.maximumFractionDigits, .bankers)
        let result = roundedMargin - roundedExpense
        guard !result.isNaN else { return nil }
        remaining = result
    }

    /// A plain decimal amount; grouping separators and expressions are not accepted.
    public static func expense(from text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, normalized.contains(where: { $0.isASCII && $0.isNumber }),
              normalized.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }),
              normalized.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0 else { return nil }
        return value
    }
}
