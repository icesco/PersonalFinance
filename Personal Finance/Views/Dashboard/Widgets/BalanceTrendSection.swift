//
//  BalanceTrendSection.swift
//  Personal Finance
//

import SwiftUI
import Charts
import FinanceCore

struct BalanceTrendSection: View {
    let pastData: [BalanceDataPoint]
    let futureData: [BalanceDataPoint]
    let yDomain: ClosedRange<Decimal>
    let useWeeklyAxis: Bool
    let axisStrideCount: Int
    let themeColor: Color
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Andamento Saldo").font(.headline)
                if onExpand != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onExpand?() }

            if pastData.isEmpty && futureData.isEmpty {
                ContentUnavailableView {
                    Label("Nessun dato", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("I dati appariranno qui")
                }
                .frame(height: 200)
            } else {
                Chart {
                    ForEach(pastData, id: \.date) { item in
                        LineMark(
                            x: .value("Data", item.date, unit: .day),
                            y: .value("Saldo", item.balance),
                            series: .value("Serie", "Passato")
                        )
                        .foregroundStyle(themeColor.gradient)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }

                    ForEach(futureData, id: \.date) { item in
                        LineMark(
                            x: .value("Data", item.date, unit: .day),
                            y: .value("Saldo", item.balance),
                            series: .value("Serie", "Futuro")
                        )
                        .foregroundStyle(themeColor.opacity(0.4))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    }
                }
                .chartXAxis {
                    if useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day())
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: axisStrideCount)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let decimal = value.as(Decimal.self) {
                                Text(BalanceCalculator.formatCompactCurrency(decimal))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .frame(height: 200)
            }
        }
        .unifiedCard()
    }
}
