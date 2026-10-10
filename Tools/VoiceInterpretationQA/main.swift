import Foundation
import FoundationModels
import FinanceCore
import Darwin

// Compile alongside the app's VoiceTransactionInterpreter.swift to exercise its actual prompt and mapping.
@main struct VoiceInterpretationQA {
    struct Expected {
        let amount: String
        let type: TransactionType?
        var account: String? = nil
        var day: String? = nil
        var dateNeedsReview = false
        var category: String? = nil
    }
    struct Case {
        let name: String
        let text: String
        let expected: [Expected]
    }

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let book = Account(name: "Prova", currency: "EUR")
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 0)
        let cash = Conto(name: "Contanti", type: .checking, initialBalance: 0)
        for conto in [bank, cash] { conto.account = book }
        book.conti = [bank, cash]
        book.categories = [Category(name: "Stipendio", kind: .income), Category(name: "Bar", kind: .expense), Category(name: "Supermercato", kind: .expense)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        let evidenceChecks = try EvidenceChecks.run(now: now)
        print("PASS \(evidenceChecks) deterministic evidence checks")
        let replayChecks = try ExtractionChecks.run(conti: [bank, cash], now: now)
        print("PASS \(replayChecks) extraction replay checks")
        if ProcessInfo.processInfo.environment["FORMI_QA_EVIDENCE_ONLY"] == "1" { return }
        guard VoiceTransactionInterpreter.unavailableReason == nil else {
            print(VoiceTransactionInterpreter.unavailableReason!)
            Foundation.exit(2)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let cases: [Case] = [
            Case(name: "stipendio", text: "Ho ricevuto lo stipendio di 1800 euro sul conto Banca", expected: [Expected(amount: "1800", type: .income, account: "Banca")]),
            Case(name: "elenco senza conto", text: "Ho speso 3 euro al bar e 5 euro al supermercato", expected: [Expected(amount: "3", type: .expense), Expected(amount: "5", type: .expense)]),
            Case(name: "ieri e conto condiviso", text: "Ieri ho speso 3 euro al bar e 5 euro al supermercato, entrambi dal conto Banca", expected: [Expected(amount: "3", type: .expense, account: "Banca", day: "2026-10-09"), Expected(amount: "5", type: .expense, account: "Banca", day: "2026-10-09")]),
            Case(name: "ripetuti", text: "Ho speso 3 euro al bar stamattina e altri 3 euro allo stesso bar nel pomeriggio", expected: [Expected(amount: "3", type: .expense, day: "2026-10-10"), Expected(amount: "3", type: .expense, day: "2026-10-10")]),
            Case(name: "decimali", text: "Ho pagato dodici euro e cinquanta al supermercato dal conto Contanti", expected: [Expected(amount: "12.50", type: .expense, account: "Contanti")]),
            Case(name: "data esplicita", text: "Il 5 ottobre 2026 ho ricevuto 250 euro sul conto Banca", expected: [Expected(amount: "250", type: .income, account: "Banca", day: "2026-10-05")]),
            Case(name: "conto sconosciuto", text: "Ho speso 20 euro dal conto Vacanze", expected: [Expected(amount: "20", type: .expense)]),
            Case(name: "importo mancante", text: "Ho ricevuto lo stipendio sul conto Banca", expected: [Expected(amount: "", type: .income, account: "Banca")]),
            Case(name: "negazione", text: "Non ho pagato i 50 euro al ristorante", expected: [Expected(amount: "50", type: nil)]),
            Case(name: "trasferimento", text: "Ho trasferito 100 euro da Banca a Contanti", expected: [Expected(amount: "100", type: nil)]),
            Case(name: "decimali in cifre", text: "Ho pagato 12.50 euro al bar", expected: [Expected(amount: "12.50", type: .expense)]),
            Case(name: "due date diverse", text: "Ieri ho speso 3 euro al bar e oggi ho ricevuto 20 euro", expected: [Expected(amount: "3", type: .expense, day: "2026-10-09"), Expected(amount: "20", type: .income, day: "2026-10-10", category: "")]),
            Case(name: "negazione e spesa reale", text: "Non ho pagato 50 euro al ristorante, ma ho speso 3 euro al bar", expected: [Expected(amount: "50", type: nil), Expected(amount: "3", type: .expense)]),
            Case(name: "domani", text: "Domani pagherò 20 euro al supermercato dal conto Banca", expected: [Expected(amount: "20", type: .expense, account: "Banca", day: "2026-10-11")]),
            Case(name: "data impossibile", text: "Il 30 febbraio 2026 ho pagato 10 euro al bar", expected: [Expected(amount: "10", type: .expense, dateNeedsReview: true)]),
            Case(name: "data vaga", text: "La settimana scorsa ho speso 10 euro al bar", expected: [Expected(amount: "10", type: .expense, dateNeedsReview: true)]),
            Case(name: "accredito senza causale", text: "Ho ricevuto 250 euro sul conto Banca", expected: [Expected(amount: "250", type: .income, account: "Banca", category: "")]),
            Case(name: "spesa senza causale", text: "Ho speso 20 euro dal conto Banca", expected: [Expected(amount: "20", type: .expense, account: "Banca", category: "")])
        ]
        let repeats = Int(ProcessInfo.processInfo.environment["FORMI_QA_REPEATS"] ?? "3") ?? 3
        var results: [[String: Any]] = []
        var failures = 0
        for run in 1...max(1, repeats) {
            for test in cases {
                let start = Date()
                do {
                    var evidence: [[String: Any]] = []
                    let drafts = try await VoiceTransactionInterpreter.interpret(test.text, conti: [bank, cash], now: now) { extraction in
                        evidence = extraction.movements.map { ["sourceText": $0.sourceText, "dateExpression": $0.dateExpression, "account": $0.account, "note": $0.note, "category": $0.category] }
                    }
                    var issues: [String] = []
                    if drafts.count != test.expected.count { issues.append("count \(drafts.count), expected \(test.expected.count)") }
                    for (draft, expected) in zip(drafts, test.expected) {
                        let amountMatches = expected.amount.isEmpty ? draft.amount.isEmpty : Decimal(string: draft.amount) == Decimal(string: expected.amount)
                        if !amountMatches { issues.append("amount \(draft.amount), expected \(expected.amount)") }
                        if draft.type != expected.type { issues.append("type \(String(describing: draft.type)), expected \(String(describing: expected.type))") }
                        let account = [bank, cash].first { $0.id == draft.contoID }?.name
                        if account != expected.account { issues.append("account \(account ?? "nil"), expected \(expected.account ?? "nil")") }
                        if draft.dateNeedsReview != expected.dateNeedsReview { issues.append("date review \(draft.dateNeedsReview), expected \(expected.dateNeedsReview)") }
                        if let category = expected.category, draft.suggestedCategory != category { issues.append("category \(draft.suggestedCategory), expected \(category)") }
                        if let day = expected.day {
                            if formatter.string(from: draft.date) != day { issues.append("day \(formatter.string(from: draft.date)), expected \(day)") }
                        } else if draft.date != now { issues.append("missing date did not preserve exact now") }
                    }
                    let output: [[String: Any]] = drafts.map { draft in
                        ["amount": draft.amount, "type": draft.type?.rawValue ?? "unresolved", "note": draft.note,
                         "date": formatter.string(from: draft.date), "timestamp": draft.date.timeIntervalSince1970, "dateNeedsReview": draft.dateNeedsReview,
                         "account": [bank, cash].first { $0.id == draft.contoID }?.name ?? "", "category": draft.suggestedCategory]
                    }
                    results.append(["run": run, "case": test.name, "input": test.text, "seconds": Date().timeIntervalSince(start), "output": output, "dateEvidence": evidence, "issues": issues])
                    if !issues.isEmpty { failures += 1 }
                    print("\(issues.isEmpty ? "PASS" : "FAIL") \(run) \(test.name): \(issues.joined(separator: "; "))")
                } catch {
                    failures += 1
                    results.append(["run": run, "case": test.name, "input": test.text, "error": String(describing: error)])
                    print("ERROR \(run) \(test.name): \(error)")
                }
            }
        }
        let report = ProcessInfo.processInfo.environment["FORMI_QA_REPORT"] ?? "/private/tmp/formi-voice-model-report.json"
        try JSONSerialization.data(withJSONObject: ["availability": "available", "system": ProcessInfo.processInfo.operatingSystemVersionString, "timeZone": TimeZone.current.identifier, "referenceNow": now.timeIntervalSince1970, "evidenceChecks": evidenceChecks, "replayChecks": replayChecks, "results": results, "failures": failures], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: report))
        print("\(results.count - failures)/\(results.count) passed. Report: \(report)")
        if failures > 0 { Foundation.exit(1) }
    }
}
