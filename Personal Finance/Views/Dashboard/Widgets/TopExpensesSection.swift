//
//  TopExpensesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct TopExpensesSection: View {
    let expenses: [FinanceTransaction]
    var title: String = "Top Spese del Mese"
    var onTapTransaction: ((FinanceTransaction) -> Void)?
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                if onExpand != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onExpand?() }

            if expenses.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna spesa", systemImage: "flame")
                } description: {
                    Text("Le spese maggiori appariranno qui")
                }
            .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { index, transaction in
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Image(systemName: transaction.category?.icon ?? "arrow.up.circle")
                            .font(.body)
                            .foregroundStyle(Color(hex: transaction.category?.color ?? "#FF5252"))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.transactionDescription ?? transaction.category?.name ?? "Spesa")
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(transaction.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text((transaction.amount ?? Decimal(0)).currencyFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTapTransaction?(transaction) }
                    .transition(.opacity.combined(with: .offset(y: 8)))

                    if index < expenses.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}
