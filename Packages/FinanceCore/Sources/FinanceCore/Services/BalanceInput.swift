import Foundation

/// A signed balance, using either decimal separator and no grouping separators.
/// Rejects partial parsing, non-finite values and unsupported currency precision.
public enum BalanceInput {
    public static func parse(_ text: String, currency: String) -> Decimal? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return .zero }
        guard input.count <= 64,
              input.range(of: #"^[+-]?(?:[0-9]+(?:[.,][0-9]+)?|[.,][0-9]+)$"#, options: .regularExpression) != nil,
              input.filter(\.isNumber).count <= 28,
              let value = Decimal(string: input.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        var original = value, rounded = Decimal.zero
        NSDecimalRound(&rounded, &original, formatter.maximumFractionDigits, .plain)
        return rounded == value ? value : nil
    }
}
