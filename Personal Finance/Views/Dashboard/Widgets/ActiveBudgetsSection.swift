//
//  ActiveBudgetsSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct ActiveBudgetsSection: View {
    let budgets: [BudgetSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget in Corso").font(.headline)

            if budgets.isEmpty {
                ContentUnavailableView {
                    Label("Nessun budget", systemImage: "target")
                } description: {
                    Text("Crea un budget dalle Impostazioni")
                }
            } else {
                ForEach(budgets) { budget in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(budget.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(budget.spent.currencyFormatted + " / " + budget.limit.currencyFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geometry in
                            let fillWidth = geometry.size.width * min(budget.percentage, 1.0)
                            let overflowWidth = budget.percentage > 1.0
                                ? geometry.size.width * min(budget.percentage - 1.0, 1.0)
                                : 0

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.tertiarySystemFill))

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(budget.barColor.gradient)
                                    .frame(width: fillWidth)

                                if overflowWidth > 0 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: geometry.size.width)
                                }
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            Text(String(format: "%.0f%%", budget.percentage * 100))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(budget.barColor)

                            Spacer()

                            if budget.daysRemaining > 0 {
                                Text("\(budget.daysRemaining)g rimanenti")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if budget.id != budgets.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}
