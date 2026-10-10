import Foundation
import FinanceCore

@MainActor enum ExtractionChecks {
    static func run(conti: [Conto], now: Date) throws -> Int {
        func movement(_ source: String, _ amount: String, _ note: String = "", type: SpokenMovementType = .expense) -> SpokenMovement {
            SpokenMovement(sourceText: source, amount: amount, currency: "EUR", type: type, note: note, dateExpression: "", account: "", category: "")
        }
        func map(_ items: [SpokenMovement], text: String) throws -> [VoiceTransactionDraft] {
            try VoiceTransactionInterpreter.drafts(from: SpokenMovementList(exceedsLimit: false, movements: items), text: text, conti: conti, now: now)
        }
        // Replay the real model's extra fragment, preserving both genuine movements and their polarity.
        let mixed = try map([movement("Non ho pagato", "", type: .unresolved), movement("50 euro", "50", "al ristorante"), movement("ho speso", "3", "al bar")],
                            text: "Non ho pagato 50 euro al ristorante, ma ho speso 3 euro al bar")
        guard mixed.count == 2, mixed[0].amount == "50", mixed[0].type == nil, mixed[1].amount == "3", mixed[1].type == .expense else {
            throw EvidenceChecks.Failure(name: "extra fragment replay")
        }
        let repeated = try map([movement("Ho speso 3 euro al bar", "3", "bar"), movement("Ho speso 3 euro al bar", "3", "bar")],
                               text: "Ho speso 3 euro al bar. Ho speso 3 euro al bar.")
        guard repeated.count == 2 else { throw EvidenceChecks.Failure(name: "actual repeated payments preserved") }
        let missing = try map([movement("Ho ricevuto lo stipendio", "", "stipendio", type: .income)], text: "Ho ricevuto lo stipendio")
        guard missing.count == 1, missing[0].amount.isEmpty else { throw EvidenceChecks.Failure(name: "missing amount preserved for review") }
        let separate = try map([movement("Non ho pagato", "", type: .unresolved), movement("ho ricevuto 20 euro", "20", type: .income)],
                               text: "Non ho pagato, ma ho ricevuto 20 euro")
        guard separate.count == 2 else { throw EvidenceChecks.Failure(name: "separate incomplete movement preserved") }
        return 4
    }
}
