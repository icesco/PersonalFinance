//
//  SpendingPaceSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct SpendingPaceSection: View {
    let monthlyExpenses: Decimal
    let periodAverageExpenses: Decimal

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let daysElapsed = max(1, calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30

        let dailyRate = daysElapsed > 0 ? monthlyExpenses / Decimal(daysElapsed) : Decimal(0)
        let projectedTotal = dailyRate * Decimal(daysInMonth)
        let averageDaily = periodAverageExpenses > 0
            ? periodAverageExpenses / Decimal(daysInMonth)
            : Decimal(0)
        let isFaster = dailyRate > averageDaily && averageDaily > 0

        VStack(alignment: .leading, spacing: 16) {
            Text("Velocit\u{00E0} di Spesa").font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.title2)
                        .foregroundStyle(isFaster ? .red : .green)
                    Text(dailyRate.currencyFormatted)
                        .font(.title3.weight(.bold))
                    Text("al giorno")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 60)

                VStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(projectedTotal.currencyFormatted)
                        .font(.title3.weight(.bold))
                    Text("proiezione mese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if averageDaily > 0 {
                HStack(spacing: 4) {
                    Image(systemName: isFaster ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                    Text(isFaster
                         ? "Stai spendendo pi\u{00F9} della media (\(averageDaily.currencyFormatted)/g)"
                         : "Sotto la media di \(averageDaily.currencyFormatted)/g")
                        .font(.caption)
                }
                .foregroundStyle(isFaster ? .orange : .green)
            }
        }
        .unifiedCard()
    }
}
