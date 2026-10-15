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
                .font(.headline).foregroundStyle(ForgiaPalette.accent)
            if trend.hasInvalidAmounts {
                Text("Controlla gli importi mancanti o non validi prima di confrontare le spese.")
                    .foregroundStyle(ForgiaPalette.accent)
            } else if let last = trend.current.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last.amount, format: .currency(code: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit().financeNumericMotion(last.amount).foregroundStyle(AnalysisPalette.spending)
                    Text(trend.isInProgress ? "Spese registrate fino a oggi" : "Spese registrate nel mese")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.accent)
                }
                MonthlySpendingLines(trend: trend, currency: currency)
                HStack(spacing: 18) {
                    Label("Mese selezionato", systemImage: "minus").foregroundStyle(AnalysisPalette.spending)
                    if trend.hasPreviousExpenses {
                        Label("Mese precedente", systemImage: "ellipsis").foregroundStyle(ForgiaPalette.accent)
                    }
                }.font(.caption)
                if trend.hasPreviousExpenses, let previous = trend.previous.last {
                    let difference = last.amount - previous.amount
                    Text("Differenza rispetto al mese precedente: \(difference, format: .currency(code: currency))")
                        .font(.subheadline.weight(.medium))
                    if trend.previous.count < trend.current.count {
                        Text("Il mese precedente ha meno giorni: il suo totale si ferma all'ultimo giorno disponibile.")
                            .font(.caption).foregroundStyle(ForgiaPalette.accent)
                    }
                } else {
                    Text("Non risultano spese nel mese precedente fino al giorno confrontato.")
                        .font(.subheadline).foregroundStyle(ForgiaPalette.accent)
                }
            } else {
                Text("Il periodo non è ancora iniziato.").foregroundStyle(ForgiaPalette.accent)
            }
            DisclosureGroup("Come leggere il grafico", isExpanded: $showsExplanation) {
                Text("Le linee sommano le spese registrate giorno dopo giorno. Nel mese in corso il confronto arriva allo stesso giorno e alla stessa ora del mese precedente. Trasferimenti ed entrate sono esclusi. L'assenza di movimenti non conferma che i dati siano completi.")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.accent)
                    .padding(.top, 8)
            }.font(.subheadline).tint(AnalysisPalette.spending)
        }
        .unifiedCard(tint: AnalysisPalette.spending).financeCardEntrance()
        .accessibilityIdentifier("monthly-spending-trend")
    }
}

