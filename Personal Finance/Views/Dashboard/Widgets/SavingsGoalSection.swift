//
//  SavingsGoalSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct SavingsGoalSection: View {
    let data: SavingsGoalData
    let themeColor: Color

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Obiettivo Risparmio").font(.headline)
                Spacer()
                if data.monthlyTarget > 0 {
                    Text(data.monthlyTarget.currencyFormatted + "/mese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if data.monthlyTarget <= 0 {
                VStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Nessun obiettivo impostato")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Basato sulla media risparmi degli ultimi mesi")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: min(CGFloat(data.progressPercent) / 100, 1.0))
                        .stroke(
                            data.progressPercent >= 100
                                ? Color.green.gradient
                                : themeColor.gradient,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: data.progressPercent)

                    VStack(spacing: 2) {
                        Text(data.currentSavings.currencyFormatted)
                            .font(.title3.weight(.bold))
                        Text("di \(data.monthlyTarget.currencyFormatted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", data.progressPercent))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(data.progressPercent >= 100 ? .green : themeColor)
                        Text("Raggiunto")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1, height: 30)

                    VStack(spacing: 2) {
                        Text(data.remaining.currencyFormatted)
                            .font(.subheadline.weight(.bold))
                        Text("Mancanti")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1, height: 30)

                    VStack(spacing: 2) {
                        Text("\(data.daysRemaining)g")
                            .font(.subheadline.weight(.bold))
                        Text("Rimanenti")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if data.projectedEndOfMonth > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: data.onTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(data.onTrack
                             ? "In linea! Proiezione: \(data.projectedEndOfMonth.currencyFormatted)"
                             : "Attenzione: proiezione \(data.projectedEndOfMonth.currencyFormatted)")
                            .font(.caption)
                    }
                    .foregroundStyle(data.onTrack ? .green : .orange)
                }
            }
        }
        .unifiedCard()
    }
}
