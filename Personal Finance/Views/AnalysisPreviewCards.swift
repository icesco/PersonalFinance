import SwiftUI
import FinanceCore

/// Details retain the period and account scope selected on the analysis tab.
struct AnalysisDetailScreen<Content: View>: View {
    let title: LocalizedStringKey
    let periodTitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(periodTitle).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                content
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .themedBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
    }
}

struct AnalysisPreviewHeading: View {
    let title: LocalizedStringKey
    let icon: String
    var tint: Color = ForgiaPalette.accent
    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(title).font(.headline).foregroundStyle(tint)
            } icon: {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint).frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText).accessibilityHidden(true)
        }
    }
}

struct MonthlySpendingTrendCard: View {
    let trend: MonthlySpendingTrend
    let currency: String
    var periodTitle = ""

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Andamento delle spese", periodTitle: periodTitle) {
                MonthlySpendingTrendDetailContent(trend: trend, currency: currency)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Andamento delle spese", icon: "chart.xyaxis.line", tint: ForgiaPalette.spending)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if trend.hasInvalidAmounts {
                            Text("Importi da verificare").font(.title3.weight(.semibold))
                        } else if let last = trend.current.last {
                            Text(last.amount, format: .currency(code: currency))
                                .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit().financeNumericMotion(last.amount).foregroundStyle(ForgiaPalette.spending)
                            Text(trend.isInProgress ? "Registrate fino a oggi" : "Registrate nel mese")
                                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        } else {
                            Text("Periodo non iniziato").font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !trend.hasInvalidAmounts && !trend.current.isEmpty {
                        MonthlySpendingLines(trend: trend, currency: currency, compact: true)
                            .frame(width: 100).accessibilityHidden(true)
                    }
                }
            }.unifiedCard(tint: ForgiaPalette.spending).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("analysis-trend-preview")
    }
}

struct RecordedSavingsCard: View {
    let report: RecordedSavingsReport
    let currency: String
    let isInProgress: Bool
    var plan: BudgetingPlan? = nil
    var periodTitle = ""

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Tasso di risparmio", periodTitle: periodTitle) {
                RecordedSavingsDetailContent(report: report, currency: currency, isInProgress: isInProgress, plan: plan)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Tasso di risparmio", icon: "gauge.with.needle", tint: ForgiaPalette.savings)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let rate = report.savingsRate {
                            Text(rate, format: .percent.precision(.fractionLength(1)))
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .foregroundStyle(rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings).monospacedDigit().financeNumericMotion(rate)
                            Text(rate < 0 ? "Spese oltre le entrate" : "Margine sulle entrate")
                                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        } else {
                            Text("Non calcolabile").font(.title3.weight(.semibold)).foregroundStyle(ForgiaPalette.savings)
                            Text(report.hasInvalidAmounts ? "Importi da verificare" : "Servono entrate registrate")
                                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let rate = report.savingsRate {
                        SavingsRateGauge(rate: rate, compact: true).frame(width: 112)
                            .accessibilityHidden(true)
                    }
                }
            }.unifiedCard(tint: ForgiaPalette.savings).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("analysis-savings-preview")
    }
}

struct FinancialSharePreview: View {
    let share: Double
    var icon = "leaf"
    var tint: Color = ForgiaPalette.margin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: appeared || reduceMotion ? share : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon).foregroundStyle(tint)
        }.frame(width: 58, height: 58).padding(5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: share)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { appeared = true } }
    }
}
