//
//  SpendingByWeekdaySection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore
import Charts

struct SpendingByWeekdaySection: View {
    let data: [WeekdaySpending]
    let themeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spese per Giorno").font(.headline)

            if data.isEmpty {
                ContentUnavailableView {
                    Label("Nessun dato", systemImage: "calendar")
                } description: {
                    Text("Le spese per giorno appariranno qui")
                }
            } else {
                let maxAmount = data.map(\.amount).max() ?? Decimal(1)

                Chart(data) { day in
                    BarMark(
                        x: .value("Giorno", day.label),
                        y: .value("Importo", NSDecimalNumber(decimal: day.amount).doubleValue)
                    )
                    .foregroundStyle(
                        day.amount == maxAmount
                            ? Color.red.gradient
                            : themeColor.gradient
                    )
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
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
                .frame(height: 150)

                if let peakDay = data.max(by: { $0.amount < $1.amount }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                        Text("Picco di spesa: **\(peakDay.fullName)** (\(peakDay.amount.currencyFormatted))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .unifiedCard()
    }
}
