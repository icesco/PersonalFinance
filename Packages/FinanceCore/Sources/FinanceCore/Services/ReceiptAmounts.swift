import Foundation

public struct ReceiptAmountCandidate: Identifiable, Sendable {
    public let id: Int
    public let amount: Decimal
    public let line: String
    public let isPossibleTotal: Bool
}

public enum ReceiptAmounts {
    /// Candidates, never an automatically accepted total. Rejects dates and incomplete separators.
    public static func candidates(in text: String) -> [ReceiptAmountCandidate] {
        let pattern = #"(?<![\d.,])(?:\d{1,3}(?:[., ]\d{3})+|\d+)[.,]\d{2}(?![\d.,])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [ReceiptAmountCandidate] = []
        for line in text.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            let possibleTotal = lower.range(of: #"\b(totale|total|importo|da pagare)\b"#, options: .regularExpression) != nil
                && !["iva", "tax", "resto", "subtotal", "subtotale", "imponibile"].contains(where: lower.contains)
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let range = Range(match.range, in: line) else { continue }
                let prefix = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let suffix = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !prefix.hasSuffix("-"), !prefix.hasSuffix("−"), !suffix.hasPrefix("%") else { continue }
                let token = String(line[range])
                let digits = token.filter(\.isNumber)
                guard digits.count >= 3, digits.count <= 15 else { continue }
                let normalized = String(digits.dropLast(2)) + "." + String(digits.suffix(2))
                guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else { continue }
                result.append(ReceiptAmountCandidate(id: result.count, amount: amount, line: line, isPossibleTotal: possibleTotal))
            }
        }
        return result.sorted { $0.isPossibleTotal != $1.isPossibleTotal ? $0.isPossibleTotal : $0.id < $1.id }
    }
}
