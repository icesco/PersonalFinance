import SwiftUI
import FinanceCore

struct RecordedSavingsDetailContent: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    @AppStorage("savingsReferencePercent") private var referencePercent = 20
    @State private var showingExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tasso di risparmio", systemImage: "gauge.with.needle").font(.headline).foregroundStyle(ForgiaPalette.savings)
            if let rate = report.savingsRate {
                SavingsRateHero(rate: rate)

                SavingsRateComparison(rate: rate, referencePercent: referencePercent)
            } else {
                Text("Non calcolabile").font(.title2.weight(.semibold)).foregroundStyle(ForgiaPalette.savings)
                Text(report.hasInvalidAmounts
                     ? "Controlla gli importi mancanti o non validi."
                     : "Servono entrate registrate maggiori di zero nel periodo.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
            Text("La quota delle entrate che rimane dopo le spese registrate. Gli accantonamenti sono una misura diversa.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            if !report.hasInvalidAmounts {
                RecordedSavingsAmountRow(title: "Entrate", amount: report.income, currency: currency)
                RecordedSavingsAmountRow(title: "Spese", amount: report.expenses, currency: currency)
                RecordedSavingsAmountRow(title: "Margine del periodo", amount: report.remainder, currency: currency)
            }
            if isInProgress {
                Label("Periodo in corso · dati fino a oggi", systemImage: "clock")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
            Button { showingExplanation = true } label: {
                Label("Come funziona e consigli", systemImage: "info.circle")
            }.accessibilityIdentifier("analysis-savings-explanation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard(tint: ForgiaPalette.savings).financeCardEntrance()
        .financePresentation(isPresented: $showingExplanation, title: "Come funziona", width: 680) {
            SavingsRateGuide(report: report, currency: currency, isInProgress: isInProgress, referencePercent: $referencePercent)
        }
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
