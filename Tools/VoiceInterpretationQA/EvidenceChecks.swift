import Foundation

enum EvidenceChecks {
    struct Failure: Error { let name: String }

    static func run(now: Date) throws -> Int {
        var count = 0
        func check(_ name: String, _ condition: Bool) throws {
            guard condition else { throw Failure(name: name) }
            count += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func date(_ text: String, clause: String? = nil, expression: String = "") -> Date? {
            VoiceTextEvidence.date(in: text, clause: clause ?? text, expression: expression, now: now)
        }
        try check("omitted date preserves exact now", date("Ho ricevuto 1800 euro", expression: "stipendio") == now)
        try check("decimal amount is not a date", date("Ho pagato 12.50 euro") == now)
        try check("yesterday uses calendar", date("Ieri ho pagato 3 euro") == calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        try check("tomorrow uses calendar", date("Domani pagherò 3 euro") == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        try check("invalid date needs review", date("Il 30 febbraio 2026 ho pagato 3 euro") == nil)
        try check("vague date needs review", date("Il mese scorso ho pagato 3 euro") == nil)
        try check("ambiguous numeric date needs review", date("Il 5/10 ho pagato 3 euro") == nil)
        try check("ISO day resolves strictly", date("Il 2026-10-05 ho pagato 3 euro") == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let mixed = "Non ho pagato 50 euro al ristorante, ma ho speso 3 euro al bar"
        let negated = VoiceTextEvidence.clause(for: "ho pagato 50 euro al ristorante", in: mixed)
        let paid = VoiceTextEvidence.clause(for: "ho speso 3 euro al bar", in: mixed)
        try check("negation remains in source clause", negated.map(VoiceTextEvidence.isUnresolved) == true)
        try check("actual expense stays separate", paid.map(VoiceTextEvidence.isUnresolved) == false)
        try check("non solo is not negated", !VoiceTextEvidence.isUnresolved("Non solo ho pagato 3 euro al bar"))
        try check("transfer needs review", VoiceTextEvidence.isUnresolved("Ho trasferito 100 euro"))
        try check("hypothetical needs review", VoiceTextEvidence.isUnresolved("Vorrei spendere 100 euro"))
        try check("invented clause rejected", VoiceTextEvidence.clause(for: "Ho ricevuto 200 euro", in: "Ho pagato 3 euro") == nil)
        let list = "Ieri ho speso 3 euro al bar e 5 euro al supermercato"
        try check("elided verb grounded", VoiceTextEvidence.clause(for: "ho speso 5 euro al supermercato", in: list) == list)
        let dates = "Ieri ho speso 3 euro al bar e oggi ho ricevuto 20 euro"
        let todayClause = VoiceTextEvidence.clause(for: "ho ricevuto 20 euro", in: dates)
        try check("two dates keep their own clauses", date(dates, clause: todayClause) == calendar.startOfDay(for: now))
        try check("unsupported purpose rejected", VoiceTextEvidence.purpose("Stipendio", in: "Ho ricevuto 250 euro", accountNames: []) == "")
        try check("generic verb is not a purpose", VoiceTextEvidence.purpose("speso", in: "Ho speso 20 euro", accountNames: []) == "")
        try check("actual merchant accepted", VoiceTextEvidence.purpose("bar", in: "Ho speso 3 euro al bar", accountNames: []) == "bar")
        try check("account explicitly mentioned", VoiceTextEvidence.accountWasSpoken("Banca", in: "dal conto Banca"))
        try check("account substring rejected", !VoiceTextEvidence.accountWasSpoken("Banca", in: "dal conto Bancario"))
        return count
    }
}
