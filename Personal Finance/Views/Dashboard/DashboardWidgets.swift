import SwiftUI
import Charts
import FinanceCore

// MARK: - Balance Distribution Widget

struct BalanceDistributionWidget: View {
    let income: Decimal
    let expenses: Decimal
    let periodAvgIncome: Decimal
    let periodAvgExpenses: Decimal
    let periodLabel: String
    let theme: AppTheme

    private var total: Decimal { income + expenses }
    private var incomePercent: Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: income / total * 100).doubleValue
    }
    private var expensePercent: Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: expenses / total * 100).doubleValue
    }

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(theme.color)
                    Text("Distribuzione")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                if total == 0 {
                    emptyState
                } else {
                    VStack(spacing: 8) {
                        // Income bar
                        DistributionBar(
                            label: "Entrate",
                            amount: income,
                            percent: incomePercent,
                            color: Color(hex: "#4CAF50"),
                            total: total,
                            periodAvg: periodAvgIncome
                        )

                        // Expense bar
                        DistributionBar(
                            label: "Uscite",
                            amount: expenses,
                            percent: expensePercent,
                            color: Color(hex: "#FF5252"),
                            total: total,
                            periodAvg: periodAvgExpenses
                        )
                    }

                    // Period reference
                    if periodAvgExpenses > 0 {
                        Text("vs media \(periodLabel)")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .padding(14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.3))
            Text("Nessun dato")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct DistributionBar: View {
    let label: String
    let amount: Decimal
    let percent: Double
    let color: Color
    let total: Decimal
    var periodAvg: Decimal = 0

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: amount / total).doubleValue)
    }

    private var avgFraction: CGFloat {
        guard total > 0, periodAvg > 0 else { return 0 }
        // Clamp to 1.0 so the marker stays within the bar
        return min(1.0, CGFloat(NSDecimalNumber(decimal: periodAvg / total).doubleValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * fraction), height: 6)

                    // Period average marker
                    if periodAvg > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * avgFraction - 1)
                    }
                }
            }
            .frame(height: 10)

            HStack {
                Text(amount.currencyFormatted)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                if periodAvg > 0 {
                    Spacer()
                    Text("media " + periodAvg.currencyFormatted)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}

// MARK: - Savings Rate Widget

struct SavingsRateWidget: View {
    let income: Decimal
    let expenses: Decimal
    let periodAvgIncome: Decimal
    let periodAvgExpenses: Decimal
    let periodLabel: String
    let theme: AppTheme

    private var savingsRate: Double {
        guard income > 0 else { return 0 }
        let rate = (income - expenses) / income * 100
        return NSDecimalNumber(decimal: rate).doubleValue
    }

    private var periodSavingsRate: Double {
        guard periodAvgIncome > 0 else { return 0 }
        let rate = (periodAvgIncome - periodAvgExpenses) / periodAvgIncome * 100
        return NSDecimalNumber(decimal: rate).doubleValue
    }

    private var isValid: Bool { income > 0 }

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundStyle(theme.color)
                    Text("Risparmio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }

                if !isValid {
                    VStack(spacing: 4) {
                        Text("N/D")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Nessuna entrata")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    // Gauge ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 6)

                        Circle()
                            .trim(from: 0, to: CGFloat(max(0, min(savingsRate, 100)) / 100))
                            .stroke(
                                savingsRate >= 0 ? theme.color : Color(hex: "#FF5252"),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 0) {
                            Text(String(format: "%.0f%%", savingsRate))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                            Text("del mese")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 80, height: 80)

                    // Period comparison
                    if periodAvgIncome > 0 {
                        HStack(spacing: 4) {
                            Text("Media \(periodLabel):")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(String(format: "%.0f%%", periodSavingsRate))
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    } else {
                        Text((income - expenses).currencyFormatted)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Spending Trend Widget

struct SpendingTrendWidget: View {
    let currentMonthExpenses: Decimal
    let averageExpenses: Decimal
    let trend: [(month: String, expenses: Decimal)]
    let periodLabel: String
    let theme: AppTheme

    private var trendMessage: String {
        guard averageExpenses > 0 else {
            return "Primo mese di utilizzo"
        }
        if currentMonthExpenses < averageExpenses {
            return "Hai speso meno del solito"
        } else if currentMonthExpenses > averageExpenses {
            return "Hai speso piu' del solito"
        }
        return "Spesa nella media"
    }

    private var trendIcon: String {
        guard averageExpenses > 0 else { return "chart.line.flattrend.xyaxis" }
        if currentMonthExpenses < averageExpenses { return "arrow.down.right" }
        if currentMonthExpenses > averageExpenses { return "arrow.up.right" }
        return "equal"
    }

    private var trendColor: Color {
        guard averageExpenses > 0 else { return .white.opacity(0.5) }
        if currentMonthExpenses < averageExpenses { return Color(hex: "#4CAF50") }
        if currentMonthExpenses > averageExpenses { return Color(hex: "#FF5252") }
        return .white.opacity(0.7)
    }

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(theme.color)
                    Text("Andamento spese")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()

                    // Trend indicator
                    HStack(spacing: 3) {
                        Image(systemName: trendIcon)
                            .font(.caption2)
                        Text(trendMessage)
                            .font(.caption2)
                    }
                    .foregroundStyle(trendColor)
                }

                if trend.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 16) {
                        // Current month value
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Questo mese")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(currentMonthExpenses.currencyFormatted)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(trendColor)
                        }

                        // Average value
                        if averageExpenses > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Media \(periodLabel)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(averageExpenses.currencyFormatted)
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }

                        Spacer()
                    }

                    // Mini chart
                    miniChart
                        .frame(height: 60)
                }
            }
            .padding(14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.3))
            Text("Nessun dato")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var miniChart: some View {
        Chart {
            // Expense bars for each month
            ForEach(Array(trend.enumerated()), id: \.offset) { index, item in
                BarMark(
                    x: .value("Mese", item.month),
                    y: .value("Spese", item.expenses)
                )
                .foregroundStyle(
                    index == trend.count - 1
                        ? trendColor.opacity(0.8)
                        : Color.white.opacity(0.2)
                )
                .cornerRadius(3)
            }

            // Average line
            if averageExpenses > 0 {
                RuleMark(y: .value("Media", averageExpenses))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 8))
            }
        }
        .chartYAxis(.hidden)
    }
}
