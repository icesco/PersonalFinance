//
//  TopPayeesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct TopPayeesSection: View {
    let payees: [PayeeData]
    let themeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Destinatari").font(.headline)

            if payees.isEmpty {
                ContentUnavailableView {
                    Label("Nessun dato", systemImage: "person.2")
                } description: {
                    Text("I destinatari più frequenti appariranno qui")
                }
            } else {
                let maxAmount = payees.first?.totalAmount ?? Decimal(1)

                ForEach(Array(payees.enumerated()), id: \.element.id) { index, payee in
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(payee.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(payee.transactionCount) transazioni")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(payee.totalAmount.currencyFormatted)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        GeometryReader { geometry in
                            let fraction = maxAmount > 0
                                ? CGFloat(NSDecimalNumber(decimal: payee.totalAmount / maxAmount).doubleValue)
                                : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.tertiarySystemFill))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(themeColor.gradient)
                                    .frame(width: geometry.size.width * fraction)
                            }
                        }
                        .frame(height: 6)
                    }

                    if index < payees.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}
