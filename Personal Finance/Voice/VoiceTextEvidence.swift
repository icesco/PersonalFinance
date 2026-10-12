import Foundation
import FinanceCore

enum VoiceTextEvidence {
    static func contains(_ quote: String, in text: String) -> Bool {
        !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func clause(for quote: String, in text: String) -> String? {
        let words = quote.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        // The model may repeat an elided verb: "ho speso 5 euro" for "e 5 euro".
        // Locate the literal suffix, then retain its original clause, including any negation.
        let candidates = (0..<min(5, words.count)).map { words.dropFirst($0).joined(separator: " ") }
        guard let quote = candidates.first(where: { $0.split(separator: " ").count >= 2 && contains($0, in: text) }) else { return nil }
        // Preserve decimal amounts and "e cinquanta" while separating independent statements.
        let boundaries = matches(#"[;!?]|\.(?=\s|$)|\b(?:ma|però|but)\b|\be\s+(?=(?:(?:ieri|oggi|domani|stamattina|stasera)\s+)?(?:non\s+)?(?:ho|hai|ha|abbiamo|pagato|speso|ricevuto|trasferito)\b)"#, in: text)
        var start = text.startIndex
        var clauses: [String] = []
        for boundary in boundaries {
            clauses.append(String(text[start..<boundary.range.lowerBound]))
            start = boundary.range.upperBound
        }
        clauses.append(String(text[start...]))
        let containing = clauses.filter { contains(quote, in: $0) }
        if containing.count == 1 { return containing[0] }
        // A quote spanning several clauses is kept conservative rather than dropping a negation.
        return text
    }

    static func isUnresolved(_ text: String) -> Bool {
        !matches(#"\b(?:non(?!\s+solo\b)|mai|not|never|trasferit\w*|transfer\w*|ipotetic\w*|esempio|example|vorrei|potrei|spenderei|pagherei)\b|\bse\s+(?:spendessi|pagassi|ricevessi)\b"#, in: text).isEmpty
    }

    static func isDirectionFragment(_ text: String) -> Bool {
        !matches(#"^\s*(?:non\s+)?(?:ho\s+)?(?:pagato|speso|ricevuto|versato|trasferito)\s*$"#, in: text).isEmpty
    }

    static func accountWasSpoken(_ name: String, in text: String) -> Bool {
        let literal = NSRegularExpression.escapedPattern(for: name)
        return !matches(#"\b(?:(?:conto|account)\s+|(?:su|sul|sulla|dal|dalla|da|nel|nella|con|on|from|in)\s+(?:(?:il|la|my)\s+)?)[“"']?"# + literal + #"(?![\p{L}\p{N}])"#, in: text).isEmpty
    }

    static func purpose(_ proposed: String, in text: String, accountNames: [String]) -> String {
        guard contains(proposed, in: text) else { return "" }
        let ignored = Set(("ho hai ha abbiamo ricevuto ricevuti speso spesi pagato pagati pagamento pagamenti versato accreditato euro eur conto dal sul al il lo la i gli le un una di da e a per received spent paid payment money the on in bank".split(separator: " ").map(String.init))
            + accountNames.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
        let words = matches(#"\p{L}+"#, in: proposed).map { $0.text.lowercased() }
        return words.contains { !ignored.contains($0) } ? proposed : ""
    }

    /// Dates and times are resolved by FinanceCore so the rules are unit-tested.
    static func date(in text: String, clause: String?, expression: String, now: Date) -> Date? {
        SpokenDateParser.date(in: text, clause: clause, expression: expression, now: now)
    }

    private static func matches(_ pattern: String, in text: String) -> [(text: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]), range)
        }
    }
}
