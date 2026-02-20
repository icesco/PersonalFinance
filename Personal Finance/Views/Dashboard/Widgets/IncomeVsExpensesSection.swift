//
//  IncomeVsExpensesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore
import Charts

struct IncomeVsExpensesSection: View {
    let data: [MonthlyIncomeExpense]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entrate vs Uscite").font(.headline)

            if data.isEmpty {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "chart.bar.fill")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            .frame(maxWidth: .infinity)
            } else {
                Chart(data) { month in
                    BarMark(
                        x: .value("Mese", month.label),
                        y: .value("Entrate", month.income.doubleValue)
                    )
                    .foregroundStyle(.green.gradient)
                    .position(by: .value("Tipo", "Entrate"))
                    .cornerRadius(4)

                    BarMark(
                        x: .value("Mese", month.label),
                        y: .value("Uscite", month.expenses.doubleValue)
                    )
                    .foregroundStyle(.red.gradient)
                    .position(by: .value("Tipo", "Uscite"))
                    .cornerRadius(4)
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
                .chartForegroundStyleScale([
                    "Entrate": Color.green,
                    "Uscite": Color.red
                ])
                .frame(height: 200)
            }
        }
        .unifiedCard()
    }
}
