import Foundation

/// Resolves the date and time spoken for a dictated movement ("ieri sera", "sabato alle 13",
/// "tre giorni fa", "il 5 alle 8 e mezza"). Returns `nil` when the words are ambiguous, so the
/// movement is flagged for review instead of silently landing on a guessed day.
public enum SpokenDateParser {
    /// - Parameters:
    ///   - text: The whole dictation, used when a date or time is shared by several movements.
    ///   - clause: The part of the dictation describing this movement, if it could be located.
    ///   - expression: The date words the language model copied for this movement.
    /// - Returns: `now` when nothing about time was said; a precise moment when it was; `nil` when unclear.
    public static func date(in text: String, clause: String?, expression: String, now: Date,
                            calendar: Calendar = .current) -> Date? {
        let day = pick(dayPattern, text: text, clause: clause, expression: expression, strict: true)
        let time = pick(timePattern, text: text, clause: clause, expression: expression)
        let period = pick(periodPattern, text: text, clause: clause, expression: expression)
        if case .ambiguous = day { return nil }
        if case .ambiguous = time { return nil }
        guard day.value != nil || time.value != nil || period.value != nil else { return now }

        let today = calendar.startOfDay(for: now)
        let periodWord = period.value?.lowercased()
        var base = today
        if let spoken = day.value {
            guard let resolved = resolveDay(spoken.lowercased(), now: now, calendar: calendar) else { return nil }
            base = resolved
        }

        let clock: (hour: Int, minute: Int)
        if let spoken = time.value {
            guard let parsed = resolveTime(spoken.lowercased(), period: periodWord) else { return nil }
            clock = parsed
        } else if let periodWord, let typical = typicalTime(for: periodWord) {
            clock = typical
        } else if periodWord.map(isNight) == true {
            // "Stanotte" can mean before or after midnight: ask rather than guess the day.
            return nil
        } else {
            clock = (calendar.component(.hour, from: now), calendar.component(.minute, from: now))
        }
        return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: base)
    }

    // MARK: - Choosing the words that belong to this movement

    private enum Pick {
        case none, value(String), ambiguous
        var value: String? { if case .value(let text) = self { text } else { nil } }
    }

    /// Words in the movement's own clause win; otherwise a single shared value applies to every movement.
    /// `strict` asks for review when other movements name different days and this one names none.
    private static func pick(_ pattern: String, text: String, clause: String?, expression: String, strict: Bool = false) -> Pick {
        let local = distinct(matches(pattern, in: clause ?? ""))
        if local.count == 1 { return .value(local[0]) }
        if local.count > 1 { return .ambiguous }
        let all = distinct(matches(pattern, in: text))
        if all.isEmpty { return .none }
        if all.count == 1 { return .value(all[0]) }
        let spoken = distinct(matches(pattern, in: expression))
        if spoken.count == 1, let clause, clause.range(of: spoken[0], options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return .value(spoken[0])
        }
        // Other movements carry their own words and this one has none.
        return strict || clause == nil || clause == text ? .ambiguous : .none
    }

    private static func distinct(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Vocabulary

    private static let months = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto",
                                 "settembre", "ottobre", "novembre", "dicembre", "january", "february", "march", "april",
                                 "may", "june", "july", "august", "september", "october", "november", "december"]
    /// Gregorian weekday numbers (1 = Sunday).
    private static let weekdays: [(String, Int)] = [
        ("domenica", 1), ("lunedì", 2), ("lunedi", 2), ("martedì", 3), ("martedi", 3), ("mercoledì", 4), ("mercoledi", 4),
        ("giovedì", 5), ("giovedi", 5), ("venerdì", 6), ("venerdi", 6), ("sabato", 7),
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]
    private static let numberWords: [String: Int] = [
        "un": 1, "uno": 1, "una": 1, "primo": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7,
        "otto": 8, "nove": 9, "dieci": 10, "undici": 11, "dodici": 12, "quindici": 15, "venti": 20, "trenta": 30,
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10
    ]
    private static let numberAlternation = #"\d{1,2}|un|uno|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici|quindici|venti|trenta|a|an|one|two|three|four|five|six|seven|ten"#
    private static let hourWords = #"\d{1,2}|una|due|tre|quattro|cinque|sei|sette|otto|nove|dieci|undici|dodici"#

    private static var dayPattern: String {
        let month = months.joined(separator: "|")
        let weekday = weekdays.map(\.0).joined(separator: "|")
        return #"\b(?:"#
            + #"l['’]altro\s*ieri|ieri\s+l['’]altro|avantieri|dopodomani|day before yesterday|day after tomorrow"#
            + #"|(?:"# + numberAlternation + #")\s+(?:giorni|giorno|settimane|settimana|mesi|mese)\s+fa"#
            + #"|(?:"# + numberAlternation + #")\s+(?:days?|weeks?|months?)\s+ago"#
            + #"|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{1,2}\.\d{1,2}\.\d{4}"#
            + #"|(?:il\s+|l['’])?(?:\d{1,2}|primo)\s+(?:"# + month + #")(?:\s+\d{4})?"#
            + #"|(?:il|l['’])\s*(?:\d{1,2}|primo)(?!\s*(?:euro|eur|€|%|per\s*cento|[,.]\d|\d))"#
            + #"|(?:la\s+)?(?:settimana|mese|anno)\s+(?:scors[oa]|passat[oa]|prossim[oa])|last (?:week|month|year)|next (?:week|month|year)"#
            + #"|(?:(?:last|next)\s+)?(?:"# + weekday + #")(?:\s+(?:scors[oa]|passat[oa]|prossim[oa]))?"#
            + #"|ieri|oggi|domani|stamattina|stamani|stasera|stanotte|yesterday|today|tomorrow|tonight"#
            + #")(?![\p{L}])"#
    }

    private static var timePattern: String {
        #"(?:\b(?:alle|verso\s+le|intorno\s+alle|per\s+le|dalle|ore|h|at)\s*|\ball['’]\s*)(?:"# + hourWords
            + #")(?:\s*[:.]\s*\d{2}|\s+e\s+(?:mezza|mezzo|un\s+quarto|quarto|tre\s+quarti|\d{1,2}))?"#
            + #"(?:\s*(?:am|pm)|\s+(?:di|del|della|in)\s+(?:mattina|pomeriggio|sera|notte))?(?![\p{L}\d])"#
            + #"|\b\d{1,2}:\d{2}\b|\b\d{1,2}\s*(?:am|pm)\b|\b(?:a\s+)?mezzogiorno\b|\b(?:a\s+)?mezzanotte\b"#
    }

    private static var periodPattern: String {
        #"\b(?:stamattina|stamani|stasera|stanotte|stamane|tonight|this morning|this afternoon|this evening"#
            + #"|(?:questa|questo|ieri|oggi|domani|di|in|la|il|al)\s+(?:mattina|mattinata|pomeriggio|sera|serata|notte)"#
            + #"|(?:a|per)\s+(?:colazione|pranzo|cena|merenda|aperitivo)|(?:at\s+)?(?:breakfast|lunch|dinner))\b"#
    }

    // MARK: - Resolution

    private static func resolveDay(_ key: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        func offset(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }
        let relative: [String: Int] = [
            "ieri": -1, "yesterday": -1, "avantieri": -2, "day before yesterday": -2,
            "oggi": 0, "today": 0, "stamattina": 0, "stamani": 0, "stasera": 0, "stanotte": 0, "tonight": 0,
            "domani": 1, "tomorrow": 1, "dopodomani": 2, "day after tomorrow": 2
        ]
        if let days = relative[key] { return offset(days) }
        if key.contains("altro") && key.contains("ieri") { return offset(-2) }

        if key.hasSuffix(" fa") || key.hasSuffix(" ago") {
            let words = key.split(separator: " ").map(String.init)
            guard let first = words.first, let count = Int(first) ?? numberWords[first] else { return nil }
            let unit = words.dropFirst().first ?? ""
            if unit.hasPrefix("settiman") || unit.hasPrefix("week") { return offset(-7 * count) }
            if unit.hasPrefix("mes") || unit.hasPrefix("month") { return calendar.date(byAdding: .month, value: -count, to: today) }
            return offset(-count)
        }
        if key.contains("settimana") || key.contains("mese") || key.contains("anno")
            || key.contains("week") || key.contains("month") || key.contains("year") {
            // A whole week or month is not a day.
            return nil
        }
        if let weekday = weekdays.first(where: { key.range(of: #"\b"# + $0.0 + #"\b"#, options: .regularExpression) != nil })?.1 {
            let todayWeekday = calendar.component(.weekday, from: today)
            if key.contains("prossim") || key.contains("next") {
                let ahead = (weekday - todayWeekday + 7) % 7
                return offset(ahead == 0 ? 7 : ahead)
            }
            let back = (todayWeekday - weekday + 7) % 7
            // "Lunedì scorso" said on a Monday means a week ago; a bare "lunedì" means today.
            let explicitPast = key.contains("scors") || key.contains("passat") || key.contains("last")
            return offset(-(back == 0 && explicitPast ? 7 : back))
        }
        let numbers = matches(#"\d+"#, in: key).compactMap { Int($0) }
        if !matches(#"^\d{4}-\d{1,2}-\d{1,2}$"#, in: key).isEmpty {
            return strictDay(year: numbers[0], month: numbers[1], day: numbers[2], calendar: calendar)
        }
        if let monthIndex = months.firstIndex(where: { key.contains($0) }) {
            let day = numbers.first ?? (key.contains("primo") ? 1 : nil)
            guard let day else { return nil }
            let year = numbers.count > 1 ? numbers[1] : calendar.component(.year, from: now)
            return strictDay(year: year, month: monthIndex % 12 + 1, day: day, calendar: calendar)
        }
        if !matches(#"^\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?$"#, in: key).isEmpty {
            // Numeric dates without a four-digit year remain ambiguous across locales.
            guard numbers.count == 3, numbers[2] > 999 else { return nil }
            return strictDay(year: numbers[2], month: numbers[1], day: numbers[0], calendar: calendar)
        }
        if key.hasPrefix("il") || key.hasPrefix("l'") || key.hasPrefix("l’") {
            // "Il 5": this month, or last month when the day has not come yet.
            guard let day = numbers.first ?? (key.contains("primo") ? 1 : nil) else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: today)
            guard let year = components.year, let month = components.month, let currentDay = components.day else { return nil }
            if day <= currentDay { return strictDay(year: year, month: month, day: day, calendar: calendar) }
            guard let previous = calendar.date(byAdding: .month, value: -1, to: today) else { return nil }
            let earlier = calendar.dateComponents([.year, .month], from: previous)
            return strictDay(year: earlier.year ?? year, month: earlier.month ?? month, day: day, calendar: calendar)
        }
        return nil
    }

    private static func resolveTime(_ key: String, period: String?) -> (hour: Int, minute: Int)? {
        if key.contains("mezzogiorno") { return (12, 0) }
        if key.contains("mezzanotte") { return (0, 0) }
        let words = matches(#"\d+|\p{L}+"#, in: key)
        guard let hourIndex = words.firstIndex(where: { Int($0) != nil || hourValue($0) != nil }),
              var hour = Int(words[hourIndex]) ?? hourValue(words[hourIndex]) else { return nil }
        var minute = 0
        let rest = Array(words[(hourIndex + 1)...])
        if let value = rest.lazy.compactMap({ Int($0) }).first {
            minute = value
        } else if rest.contains("mezza") || rest.contains("mezzo") {
            minute = 30
        } else if rest.contains("tre"), rest.contains("quarti") {
            minute = 45
        } else if rest.contains("quarto") {
            minute = 15
        }
        let qualifier = rest.first { ["mattina", "pomeriggio", "sera", "notte", "am", "pm"].contains($0) }
        let afternoon = ["pomeriggio", "sera", "pm"]
        if hour < 12, let qualifier, afternoon.contains(qualifier) { hour += 12 }
        else if hour < 12, qualifier == "notte", hour >= 9 { hour += 12 }
        else if hour == 12, qualifier == "am" { hour = 0 }
        else if hour < 12, qualifier == nil, let period, isEvening(period), hour >= 1 { hour += 12 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func hourValue(_ word: String) -> Int? {
        guard let value = numberWords[word], word != "a", word != "an", word != "primo" else { return nil }
        return value <= 12 ? value : nil
    }

    private static func isEvening(_ period: String) -> Bool {
        ["sera", "serata", "stasera", "cena", "aperitivo", "pomeriggio", "dinner", "evening", "tonight", "afternoon"]
            .contains { period.contains($0) }
    }

    private static func isNight(_ period: String) -> Bool {
        period.contains("notte") || period.contains("stanotte")
    }

    private static func typicalTime(for period: String) -> (hour: Int, minute: Int)? {
        if period.contains("colazione") || period.contains("breakfast") { return (8, 0) }
        if period.contains("pranzo") || period.contains("lunch") { return (13, 0) }
        if period.contains("merenda") { return (16, 30) }
        if period.contains("aperitivo") { return (19, 0) }
        if period.contains("cena") || period.contains("dinner") { return (20, 30) }
        if period.contains("pomeriggio") || period.contains("afternoon") { return (15, 0) }
        if period.contains("sera") || period.contains("evening") || period.contains("tonight") { return (20, 0) }
        if period.contains("matt") || period.contains("stamani") || period.contains("stamane") || period.contains("morning") { return (9, 0) }
        return nil
    }

    private static func strictDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard !text.isEmpty, let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
