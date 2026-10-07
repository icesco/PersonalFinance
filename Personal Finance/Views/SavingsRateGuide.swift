import SwiftUI
import Charts
import FinanceCore

struct SavingsRateGuide: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    @Binding var referencePercent: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quanto resta delle tue entrate")
                            .font(.system(.title, design: .serif, weight: .semibold))
                        Text("Il tasso indica la quota delle entrate registrate rimasta dopo le spese del periodo.")
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                    SavingsGuideExample(currency: currency)
                    SavingsGuideReference(referencePercent: $referencePercent)
                    SavingsGuideAdvice(report: report, referencePercent: referencePercent, isInProgress: isInProgress)
                    SavingsGuideDataRules()
                }
                .padding(22)
            }
            .themedBackground()
            .navigationTitle("Capire il risparmio")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                        .accessibilityIdentifier("savings-guide-done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 600)
        #endif
    }
}

private struct SavingsGuideExample: View {
    let currency: String
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Un esempio semplice").font(.headline)
            ZStack {
                Chart {
                    SectorMark(angle: .value("Spese", 75), innerRadius: .ratio(0.72), angularInset: 3)
                        .foregroundStyle(ForgiaPalette.mutedText.opacity(0.25))
                    SectorMark(angle: .value("Rimane", 25), innerRadius: .ratio(0.72), angularInset: 3)
                        .foregroundStyle(ForgiaPalette.accent)
                }
                .frame(height: 160)
                VStack(spacing: 3) {
                    Text(0.25, format: .percent.precision(.fractionLength(0)).locale(locale))
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("rimane").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Esempio: 75% speso, 25% rimasto")
            LabeledContent("Entrate") { Text(Decimal(2000), format: .currency(code: currency).locale(locale)) }
            LabeledContent("Spese · 75%") { Text(Decimal(1500), format: .currency(code: currency).locale(locale)) }
            LabeledContent("Rimane · 25%") { Text(Decimal(500), format: .currency(code: currency).locale(locale)) }
            Text("(2.000 − 1.500) ÷ 2.000 × 100 = 25%")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            Text("È un esempio illustrativo, non il tuo risultato.")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }
        .unifiedCard()
    }
}

private struct SavingsGuideReference: View {
    @Binding var referencePercent: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Un riferimento adatto a te").font(.headline)
            Stepper(value: $referencePercent, in: 0...100, step: 5) {
                Text("Riferimento: \(referencePercent)%").fontWeight(.semibold)
            }
            .accessibilityIdentifier("savings-reference-stepper")
            Text("Il 20% iniziale è un punto di partenza orientativo, ispirato alla regola 50/30/20. Quella regola comprende risparmio e rimborso dei debiti: non coincide esattamente con questo tasso.")
            Text("Puoi scegliere una quota sostenibile per le tue entrate e necessità. Il riferimento vale per tutti i libri e periodi su questo dispositivo; non modifica i budget del tuo piano.")
            Text("Superarlo non certifica la tua salute finanziaria. Per settimane o periodi brevi, la data dello stipendio può cambiare molto il risultato.")
            Link("La guida del CFPB", destination: URL(string: "https://files.consumerfinance.gov/f/documents/cfpb_worksheet_my-spending-rule-to-live-by.pdf")!)
        }
        .font(.subheadline)
        .unifiedCard()
    }
}

private struct SavingsGuideAdvice: View {
    let report: RecordedSavingsReport
    let referencePercent: Int
    let isInProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Da dove iniziare", systemImage: "sparkles").font(.headline)
            if let rate = report.savingsRate {
                if rate < 0 {
                    Text("Nel periodo registrato hai speso più di quanto è entrato. Controlla se ci sono spese occasionali o entrate ancora da registrare; poi guarda quali uscite puoi ridurre.")
                } else if rate < Decimal(min(100, max(0, referencePercent))) / 100 {
                    Text("Il risultato è sotto il riferimento scelto. Prova un piccolo obiettivo sostenibile e controlla le categorie di spesa più consistenti, senza trascurare le necessità.")
                } else {
                    Text("Il risultato raggiunge il riferimento scelto. Verifica le spese meno frequenti prima di decidere quanto accantonare davvero; una quota regolare può aiutarti a mantenere l'abitudine.")
                }
            } else {
                Text("Prima di interpretare il risultato, registra le entrate e controlla che gli importi dei movimenti siano completi e corretti.")
            }
            if isInProgress {
                Text("Il periodo è ancora in corso. Entrate e spese dei prossimi giorni possono cambiare il tasso: rileggilo a periodo concluso.")
            }
            Text("Confronta anche più mesi: una spesa annuale o un'entrata occasionale può rendere un singolo periodo poco rappresentativo.")
        }
        .font(.subheadline)
        .unifiedCard()
    }
}

private struct SavingsGuideDataRules: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Leggerlo correttamente", systemImage: "checklist").font(.headline)
            Text("Il calcolo usa entrate e spese registrate fino a oggi, negli stessi conti, periodo e valuta. Per più mesi si usano i totali, non la media delle percentuali.")
            Text("Trasferimenti, saldi iniziali e ricorrenze previste sono esclusi. Le ricorrenze già registrate contano come gli altri movimenti.")
            Text("Senza entrate positive il tasso non è calcolabile. Se le spese superano le entrate, il valore resta negativo.")
            Text("Usa entrate al netto delle imposte. Rimborsi, prestiti e disinvestimenti registrati come entrate possono alterare il tasso; verifica la classificazione. Investimenti e rimborso del capitale dei debiti richiedono una classificazione coerente.")
            Text("La differenza non indica il saldo disponibile né quanto hai effettivamente accantonato. Movimenti mancanti possono cambiare il risultato.")
        }
        .font(.subheadline)
        .unifiedCard()
    }
}