struct MonthlySpendingLines: View {
    let trend: MonthlySpendingTrend
    let currency: String
    var compact = false
    @State private var selectedDay: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            if compact {
                plot
                HStack {
                    Text("Giorno 1")
                    Spacer()
                    if lastPlottedDay > 1 {
                        Text("Giorno \(lastPlottedDay)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(ForgiaPalette.accent)
                HStack(spacing: 14) {
                    Label("Mese selezionato", systemImage: "minus")
                        .foregroundStyle(AnalysisPalette.spending)
                    if trend.hasPreviousExpenses {
                        Label("Mese precedente", systemImage: "ellipsis")
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                }
                .font(.caption2.weight(.medium))
            } else {
                plot.chartXSelection(value: $selectedDay)
                SpendingTrendDaySelection(points: trend.current, selectedDay: $selectedDay, currency: currency)
            }
        }
    }

    private var selectedPoint: MonthlySpendingTrend.Point? {
        guard let selectedDay else { return nil }
        return trend.current.min { abs($0.day - selectedDay) < abs($1.day - selectedDay) }
    }

    private var lastPlottedDay: Int {
        max(trend.current.last?.day ?? 1,
            trend.hasPreviousExpenses ? (trend.previous.last?.day ?? 1) : 1)
    }

    private var dayDomain: ClosedRange<Double> {
        guard compact else { return 1...Double(max(trend.daysInMonth, trend.previous.count)) }
        return lastPlottedDay == 1 ? 0.5...1.5 : 1...Double(lastPlottedDay)
    }

    private var plot: some View {
        Chart {
            ForEach(trend.current) { point in
                LineMark(x: .value("Giorno", point.day), y: .value("Spese", number(point.amount)), series: .value("Periodo", "current"))
                    .interpolationMethod(FinanceChartStyle.interpolation)
                    .foregroundStyle(AnalysisPalette.spending).lineStyle(StrokeStyle(lineWidth: 3))
            }
            if trend.hasPreviousExpenses {
                ForEach(trend.previous) { point in
                    LineMark(x: .value("Giorno", point.day), y: .value("Spese", number(point.amount)), series: .value("Periodo", "previous"))
                        .interpolationMethod(FinanceChartStyle.interpolation)
                        .foregroundStyle(ForgiaPalette.mutedText).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            if let last = trend.current.last {
                PointMark(x: .value("Giorno", last.day), y: .value("Spese", number(last.amount)))
                    .foregroundStyle(AnalysisPalette.spending).symbolSize(45)
            }
            if !compact, let point = selectedPoint {
                RuleMark(x: .value("Giorno selezionato", point.day))
                    .foregroundStyle(AnalysisPalette.spending.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("Giorno", point.day), y: .value("Spese", number(point.amount)))
                    .foregroundStyle(AnalysisPalette.spending).symbolSize(70)
            }
        }
        .chartXScale(domain: dayDomain, range: .plotDimension(padding: 4))
        .chartYScale(domain: .automatic(includesZero: !compact))
        .chartXAxis { AxisMarks(values: [1, 5, 10, 15, 20, 25, trend.daysInMonth]) }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
        .chartXAxis(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: trend.current.map(\.amount))
        .padding(.vertical, compact ? 0 : 8)
        .financeChartReveal()
        .frame(height: compact ? 80 : 200)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spese cumulative per giorno del mese")
        .accessibilityValue((trend.current.last?.amount ?? Decimal.zero).formatted(.currency(code: currency)))
    }

    private func number(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

private struct SpendingTrendDaySelection: View {
    let points: [MonthlySpendingTrend.Point]
    @Binding var selectedDay: Int?
    let currency: String

    private var point: MonthlySpendingTrend.Point? {
        guard let selectedDay else { return points.last }
        return points.min { abs($0.day - selectedDay) < abs($1.day - selectedDay) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(points) { item in
                            Button { selectedDay = item.day } label: {
                                Text(item.day, format: .number)
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .frame(minWidth: 44, minHeight: 44)
                                    .foregroundStyle(point?.day == item.day ? ForgiaPalette.onAccent : .primary)
                                    .background(point?.day == item.day ? AnalysisPalette.spending : ForgiaPalette.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Giorno \(item.day)")
                            .accessibilityAddTraits(point?.day == item.day ? .isSelected : [])
                            .accessibilityIdentifier("spending-trend-day-\(item.day)")
                            .id(item.day)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear { if let point { proxy.scrollTo(point.day, anchor: .center) } }
                .onChange(of: point?.day) { _, day in
                    if let day { proxy.scrollTo(day, anchor: .center) }
                }
            }
            if let point {
                let prior = points.first { $0.day == point.day - 1 }?.amount ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    Text("Giorno \(point.day)").font(.subheadline.weight(.semibold))
                    HStack {
                        Text("Spesa del giorno").foregroundStyle(ForgiaPalette.mutedText)
                        Spacer(minLength: 8)
                        Text(point.amount - prior, format: .currency(code: currency)).monospacedDigit()
                    }
                    HStack {
                        Text("Totale fino a questo giorno").foregroundStyle(ForgiaPalette.mutedText)
                        Spacer(minLength: 8)
                        Text(point.amount, format: .currency(code: currency)).monospacedDigit()
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("spending-trend-day-detail")
            }
        }
    }
}
