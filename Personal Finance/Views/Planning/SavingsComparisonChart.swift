import SwiftUI
import Charts
import FinanceCore

/// A signed bar and a visible reference marker; values are never clamped to make them look better.
struct SavingsComparisonChart: View {
    let title: LocalizedStringResource
    let actual: Decimal?
    let reference: Decimal?
    let currency: String?
    let isCeiling: Bool
    let isInProgress: Bool
    private var assessment: SavingsAssessment {
        if let reference {
            return .compare(actual: actual, reference: reference, isCeiling: isCeiling, isInProgress: isInProgress)
        }
        guard let actual else { return .unavailable }
        return .margin(income: max(actual, 0), expenses: max(-actual, 0))
    }
    private var badgeTitle: LocalizedStringResource? {
        if currency == nil {
            switch assessment {
            case .targetReached: return "Margine in linea"
            case .inProgress: return "Sotto riferimento finora"
            case .belowTarget: return "Sotto il riferimento"
            default: return nil
            }
        }
        if !isCeiling {
            switch assessment {
            case .deficit: return "Risparmi utilizzati"
            case .positiveMargin: return "Accantonamenti positivi"
            case .balanced: return "Nessuna variazione netta"
            default: return nil
            }
        }
        return nil
    }
    private var value: Double { actual.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 }
    private var target: Double { reference.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 }
    private var domain: ClosedRange<Double> {
        let low = min(0, value * 1.12)
        let high = max(1, max(value, target) * 1.15)
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let actual {
                    SavingsChartValue(value: actual, currency: currency).font(.headline).monospacedDigit()
                } else { Text("Non misurato").font(.subheadline).foregroundStyle(.secondary) }
            }
            Chart {
                if actual != nil {
                    BarMark(xStart: .value("Zero", 0), xEnd: .value("Registrato", value), y: .value("Misura", ""), height: .ratio(0.55))
                        .foregroundStyle(assessment == .deficit || assessment == .limitExceeded
                            ? ForgiaPalette.deficit : isCeiling ? ForgiaPalette.spending : ForgiaPalette.savings).cornerRadius(5)
                }
                RuleMark(x: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.35))
                if reference != nil {
                    RuleMark(x: .value("Riferimento", target))
                        .foregroundStyle(isCeiling ? ForgiaPalette.spending : ForgiaPalette.savings).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .chartXScale(domain: domain)
            .chartYAxis(.hidden)
            .chartXAxis {
                if currency == nil {
                    AxisMarks(values: .automatic(desiredCount: 3)) { tick in
                        if let number = tick.as(Double.self) {
                            AxisValueLabel {
                                Text(number, format: .percent.precision(.fractionLength(0))).font(.caption2)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: [0.0]) { _ in
                        AxisValueLabel { Text("0").font(.caption2) }
                    }
                }
            }
            .frame(height: 46)
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    SavingsAssessmentBadge(assessment: assessment, isInProgress: isInProgress, titleOverride: badgeTitle)
                    Spacer(minLength: 8)
                    SavingsReferenceLabel(reference: reference, currency: currency, isCeiling: isCeiling)
                }
                VStack(alignment: .leading, spacing: 6) {
                    SavingsAssessmentBadge(assessment: assessment, isInProgress: isInProgress, titleOverride: badgeTitle)
                    SavingsReferenceLabel(reference: reference, currency: currency, isCeiling: isCeiling)
                }
            }
        }
        .padding(14)
        .background(ForgiaPalette.canvas, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct SavingsReferenceLabel: View {
    let reference: Decimal?
    let currency: String?
    let isCeiling: Bool
    var body: some View {
        if let reference {
            HStack(spacing: 5) {
                Image(systemName: "line.diagonal").accessibilityHidden(true)
                Text(currency == nil ? "Riferimento" : isCeiling ? "Limite" : "Obiettivo")
                SavingsChartValue(value: reference, currency: currency)
            }.font(.caption).foregroundStyle(.secondary)
        } else { Text("Senza obiettivo di confronto").font(.caption).foregroundStyle(.secondary) }
    }
}

struct SavingsChartValue: View {
    let value: Decimal
    let currency: String?
    @Environment(\.locale) private var locale
    var body: some View {
        if let currency { Text(value, format: .currency(code: currency).locale(locale)) }
        else { Text(value, format: .percent.precision(.fractionLength(1)).locale(locale)) }
    }
}

struct SavingsAssessmentBadge: View {
    let assessment: SavingsAssessment
    var isInProgress = false
    var titleOverride: LocalizedStringResource? = nil
    var body: some View {
        Label(titleOverride ?? assessment.title(isInProgress: isInProgress), systemImage: assessment.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(assessment.tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(assessment.tint.opacity(0.10), in: Capsule())
    }
}

extension SavingsAssessment {
    var tint: Color {
        switch self {
        case .deficit, .limitExceeded, .belowTarget: .red
        case .withinLimit, .targetReached: ForgiaPalette.accent
        case .inProgress: .orange
        default: .secondary
        }
    }
    var symbol: String {
        switch self {
        case .deficit, .limitExceeded, .belowTarget: "exclamationmark.circle"
        case .withinLimit, .targetReached: "checkmark.circle"
        case .inProgress: "clock"
        default: "info.circle"
        }
    }
    func title(isInProgress: Bool) -> LocalizedStringResource {
        switch self {
        case .unavailable: "Dati insufficienti"
        case .deficit: "Spese oltre entrate"
        case .positiveMargin: "Margine positivo"
        case .balanced: "Entrate e spese in equilibrio"
        case .withinLimit: isInProgress ? "Entro il limite finora" : "Entro il limite"
        case .limitExceeded: "Limite superato"
        case .targetReached: "Obiettivo raggiunto"
        case .inProgress: "Obiettivo in corso"
        case .belowTarget: "Sotto l'obiettivo"
        case .noTarget: "Nessun obiettivo impostato"
        }
    }
}
