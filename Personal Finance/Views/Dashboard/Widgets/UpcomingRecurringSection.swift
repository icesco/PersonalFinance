//
//  UpcomingRecurringSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct UpcomingRecurringSection: View {
    let items: [(transaction: FinanceTransaction, nextDate: Date)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spese Ricorrenti in Arrivo").font(.headline)

            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna ricorrenza", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Le spese ricorrenti appariranno qui")
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.transaction.id) { index, item in
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(Self.dayFormatter.string(from: item.nextDate))
                                .font(.title3.weight(.bold))
                            Text(Self.monthFormatter.string(from: item.nextDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.transaction.transactionDescription ?? item.transaction.category?.name ?? "Ricorrenza")
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(item.transaction.recurrenceFrequency?.displayName ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text((item.transaction.amount ?? Decimal(0)).currencyFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.transaction.type == .income ? .green : .red)
                    }

                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()
}
