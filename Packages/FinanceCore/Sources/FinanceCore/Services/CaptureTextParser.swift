import Foundation

public struct CaptureMoney: Equatable, Sendable {
    public let amount: Decimal
    public let currency: String
}
public enum CaptureTextParser {
    /// Only explicit currency amounts are suggested; a balance and a payment stay ambiguous.
    public static func money(in text: String) -> [CaptureMoney] {
        let currency = #"(?:EUR|USD|GBP|CHF|JPY|CAD|AUD|€|\$|£)"#
        let number = #"(?:\d{1,3}(?:[., ]\d{3})+|\d+)(?:[.,]\d{2})?"#
        let pattern = "(?<![\\w.,])(?:(" + currency + ")\\s*(" + number + ")|(" + number + ")\\s*(" + currency + "))(?![\\w]|[.,]\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var values: [CaptureMoney] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            func group(_ n: Int) -> String? { Range(match.range(at: n), in: text).map { String(text[$0]) } }
            guard let token = group(2) ?? group(3), let rawCurrency = group(1) ?? group(4), let amount = decimal(token), amount > 0 else { continue }
            let code: String
            switch rawCurrency.uppercased() { case "€": code = "EUR"; case "$": code = ""; case "£": code = "GBP"; default: code = rawCurrency.uppercased() }
            let value = CaptureMoney(amount: amount, currency: code)
            if !values.contains(value) { values.append(value) }
        }
        return values
    }
    public static func decimal(_ text: String) -> Decimal? {
        var token = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !token.isEmpty, token.range(of: #"^(?:[0-9]+(?:[.,][0-9]{1,2})?|[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]{1,3}(?:\.[0-9]{3})+(?:,[0-9]{1,2})?)$"#, options: .regularExpression) != nil else { return nil }
        if let separator = token.lastIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = token.distance(from: token.index(after: separator), to: token.endIndex)
            if fraction == 1 || fraction == 2 {
                token = token[..<separator].filter(\.isNumber) + "." + token[token.index(after: separator)...]
            } else if fraction == 3 { token = token.filter(\.isNumber) } else { return nil }
        }
        return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func merchant(in text: String) -> String? {
        let pattern = #"(?:presso|merchant:|esercente:|fornitore:|at)\s+([^\n;]+)"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let fragment = String(text[range])
        guard let start = fragment.range(of: #"^(?:presso|merchant:|esercente:|fornitore:|at)\s+"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(fragment[start.upperBound...].prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
