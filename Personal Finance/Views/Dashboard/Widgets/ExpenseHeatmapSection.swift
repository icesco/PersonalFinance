//
//  ExpenseHeatmapSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct ExpenseHeatmapSection: View {
    let dailyExpenses: [Date: Decimal]
    let referenceDate: Date
    let themeColor: Color

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
        let maxExpense = dailyExpenses.values.max() ?? Decimal(1)
        let weekdayLabels = ["L", "M", "M", "G", "V", "S", "D"]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heatmap Spese").font(.headline)
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
                                let expense = dailyExpenses[calendar.startOfDay(for: date)] ?? Decimal(0)
                                let intensity = maxExpense > 0
                                    ? CGFloat((expense / maxExpense).doubleValue)
                                    : 0

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(intensity > 0
                                          ? themeColor.opacity(0.15 + Double(intensity) * 0.85)
                                          : Color(.tertiarySystemFill))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Text("\(dayNumber)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(intensity > 0.6 ? .white : .secondary)
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

            HStack(spacing: 4) {
                Text("Meno")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == 0 ? Color(.tertiarySystemFill) : themeColor.opacity(Double(i) / 4.0))
                        .frame(width: 14, height: 14)
                }
                Text("Pi\u{00F9}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .unifiedCard()
    }
}
