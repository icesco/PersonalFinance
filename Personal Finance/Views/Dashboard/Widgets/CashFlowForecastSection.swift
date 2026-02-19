//
//  CashFlowForecastSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore
import Charts

struct CashFlowForecastSection: View {
    let forecast: [CashFlowWeek]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previsione Cash Flow").font(.headline)

            if forecast.isEmpty {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "chart.bar.xaxis.ascending")
                } description: {
                    Text("Servono transazioni ricorrenti per la previsione")
                }
            } else {
                Chart(forecast) { week in
                    BarMark(
                        x: .value("Settimana", week.label),
                        y: .value("Entrate", week.projectedIncome.doubleValue)
                    )
                    .foregroundStyle(.green.gradient)
                    .position(by: .value("Tipo", "Entrate"))

                    BarMark(
                        x: .value("Settimana", week.label),
                        y: .value("Uscite", week.projectedExpenses.doubleValue)
                    )
                    .foregroundStyle(.red.gradient)
                    .position(by: .value("Tipo", "Uscite"))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(BalanceCalculator.formatCompactCurrency(Decimal(v)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)

                let totalNet = forecast.reduce(Decimal(0)) { $0 + $1.projectedIncome - $1.projectedExpenses }
                HStack(spacing: 4) {
                    Image(systemName: totalNet >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .font(.caption)
                    Text("Flusso netto previsto: \(totalNet.currencyFormatted)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(totalNet >= 0 ? .green : .red)
            }
        }
        .unifiedCard()
    }
}
