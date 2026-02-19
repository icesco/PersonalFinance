//
//  SpendingDistributionSection.swift
//  Personal Finance
//

import SwiftUI
import Charts
import FinanceCore

struct SpendingDistributionSection: View {
    let categories: [SpendingCategory]
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dove vanno i soldi").font(.headline)
                if onExpand != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onExpand?() }

            if categories.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna spesa", systemImage: "chart.pie")
                } description: {
                    Text("Le tue spese appariranno qui")
                }
                .frame(height: 180)
            } else {
                Chart(categories) { item in
                    SectorMark(
                        angle: .value("Importo", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.color))
                    .cornerRadius(4)
                }
                .frame(height: 180)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(categories.prefix(6)) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: item.color))
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(item.percentage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .unifiedCard()
    }
}
