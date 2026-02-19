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

            GeometryReader { geometry in
                let width = geometry.size.width
                let clampedRate = min(max(savingsRate, -100), 100)
                let fillFraction = abs(clampedRate) / 100.0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 16)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(savingsRate >= 0
                              ? Color.green.gradient
                              : Color.red.gradient)
                        .frame(width: width * fillFraction, height: 16)
                }
            }
            .frame(height: 16)

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
