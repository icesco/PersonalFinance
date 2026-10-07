import SwiftUI
import FinanceCore

struct RecordedSavingsDetailContent: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    var plan: BudgetingPlan? = nil
    @State private var showingExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tasso di risparmio", systemImage: "gauge.with.needle").font(.headline).foregroundStyle(ForgiaPalette.savings)
            if let rate = report.savingsRate {
                SavingsRateHero(rate: rate)

                SavingsComparisonChart(title: "Margine sulle entrate", actual: rate,
                    reference: plan.map { Decimal($0.savingsPercent) / 100 }, currency: nil,
                    isCeiling: false, isInProgress: isInProgress)
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
                SavingsAmountRow(title: "Entrate", amount: report.income, currency: currency)
                SavingsAmountRow(title: "Spese", amount: report.expenses, currency: currency)
                SavingsAmountRow(title: "Margine del periodo", amount: report.remainder, currency: currency)
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
            SavingsExplanationView(plan: plan, recordedReport: report, currency: currency)
        }
    }
}
