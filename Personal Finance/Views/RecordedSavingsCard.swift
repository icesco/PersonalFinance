import SwiftUI
import FinanceCore

struct RecordedSavingsDetailContent: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    var plan: BudgetingPlan? = nil
    @State private var showingExplanation = false

    private var resultTint: Color {
        report.savingsRate.map { $0 < 0 ? AnalysisPalette.deficit : AnalysisPalette.savings } ?? AnalysisPalette.savings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Tasso di risparmio", systemImage: "gauge.with.needle")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
            if let rate = report.savingsRate {
                SavingsRateHero(rate: rate)

                SavingsComparisonChart(title: "Margine sulle entrate", actual: rate,
                    reference: plan.map { Decimal($0.savingsPercent) / 100 }, currency: nil,
                    isCeiling: false, isInProgress: isInProgress)
            } else {
                AnalysisEmptyState(symbol: .accounts, title: "Non calcolabile",
                    message: report.hasInvalidAmounts
                        ? "Controlla gli importi mancanti o non validi."
                        : "Servono entrate registrate maggiori di zero nel periodo.")
            }
            Text("La quota delle entrate che rimane dopo le spese registrate. Gli accantonamenti sono una misura diversa.")
                .font(.subheadline).foregroundStyle(ForgiaPalette.accent)
            if !report.hasInvalidAmounts {
                SavingsAmountRow(title: "Entrate", amount: report.income, currency: currency)
                SavingsAmountRow(title: "Spese", amount: report.expenses, currency: currency)
                SavingsAmountRow(title: "Margine del periodo", amount: report.remainder, currency: currency)
            }
            if isInProgress {
                Label("Periodo in corso · dati fino a oggi", systemImage: "clock")
                    .font(.caption).foregroundStyle(ForgiaPalette.accent)
            }
            Button { showingExplanation = true } label: {
                Label("Come funziona e consigli", systemImage: "info.circle")
            }.accessibilityIdentifier("analysis-savings-explanation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard(tint: resultTint)
        .financeCardEntrance()
        .financePresentation(isPresented: $showingExplanation, title: "Come funziona", width: 680) {
            SavingsExplanationView(plan: plan, recordedReport: report, currency: currency)
        }
    }
}
