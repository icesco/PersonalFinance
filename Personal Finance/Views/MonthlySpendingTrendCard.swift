import SwiftUI
import Charts
import FinanceCore

struct MonthlySpendingTrendDetailContent: View {
    let trend: MonthlySpendingTrend
    let currency: String
    @State private var showsExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Andamento delle spese", systemImage: "chart.xyaxis.line")
                .font(.headline).foregroundStyle(ForgiaPalette.spending)
            if trend.hasInvalidAmounts {
                Text("Controlla gli importi mancanti o non validi prima di confrontare le spese.")
                    .foregroundStyle(ForgiaPalette.mutedText)
            } else if let last = trend.current.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last.amount, format: .currency(code: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit().financeNumericMotion(last.amount).foregroundStyle(ForgiaPalette.spending)
                    Text(trend.isInProgress ? "Spese registrate fino a oggi" : "Spese registrate nel mese")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                }
                MonthlySpendingLines(trend: trend, currency: currency)
                HStack(spacing: 18) {
                    Label("Mese selezionato", systemImage: "minus").foregroundStyle(ForgiaPalette.spending)
                    if trend.hasPreviousExpenses {
                        Label("Mese precedente", systemImage: "ellipsis").foregroundStyle(ForgiaPalette.mutedText)
                    }
                }.font(.caption)
                if trend.hasPreviousExpenses, let previous = trend.previous.last {
                    let difference = last.amount - previous.amount
                    Text("Differenza rispetto al mese precedente: \(difference, format: .currency(code: currency))")
                        .font(.subheadline.weight(.medium))
                    if trend.previous.count < trend.current.count {
                        Text("Il mese precedente ha meno giorni: il suo totale si ferma all'ultimo giorno disponibile.")
                            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                } else {
                    Text("Non risultano spese nel mese precedente fino al giorno confrontato.")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                }
            } else {
                Text("Il periodo non è ancora iniziato.").foregroundStyle(ForgiaPalette.mutedText)
            }
            DisclosureGroup("Come leggere il grafico", isExpanded: $showsExplanation) {
                Text("Le linee sommano le spese registrate giorno dopo giorno. Nel mese in corso il confronto arriva allo stesso giorno e alla stessa ora del mese precedente. Trasferimenti ed entrate sono esclusi. L'assenza di movimenti non conferma che i dati siano completi.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .padding(.top, 8)
            }.font(.subheadline).tint(ForgiaPalette.spending)
        }
        .unifiedCard(tint: ForgiaPalette.spending).financeCardEntrance()
        .accessibilityIdentifier("monthly-spending-trend")
    }
}

struct MonthlySpendingLines: View {
    let trend: MonthlySpendingTrend
    let currency: String
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart {
            ForEach(trend.current) { point in
                LineMark(x: .value("Giorno", point.day), y: .value("Spese", number(point.amount)), series: .value("Periodo", "current"))
                    .foregroundStyle(ForgiaPalette.spending).lineStyle(StrokeStyle(lineWidth: 3))
            }
            if trend.hasPreviousExpenses {
                ForEach(trend.previous) { point in
                    LineMark(x: .value("Giorno", point.day), y: .value("Spese", number(point.amount)), series: .value("Periodo", "previous"))
                        .foregroundStyle(ForgiaPalette.mutedText).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            if let last = trend.current.last {
                PointMark(x: .value("Giorno", last.day), y: .value("Spese", number(last.amount)))
                    .foregroundStyle(ForgiaPalette.spending).symbolSize(45)
            }
        }
        .chartXScale(domain: 1...max(trend.daysInMonth, trend.previous.count))
        .chartXAxis { AxisMarks(values: [1, 5, 10, 15, 20, 25, trend.daysInMonth]) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: trend.current.map(\.amount))
        .financeChartReveal()
        .frame(height: compact ? 64 : 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spese cumulative per giorno del mese")
        .accessibilityValue((trend.current.last?.amount ?? Decimal.zero).formatted(.currency(code: currency)))
    }

    private func number(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}
