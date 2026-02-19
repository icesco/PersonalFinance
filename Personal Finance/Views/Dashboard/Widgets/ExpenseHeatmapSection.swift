//
//  ExpenseHeatmapSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct ExpenseHeatmapSection: View {
    let dailyFlow: [Date: DailyFlow]
    let referenceDate: Date

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    var body: some View {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let mondayOffset = (firstWeekday + 5) % 7
        let weekdayLabels = ["L", "M", "M", "G", "V", "S", "D"]

        // Compute max absolute values for scaling intensity
        let allFlows = dailyFlow.values
        let maxExpense = allFlows.map(\.expenses).max() ?? Decimal(1)
        let maxIncome = allFlows.map(\.income).max() ?? Decimal(1)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heatmap Flussi").font(.headline)
                Spacer()
                Text(Self.monthYearFormatter.string(from: startOfMonth).capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayLabels[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let totalCells = mondayOffset + daysInMonth
            let rows = (totalCells + 6) / 7

            VStack(spacing: 4) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let dayNumber = cellIndex - mondayOffset + 1

                            if dayNumber >= 1 && dayNumber <= daysInMonth {
                                let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: startOfMonth)!
                                let flow = dailyFlow[calendar.startOfDay(for: date)]
                                let cellColor = cellColor(
                                    for: flow, maxExpense: maxExpense, maxIncome: maxIncome
                                )

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(cellColor)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Text("\(dayNumber)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(textColor(for: flow, maxExpense: maxExpense, maxIncome: maxIncome))
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.clear)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendRow(label: "Entrate", color: .green)
                legendRow(label: "Uscite", color: .red)
                legendRow(label: "Nessuna", color: Color(.tertiarySystemFill))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .unifiedCard()
    }

    // MARK: - Helpers

    private func cellColor(for flow: DailyFlow?, maxExpense: Decimal, maxIncome: Decimal) -> Color {
        guard let flow else { return Color(.tertiarySystemFill) }

        let hasExpenses = flow.expenses > 0
        let hasIncome = flow.income > 0

        if hasIncome && hasExpenses {
            // Mixed day: use net to decide color
            let net = flow.net
            if net >= 0 {
                let intensity = maxIncome > 0 ? CGFloat(flow.income.doubleValue / maxIncome.doubleValue) : 0
                return Color.green.opacity(0.15 + Double(intensity) * 0.7)
            } else {
                let intensity = maxExpense > 0 ? CGFloat(flow.expenses.doubleValue / maxExpense.doubleValue) : 0
                return Color.red.opacity(0.15 + Double(intensity) * 0.7)
            }
        } else if hasExpenses {
            let intensity = maxExpense > 0 ? CGFloat(flow.expenses.doubleValue / maxExpense.doubleValue) : 0
            return Color.red.opacity(0.15 + Double(intensity) * 0.7)
        } else if hasIncome {
            let intensity = maxIncome > 0 ? CGFloat(flow.income.doubleValue / maxIncome.doubleValue) : 0
            return Color.green.opacity(0.15 + Double(intensity) * 0.7)
        }

        return Color(.tertiarySystemFill)
    }

    private func textColor(for flow: DailyFlow?, maxExpense: Decimal, maxIncome: Decimal) -> Color {
        guard let flow else { return .secondary }

        let dominant: (amount: Decimal, max: Decimal) = flow.net >= 0
            ? (flow.income, maxIncome)
            : (flow.expenses, maxExpense)

        let intensity = dominant.max > 0
            ? dominant.amount.doubleValue / dominant.max.doubleValue
            : 0
        return intensity > 0.5 ? .white : .secondary
    }

    private func legendRow(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color == Color(.tertiarySystemFill) ? color : color.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
