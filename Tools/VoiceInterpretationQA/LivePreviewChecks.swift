import Foundation

@main struct LivePreviewChecks {
    static func main() {
        let cases: [(String, [String], [String])] = [
            ("Ho speso 3 euro al bar e 5 euro al supermercato", ["3", "5"], ["bar", "supermercato"]),
            ("Ho speso tre euro al bar e cinque euro al supermercato", ["3", "5"], ["bar", "supermercato"]),
            ("Ho speso 3 euro", ["3"], [""]),
            ("Ho speso 3 euro al bar e 5 euro", ["3", "5"], ["bar", ""]),
            ("Ho ricevuto lo stipendio di 1.800 euro sul conto Banca", ["1800"], ["stipendio"]),
            ("Ho speso 3,50 euro al bar", ["3.5"], ["bar"]),
            ("Ho speso 3 euro e cinquanta al bar e 5 euro al supermercato", ["3.5", "5"], ["bar", "supermercato"]),
            ("Ho speso ventotto euro al bar", ["28"], ["bar"]),
            ("Ho speso €3 al bar e $5 al supermercato", ["3", "5"], ["bar", "supermercato"]),
            ("Ieri ho speso 3 euro al bar e ho ricevuto 5 euro di rimborso", ["3", "5"], ["bar", "rimborso"]),
            ("Non ho speso 3 euro al bar ma ho pagato 5 euro al supermercato", ["5"], ["supermercato"]),
            ("Vorrei spendere 5 euro al bar", [], []),
            ("Ho trasferito 50 euro dal conto A al conto B", [], []),
            ("Ho speso 3 euro al bar e 3 euro al bar", ["3", "3"], ["bar", "bar"]),
            ("Ho speso il 3 ottobre alle 5", [], []),
            ("Ho speso 0 euro al bar", [], []),
            ("Ho speso 3 euro al bar ieri", ["3"], ["bar"]),
            ("Ho speso", [], [])
        ]
        var failures = 0
        for (text, amounts, titles) in cases {
            let tokens = VoiceLivePreview.tokens(in: text)
            let expected = amounts.compactMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
            if tokens.map(\.amount) != expected || tokens.map(\.title) != titles {
                failures += 1
                print("FAIL: \(text) → \(tokens)")
            }
        }
        let mixed = VoiceLivePreview.tokens(in: "Ho speso 3 euro al bar e ho ricevuto 5 euro di rimborso")
        if mixed.map(\.direction) != [.expense, .income] { failures += 1; print("FAIL: mixed directions") }
        let carried = VoiceLivePreview.tokens(in: "Ho speso 3 euro al bar e 5 euro al supermercato")
        if carried.map(\.direction) != [.expense, .expense] { failures += 1; print("FAIL: inherited direction") }
        let currencies = VoiceLivePreview.tokens(in: "Ho speso €3 al bar e $5 al supermercato")
        if currencies.map(\.currency) != ["EUR", "USD"] { failures += 1; print("FAIL: currencies") }
        let partial = VoiceLivePreview.tokens(in: "Ho speso 3 euro")
        let corrected = VoiceLivePreview.tokens(in: "Ho speso 30 euro al bar")
        if partial.first?.sourceOffset != corrected.first?.sourceOffset { failures += 1; print("FAIL: revision anchor") }
        print("Live preview: \(cases.count + 4 - failures)/\(cases.count + 4) checks passed")
        if failures > 0 { exit(1) }
    }
}
