import SwiftUI
import Charts
import FinanceCore

// MARK: - Distribution Detail View

struct DistributionDetailView: View {
    let viewModel: DashboardViewModel
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss

    private var periodLabel: String { viewModel.selectedPeriod.displayName }
    private var trend: [(month: String, income: Decimal, expenses: Decimal)] { viewModel.monthlyExpensesTrend }
    private var net: Decimal { viewModel.monthlyIncome - viewModel.monthlyExpenses }

    private var incomeDeltaPercent: Double {
        guard viewModel.periodAverageIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: (viewModel.monthlyIncome - viewModel.periodAverageIncome) / viewModel.periodAverageIncome * 100).doubleValue
    }

    private var expensesDeltaPercent: Double {
        guard viewModel.periodAverageExpenses > 0 else { return 0 }
        return NSDecimalNumber(decimal: (viewModel.monthlyExpenses - viewModel.periodAverageExpenses) / viewModel.periodAverageExpenses * 100).doubleValue
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section 1: Monthly summary
                monthlySummarySection

                // Section 2: Comparison with average
                if viewModel.periodAverageIncome > 0 || viewModel.periodAverageExpenses > 0 {
                    comparisonSection
                }

                // Section 3: Monthly trend (grouped bars)
                if trend.count > 1 {
                    groupedBarChartSection
                }

                // Section 4: Net balance per month
                if trend.count > 1 {
                    netBalanceChartSection
                }
            }
            .padding()
        }
        .navigationTitle("Distribuzione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var monthlySummarySection: some View {
        VStack(spacing: 12) {
            sectionHeader("Riepilogo del mese", icon: "chart.bar.fill")

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Entrate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.monthlyIncome.currencyFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color(hex: "#4CAF50"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Uscite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.monthlyExpenses.currencyFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color(hex: "#FF5252"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Netto")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(net.currencyFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(net >= 0 ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                }
                .frame(maxWidth: .infinity)
            }

            // Proportional bar
            if viewModel.monthlyIncome + viewModel.monthlyExpenses > 0 {
                let total = viewModel.monthlyIncome + viewModel.monthlyExpenses
                let incomeFraction = CGFloat(NSDecimalNumber(decimal: viewModel.monthlyIncome / total).doubleValue)

                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#4CAF50"))
                            .frame(width: max(4, geo.size.width * incomeFraction))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#FF5252"))
                            .frame(width: max(4, geo.size.width * (1 - incomeFraction)))
                    }
                }
                .frame(height: 8)
            }
        }
        .cardStyle()
    }

    private var comparisonSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Confronto con la media", icon: "arrow.left.arrow.right")

            VStack(spacing: 10) {
                comparisonRow(
                    label: "Entrate",
                    current: viewModel.monthlyIncome,
                    average: viewModel.periodAverageIncome,
                    deltaPercent: incomeDeltaPercent,
                    positiveIsGood: true
                )

                Divider()

                comparisonRow(
                    label: "Uscite",
                    current: viewModel.monthlyExpenses,
                    average: viewModel.periodAverageExpenses,
                    deltaPercent: expensesDeltaPercent,
                    positiveIsGood: false
                )
            }

            Text("Media calcolata su \(periodLabel)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
    }

    private var groupedBarChartSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Andamento mensile", icon: "chart.bar.xaxis")

            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Mese", item.month),
                        y: .value("Importo", item.income)
                    )
                    .foregroundStyle(Color(hex: "#4CAF50").opacity(0.8))
                    .position(by: .value("Tipo", "Entrate"))

                    BarMark(
                        x: .value("Mese", item.month),
                        y: .value("Importo", item.expenses)
                    )
                    .foregroundStyle(Color(hex: "#FF5252").opacity(0.8))
                    .position(by: .value("Tipo", "Uscite"))
                }
            }
            .chartForegroundStyleScale([
                "Entrate": Color(hex: "#4CAF50").opacity(0.8),
                "Uscite": Color(hex: "#FF5252").opacity(0.8)
            ])
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 200)
        }
        .cardStyle()
    }

    private var netBalanceChartSection: some View {
        let netData = viewModel.monthlyNetSavings

        return VStack(spacing: 12) {
            sectionHeader("Bilancio netto", icon: "plusminus")

            Chart {
                ForEach(Array(netData.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Mese", item.month),
                        y: .value("Netto", item.net)
                    )
                    .foregroundStyle(item.net >= 0 ? Color(hex: "#4CAF50").opacity(0.8) : Color(hex: "#FF5252").opacity(0.8))
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func comparisonRow(label: String, current: Decimal, average: Decimal, deltaPercent: Double, positiveIsGood: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(current.currencyFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("vs \(average.currencyFormatted)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            deltaTag(percent: deltaPercent, positiveIsGood: positiveIsGood)
        }
    }
}

// MARK: - Savings Rate Detail View

struct SavingsRateDetailView: View {
    let viewModel: DashboardViewModel
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss

    private var periodLabel: String { viewModel.selectedPeriod.displayName }

    private var currentRate: Double {
        guard viewModel.monthlyIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: (viewModel.monthlyIncome - viewModel.monthlyExpenses) / viewModel.monthlyIncome * 100).doubleValue
    }

    private var savedAmount: Decimal {
        viewModel.monthlyIncome - viewModel.monthlyExpenses
    }

    private var periodAvgRate: Double {
        guard viewModel.periodAverageIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: (viewModel.periodAverageIncome - viewModel.periodAverageExpenses) / viewModel.periodAverageIncome * 100).doubleValue
    }

    private var hasIncome: Bool { viewModel.monthlyIncome > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section 1: Current rate gauge
                currentRateSection

                // Section 2: What it means
                explanationSection

                // Section 3: Comparison with average
                if viewModel.periodAverageIncome > 0 {
                    comparisonSection
                }

                // Section 4: History line chart
                if viewModel.monthlySavingsRates.count > 1 {
                    historyChartSection
                }
            }
            .padding()
        }
        .navigationTitle("Tasso di risparmio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var currentRateSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Tasso attuale", icon: "percent")

            if !hasIncome {
                VStack(spacing: 8) {
                    Text("N/D")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.tertiary)
                    Text("Nessuna entrata registrata questo mese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                ZStack {
                    Circle()
                        .stroke(.primary.opacity(0.1), lineWidth: 10)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(currentRate, 100)) / 100))
                        .stroke(
                            gaugeColor(for: currentRate),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // 20% reference mark
                    Circle()
                        .trim(from: 0.198, to: 0.202)
                        .stroke(.primary.opacity(0.4), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", currentRate))
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        Text(savedAmount.currencyFormatted)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("risparmiato")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 150, height: 150)
                .padding(.vertical, 8)
            }
        }
        .cardStyle()
    }

    private var explanationSection: some View {
        let (message, icon, color) = explanationContent(for: currentRate)

        return VStack(spacing: 12) {
            sectionHeader("Cosa significa", icon: "lightbulb.fill")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var comparisonSection: some View {
        let diff = currentRate - periodAvgRate

        return VStack(spacing: 12) {
            sectionHeader("Confronto con la media", icon: "arrow.left.arrow.right")

            HStack {
                VStack(spacing: 4) {
                    Text("Questo mese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", currentRate))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(gaugeColor(for: currentRate))
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    Text("Media \(periodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", periodAvgRate))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if hasIncome {
                HStack(spacing: 4) {
                    Image(systemName: diff >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(diff >= 0 ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                    Text(String(format: "%+.1f punti percentuali", diff))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(diff >= 0 ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                }
            }
        }
        .cardStyle()
    }

    private var historyChartSection: some View {
        let rates = viewModel.monthlySavingsRates

        return VStack(spacing: 12) {
            sectionHeader("Storico", icon: "chart.xyaxis.line")

            Chart {
                ForEach(Array(rates.enumerated()), id: \.offset) { _, item in
                    LineMark(
                        x: .value("Mese", item.month),
                        y: .value("Tasso", item.rate)
                    )
                    .foregroundStyle(theme.color)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Mese", item.month),
                        y: .value("Tasso", item.rate)
                    )
                    .foregroundStyle(theme.color)
                    .symbolSize(20)
                }

                // 20% reference line
                RuleMark(y: .value("Obiettivo", 20))
                    .foregroundStyle(Color(hex: "#4CAF50").opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("20%")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#4CAF50").opacity(0.7))
                    }

                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func gaugeColor(for rate: Double) -> Color {
        if rate >= 20 { return Color(hex: "#4CAF50") }
        if rate >= 10 { return theme.color }
        if rate >= 0 { return .orange }
        return Color(hex: "#FF5252")
    }

    private func explanationContent(for rate: Double) -> (String, String, Color) {
        if !hasIncome {
            return ("Nessuna entrata registrata per questo mese. Il tasso di risparmio verra' calcolato quando saranno presenti entrate.", "questionmark.circle", .secondary)
        }
        if rate >= 20 {
            return ("Stai risparmiando piu' del 20% delle entrate. E' un ottimo risultato che ti permette di costruire un solido fondo di sicurezza.", "checkmark.seal.fill", Color(hex: "#4CAF50"))
        }
        if rate >= 10 {
            return ("Risparmi tra il 10% e il 20% delle entrate. Un buon ritmo, ma c'e' margine per migliorare e raggiungere l'obiettivo del 20%.", "hand.thumbsup.fill", theme.color)
        }
        if rate >= 0 {
            return ("Il tasso di risparmio e' sotto il 10%. Prova a identificare le spese non essenziali per aumentare il margine di risparmio.", "exclamationmark.triangle.fill", .orange)
        }
        return ("Stai spendendo piu' di quanto guadagni. E' importante rivedere le uscite per riportare il bilancio in positivo.", "exclamationmark.octagon.fill", Color(hex: "#FF5252"))
    }
}

// MARK: - Spending Trend Detail View

struct SpendingTrendDetailView: View {
    let viewModel: DashboardViewModel
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss

    private var periodLabel: String { viewModel.selectedPeriod.displayName }
    private var trend: [(month: String, income: Decimal, expenses: Decimal)] { viewModel.monthlyExpensesTrend }
    private var avg: Decimal { viewModel.averageMonthlyExpenses }

    private var deltaFromAvg: Decimal {
        viewModel.monthlyExpenses - avg
    }

    private var deltaPercent: Double {
        guard avg > 0 else { return 0 }
        return NSDecimalNumber(decimal: deltaFromAvg / avg * 100).doubleValue
    }

    private var trendColor: Color {
        guard avg > 0 else { return .secondary }
        if viewModel.monthlyExpenses < avg { return Color(hex: "#4CAF50") }
        if viewModel.monthlyExpenses > avg { return Color(hex: "#FF5252") }
        return .secondary
    }

    // Statistics
    private var mostExpensiveMonth: (month: String, expenses: Decimal)? {
        trend.max(by: { $0.expenses < $1.expenses }).map { ($0.month, $0.expenses) }
    }

    private var leastExpensiveMonth: (month: String, expenses: Decimal)? {
        trend.filter { $0.expenses > 0 }.min(by: { $0.expenses < $1.expenses }).map { ($0.month, $0.expenses) }
    }

    private var totalExpenses: Decimal {
        trend.reduce(Decimal(0)) { $0 + $1.expenses }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section 1: Current month expenses
                currentMonthSection

                // Section 2: Expanded bar chart
                if trend.count > 1 {
                    expandedChartSection
                }

                // Section 3: Month by month list
                if trend.count > 1 {
                    monthByMonthSection
                }

                // Section 4: Statistics
                if !trend.isEmpty {
                    statisticsSection
                }
            }
            .padding()
        }
        .navigationTitle("Andamento spese")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var currentMonthSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Spese del mese", icon: "creditcard.fill")

            Text(viewModel.monthlyExpenses.currencyFormatted)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(trendColor)

            if avg > 0 {
                HStack(spacing: 6) {
                    Image(systemName: deltaFromAvg > 0 ? "arrow.up.right" : deltaFromAvg < 0 ? "arrow.down.right" : "equal")
                        .font(.caption)
                    Text(String(format: "%+.1f%%", deltaPercent))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("(\(deltaFromAvg.currencyFormatted))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("dalla media")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(trendColor)
            } else {
                Text("Primo mese di utilizzo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var expandedChartSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Andamento mensile", icon: "chart.bar.fill")

            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { index, item in
                    BarMark(
                        x: .value("Mese", item.month),
                        y: .value("Spese", item.expenses)
                    )
                    .foregroundStyle(
                        index == trend.count - 1
                            ? trendColor.opacity(0.8)
                            : Color.primary.opacity(0.25)
                    )
                    .cornerRadius(4)
                }

                if avg > 0 {
                    RuleMark(y: .value("Media", avg))
                        .foregroundStyle(theme.color.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Media: \(avg.currencyFormatted)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 250)
        }
        .cardStyle()
    }

    private var monthByMonthSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Mese per mese", icon: "list.bullet")

            VStack(spacing: 0) {
                ForEach(Array(trend.enumerated().reversed()), id: \.offset) { index, item in
                    let monthDelta = avg > 0 ? item.expenses - avg : Decimal(0)
                    let monthDeltaPercent = avg > 0 ? NSDecimalNumber(decimal: monthDelta / avg * 100).doubleValue : 0.0

                    HStack {
                        Text(item.month.capitalized)
                            .font(.subheadline.weight(.medium))
                            .frame(width: 40, alignment: .leading)

                        Text(item.expenses.currencyFormatted)
                            .font(.subheadline.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        if avg > 0 {
                            deltaTag(percent: monthDeltaPercent, positiveIsGood: false)
                                .frame(width: 80, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 8)

                    if index > 0 {
                        Divider()
                    }
                }
            }
        }
        .cardStyle()
    }

    private var statisticsSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Statistiche", icon: "chart.pie.fill")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let most = mostExpensiveMonth {
                    statCard(title: "Mese piu' costoso", value: most.expenses.currencyFormatted, subtitle: most.month.capitalized, color: Color(hex: "#FF5252"))
                }
                if let least = leastExpensiveMonth {
                    statCard(title: "Mese meno costoso", value: least.expenses.currencyFormatted, subtitle: least.month.capitalized, color: Color(hex: "#4CAF50"))
                }
                statCard(title: "Spesa totale", value: totalExpenses.currencyFormatted, subtitle: periodLabel, color: theme.color)
                if avg > 0 {
                    statCard(title: "Media mensile", value: avg.currencyFormatted, subtitle: periodLabel, color: .secondary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func statCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Shared Helpers

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    func deltaTag(percent: Double, positiveIsGood: Bool) -> some View {
        let isPositive = percent >= 0
        let isGood = positiveIsGood ? isPositive : !isPositive
        let color = abs(percent) < 1 ? Color.secondary : (isGood ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))

        return Text(String(format: "%+.0f%%", percent))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
