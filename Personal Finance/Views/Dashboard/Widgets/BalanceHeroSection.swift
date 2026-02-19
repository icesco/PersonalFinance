//
//  BalanceHeroSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct BalanceHeroSection: View {
    let totalBalance: Decimal
    let percentageChange: Double
    let absoluteChange: Decimal

    // derived
    private var isPositiveChange: Bool { absoluteChange >= 0 }

    var body: some View {
        VStack(spacing: 8) {
            Text(totalBalance.currencyFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(totalBalance >= 0 ? .primary : .red)
                .contentTransition(.numericText(value: totalBalance.doubleValue))
                .animation(.easeOut(duration: 0.5), value: totalBalance)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                    Text(String(format: "%.1f%%", abs(percentageChange)))
                        .font(.caption.weight(.bold))
                        .contentTransition(.numericText(value: percentageChange))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                )
                .animation(.easeOut(duration: 0.4), value: isPositiveChange)

                Text((isPositiveChange ? "+" : "") + absoluteChange.currencyFormatted)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: absoluteChange.doubleValue))
            }
            .animation(.easeOut(duration: 0.5), value: percentageChange)
        }
        .padding(.vertical, 8)
    }
}
