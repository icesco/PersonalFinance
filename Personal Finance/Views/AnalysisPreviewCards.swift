import SwiftUI
import FinanceCore

private struct AnalysisMetricTypography: ViewModifier {
    let size: CGFloat
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .font(.system(size: size * scale, weight: .bold))
            .tracking(-size / 32)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }
}

extension View {
    func analysisMetric(size: CGFloat = 44) -> some View {
        modifier(AnalysisMetricTypography(size: size))
    }
}

/// Details retain the period and account scope selected on the analysis tab.
struct AnalysisDetailScreen<Content: View>: View {
    let title: LocalizedStringKey
    let periodTitle: String
    var tint: Color = ForgiaPalette.accent
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(periodTitle).font(.subheadline).foregroundStyle(ForgiaPalette.accent)
                content
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .themedBackground(tint: .clear)
        .environment(\.financeCardSurfaceStyle, .themed)
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
    var illustration: FormiFeatureSymbol? = nil
    /// Short trailing hint such as "Vedi tutti (4)"; shown before the chevron.
    var accessory: String? = nil
    var showsChevron = true
    @Environment(\.financeCardSurfaceStyle) private var surfaceStyle

    private var headingTint: Color { surfaceStyle == .themed ? ForgiaPalette.accent : tint }
    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(headingTint)
            } icon: {
                Group {
                    if let illustration, surfaceStyle != .themed {
                        FormiFeatureIcon(symbol: illustration, size: 28, ink: headingTint)
                    } else {
                        Image(systemName: icon)
                    }
                }
                    .font(.system(surfaceStyle == .themed ? .title3 : .subheadline, weight: .semibold))
                    .foregroundStyle(headingTint).frame(width: 32, height: 32)
                    .background(headingTint.opacity(surfaceStyle == .themed ? 0 : 0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 8)
            if let accessory {
                Text(accessory).font(.subheadline.weight(.medium))
                    .foregroundStyle(ForgiaPalette.accent).lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.accent).accessibilityHidden(true)
            }
        }
    }
}

struct AnalysisEmptyState: View {
    let symbol: FormiFeatureSymbol
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 16) {
                    illustration
                    explanation
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                illustration
                explanation
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ForgiaPalette.accent)
    }

    private var illustration: some View {
        FormiFeatureIcon(symbol: symbol, size: 64, ink: ForgiaPalette.accent)
            .accessibilityHidden(true)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MonthlySpendingTrendCard: View {
    let trend: MonthlySpendingTrend
    let currency: String
    var periodTitle = ""

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Andamento delle spese", periodTitle: periodTitle, tint: AnalysisPalette.spending) {
                MonthlySpendingTrendDetailContent(trend: trend, currency: currency)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Andamento delle spese", icon: "chart.xyaxis.line", tint: AnalysisPalette.spending)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if trend.hasInvalidAmounts {
                            AnalysisEmptyState(symbol: .balance, title: "Importi da verificare", message: "Controlla gli importi prima di confrontare le spese.")
                        } else if let last = trend.current.last {
                            Text(last.amount, format: .currency(code: currency))
                                .analysisMetric().financeNumericMotion(last.amount).foregroundStyle(AnalysisPalette.spending)
                            Text(trend.isInProgress ? "Registrate fino a oggi" : "Registrate nel mese")
                                .font(.caption).foregroundStyle(ForgiaPalette.accent)
                        } else {
                            AnalysisEmptyState(symbol: .balance, title: "Periodo non iniziato", message: "Il grafico sarà disponibile con i movimenti del periodo.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !trend.hasInvalidAmounts && !trend.current.isEmpty {
                        MonthlySpendingLines(trend: trend, currency: currency, compact: true)
                            .frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                }
            }.unifiedCard(tint: AnalysisPalette.spending).foregroundStyle(ForgiaPalette.accent)
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

    private var resultTint: Color {
        report.savingsRate.map { $0 < 0 ? AnalysisPalette.deficit : AnalysisPalette.savings } ?? AnalysisPalette.savings
    }

    var body: some View {
        NavigationLink {
            AnalysisDetailScreen(title: "Tasso di risparmio", periodTitle: periodTitle, tint: resultTint) {
                RecordedSavingsDetailContent(report: report, currency: currency, isInProgress: isInProgress, plan: plan)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisPreviewHeading(title: "Tasso di risparmio", icon: "gauge.with.needle", tint: resultTint)
                if let rate = report.savingsRate {
                    SavingsRateHero(rate: rate, compact: true)
                } else {
                    AnalysisEmptyState(symbol: .accounts, title: "Non calcolabile",
                        message: report.hasInvalidAmounts ? "Importi da verificare" : "Servono entrate registrate")
                }
            }
            .unifiedCard(tint: resultTint)
            .foregroundStyle(ForgiaPalette.accent)
        }
        .buttonStyle(.plain)
        .financeCardEntrance()
        .accessibilityIdentifier("analysis-savings-preview")
    }
}

struct FinancialSharePreview: View {
    let share: Double
    var icon = "leaf"
    var tint: Color = AnalysisPalette.margin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(tint.opacity(0.15), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: appeared || reduceMotion ? min(1, max(0, share)) * 0.75 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(135))
            Image(systemName: icon).foregroundStyle(tint)
        }.frame(width: 58, height: 58).padding(5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: share)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { appeared = true } }
    }
}
