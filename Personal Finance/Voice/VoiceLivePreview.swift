import Foundation

/// A partial transcript hint, never a transaction draft or a source for saving.
struct VoiceLiveToken: Equatable {
    enum Direction { case expense, income }
    let sourceOffset: Int
    let amount: Decimal
    let currency: String
    let title: String
    let direction: Direction?
}

enum VoiceLivePreview {
    private static let smallNumbers: [String: Int] = [
        "uno": 1, "un": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5,
        "sei": 6, "sette": 7, "otto": 8, "nove": 9, "dieci": 10,
        "undici": 11, "dodici": 12, "tredici": 13, "quattordici": 14,
        "quindici": 15, "sedici": 16, "diciassette": 17, "diciotto": 18,
        "diciannove": 19, "venti": 20, "trenta": 30, "quaranta": 40,
        "cinquanta": 50, "sessanta": 60, "settanta": 70, "ottanta": 80, "novanta": 90
    ]
    private static let amountPattern = #"(?<![\p{L}\p{N}.,])(?:(\d+(?:[.,]\d+)*|[\p{L}]+)\s*(euro|eur|€|dollari|usd|sterline|gbp)|([€$£])\s*(\d+(?:[.,]\d+)*))(?![\p{L}\p{N}])"#
    private static let expensePattern = #"\b(?:speso|spesi|pagato|pagati|comprato|acquistato)\b"#
    private static let incomePattern = #"\b(?:ricevuto|ricevuti|incassato|guadagnato|accreditato)\b"#
    private static let unresolvedPattern = #"\b(?:non(?!\s+solo\b)|mai|trasferit\w*|vorrei|potrei|esempio|spenderei|pagherei)\b"#
    private static let clauseBoundary = #"[;!?]|\.(?=\s|$)|\b(?:ma|però)\b|\be\s+(?=(?:non\s+)?(?:ho|abbiamo|speso|pagato|ricevuto|incassato|trasferito)\b)"#

    static func tokens(in transcript: String) -> [VoiceLiveToken] {
        // Bound work on every speech recognition revision, including pasted text.
        let text = String(transcript.prefix(4_000))
        let ns = text as NSString
        let amounts = matches(amountPattern, in: text)
        let boundaries = matches(clauseBoundary, in: text)
        var result: [VoiceLiveToken] = []
        for (index, match) in amounts.enumerated() {
            let rawAmount = capture(match, group: match.range(at: 1).location != NSNotFound ? 1 : 4, in: ns)
            guard var amount = number(rawAmount), amount > 0 else { continue }
            let marker = capture(match, group: match.range(at: 2).location != NSNotFound ? 2 : 3, in: ns).lowercased()
            let currency = ["$", "usd", "dollari"].contains(marker) ? "USD" :
                (["£", "gbp", "sterline"].contains(marker) ? "GBP" : "EUR")
            let clauseStart = boundaries.last { NSMaxRange($0.range) <= match.range.location }.map { NSMaxRange($0.range) } ?? 0
            let clauseEnd = boundaries.first { $0.range.location >= NSMaxRange(match.range) }?.range.location ?? ns.length
            let clause = ns.substring(with: NSRange(location: clauseStart, length: clauseEnd - clauseStart))
            guard matches(unresolvedPattern, in: clause).isEmpty else { continue }
            let nextAmount = index + 1 < amounts.count ? amounts[index + 1].range.location : ns.length
            let end = min(clauseEnd, nextAmount)
            var suffix = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: max(0, end - NSMaxRange(match.range))))
            if let cents = matches(#"^\s+e\s+(\d{1,2}|[\p{L}]+)(?:\s+centesimi)?(?=\s|[.,;!?]|$)"#, in: suffix).first,
               let value = number(capture(cents, group: 1, in: suffix as NSString)), value > 0, value < 100 {
                amount += value / 100
                suffix = (suffix as NSString).substring(from: NSMaxRange(cents.range))
            }
            let prefix = ns.substring(with: NSRange(location: clauseStart, length: match.range.location - clauseStart))
            let expense = matches(expensePattern, in: prefix).last?.range.location ?? -1
            let income = matches(incomePattern, in: prefix).last?.range.location ?? -1
            let direction: VoiceLiveToken.Direction? = expense == -1 && income == -1 ? nil : (income > expense ? .income : .expense)
            let after = description(suffix)
            let hasPreviousAmountInClause = index > 0 && amounts[index - 1].range.location >= clauseStart
            let before = hasPreviousAmountInClause ? "" : description(prefix)
            result.append(VoiceLiveToken(sourceOffset: match.range.location, amount: amount, currency: currency,
                                         title: after.isEmpty ? before : after, direction: direction))
        }
        return result
    }

    private static func description(_ text: String) -> String {
        var value = text
        for pattern in [
            #"\b(?:sul|su|dal|dalla|nel|con il)\s+(?:conto|carta)\b.*$"#,
            #"\b(?:ieri|oggi|domani|stamattina|stasera|il\s+\d|alle\s+\d)\b.*$"#,
            #"\b(?:ho|abbiamo|speso|spesi|pagato|pagati|ricevuto|ricevuti|incassato|guadagnato|accreditato|comprato|acquistato)\b"#,
            #"(?:\s+e\s*)$"#,
            #"^\s*(?:(?:al|alla|allo|ai|alle|a|per|da|dal|dalla|di|del|della|il|lo|la|un|una)\s+)+"#,
            #"\s+(?:di|da|per)\s*$"#
        ] {
            value = value.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func number(_ text: String) -> Decimal? {
        let word = text.lowercased()
        if let small = smallNumbers[word] { return Decimal(small) }
        for (tens, value) in smallNumbers where value >= 20 {
            for (unit, digit) in smallNumbers where digit < 10 && unit != "un" {
                let stem = digit == 1 || digit == 8 ? String(tens.dropLast()) : tens
                if word == stem + unit { return Decimal(value + digit) }
            }
        }
        var numeric = text
        if numeric.contains(",") { numeric = numeric.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if !matches(#"^\d{1,3}(?:\.\d{3})+$"#, in: numeric).isEmpty { numeric = numeric.replacingOccurrences(of: ".", with: "") }
        return Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func capture(_ match: NSTextCheckingResult, group: Int, in text: NSString) -> String {
        let range = match.range(at: group)
        return range.location == NSNotFound ? "" : text.substring(with: range)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
