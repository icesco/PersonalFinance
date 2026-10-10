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

    private static let monthNames = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static var datePattern: String {
        #"\b(?:l['’]altro ieri|dopodomani|day before yesterday|day after tomorrow|ieri|oggi|domani|stamattina|stasera|stanotte|yesterday|today|tomorrow|this morning|this evening|\d+\s+giorni?\s+fa|\d+\s+days?\s+ago|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{1,2}\.\d{1,2}\.\d{4}|\d{1,2}\s+(?:"#
            + monthNames.joined(separator: "|")
            + #")(?:\s+\d{4})?|(?:la\s+)?(?:settimana|mese|anno)\s+(?:scors[oa]|prossim[oa])|last (?:week|month|year)|next (?:week|month|year)|lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
    }

    static func date(in text: String, clause: String?, expression: String, now: Date) -> Date? {
        let all = matches(datePattern, in: text)
        guard !all.isEmpty else { return now }
        let local = matches(datePattern, in: clause ?? "")
        let unique = Set(all.map { $0.text.lowercased() })
        let source: String
        if local.count == 1 {
            source = local[0].text
        } else if unique.count == 1, let first = all.first {
            source = first.text
        } else if contains(expression, in: clause ?? ""), matches(datePattern, in: expression).count == 1 {
            source = expression
        } else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let key = source.lowercased()
        let offsets = ["ieri": -1, "yesterday": -1, "l'altro ieri": -2, "l’altro ieri": -2, "day before yesterday": -2,
                       "oggi": 0, "today": 0, "stamattina": 0, "stasera": 0, "stanotte": 0, "this morning": 0, "this evening": 0,
                       "domani": 1, "tomorrow": 1, "dopodomani": 2, "day after tomorrow": 2]
        if let offset = offsets[key] {
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        }
        if key.contains(" fa") || key.contains(" ago"), let count = matches(#"\d+"#, in: key).first.flatMap({ Int($0.text) }) {
            return calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now))
        }
        if let iso = matches(#"^\d{4}-\d{1,2}-\d{1,2}$"#, in: key).first {
            let parts = iso.text.split(separator: "-").compactMap { Int($0) }
            return strictDay(year: parts[0], month: parts[1], day: parts[2], now: now, calendar: calendar)
        }
        if let monthIndex = monthNames.firstIndex(where: { key.contains($0) }) {
            let numbers = matches(#"\d+"#, in: key).compactMap { Int($0.text) }
            guard let day = numbers.first else { return nil }
            return strictDay(year: numbers.count > 1 ? numbers[1] : calendar.component(.year, from: now), month: monthIndex % 12 + 1, day: day, now: now, calendar: calendar)
        }
        if !matches(#"^\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?$"#, in: key).isEmpty {
            let numbers = matches(#"\d+"#, in: key).compactMap { Int($0.text) }
            // Numeric dates without a four-digit year remain ambiguous across locales.
            guard numbers.count == 3, numbers[2] > 999 else { return nil }
            return strictDay(year: numbers[2], month: numbers[1], day: numbers[0], now: now, calendar: calendar)
        }
        // A weekday or vague range needs review rather than a model-generated precise day.
        return nil
    }

    private static func strictDay(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Date? {
        VoiceTransactionDraft.resolvedDate(String(format: "%04d-%02d-%02d", year, month, day), wasSpecified: true, now: now, calendar: calendar)
    }

    private static func matches(_ pattern: String, in text: String) -> [(text: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]), range)
        }
    }
}
