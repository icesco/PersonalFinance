//
//  CategorySparklinesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore
import Charts

struct CategorySparklinesSection: View {
    let trends: [CategoryTrendData]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trend per Categoria").font(.headline)

            if trends.isEmpty {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            } else {
                ForEach(trends) { trend in
                    HStack(spacing: 12) {
                        Image(systemName: trend.icon)
                            .font(.body)
                            .foregroundStyle(Color(hex: trend.color))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(trend.currentMonth.currencyFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 100, alignment: .leading)

                        Chart(Array(trend.monthlyAmounts.enumerated()), id: \.offset) { index, amount in
                            LineMark(
                                x: .value("Mese", index),
                                y: .value("Importo", NSDecimalNumber(decimal: amount).doubleValue)
                            )
                            .foregroundStyle(Color(hex: trend.color))
                            .interpolationMethod(.monotone)

                            AreaMark(
                                x: .value("Mese", index),
                                y: .value("Importo", NSDecimalNumber(decimal: amount).doubleValue)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color(hex: trend.color).opacity(0.3), Color(hex: trend.color).opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 32)

                        Image(systemName: trend.isIncreasing ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trend.isIncreasing ? .red : .green)
                            .frame(width: 20)
                    }

                    if trend.id != trends.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}
