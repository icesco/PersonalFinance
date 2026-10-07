import SwiftUI
import Charts
import FinanceCore

extension AccountBalanceSeries {
    var color: Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(hex, radix: 16) ?? 0x238B83
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

/// The same ledger chart is rendered by the app and the WidgetKit extension.
struct BalanceHistoryPlot: View {
    let series: [AccountBalanceSeries]
    let interval: DateInterval
    let currency: String
    @Binding var selectedDate: Date?
    var compact = false
    var interactive = true
    var snapshotLabel = false
    var minimal = false

    @ViewBuilder var body: some View {
        if interactive { plot.chartXSelection(value: $selectedDate) }
        else { plot }
    }

    private var plot: some View {
        let openingDate = series.first?.points.first?.date ?? interval.start
        let closingDate = series.first?.points.last?.date ?? interval.start
        let hasProjection = series.contains { !$0.projected.isEmpty }
        let endDate = hasProjection ? interval.end : closingDate
        let probeDate = selectedDate.map { min(max($0, openingDate), endDate) } ?? closingDate
        let domain = BalanceCalculator.chartYDomain(dataPoints: series.flatMap { $0.points + $0.projected })
        return Chart {
            ForEach(series) { account in
                ForEach(account.points, id: \.date) { point in
                    accountLine(account, point: point)
                }
                ForEach(account.projected, id: \.date) { point in
                    accountLine(account, point: point, projected: true)
                }
                PointMark(x: .value("Data", probeDate),
                          y: .value("Saldo", NSDecimalNumber(decimal: account.balance(at: probeDate)).doubleValue))
                    .foregroundStyle(account.color).symbolSize(36)
                    .accessibilityLabel(account.name)
                    .accessibilityValue(Text(account.balance(at: probeDate), format: .currency(code: currency)))
            }
            if hasProjection && !minimal {
                RuleMark(x: .value("Oggi", closingDate))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(snapshotLabel ? "Registrato" : "Oggi").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if selectedDate != nil {
                RuleMark(x: .value("Selezione", probeDate))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: NSDecimalNumber(decimal: domain.lowerBound).doubleValue...NSDecimalNumber(decimal: domain.upperBound).doubleValue)
        .chartXScale(domain: openingDate...max(endDate, openingDate.addingTimeInterval(1)))
        .chartLegend(.hidden)
        .chartXAxis {
            if !minimal {
                AxisMarks(values: .automatic(desiredCount: compact ? 2 : 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .number.notation(.compactName)).font(.caption2)
                        }
                    }
                }
            }
        }

        .accessibilityLabel(hasProjection ? "Saldo registrato e previsto per conto. Valori in \(currency)." : "Saldo registrato per conto. Valori in \(currency).")
    }
    private func accountLine(_ account: AccountBalanceSeries, point: BalanceDataPoint, projected: Bool = false) -> some ChartContent {
        let amount = NSDecimalNumber(decimal: point.balance).doubleValue
        let label = point.balance.formatted(.currency(code: currency))
        return LineMark(x: .value("Data", point.date), y: .value("Saldo", amount),
                        series: .value("Conto", account.id.uuidString + (projected ? "-previsto" : "-registrato")))
            .interpolationMethod(.stepEnd)
            .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round, dash: projected ? [5, 4] : []))
            .foregroundStyle(account.color.opacity(projected ? 0.65 : 1))
            .accessibilityLabel(account.name + (projected ? ", previsto" : ", registrato"))
            .accessibilityValue(label)
    }

}
