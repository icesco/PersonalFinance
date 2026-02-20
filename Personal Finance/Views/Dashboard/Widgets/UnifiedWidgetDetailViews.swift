//
//  UnifiedWidgetDetailViews.swift
//  Personal Finance
//
//  Full-screen detail modals for unified dashboard widgets.
//

import SwiftUI
import Charts
import FinanceCore

// MARK: - Detail Type Enum

enum UnifiedWidgetDetail: String, Identifiable {
    case heatmap
    case spendingDistribution
    case balanceTrend
    case financialHealth
    case topExpenses

    var id: String { rawValue }
}

// MARK: - Heatmap Detail View

struct HeatmapDetailView: View {
    let dailyFlow: [Date: DailyFlow]
    let transactions: [FinanceTransaction]
    let referenceDate: Date

    @State private var selectedDay: Date?
    @Environment(\.dismiss) private var dismiss

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    private var calendar: Calendar { Calendar.current }

    private var startOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
    }

    private var monthTitle: String {
        Self.monthYearFormatter.string(from: startOfMonth).capitalized
    }

    private var monthIncome: Decimal {
        dailyFlow.values.reduce(Decimal(0)) { $0 + $1.income }
    }

    private var monthExpenses: Decimal {
        dailyFlow.values.reduce(Decimal(0)) { $0 + $1.expenses }
    }

    private var monthNet: Decimal { monthIncome - monthExpenses }

    private var transactionsForSelectedDay: [FinanceTransaction] {
        guard let day = selectedDay else { return [] }
        return transactions.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summarySection
                heatmapGrid

                if let day = selectedDay {
                    daySection(for: day)
                }
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Heatmap Flussi")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 12) {
            Text(monthTitle).font(.title3.weight(.semibold))

            HStack(spacing: 0) {
                statColumn(label: "Entrate", value: monthIncome, color: .green)
                statColumn(label: "Uscite", value: monthExpenses, color: .red)
                statColumn(label: "Netto", value: monthNet, color: monthNet >= 0 ? .green : .red)
            }
        }
        .unifiedCard()
    }

    private func statColumn(label: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.currencyFormatted)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heatmap Grid

    private var heatmapGrid: some View {
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let mondayOffset = (firstWeekday + 5) % 7
        let weekdayLabels = ["L", "M", "M", "G", "V", "S", "D"]

        let allFlows = dailyFlow.values
        let maxExpense = allFlows.map(\.expenses).max() ?? Decimal(1)
        let maxIncome = allFlows.map(\.income).max() ?? Decimal(1)

        let totalCells = mondayOffset + daysInMonth
        let rows = (totalCells + 6) / 7

        return VStack(alignment: .leading, spacing: 12) {
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayLabels[i])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let dayNumber = cellIndex - mondayOffset + 1

                            if dayNumber >= 1 && dayNumber <= daysInMonth {
                                let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: startOfMonth)!
                                let dayKey = calendar.startOfDay(for: date)
                                let flow = dailyFlow[dayKey]
                                let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                                dayCellView(
                                    dayNumber: dayNumber, date: date, flow: flow,
                                    maxExpense: maxExpense, maxIncome: maxIncome,
                                    isSelected: isSelected
                                )
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.clear)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(label: "Entrate", color: .green)
                legendDot(label: "Uscite", color: .red)
                legendDot(label: "Nessuna", color: Color(.tertiarySystemFill))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .unifiedCard()
    }

    private func dayCellView(
        dayNumber: Int, date: Date, flow: DailyFlow?,
        maxExpense: Decimal, maxIncome: Decimal, isSelected: Bool
    ) -> some View {
        let bgColor = heatmapCellColor(for: flow, maxExpense: maxExpense, maxIncome: maxIncome)
        let fgColor = heatmapTextColor(for: flow, maxExpense: maxExpense, maxIncome: maxIncome)

        return RoundedRectangle(cornerRadius: 6)
            .fill(bgColor)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 1) {
                    Text("\(dayNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(fgColor)

                    if let flow, flow.net != 0 {
                        Text(flow.net > 0 ? "+" : "")
                            .font(.system(size: 7))
                            .foregroundStyle(fgColor.opacity(0.8))
                    }
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDay = calendar.isDate(date, inSameDayAs: selectedDay ?? .distantPast) ? nil : date
                }
            }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color == Color(.tertiarySystemFill) ? color : color.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Day Transactions

    private func daySection(for day: Date) -> some View {
        let dayTransactions = transactionsForSelectedDay
        let dayFlow = dailyFlow[calendar.startOfDay(for: day)]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Self.dayFormatter.string(from: day).capitalized)
                    .font(.headline)
                Spacer()
                if let flow = dayFlow {
                    Text(flow.net >= 0 ? "+" : "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(flow.net >= 0 ? .green : .red)
                    + Text(flow.net.currencyFormatted)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(flow.net >= 0 ? .green : .red)
                }
            }

            if dayTransactions.isEmpty {
                Text("Nessuna transazione")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(dayTransactions, id: \.id) { tx in
                    HStack(spacing: 12) {
                        Image(systemName: tx.category?.icon ?? (tx.type == .income ? "arrow.down.circle" : "arrow.up.circle"))
                            .font(.body)
                            .foregroundStyle(tx.type == .income ? .green : .red)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.transactionDescription ?? tx.category?.name ?? "Transazione")
                                .font(.subheadline)
                                .lineLimit(1)
                            if let cat = tx.category?.name {
                                Text(cat)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text((tx.amount ?? Decimal(0)).currencyFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tx.type == .income ? .green : .red)
                    }

                    if tx.id != dayTransactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Color Helpers

    private func heatmapCellColor(for flow: DailyFlow?, maxExpense: Decimal, maxIncome: Decimal) -> Color {
        guard let flow else { return Color(.tertiarySystemFill) }
        let hasExpenses = flow.expenses > 0
        let hasIncome = flow.income > 0

        if hasIncome && hasExpenses {
            if flow.net >= 0 {
                let intensity = maxIncome > 0 ? flow.income.doubleValue / maxIncome.doubleValue : 0
                return Color.green.opacity(0.15 + intensity * 0.7)
            } else {
                let intensity = maxExpense > 0 ? flow.expenses.doubleValue / maxExpense.doubleValue : 0
                return Color.red.opacity(0.15 + intensity * 0.7)
            }
        } else if hasExpenses {
            let intensity = maxExpense > 0 ? flow.expenses.doubleValue / maxExpense.doubleValue : 0
            return Color.red.opacity(0.15 + intensity * 0.7)
        } else if hasIncome {
            let intensity = maxIncome > 0 ? flow.income.doubleValue / maxIncome.doubleValue : 0
            return Color.green.opacity(0.15 + intensity * 0.7)
        }
        return Color(.tertiarySystemFill)
    }

    private func heatmapTextColor(for flow: DailyFlow?, maxExpense: Decimal, maxIncome: Decimal) -> Color {
        guard let flow else { return .secondary }
        let dominant: (amount: Decimal, max: Decimal) = flow.net >= 0
            ? (flow.income, maxIncome) : (flow.expenses, maxExpense)
        let intensity = dominant.max > 0 ? dominant.amount.doubleValue / dominant.max.doubleValue : 0
        return intensity > 0.5 ? .white : .secondary
    }
}

// MARK: - Spending Distribution Detail View

struct SpendingDistributionDetailView: View {
    let categories: [SpendingCategory]
    @Environment(\.dismiss) private var dismiss

    private var totalSpending: Decimal {
        categories.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var maxCategoryAmount: Decimal {
        totalSpending > 0 ? totalSpending : Decimal(1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Total header
                VStack(spacing: 4) {
                    Text("Spese Totali").font(.caption).foregroundStyle(.secondary)
                    Text(totalSpending.currencyFormatted)
                        .font(.title.weight(.bold))
                    Text("\(categories.count) categorie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .unifiedCard()

                // Chart
                if !categories.isEmpty {
                    Chart(categories) { item in
                        SectorMark(
                            angle: .value("Importo", item.amount),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color(hex: item.color))
                        .cornerRadius(4)
                    }
                    .frame(height: 240)
                    .unifiedCard()
                }

                // Full category list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tutte le Categorie").font(.headline)

                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category: category, rank: index + 1)

                        if index < categories.count - 1 {
                            Divider()
                        }
                    }
                }
                .unifiedCard()
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Distribuzione Spese")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    private func categoryRow(category: SpendingCategory, rank: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundStyle(Color(hex: category.color))
                    .frame(width: 28)

                Text(category.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(category.amount.currencyFormatted)
                        .font(.subheadline.weight(.semibold))
                    Text(category.percentage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PercentageBar(
                fraction: maxCategoryAmount > 0
                    ? CGFloat(category.amount.doubleValue / maxCategoryAmount.doubleValue)
                    : 0,
                color: Color(hex: category.color),
                height: 6
            )
        }
    }
}

// MARK: - Balance Trend Detail View

struct BalanceTrendDetailView: View {
    let pastData: [BalanceDataPoint]
    let futureData: [BalanceDataPoint]
    let yDomain: ClosedRange<Decimal>
    let themeColor: Color

    @State private var selectedPoint: BalanceDataPoint?
    @Environment(\.dismiss) private var dismiss

    private var allData: [BalanceDataPoint] { pastData + futureData }

    private var periodHigh: Decimal {
        allData.map(\.balance).max() ?? Decimal(0)
    }

    private var periodLow: Decimal {
        allData.map(\.balance).min() ?? Decimal(0)
    }

    private var periodStart: Decimal {
        pastData.first?.balance ?? Decimal(0)
    }

    private var periodEnd: Decimal {
        pastData.last?.balance ?? Decimal(0)
    }

    private var periodChange: Decimal { periodEnd - periodStart }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                chartSection
                statsSection
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Andamento Saldo")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let point = selectedPoint {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.balance.currencyFormatted)
                            .font(.title3.weight(.bold))
                        Text(point.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            Chart {
                ForEach(pastData, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Passato")
                    )
                    .foregroundStyle(themeColor.gradient)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                ForEach(pastData, id: \.date) { item in
                    AreaMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance),
                        series: .value("Area", "Passato")
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeColor.opacity(0.2), themeColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                ForEach(futureData, id: \.date) { item in
                    LineMark(
                        x: .value("Data", item.date, unit: .day),
                        y: .value("Saldo", item.balance),
                        series: .value("Serie", "Futuro")
                    )
                    .foregroundStyle(themeColor.opacity(0.4))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                }

                if let point = selectedPoint {
                    RuleMark(x: .value("Selected", point.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    PointMark(
                        x: .value("Data", point.date, unit: .day),
                        y: .value("Saldo", point.balance)
                    )
                    .foregroundStyle(themeColor)
                    .symbolSize(60)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let decimal = value.as(Decimal.self) {
                            Text(BalanceCalculator.formatCompactCurrency(decimal))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 300)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let plotFrame = geo[proxy.plotFrame!]
                                    let x = value.location.x - plotFrame.origin.x
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    let closest = allData.min { a, b in
                                        abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
                                    }
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedPoint = closest
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedPoint = nil
                                    }
                                }
                        )
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 12) {
            Text("Statistiche Periodo").font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(label: "Saldo Iniziale", value: periodStart.currencyFormatted, icon: "arrow.right", color: .secondary)
                statCard(label: "Saldo Attuale", value: periodEnd.currencyFormatted, icon: "target", color: themeColor)
                statCard(label: "Massimo", value: periodHigh.currencyFormatted, icon: "arrow.up", color: .green)
                statCard(label: "Minimo", value: periodLow.currencyFormatted, icon: "arrow.down", color: .red)
            }

            HStack {
                Text("Variazione Periodo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((periodChange >= 0 ? "+" : "") + periodChange.currencyFormatted)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(periodChange >= 0 ? .green : .red)
            }
            .padding(.top, 4)
        }
        .unifiedCard()
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Financial Health Detail View

struct FinancialHealthDetailView: View {
    let healthScore: FinancialHealthResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreSection
                componentsSection
                recommendationsSection
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Financial Health")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }

    // MARK: - Score

    private var scoreSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: CGFloat(healthScore.score) / 100)
                    .stroke(healthScore.color.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: healthScore.score)

                VStack(spacing: 4) {
                    Text("\(Int(healthScore.score))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("/ 100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(healthScore.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(healthScore.color)
                }
            }
            .frame(width: 180, height: 180)
        }
        .frame(maxWidth: .infinity)
        .unifiedCard()
    }

    // MARK: - Components

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Componenti del Punteggio").font(.headline)

            componentCard(
                icon: "banknote",
                label: "Risparmio",
                score: healthScore.savingsPoints,
                maxScore: 30,
                color: .green,
                description: "Misura quanto riesci a risparmiare rispetto alle entrate. Un tasso di risparmio superiore al 20% contribuisce al punteggio massimo."
            )

            componentCard(
                icon: "chart.pie",
                label: "Budget",
                score: healthScore.budgetPoints,
                maxScore: 25,
                color: .blue,
                description: "Valuta quanto rispetti i budget impostati. Rimanere entro i limiti di spesa per ogni categoria migliora questo punteggio."
            )

            componentCard(
                icon: "arrow.down.circle",
                label: "Stabilita\u{0300} Entrate",
                score: healthScore.incomePoints,
                maxScore: 20,
                color: .purple,
                description: "Misura la costanza delle entrate nel tempo. Entrate regolari e prevedibili indicano maggiore stabilita\u{0300} finanziaria."
            )

            componentCard(
                icon: "arrow.up.circle",
                label: "Trend Spese",
                score: healthScore.spendingPoints,
                maxScore: 25,
                color: .orange,
                description: "Valuta l'andamento delle spese negli ultimi mesi. Spese stabili o in diminuzione contribuiscono positivamente."
            )
        }
        .unifiedCard()
    }

    private func componentCard(
        icon: String, label: String, score: Double,
        maxScore: Double, color: Color, description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 28)

                Text(label)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text("\(Int(score))/\(Int(maxScore))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }

            PercentageBar(
                fraction: maxScore > 0 ? score / maxScore : 0,
                color: color,
                height: 10,
                cornerRadius: 5
            )

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggerimenti").font(.headline)

            ForEach(recommendations, id: \.self) { rec in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                    Text(rec)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .unifiedCard()
    }

    private var recommendations: [String] {
        var recs: [String] = []

        if healthScore.savingsPoints < 15 {
            recs.append("Prova ad aumentare il tasso di risparmio. Anche piccoli incrementi mensili fanno la differenza nel lungo periodo.")
        }
        if healthScore.budgetPoints < 12 {
            recs.append("Rivedi i tuoi budget e cerca di rispettarli. Considera di impostare limiti piu\u{0300} realistici per le categorie dove sfori spesso.")
        }
        if healthScore.incomePoints < 10 {
            recs.append("Le entrate sono irregolari. Cerca di diversificare le fonti di reddito o creare un fondo di emergenza.")
        }
        if healthScore.spendingPoints < 12 {
            recs.append("Le spese sono in aumento. Identifica le categorie con la crescita maggiore e valuta dove tagliare.")
        }

        if recs.isEmpty {
            recs.append("Ottimo lavoro! Continua cosi\u{0300} per mantenere una salute finanziaria eccellente.")
        }

        return recs
    }
}

// MARK: - Top Expenses Detail View

struct TopExpensesDetailView: View {
    let expenses: [FinanceTransaction]
    var onTapTransaction: ((FinanceTransaction) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var totalAmount: Decimal {
        expenses.reduce(Decimal(0)) { $0 + ($1.amount ?? Decimal(0)) }
    }

    private var groupedByCategory: [(name: String, color: String, icon: String, amount: Decimal, count: Int)] {
        var groups: [String: (color: String, icon: String, amount: Decimal, count: Int)] = [:]
        for tx in expenses {
            let name = tx.category?.name ?? "Altro"
            let color = tx.category?.color ?? "#9E9E9E"
            let icon = tx.category?.icon ?? "questionmark.circle"
            let amount = tx.amount ?? Decimal(0)
            if let existing = groups[name] {
                groups[name] = (color, icon, existing.amount + amount, existing.count + 1)
            } else {
                groups[name] = (color, icon, amount, 1)
            }
        }
        return groups.map { (name: $0.key, color: $0.value.color, icon: $0.value.icon, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary
                VStack(spacing: 4) {
                    Text("Spese Totali").font(.caption).foregroundStyle(.secondary)
                    Text(totalAmount.currencyFormatted)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.red)
                    Text("\(expenses.count) transazioni")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .unifiedCard()

                // By category summary
                if !groupedByCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Per Categoria").font(.headline)

                        ForEach(groupedByCategory, id: \.name) { group in
                            HStack(spacing: 10) {
                                Image(systemName: group.icon)
                                    .font(.body)
                                    .foregroundStyle(Color(hex: group.color))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(.subheadline.weight(.medium))
                                    Text("\(group.count) transazioni").font(.caption).foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(group.amount.currencyFormatted)
                                    .font(.subheadline.weight(.semibold))
                            }

                            if group.name != groupedByCategory.last?.name {
                                Divider()
                            }
                        }
                    }
                    .unifiedCard()
                }

                // Full list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tutte le Spese").font(.headline)

                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, tx in
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)

                            Image(systemName: tx.category?.icon ?? "arrow.up.circle")
                                .font(.body)
                                .foregroundStyle(Color(hex: tx.category?.color ?? "#FF5252"))
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.transactionDescription ?? tx.category?.name ?? "Spesa")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(tx.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text((tx.amount ?? Decimal(0)).currencyFormatted)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onTapTransaction?(tx) }

                        if index < expenses.count - 1 {
                            Divider()
                        }
                    }
                }
                .unifiedCard()
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Top Spese")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
    }
}
