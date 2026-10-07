import SwiftUI
import Charts

/// The actual value is never clamped: overspending and expense corrections
/// can put the rate outside 0...100%. Only the chart domain adapts.
struct SavingsRateComparison: View {
    let rate: Decimal
    let referencePercent: Int
    @Environment(\.locale) private var locale

    private var reference: Decimal { Decimal(min(100, max(0, referencePercent))) / 100 }
    private var value: Double { NSDecimalNumber(decimal: rate).doubleValue }
    private var target: Double { NSDecimalNumber(decimal: reference).doubleValue }
    private var color: Color {
        rate < 0 ? ForgiaPalette.deficit : rate < reference ? ForgiaPalette.calendar : ForgiaPalette.savings
    }
    private var verdict: LocalizedStringKey {
        if rate < 0 { return "Spese oltre le entrate" }
        if rate == 0 { return "Entrate interamente spese" }
        if rate < reference { return "Sotto il riferimento" }
        if rate == reference { return "In linea con il riferimento" }
        return "Sopra il riferimento"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(verdict, systemImage: rate < 0 ? "arrow.down.right" : rate < reference ? "arrow.up.right" : "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Chart {
                BarMark(xStart: .value("Quota", 0), xEnd: .value("Quota", value),
                        y: .value("Confronto", "Periodo"), height: .fixed(18))
                    .foregroundStyle(color)
                    .cornerRadius(5)
                BarMark(xStart: .value("Quota", 0), xEnd: .value("Quota", target),
                        y: .value("Confronto", "Riferimento"), height: .fixed(18))
                    .foregroundStyle(ForgiaPalette.mutedText.opacity(0.35))
                    .cornerRadius(5)
                RuleMark(x: .value("Zero", 0))
                    .foregroundStyle(ForgiaPalette.mutedText.opacity(0.4))
            }
            .chartXScale(domain: min(0, value)...max(0.4, value, target))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { axis in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = axis.as(Double.self) {
                            Text(number, format: .percent.precision(.fractionLength(0)).locale(locale))
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
            .frame(height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Confronto del tasso di risparmio")
            .accessibilityValue("Periodo \(rate.formatted(.percent.precision(.fractionLength(1)).locale(locale))), riferimento \(reference.formatted(.percent.precision(.fractionLength(0)).locale(locale)))")
            Text("Riferimento personale: \(reference, format: .percent.precision(.fractionLength(0)).locale(locale)) · modificabile nella guida")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }
    }
}
