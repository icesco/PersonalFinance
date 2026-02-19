//
//  SavingsRateSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct SavingsRateSection: View {
    let savingsRate: Double
    let monthlyIncome: Decimal
    let monthlyExpenses: Decimal

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Tasso di Risparmio").font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", savingsRate))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(savingsRate >= 0 ? .green : .red)
            }

            PercentageBar(
                fraction: abs(min(max(savingsRate, -100), 100)) / 100.0,
                color: savingsRate >= 0 ? .green : .red,
                height: 16,
                cornerRadius: 8
            )

            HStack {
                Label(monthlyIncome.currencyFormatted, systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Label(monthlyExpenses.currencyFormatted, systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .unifiedCard()
    }
}
