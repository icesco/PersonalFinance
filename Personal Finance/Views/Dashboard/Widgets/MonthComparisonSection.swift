//
//  MonthComparisonSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct MonthComparisonSection: View {
    let trend: [(month: String, income: Decimal, expenses: Decimal)]

    var body: some View {
        let current = trend.last
        let previous = trend.count >= 2 ? trend[trend.count - 2] : nil

        VStack(alignment: .leading, spacing: 16) {
            Text("Confronto Mese Precedente").font(.headline)

            if let current, let previous {
                VStack(spacing: 12) {
                    MonthComparisonRow(
                        label: "Entrate",
                        current: current.income,
                        previous: previous.income,
                        color: .green
                    )
                    MonthComparisonRow(
                        label: "Uscite",
                        current: current.expenses,
                        previous: previous.expenses,
                        color: .red,
                        invertDelta: true
                    )

                    Divider()

                    let currentSavings = current.income - current.expenses
                    let previousSavings = previous.income - previous.expenses
                    MonthComparisonRow(
                        label: "Risparmi",
                        current: currentSavings,
                        previous: previousSavings,
                        color: currentSavings >= 0 ? .green : .red
                    )
                }
            } else {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            }
        }
        .unifiedCard()
    }
}

// MARK: - Month Comparison Row

private struct MonthComparisonRow: View {
    let label: String
    let current: Decimal
    let previous: Decimal
    let color: Color
    var invertDelta: Bool = false

    private var delta: Double {
        guard previous != 0 else { return 0 }
        return ((current - previous) / abs(previous) * 100).doubleValue
    }

    private var isDeltaPositive: Bool {
        invertDelta ? delta <= 0 : delta >= 0
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(current.currencyFormatted)
                    .font(.subheadline.weight(.semibold))

                if previous != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: isDeltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text(String(format: "%.0f%%", abs(delta)))
                            .font(.caption2.weight(.bold))
                        Text("vs " + previous.currencyFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(isDeltaPositive ? .green : .red)
                }
            }
        }
    }
}
