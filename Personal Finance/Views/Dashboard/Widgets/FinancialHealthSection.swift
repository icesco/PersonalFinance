//
//  FinancialHealthSection.swift
//  Personal Finance
//

import SwiftUI
import FinanceCore

struct FinancialHealthSection: View {
    let healthScore: FinancialHealthResult

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Financial Health").font(.headline)
                Spacer()
                Text(healthScore.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(healthScore.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(healthScore.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: CGFloat(healthScore.score) / 100)
                    .stroke(healthScore.color.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: healthScore.score)

                VStack(spacing: 2) {
                    Text("\(Int(healthScore.score))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)

            VStack(spacing: 8) {
                HealthComponentRow(label: "Risparmio", score: healthScore.savingsPoints, maxScore: 30, color: .green)
                HealthComponentRow(label: "Budget", score: healthScore.budgetPoints, maxScore: 25, color: .blue)
                HealthComponentRow(label: "Stabilit\u{00E0} Entrate", score: healthScore.incomePoints, maxScore: 20, color: .purple)
                HealthComponentRow(label: "Trend Spese", score: healthScore.spendingPoints, maxScore: 25, color: .orange)
            }
        }
        .unifiedCard()
    }
}

private struct HealthComponentRow: View {
    let label: String
    let score: Double
    let maxScore: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geometry in
                let fraction = maxScore > 0 ? score / maxScore : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text("\(Int(score))/\(Int(maxScore))")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
