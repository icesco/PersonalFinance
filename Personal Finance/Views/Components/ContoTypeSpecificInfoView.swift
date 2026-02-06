import SwiftUI
import FinanceCore

struct ContoTypeSpecificInfoView: View {
    let conto: Conto
    var compact: Bool = true

    var body: some View {
        switch conto.type {
        case .credit:
            creditCardInfo
        case .investment:
            investmentInfo
        case .savings:
            savingsInfo
        default:
            EmptyView()
        }
    }

    // MARK: - Credit Card Info

    @ViewBuilder
    private var creditCardInfo: some View {
        if let ratio = conto.creditLimitUsageRatio, let remaining = conto.creditLimitRemaining {
            if compact {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: min(ratio, 1.0))
                        .tint(creditColor(for: ratio))
                        .frame(width: 80)
                    Text("Disp. " + remaining.currencyFormatted)
                        .font(.caption2)
                        .foregroundStyle(creditColor(for: ratio))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Utilizzo plafond")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(min(ratio, 1.0) * 100))%")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(creditColor(for: ratio))
                    }
                    ProgressView(value: min(ratio, 1.0))
                        .tint(creditColor(for: ratio))
                    HStack {
                        Text("Speso: " + conto.currentMonthSpending.currencyFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Disponibile: " + remaining.currencyFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Investment Info

    @ViewBuilder
    private var investmentInfo: some View {
        if let annualReturn = conto.projectedAnnualReturn, let rate = conto.annualInterestRate {
            if compact {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+" + annualReturn.currencyFormatted + "/anno")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#4CAF50"))
                    Text(String(format: "%.2f%%", NSDecimalNumber(decimal: rate).doubleValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rendimento atteso")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("+" + annualReturn.currencyFormatted + "/anno")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hex: "#4CAF50"))
                    }
                    Spacer()
                    Text(String(format: "%.2f%%", NSDecimalNumber(decimal: rate).doubleValue))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(hex: "#4CAF50"))
                }
            }
        }
    }

    // MARK: - Savings Info

    @ViewBuilder
    private var savingsInfo: some View {
        if let progress = conto.savingsGoalProgress, let remaining = conto.savingsGoalRemaining {
            if compact {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: min(progress, 1.0))
                        .tint(progress >= 1.0 ? .green : .blue)
                        .frame(width: 80)
                    if remaining > 0 {
                        Text("Mancano " + remaining.currencyFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Obiettivo raggiunto!")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Obiettivo di risparmio")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(min(progress, 1.0) * 100))%")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(progress >= 1.0 ? .green : .blue)
                    }
                    ProgressView(value: min(progress, 1.0))
                        .tint(progress >= 1.0 ? .green : .blue)
                    if remaining > 0 {
                        Text("Mancano " + remaining.currencyFormatted + " all'obiettivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Obiettivo raggiunto!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func creditColor(for ratio: Double) -> Color {
        if ratio > 0.9 { return .red }
        if ratio > 0.7 { return .orange }
        return .green
    }
}
