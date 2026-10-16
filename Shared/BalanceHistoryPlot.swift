import SwiftUI
import Charts
import FinanceCore
import WidgetKit

enum FinanceChartStyle {
    static let interpolation: InterpolationMethod = .monotone
}

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
    var colorOverride: Color? = nil
    var lineWidth: CGFloat = 1.75
    var showsSnapshotLabel = true
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var distinguishesAccounts: Bool { snapshotLabel && renderingMode == .accented && series.count > 1 }
    @Environment(\.colorScheme) private var colorScheme

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
        let domain = BalanceCalculator.chartYDomain(dataPoints: series.flatMap { $0.points + $0.projected + ($0.savingsCapital ?? []) + ($0.savingsValue ?? []) })
        return Chart {
            ForEach(series) { account in
                ForEach(account.points, id: \.date) { point in
                    accountLine(account, point: point)
                }
                ForEach(account.savingsCapital ?? [], id: \.date) { point in
                    LineMark(x: .value("Data", point.date), y: .value("Capitale versato", NSDecimalNumber(decimal: point.balance).doubleValue),
                             series: .value("Conto", account.id.uuidString + "-capitale"))
                        .interpolationMethod(FinanceChartStyle.interpolation)
                        .foregroundStyle(account.color.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(account.savingsValue ?? [], id: \.date) { point in
                    LineMark(x: .value("Data", point.date), y: .value("Controvalore stimato", NSDecimalNumber(decimal: point.balance).doubleValue),
                             series: .value("Conto", account.id.uuidString + "-controvalore"))
                        .interpolationMethod(FinanceChartStyle.interpolation)
                        .foregroundStyle(account.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 3]))
                }
                ForEach(account.projected, id: \.date) { point in
                    accountLine(account, point: point, projected: true)
                }
                if snapshotLabel {
                    ForEach(account.projected.filter { $0.date > closingDate && $0.date < interval.end }, id: \.date) { point in
                        PointMark(x: .value("Data", point.date),
                                  y: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue))
                            .symbol(distinguishesAccounts ? BalanceAccountSymbol.shape(for: account.id, in: series) : .circle)
                            .symbolSize(minimal ? 12 : (distinguishesAccounts ? 30 : 20))
                            .foregroundStyle((colorOverride ?? account.color).opacity(0.9))
                            .accessibilityLabel("\(account.name), movimenti programmati")
                            .accessibilityValue(Text("\(point.date, format: .dateTime.day().month()), saldo previsto \(point.balance, format: .currency(code: currency))"))
                    }
                }
                PointMark(x: .value("Data", probeDate),
                          y: .value("Saldo", NSDecimalNumber(decimal: account.balance(at: probeDate)).doubleValue))
                    .foregroundStyle(colorOverride ?? account.color)
                    .symbol(distinguishesAccounts ? BalanceAccountSymbol.shape(for: account.id, in: series) : .circle)
                    .symbolSize(distinguishesAccounts ? (minimal ? 25 : 49) : (minimal ? 16 : 36))
                    .accessibilityLabel(account.name)
                    .accessibilityValue(Text(account.balance(at: probeDate), format: .currency(code: currency)))
            }
            if distinguishesAccounts && !minimal {
                ForEach(series) { account in
                    if let point = account.projected.last {
                        PointMark(x: .value("Data", point.date),
                                  y: .value("Saldo", NSDecimalNumber(decimal: point.balance).doubleValue))
                            .symbol(BalanceAccountSymbol.shape(for: account.id, in: series))
                            .symbolSize(49)
                            .foregroundStyle(.primary.opacity(0.85))
                            .accessibilityHidden(true)
                    }
                }
            }
            if hasProjection && !minimal {
                RuleMark(x: .value("Oggi", closingDate))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .trailing) {
                        if showsSnapshotLabel {
                            Text(snapshotLabel ? "Registrato" : "Oggi").font(.caption2).foregroundStyle(.secondary)
                        }
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
        .chartPlotStyle { content in
            content.background {
                if snapshotLabel && !minimal {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
                }
            }
        }
        .chartXAxis {
            if !minimal {
                AxisMarks(values: .automatic(desiredCount: compact ? 2 : 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            if !minimal && (!compact || snapshotLabel) {
                AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 2 : (snapshotLabel ? 3 : 4))) { value in
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
            .interpolationMethod(FinanceChartStyle.interpolation)
            .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: projected ? [5, 4] : []))
            .foregroundStyle((colorOverride ?? account.color).opacity(projected ? (snapshotLabel ? 0.85 : 0.65) : 1))
            .accessibilityLabel(account.name + (projected ? ", previsto" : ", registrato"))
            .accessibilityValue(label)
    }

}

struct BalanceAccountSymbol {
    static func shape(for accountID: UUID, in series: [AccountBalanceSeries]) -> BasicChartSymbolShape {
        let shapes: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond, .pentagon, .plus, .cross, .asterisk]
        return shapes[(series.firstIndex { $0.id == accountID } ?? 0) % shapes.count]
    }
}

struct BalanceAccountLegendKey: View {
    let account: AccountBalanceSeries
    let series: [AccountBalanceSeries]
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .accented && series.count > 1 {
            BalanceAccountSymbol.shape(for: account.id, in: series)
                .fill(.primary).frame(width: compact ? 7 : 9, height: compact ? 7 : 9)
                .frame(width: compact ? 7 : 14)
                .accessibilityHidden(true)
        } else if compact {
            Circle().fill(account.color).frame(width: 5, height: 5)
        } else {
            Capsule().fill(account.color).frame(width: 14, height: 3)
        }
    }
}
