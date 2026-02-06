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
    var onTap: (() -> Void)? = nil

    // Use current month if available, otherwise fall back to period averages
    private var hasCurrentMonth: Bool { income + expenses > 0 }
    private var displayIncome: Decimal { hasCurrentMonth ? income : periodAvgIncome }
    private var displayExpenses: Decimal { hasCurrentMonth ? expenses : periodAvgExpenses }
    private var displayTotal: Decimal { displayIncome + displayExpenses }

    private var incomePercent: Double {
        guard displayTotal > 0 else { return 0 }
        return NSDecimalNumber(decimal: displayIncome / displayTotal * 100).doubleValue
    }
    private var expensePercent: Double {
        guard displayTotal > 0 else { return 0 }
        return NSDecimalNumber(decimal: displayExpenses / displayTotal * 100).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(theme.color)
                Text("Distribuzione")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if displayTotal == 0 {
                emptyState
            } else {
                VStack(spacing: 8) {
                    DistributionBar(
                        label: "Entrate",
                        amount: displayIncome,
                        percent: incomePercent,
                        color: Color(hex: "#4CAF50"),
                        total: displayTotal,
                        periodAvg: hasCurrentMonth ? periodAvgIncome : 0
                    )

                    DistributionBar(
                        label: "Uscite",
                        amount: displayExpenses,
                        percent: expensePercent,
                        color: Color(hex: "#FF5252"),
                        total: displayTotal,
                        periodAvg: hasCurrentMonth ? periodAvgExpenses : 0
                    )
                }

                // Context label
                Text(hasCurrentMonth ? "Questo mese vs media \(periodLabel)" : "Media \(periodLabel)")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .onTapGesture { onTap?() }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Nessun dato")
                .font(.caption2)
                .foregroundStyle(.quaternary)
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .frame(height: 6)

                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * fraction), height: 6)

                    // Period average marker
                    if periodAvg > 0 {
                        Rectangle()
                            .fill(.primary.opacity(0.6))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * avgFraction - 1)
                    }
                }
            }
            .frame(height: 10)

            HStack {
                Text(amount.currencyFormatted)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if periodAvg > 0 {
                    Spacer()
                    Text("media " + periodAvg.currencyFormatted)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
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
    var onTap: (() -> Void)? = nil

    // Use current month if it has income, otherwise fall back to period averages
    private var hasCurrentMonth: Bool { income > 0 }
    private var displayIncome: Decimal { hasCurrentMonth ? income : periodAvgIncome }
    private var displayExpenses: Decimal { hasCurrentMonth ? expenses : periodAvgExpenses }

    private var displayRate: Double {
        guard displayIncome > 0 else { return 0 }
        let rate = (displayIncome - displayExpenses) / displayIncome * 100
        return NSDecimalNumber(decimal: rate).doubleValue
    }

    private var periodSavingsRate: Double {
        guard periodAvgIncome > 0 else { return 0 }
        let rate = (periodAvgIncome - periodAvgExpenses) / periodAvgIncome * 100
        return NSDecimalNumber(decimal: rate).doubleValue
    }

    private var hasData: Bool { displayIncome > 0 }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "percent")
                    .font(.caption)
                    .foregroundStyle(theme.color)
                Text("Risparmio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if !hasData {
                VStack(spacing: 4) {
                    Text("N/D")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text("Nessun dato")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } else {
                // Gauge ring
                ZStack {
                    Circle()
                        .stroke(.primary.opacity(0.1), lineWidth: 6)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(displayRate, 100)) / 100))
                        .stroke(
                            displayRate >= 0 ? theme.color : Color(hex: "#FF5252"),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", displayRate))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(hasCurrentMonth ? "del mese" : "media")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                // Context: show period comparison if current month, or period label if fallback
                if hasCurrentMonth, periodAvgIncome > 0 {
                    HStack(spacing: 4) {
                        Text("Media \(periodLabel):")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(String(format: "%.0f%%", periodSavingsRate))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(periodLabel)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .onTapGesture { onTap?() }
    }
}

// MARK: - Spending Trend Widget

struct SpendingTrendWidget: View {
    let currentMonthExpenses: Decimal
    let averageExpenses: Decimal
    let trend: [(month: String, income: Decimal, expenses: Decimal)]
    let periodLabel: String
    let theme: AppTheme
    var onTap: (() -> Void)? = nil

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
        guard averageExpenses > 0 else { return .secondary }
        if currentMonthExpenses < averageExpenses { return Color(hex: "#4CAF50") }
        if currentMonthExpenses > averageExpenses { return Color(hex: "#FF5252") }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(theme.color)
                Text("Andamento spese")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                        Text(currentMonthExpenses.currencyFormatted)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(trendColor)
                    }

                    // Average value
                    if averageExpenses > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media \(periodLabel)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(averageExpenses.currencyFormatted)
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
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
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .onTapGesture { onTap?() }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Nessun dato")
                .font(.caption2)
                .foregroundStyle(.quaternary)
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
                        : Color.primary.opacity(0.2)
                )
                .cornerRadius(3)
            }

            // Average line
            if averageExpenses > 0 {
                RuleMark(y: .value("Media", averageExpenses))
                    .foregroundStyle(.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.secondary)
                    .font(.system(size: 8))
            }
        }
        .chartYAxis(.hidden)
    }
}
