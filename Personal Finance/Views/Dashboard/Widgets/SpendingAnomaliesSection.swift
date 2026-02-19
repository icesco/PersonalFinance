//
//  SpendingAnomaliesSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct SpendingAnomaliesSection: View {
    let anomalies: [SpendingAnomaly]
    var onInfoTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Anomalie di Spesa").font(.headline)
                if let onInfoTap {
                    Button { onInfoTap() } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if !anomalies.isEmpty {
                    Text("\(anomalies.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange))
                }
            }

            if anomalies.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nessuna anomalia rilevata")
                            .font(.subheadline.weight(.medium))
                        Text("Le tue spese sono nella norma")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(Array(anomalies.enumerated()), id: \.element.id) { index, anomaly in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(anomaly.severity.color)
                            .frame(width: 10, height: 10)

                        Image(systemName: anomaly.icon)
                            .font(.body)
                            .foregroundStyle(Color(hex: anomaly.categoryColor))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(anomaly.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(anomaly.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(anomaly.amount.currencyFormatted)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                            Text("+\(Int(anomaly.deviationPercent))%")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }

                    if index < anomalies.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }
}
