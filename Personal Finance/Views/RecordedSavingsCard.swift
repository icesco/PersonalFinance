import SwiftUI
import FinanceCore

struct RecordedSavingsCard: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tasso di risparmio").font(.headline)
            Text("Sui movimenti registrati")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)

            if let rate = report.savingsRate {
                Text(rate, format: .percent.precision(.fractionLength(1)).locale(locale))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                if report.remainder < 0 {
                    Text("Le spese superano le entrate del periodo.")
                        .font(.subheadline)
                } else {
                    Text("Quota delle entrate rimasta dopo le spese.")
                        .font(.subheadline)
                }
            } else {
                Text("Non calcolabile").font(.title2.weight(.semibold))
                Text(report.hasInvalidAmounts
                     ? "Alcuni movimenti hanno importi mancanti o non validi. Controllali prima di leggere il tasso."
                     : "Servono entrate registrate maggiori di zero nel periodo.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }

            if !report.hasInvalidAmounts {
                RecordedSavingsAmountRow(title: "Entrate", amount: report.income, currency: currency)
                RecordedSavingsAmountRow(title: "Spese", amount: report.expenses, currency: currency)
                RecordedSavingsAmountRow(title: "Differenza", amount: report.remainder, currency: currency)
            }

            if isInProgress {
                Label("Periodo in corso · dati fino a oggi", systemImage: "clock")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }

            DisclosureGroup("Come si calcola") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("(Entrate − spese) ÷ entrate × 100. Per più mesi si usano i totali, non la media delle percentuali.")
                    Text("Sono inclusi solo i movimenti registrati fino a oggi nei conti selezionati. Trasferimenti e ricorrenze previste sono esclusi.")
                    Text("Usa entrate al netto delle imposte. Rimborsi, prestiti e disinvestimenti registrati come entrate possono alterare il tasso; verifica la loro classificazione.")
                    Text("La differenza non indica il saldo disponibile né quanto hai effettivamente accantonato. Investimenti e rimborso del capitale dei debiti richiedono una classificazione coerente.")
                }
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                .padding(.top, 8)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
    }
}

private struct RecordedSavingsAmountRow: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let currency: String
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(title).foregroundStyle(ForgiaPalette.mutedText)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(amount, format: .currency(code: currency).locale(locale))
                .fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
