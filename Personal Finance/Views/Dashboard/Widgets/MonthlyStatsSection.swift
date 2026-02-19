//
//  MonthlyStatsSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct MonthlyStatsSection: View {
    let income: Decimal
    let expenses: Decimal
    let savings: Decimal

    var body: some View {
        HStack(spacing: 12) {
            UnifiedStatCell(
                icon: "arrow.down.circle.fill",
                value: income.currencyFormatted,
                label: "Entrate",
                color: .green
            )
            UnifiedStatCell(
                icon: "arrow.up.circle.fill",
                value: expenses.currencyFormatted,
                label: "Uscite",
                color: .red
            )
            UnifiedStatCell(
                icon: savings >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                value: savings.currencyFormatted,
                label: "Risparmi",
                color: savings >= 0 ? .green : .red
            )
        }
    }
}
