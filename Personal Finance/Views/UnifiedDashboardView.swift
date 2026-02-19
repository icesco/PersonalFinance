//
//  UnifiedDashboardView.swift
//  Personal Finance
//
//  Unified dashboard combining clarity of Classic with visual appeal of Crypto.
//  Scrollable single-page layout with system cards on a subtle accent gradient.
//

import SwiftUI
import SwiftData
import Charts
import FinanceCore

struct UnifiedDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppStateManager.self) private var appState

    @Query private var allAccounts: [Account]

    @State private var viewModel = DashboardViewModel()
    @State private var layoutManager = DashboardLayoutManager()
    @State private var spendingByCategory: [SpendingCategory] = []
    @State private var topExpenses: [FinanceTransaction] = []
    @State private var budgetSnapshots: [BudgetSnapshot] = []
    @State private var upcomingRecurring: [(transaction: FinanceTransaction, nextDate: Date)] = []
    @State private var dailyExpenses: [Date: Decimal] = [:]
    @State private var healthScore: FinancialHealthResult = .empty
    @State private var spendingAnomalies: [SpendingAnomaly] = []
    @State private var categoryTrends: [CategoryTrendData] = []

    @State private var transactionToDetail: FinanceTransaction?
    @State private var transactionToEdit: FinanceTransaction?
    @State private var showingCustomization = false

    private var theme: AppTheme { appState.themeManager.currentTheme }

    private var experienceLevel: UserExperienceLevel {
        appState.experienceLevelManager.currentLevel
    }

    // MARK: - Accounts / Conti Logic

    private var activeAccounts: [Account] {
        var seen = Set<UUID>()
        return allAccounts.filter { $0.isActive == true }.filter { account in
            guard !seen.contains(account.id) else { return false }
            seen.insert(account.id)
            return true
        }
    }

    private var displayedAccounts: [Account] {
        if appState.showAllAccounts {
            return activeAccounts
        } else if let account = appState.selectedAccount {
            return [account]
        }
        return []
    }

    private var allDisplayedConti: [Conto] {
        if !appState.showAllConti, let selectedConto = appState.selectedConto {
            return [selectedConto]
        }
        var seen = Set<UUID>()
        return displayedAccounts.flatMap { $0.activeConti }.filter { conto in
            guard !seen.contains(conto.id) else { return false }
            seen.insert(conto.id)
            return true
        }
    }

    private var totalBalance: Decimal {
        allDisplayedConti.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var absoluteChange: Decimal {
        viewModel.absoluteChange(currentTotal: totalBalance)
    }

    private var percentageChange: Double {
        viewModel.percentageChange(currentTotal: totalBalance)
    }

    private var isPositiveChange: Bool { absoluteChange >= 0 }

    private var monthlySavings: Decimal { viewModel.monthlyIncome - viewModel.monthlyExpenses }

    private var displayName: String {
        if appState.showAllAccounts { return "Tutti i Libri" }
        if let libro = appState.selectedAccount {
            if appState.showAllConti { return libro.name ?? "Libro" }
            else if let conto = appState.selectedConto { return conto.name ?? "Account" }
        }
        return "Libro"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Pinned: always visible, full width
                    balanceHeroSection
                    quickActionsSection

                    // Dynamic: user-customizable order and visibility
                    if horizontalSizeClass == .regular {
                        StaggeredGrid(columns: 2, horizontalSpacing: 16, verticalSpacing: 16) {
                            ForEach(layoutManager.visibleSections) { section in
                                sectionView(for: section)
                            }
                        }
                    } else {
                        ForEach(layoutManager.visibleSections) { section in
                            sectionView(for: section)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background {
                // Subtle adaptive gradient: light mode white→accent, dark mode accent→black
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [theme.color.opacity(0.15), Color(.systemBackground)]
                        : [Color(.systemBackground), theme.color.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    periodSelector
                }
                ToolbarItem(placement: .topBarTrailing) {
                    accountSwitcher
                }
            }
            .onAppear { loadAllData() }
            .onChange(of: appState.selectedAccount) { _, _ in loadAllData() }
            .onChange(of: appState.showAllAccounts) { _, _ in loadAllData() }
            .onChange(of: appState.selectedConto) { _, _ in loadAllData() }
            .onChange(of: appState.showAllConti) { _, _ in loadAllData() }
            .onChange(of: appState.dataRefreshTrigger) { _, _ in loadAllData() }
            .sheet(item: $transactionToDetail) { transaction in
                NavigationStack {
                    TransactionDetailView(transaction: transaction)
                }
            }
            .sheet(item: $transactionToEdit) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .sheet(isPresented: $showingCustomization) {
                DashboardCustomizationView(layoutManager: layoutManager)
            }
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: DashboardSection) -> some View {
        switch section {
        case .monthlyStats:
            monthlyStatsSection
        case .spendingDistribution:
            spendingDistributionSection
        case .savingsRate:
            savingsRateSection
        case .topExpenses:
            topExpensesSection
        case .monthComparison:
            monthComparisonSection
        case .balanceTrend:
            balanceTrendSection
        case .contiList:
            contiSection
        case .recentTransactions:
            recentTransactionsSection
        case .activeBudgets:
            activeBudgetsSection
        case .spendingPace:
            spendingPaceSection
        case .upcomingRecurring:
            upcomingRecurringSection
        case .financialHealth:
            financialHealthSection
        case .expenseHeatmap:
            expenseHeatmapSection
        case .spendingAnomalies:
            spendingAnomaliesSection
        case .categorySparklines:
            categorySparklinesSection
        }
    }

    // MARK: - 1. Balance Hero

    private var balanceHeroSection: some View {
        VStack(spacing: 8) {
            Text(totalBalance.currencyFormatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(totalBalance >= 0 ? .primary : .red)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.bold))
                    Text(String(format: "%.1f%%", abs(percentageChange)))
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isPositiveChange ? Color(hex: "#4CAF50") : Color(hex: "#FF5252"))
                )

                Text((isPositiveChange ? "+" : "") + absoluteChange.currencyFormatted)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 2. Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 0) {
            UnifiedActionButton(icon: "plus", label: "Entrata", color: theme.color) {
                appState.presentQuickTransaction(type: .income)
            }
            .frame(maxWidth: .infinity)

            UnifiedActionButton(icon: "minus", label: "Uscita", color: theme.color) {
                appState.presentQuickTransaction(type: .expense)
            }
            .frame(maxWidth: .infinity)

            UnifiedActionButton(icon: "arrow.left.arrow.right", label: "Trasferimento", color: theme.color) {
                appState.presentQuickTransaction(type: .transfer)
            }
            .frame(maxWidth: .infinity)

            Menu {
                Button {
                    showingCustomization = true
                } label: {
                    Label("Personalizza Dashboard", systemImage: "slider.horizontal.3")
                }

                Divider()

                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Budget", systemImage: "chart.pie")
                }
                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Categorie", systemImage: "tag")
                }
                Button {
                    appState.selectTab(.transactions)
                } label: {
                    Label("Report", systemImage: "chart.bar")
                }
                Button {
                    appState.selectTab(.settings)
                } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                }
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(theme.color.opacity(0.1))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(theme.color)
                        }
                    Text("Altro")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 3. Monthly Stats

    private var monthlyStatsSection: some View {
        HStack(spacing: 12) {
            UnifiedStatCell(
                icon: "arrow.down.circle.fill",
                value: viewModel.monthlyIncome.currencyFormatted,
                label: "Entrate",
                color: .green
            )
            UnifiedStatCell(
                icon: "arrow.up.circle.fill",
                value: viewModel.monthlyExpenses.currencyFormatted,
                label: "Uscite",
                color: .red
            )
            UnifiedStatCell(
                icon: monthlySavings >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                value: monthlySavings.currencyFormatted,
                label: "Risparmi",
                color: monthlySavings >= 0 ? .green : .red
            )
        }
    }

    // MARK: - Savings Rate

    private var savingsRate: Double {
        guard viewModel.monthlyIncome > 0 else { return 0 }
        return NSDecimalNumber(decimal: monthlySavings / viewModel.monthlyIncome * 100).doubleValue
    }

    private var savingsRateSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Tasso di Risparmio").font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", savingsRate))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(savingsRate >= 0 ? .green : .red)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let clampedRate = min(max(savingsRate, -100), 100)
                let fillFraction = abs(clampedRate) / 100.0

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 16)

                    // Fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(savingsRate >= 0
                              ? Color.green.gradient
                              : Color.red.gradient)
                        .frame(width: width * fillFraction, height: 16)
                }
            }
            .frame(height: 16)

            HStack {
                Label(viewModel.monthlyIncome.currencyFormatted, systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Label(viewModel.monthlyExpenses.currencyFormatted, systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .unifiedCard()
    }

    // MARK: - Top Expenses

    private var topExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Spese del Mese").font(.headline)

            if topExpenses.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna spesa", systemImage: "flame")
                } description: {
                    Text("Le spese maggiori appariranno qui")
                }
            } else {
                ForEach(Array(topExpenses.enumerated()), id: \.element.id) { index, transaction in
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Image(systemName: transaction.category?.icon ?? "arrow.up.circle")
                            .font(.body)
                            .foregroundStyle(Color(hex: transaction.category?.color ?? "#FF5252"))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.transactionDescription ?? transaction.category?.name ?? "Spesa")
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(transaction.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text((transaction.amount ?? Decimal(0)).currencyFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { transactionToDetail = transaction }

                    if index < topExpenses.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Month Comparison

    private var monthComparisonSection: some View {
        let trend = viewModel.monthlyExpensesTrend
        // Current month = last entry, previous = second to last
        let current = trend.last
        let previous = trend.count >= 2 ? trend[trend.count - 2] : nil

        return VStack(alignment: .leading, spacing: 16) {
            Text("Confronto Mese Precedente").font(.headline)

            if let current, let previous {
                VStack(spacing: 12) {
                    MonthComparisonRow(
                        label: "Entrate",
                        current: current.income,
                        previous: previous.income,
                        color: .green
                    )
                    MonthComparisonRow(
                        label: "Uscite",
                        current: current.expenses,
                        previous: previous.expenses,
                        color: .red,
                        invertDelta: true
                    )

                    Divider()

                    let currentSavings = current.income - current.expenses
                    let previousSavings = previous.income - previous.expenses
                    MonthComparisonRow(
                        label: "Risparmi",
                        current: currentSavings,
                        previous: previousSavings,
                        color: currentSavings >= 0 ? .green : .red
                    )
                }
            } else {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "arrow.left.arrow.right")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - 4. Spending Distribution (Donut)

    private var spendingDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dove vanno i soldi").font(.headline)

            if spendingByCategory.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna spesa", systemImage: "chart.pie")
                } description: {
                    Text("Le tue spese appariranno qui")
                }
                .frame(height: 180)
            } else {
                Chart(spendingByCategory) { item in
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
                    ForEach(spendingByCategory.prefix(6)) { item in
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

    // MARK: - 5. Balance Trend (Line Chart)

    private var balanceTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Andamento Saldo").font(.headline)

            if viewModel.balanceHistory.isEmpty {
                ContentUnavailableView {
                    Label("Nessun dato", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("I dati appariranno qui")
                }
                .frame(height: 200)
            } else {
                let pastData = viewModel.pastBalanceHistory(for: displayedAccounts)
                let futureData = viewModel.futureBalanceHistory(for: displayedAccounts)

                Chart {
                    ForEach(pastData, id: \.date) { item in
                        LineMark(
                            x: .value("Data", item.date, unit: .day),
                            y: .value("Saldo", item.balance),
                            series: .value("Serie", "Passato")
                        )
                        .foregroundStyle(theme.color.gradient)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }

                    ForEach(futureData, id: \.date) { item in
                        LineMark(
                            x: .value("Data", item.date, unit: .day),
                            y: .value("Saldo", item.balance),
                            series: .value("Serie", "Futuro")
                        )
                        .foregroundStyle(theme.color.opacity(0.4))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    }
                }
                .chartXAxis {
                    if viewModel.selectedPeriod.useWeeklyAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.day())
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: viewModel.selectedPeriod.axisStrideCount)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
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
                .chartYScale(domain: viewModel.chartYDomain(for: displayedAccounts))
                .frame(height: 200)
            }
        }
        .unifiedCard()
    }

    // MARK: - 6. Conti Section

    private var contiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I tuoi conti").font(.headline)

            if allDisplayedConti.isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il tuo primo conto")
                }
            } else {
                ForEach(allDisplayedConti, id: \.id) { conto in
                    NavigationLink {
                        TransactionListView(initialConto: conto)
                    } label: {
                        ContoRowView(conto: conto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - 7. Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ultime transazioni")
                    .font(.headline)
                Spacer()
                Button("Vedi tutte") { appState.selectTab(.transactions) }
                    .font(.subheadline)
            }

            if viewModel.recentTransactions.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna transazione", systemImage: "list.bullet")
                } description: {
                    Text("Le tue transazioni appariranno qui")
                }
            } else {
                ForEach(viewModel.recentTransactions, id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)
                        .contentShape(Rectangle())
                        .onTapGesture { transactionToDetail = transaction }
                        .contextMenu {
                            Button {
                                transactionToDetail = transaction
                            } label: {
                                Label("Dettagli", systemImage: "info.circle")
                            }
                            Button {
                                transactionToEdit = transaction
                            } label: {
                                Label("Modifica", systemImage: "pencil")
                            }
                        }

                    if transaction.id != viewModel.recentTransactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Active Budgets

    private var activeBudgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget in Corso").font(.headline)

            if budgetSnapshots.isEmpty {
                ContentUnavailableView {
                    Label("Nessun budget", systemImage: "target")
                } description: {
                    Text("Crea un budget dalle Impostazioni")
                }
            } else {
                ForEach(budgetSnapshots) { budget in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(budget.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(budget.spent.currencyFormatted + " / " + budget.limit.currencyFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geometry in
                            let fillWidth = geometry.size.width * min(budget.percentage, 1.0)
                            let overflowWidth = budget.percentage > 1.0
                                ? geometry.size.width * min(budget.percentage - 1.0, 1.0)
                                : 0

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.tertiarySystemFill))

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(budget.barColor.gradient)
                                    .frame(width: fillWidth)

                                if overflowWidth > 0 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: geometry.size.width)
                                }
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            Text(String(format: "%.0f%%", budget.percentage * 100))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(budget.barColor)

                            Spacer()

                            if budget.daysRemaining > 0 {
                                Text("\(budget.daysRemaining)g rimanenti")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if budget.id != budgetSnapshots.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Spending Pace

    private var spendingPaceSection: some View {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let daysElapsed = max(1, calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30

        let dailyRate = daysElapsed > 0 ? viewModel.monthlyExpenses / Decimal(daysElapsed) : Decimal(0)
        let projectedTotal = dailyRate * Decimal(daysInMonth)
        let averageDaily = viewModel.periodAverageExpenses > 0
            ? viewModel.periodAverageExpenses / Decimal(daysInMonth)
            : Decimal(0)
        let isFaster = dailyRate > averageDaily && averageDaily > 0

        return VStack(alignment: .leading, spacing: 16) {
            Text("Velocità di Spesa").font(.headline)

            HStack(alignment: .top, spacing: 16) {
                // Daily rate
                VStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.title2)
                        .foregroundStyle(isFaster ? .red : .green)
                    Text(dailyRate.currencyFormatted)
                        .font(.title3.weight(.bold))
                    Text("al giorno")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 60)

                // Projected
                VStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(projectedTotal.currencyFormatted)
                        .font(.title3.weight(.bold))
                    Text("proiezione mese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if averageDaily > 0 {
                HStack(spacing: 4) {
                    Image(systemName: isFaster ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                    Text(isFaster
                         ? "Stai spendendo più della media (\(averageDaily.currencyFormatted)/g)"
                         : "Sotto la media di \(averageDaily.currencyFormatted)/g")
                        .font(.caption)
                }
                .foregroundStyle(isFaster ? .orange : .green)
            }
        }
        .unifiedCard()
    }

    // MARK: - Upcoming Recurring

    private var upcomingRecurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spese Ricorrenti in Arrivo").font(.headline)

            if upcomingRecurring.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna ricorrenza", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Le spese ricorrenti appariranno qui")
                }
            } else {
                ForEach(Array(upcomingRecurring.enumerated()), id: \.element.transaction.id) { index, item in
                    HStack(spacing: 12) {
                        // Date badge
                        VStack(spacing: 0) {
                            Text(dayFormatter.string(from: item.nextDate))
                                .font(.title3.weight(.bold))
                            Text(monthFormatter.string(from: item.nextDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.transaction.transactionDescription ?? item.transaction.category?.name ?? "Ricorrenza")
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(item.transaction.recurrenceFrequency?.displayName ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text((item.transaction.amount ?? Decimal(0)).currencyFormatted)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.transaction.type == .income ? .green : .red)
                    }

                    if index < upcomingRecurring.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }

    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "it_IT")
        return f
    }

    // MARK: - Financial Health Score

    private var financialHealthSection: some View {
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

            // Circular gauge
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

            // Component breakdown
            VStack(spacing: 8) {
                HealthComponentRow(label: "Risparmio", score: healthScore.savingsPoints, maxScore: 30, color: .green)
                HealthComponentRow(label: "Budget", score: healthScore.budgetPoints, maxScore: 25, color: .blue)
                HealthComponentRow(label: "Stabilità Entrate", score: healthScore.incomePoints, maxScore: 20, color: .purple)
                HealthComponentRow(label: "Trend Spese", score: healthScore.spendingPoints, maxScore: 25, color: .orange)
            }
        }
        .unifiedCard()
    }

    // MARK: - Expense Heatmap

    private var expenseHeatmapSection: some View {
        let calendar = Calendar.current
        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30

        // First day of month weekday (Monday = 1 in ISO)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        // Adjust to Monday-based (Mon=0, Tue=1, ..., Sun=6)
        let mondayOffset = (firstWeekday + 5) % 7

        // Max daily expense for color scaling
        let maxExpense = dailyExpenses.values.max() ?? Decimal(1)

        let weekdayLabels = ["L", "M", "M", "G", "V", "S", "D"]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heatmap Spese").font(.headline)
                Spacer()
                let monthFormatter = DateFormatter()
                let _ = monthFormatter.dateFormat = "MMMM yyyy"
                let _ = monthFormatter.locale = Locale(identifier: "it_IT")
                Text(monthFormatter.string(from: startOfMonth).capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Weekday headers
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayLabels[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            let totalCells = mondayOffset + daysInMonth
            let rows = (totalCells + 6) / 7

            VStack(spacing: 4) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let dayNumber = cellIndex - mondayOffset + 1

                            if dayNumber >= 1 && dayNumber <= daysInMonth {
                                let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: startOfMonth)!
                                let expense = dailyExpenses[calendar.startOfDay(for: date)] ?? Decimal(0)
                                let intensity = maxExpense > 0
                                    ? CGFloat(NSDecimalNumber(decimal: expense / maxExpense).doubleValue)
                                    : 0

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(intensity > 0
                                          ? theme.color.opacity(0.15 + Double(intensity) * 0.85)
                                          : Color(.tertiarySystemFill))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Text("\(dayNumber)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(intensity > 0.6 ? .white : .secondary)
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.clear)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text("Meno")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == 0 ? Color(.tertiarySystemFill) : theme.color.opacity(Double(i) / 4.0))
                        .frame(width: 14, height: 14)
                }
                Text("Più")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .unifiedCard()
    }

    // MARK: - Spending Anomalies

    private var spendingAnomaliesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Anomalie di Spesa").font(.headline)
                Spacer()
                if !spendingAnomalies.isEmpty {
                    Text("\(spendingAnomalies.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange))
                }
            }

            if spendingAnomalies.isEmpty {
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
                ForEach(Array(spendingAnomalies.enumerated()), id: \.element.id) { index, anomaly in
                    HStack(spacing: 12) {
                        // Severity indicator
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

                    if index < spendingAnomalies.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Category Sparklines

    private var categorySparklinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trend per Categoria").font(.headline)

            if categoryTrends.isEmpty {
                ContentUnavailableView {
                    Label("Dati insufficienti", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Servono almeno 2 mesi di dati")
                }
            } else {
                ForEach(categoryTrends) { trend in
                    HStack(spacing: 12) {
                        Image(systemName: trend.icon)
                            .font(.body)
                            .foregroundStyle(Color(hex: trend.color))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(trend.currentMonth.currencyFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 100, alignment: .leading)

                        // Sparkline
                        Chart(Array(trend.monthlyAmounts.enumerated()), id: \.offset) { index, amount in
                            LineMark(
                                x: .value("Mese", index),
                                y: .value("Importo", NSDecimalNumber(decimal: amount).doubleValue)
                            )
                            .foregroundStyle(Color(hex: trend.color))
                            .interpolationMethod(.monotone)

                            AreaMark(
                                x: .value("Mese", index),
                                y: .value("Importo", NSDecimalNumber(decimal: amount).doubleValue)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color(hex: trend.color).opacity(0.3), Color(hex: trend.color).opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 32)

                        // Trend arrow
                        Image(systemName: trend.isIncreasing ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(trend.isIncreasing ? .red : .green)
                            .frame(width: 20)
                    }

                    if trend.id != categoryTrends.last?.id {
                        Divider()
                    }
                }
            }
        }
        .unifiedCard()
    }

    // MARK: - Toolbar: Period Selector

    private var periodLabel: String {
        if viewModel.selectedPeriod == .oneMonth {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yy"
            formatter.locale = Locale(identifier: "it_IT")
            return formatter.string(from: viewModel.selectedMonth).capitalized
        }
        return viewModel.selectedPeriod.rawValue
    }

    private var periodSelector: some View {
        Menu {
            // 1M → submenu with month picker
            Menu {
                ForEach(availableMonths, id: \.self) { month in
                    Button {
                        viewModel.selectedPeriod = .oneMonth
                        viewModel.selectedMonth = month
                        loadAllData()
                    } label: {
                        HStack {
                            Text(monthYearFormatter.string(from: month))
                            if viewModel.selectedPeriod == .oneMonth &&
                                Calendar.current.isDate(month, equalTo: viewModel.selectedMonth, toGranularity: .month) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(ChartPeriod.oneMonth.displayName)
                    if viewModel.selectedPeriod == .oneMonth {
                        Image(systemName: "checkmark")
                    }
                }
            }

            // Other periods as plain buttons
            ForEach(ChartPeriod.allCases.filter { $0 != .oneMonth }) { period in
                Button {
                    viewModel.selectedPeriod = period
                    loadAllData()
                } label: {
                    HStack {
                        Text(period.displayName)
                        if period == viewModel.selectedPeriod {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(periodLabel)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let now = Date()
        var months: [Date] = []
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: -i, to: now) {
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
                months.append(startOfMonth)
            }
        }
        return months
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }

    // MARK: - Toolbar: Account Switcher

    private var accountSwitcher: some View {
        Menu {
            Button {
                appState.selectAllAccounts()
            } label: {
                HStack {
                    Label("Tutti i Libri", systemImage: "square.stack.3d.up.fill")
                    if appState.showAllAccounts {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(activeAccounts, id: \.id) { libro in
                Menu {
                    Button {
                        appState.selectAccount(libro)
                        appState.selectAllConti()
                    } label: {
                        HStack {
                            Text("Tutti gli account")
                            if appState.selectedAccount?.id == libro.id && appState.showAllConti {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(libro.activeConti, id: \.id) { conto in
                        Button {
                            appState.selectAccount(libro)
                            appState.selectConto(conto)
                        } label: {
                            HStack {
                                Label(conto.name ?? "Account", systemImage: conto.type?.icon ?? "creditcard")
                                if appState.selectedConto?.id == conto.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(libro.name ?? "Libro")
                        if appState.selectedAccount?.id == libro.id && !appState.showAllAccounts {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if appState.showAllAccounts {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption)
                }
                Text(displayName)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllData() {
        viewModel.loadDashboardData(
            displayedAccounts: displayedAccounts,
            allDisplayedConti: allDisplayedConti,
            showAllAccounts: appState.showAllAccounts,
            showAllConti: appState.showAllConti,
            modelContext: modelContext
        )
        loadSpendingByCategory()
        loadTopExpenses()
        loadBudgets()
        loadUpcomingRecurring()
        loadDailyExpenses()
        computeHealthScore()
        detectSpendingAnomalies()
        loadCategoryTrends()
    }

    private func loadSpendingByCategory() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            spendingByCategory = []
            return
        }

        let calendar = Calendar.current
        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            let expenses = transactions.filter { transaction in
                guard transaction.type == .expense else { return false }
                guard let fromId = transaction.fromContoId else { return false }
                return contiIDs.contains(fromId)
            }

            var categoryTotals: [String: (amount: Decimal, color: String, icon: String)] = [:]

            for expense in expenses {
                let name = expense.category?.name ?? "Altro"
                let color = expense.category?.color ?? "#9E9E9E"
                let icon = expense.category?.icon ?? "questionmark.circle"
                let amount = expense.amount ?? Decimal(0)

                if let existing = categoryTotals[name] {
                    categoryTotals[name] = (existing.amount + amount, color, icon)
                } else {
                    categoryTotals[name] = (amount, color, icon)
                }
            }

            let total = categoryTotals.values.reduce(Decimal(0)) { $0 + $1.amount }

            spendingByCategory = categoryTotals.map { name, data in
                let percentage = total > 0 ? (data.amount / total) * 100 : Decimal(0)
                return SpendingCategory(
                    name: name,
                    amount: data.amount,
                    color: data.color,
                    icon: data.icon,
                    percentage: String(format: "%.0f%%", NSDecimalNumber(decimal: percentage).doubleValue)
                )
            }
            .sorted { $0.amount > $1.amount }
        } catch {
            spendingByCategory = []
        }
    }

    private func loadTopExpenses() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            topExpenses = []
            return
        }

        let calendar = Calendar.current
        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.amount, order: .reverse)]
        )
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            topExpenses = Array(
                transactions
                    .filter { transaction in
                        guard transaction.type == .expense else { return false }
                        guard let fromId = transaction.fromContoId else { return false }
                        return contiIDs.contains(fromId)
                    }
                    .prefix(5)
            )
        } catch {
            topExpenses = []
        }
    }

    private func loadBudgets() {
        // Get budgets from displayed accounts
        let accountIDs = Set(displayedAccounts.map(\.id))
        guard !accountIDs.isEmpty else {
            budgetSnapshots = []
            return
        }

        var descriptor = FetchDescriptor<Budget>()
        descriptor.predicate = #Predicate<Budget> { budget in
            budget.isActive == true
        }

        do {
            let budgets = try modelContext.fetch(descriptor)
            let filtered = budgets.filter { budget in
                guard let accountId = budget.account?.id else { return false }
                return accountIDs.contains(accountId)
            }

            budgetSnapshots = filtered.compactMap { budget in
                guard let name = budget.name, let limit = budget.amount, limit > 0 else { return nil }
                let spent = (try? budget.getCurrentSpent(in: modelContext)) ?? Decimal(0)
                let percentage = NSDecimalNumber(decimal: spent / limit).doubleValue
                return BudgetSnapshot(
                    id: budget.id,
                    name: name,
                    spent: spent,
                    limit: limit,
                    percentage: percentage,
                    daysRemaining: budget.daysRemaining
                )
            }
        } catch {
            budgetSnapshots = []
        }
    }

    private func loadDailyExpenses() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            dailyExpenses = [:]
            return
        }

        let calendar = Calendar.current
        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)
            var grouped: [Date: Decimal] = [:]

            for transaction in transactions {
                guard transaction.type == .expense,
                      let fromId = transaction.fromContoId,
                      contiIDs.contains(fromId)
                else { continue }

                let day = calendar.startOfDay(for: transaction.date)
                grouped[day, default: Decimal(0)] += transaction.amount ?? Decimal(0)
            }

            dailyExpenses = grouped
        } catch {
            dailyExpenses = [:]
        }
    }

    private func computeHealthScore() {
        let calendar = Calendar.current
        let now = Date()

        // --- 1. Savings Rate (0-30 pts) ---
        // 20%+ savings rate = 30 pts, linear scale
        var savingsPoints: Double = 0
        if viewModel.monthlyIncome > 0 {
            let rate = NSDecimalNumber(decimal: monthlySavings / viewModel.monthlyIncome).doubleValue
            savingsPoints = min(30, max(0, rate * 150)) // 20% → 30pts
        }

        // --- 2. Budget Adherence (0-25 pts) ---
        var budgetPoints: Double = 25 // Full marks if no budgets
        if !budgetSnapshots.isEmpty {
            let underBudget = budgetSnapshots.filter { $0.percentage < 1.0 }.count
            budgetPoints = 25 * Double(underBudget) / Double(budgetSnapshots.count)
        }

        // --- 3. Income Stability (0-20 pts) ---
        // Low coefficient of variation = high stability
        var incomePoints: Double = 10 // Default if insufficient data
        let trend = viewModel.monthlyExpensesTrend
        if trend.count >= 3 {
            let incomes = trend.suffix(6).map { NSDecimalNumber(decimal: $0.income).doubleValue }
            let mean = incomes.reduce(0, +) / Double(incomes.count)
            if mean > 0 {
                let variance = incomes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(incomes.count)
                let cv = sqrt(variance) / mean // coefficient of variation
                // cv < 0.1 = very stable (20pts), cv > 0.5 = unstable (0pts)
                incomePoints = min(20, max(0, 20 * (1 - cv * 2)))
            }
        }

        // --- 4. Spending Trend (0-25 pts) ---
        // Decreasing or stable spending = good
        var spendingPoints: Double = 12.5 // Default
        if trend.count >= 2 {
            let recentExpenses = trend.suffix(3).map { NSDecimalNumber(decimal: $0.expenses).doubleValue }
            if recentExpenses.count >= 2, let last = recentExpenses.last, let first = recentExpenses.first, first > 0 {
                let changeRate = (last - first) / first
                // Decrease → 25pts, increase → lower score
                spendingPoints = min(25, max(0, 25 * (1 - changeRate)))
            }
        }

        let total = savingsPoints + budgetPoints + incomePoints + spendingPoints

        healthScore = FinancialHealthResult(
            score: total,
            savingsPoints: savingsPoints,
            budgetPoints: budgetPoints,
            incomePoints: incomePoints,
            spendingPoints: spendingPoints
        )
    }

    private func detectSpendingAnomalies() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            spendingAnomalies = []
            return
        }

        let calendar = Calendar.current
        let now = Date()

        // Fetch last 3 months of transactions for baseline
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else {
            spendingAnomalies = []
            return
        }

        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : now
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let endOfCurrentMonth = calendar.date(byAdding: .month, value: 1, to: startOfCurrentMonth)!

        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= threeMonthsAgo && transaction.date < endOfCurrentMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            let expenses = transactions.filter { tx in
                guard tx.type == .expense, let fromId = tx.fromContoId else { return false }
                return contiIDs.contains(fromId)
            }

            // Group by category, split historical vs current
            var historicalByCategory: [String: [Decimal]] = [:]  // monthly totals
            var currentByCategory: [String: Decimal] = [:]
            var categoryMeta: [String: (color: String, icon: String)] = [:]

            for expense in expenses {
                let catName = expense.category?.name ?? "Altro"
                let amount = expense.amount ?? Decimal(0)

                if categoryMeta[catName] == nil {
                    categoryMeta[catName] = (
                        color: expense.category?.color ?? "#9E9E9E",
                        icon: expense.category?.icon ?? "questionmark.circle"
                    )
                }

                if expense.date >= startOfCurrentMonth && expense.date < endOfCurrentMonth {
                    currentByCategory[catName, default: Decimal(0)] += amount
                } else {
                    // Determine which historical month
                    let monthKey = calendar.component(.month, from: expense.date)
                    let yearKey = calendar.component(.year, from: expense.date)
                    let key = "\(catName)_\(yearKey)_\(monthKey)"
                    // Simplified: just accumulate into array
                    historicalByCategory[catName, default: []].append(amount)
                }
            }

            // Regroup historical into monthly totals per category
            var monthlyAvgByCategory: [String: Decimal] = [:]
            // Simpler approach: get total historical and divide by number of historical months
            let historicalMonths = max(1, calendar.dateComponents([.month], from: threeMonthsAgo, to: startOfCurrentMonth).month ?? 1)

            // Re-aggregate historical totals
            var historicalTotalByCategory: [String: Decimal] = [:]
            for expense in expenses {
                guard expense.type == .expense,
                      let fromId = expense.fromContoId, contiIDs.contains(fromId),
                      expense.date < startOfCurrentMonth
                else { continue }
                let catName = expense.category?.name ?? "Altro"
                historicalTotalByCategory[catName, default: Decimal(0)] += expense.amount ?? Decimal(0)
            }

            for (cat, total) in historicalTotalByCategory {
                monthlyAvgByCategory[cat] = total / Decimal(historicalMonths)
            }

            // Detect anomalies: current month spending > 1.5x historical average
            var anomalies: [SpendingAnomaly] = []

            for (catName, currentAmount) in currentByCategory {
                let avg = monthlyAvgByCategory[catName] ?? Decimal(0)
                guard avg > 0 else { continue }

                let ratio = NSDecimalNumber(decimal: currentAmount / avg).doubleValue
                if ratio > 1.5 {
                    let deviation = (ratio - 1.0) * 100
                    let meta = categoryMeta[catName] ?? (color: "#9E9E9E", icon: "questionmark.circle")

                    let severity: AnomalySeverity
                    if ratio > 3.0 { severity = .high }
                    else if ratio > 2.0 { severity = .medium }
                    else { severity = .low }

                    anomalies.append(SpendingAnomaly(
                        categoryName: catName,
                        categoryColor: meta.color,
                        icon: meta.icon,
                        amount: currentAmount,
                        average: avg,
                        deviationPercent: deviation,
                        severity: severity
                    ))
                }
            }

            spendingAnomalies = anomalies.sorted { $0.deviationPercent > $1.deviationPercent }.prefix(5).map { $0 }
        } catch {
            spendingAnomalies = []
        }
    }

    private func loadCategoryTrends() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            categoryTrends = []
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let monthsBack = 6

        guard let startDate = calendar.date(byAdding: .month, value: -monthsBack + 1, to: now) else {
            categoryTrends = []
            return
        }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
        let endOfCurrentMonth = calendar.date(byAdding: .month, value: 1,
            to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)!

        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= start && transaction.date < endOfCurrentMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            let expenses = transactions.filter { tx in
                guard tx.type == .expense, let fromId = tx.fromContoId else { return false }
                return contiIDs.contains(fromId)
            }

            // Build monthly amounts per category
            var data: [String: (color: String, icon: String, months: [Int: Decimal])] = [:]

            for expense in expenses {
                let catName = expense.category?.name ?? "Altro"
                let amount = expense.amount ?? Decimal(0)
                let monthIndex = calendar.dateComponents([.month], from: start, to: expense.date).month ?? 0

                if data[catName] == nil {
                    data[catName] = (
                        color: expense.category?.color ?? "#9E9E9E",
                        icon: expense.category?.icon ?? "questionmark.circle",
                        months: [:]
                    )
                }
                data[catName]!.months[monthIndex, default: Decimal(0)] += amount
            }

            // Convert to CategoryTrendData, sorted by total
            categoryTrends = data.map { catName, info in
                let amounts = (0..<monthsBack).map { info.months[$0] ?? Decimal(0) }
                let currentMonth = amounts.last ?? Decimal(0)
                let previousMonth = amounts.count >= 2 ? amounts[amounts.count - 2] : Decimal(0)
                let isIncreasing = currentMonth > previousMonth

                return CategoryTrendData(
                    name: catName,
                    color: info.color,
                    icon: info.icon,
                    monthlyAmounts: amounts,
                    currentMonth: currentMonth,
                    isIncreasing: isIncreasing
                )
            }
            .filter { $0.monthlyAmounts.contains { $0 > 0 } } // Remove empty
            .sorted { $0.currentMonth > $1.currentMonth }
            .prefix(8)
            .map { $0 }
        } catch {
            categoryTrends = []
        }
    }

    private func loadUpcomingRecurring() {
        let contiIDs = Set(allDisplayedConti.map(\.id))
        guard !contiIDs.isEmpty else {
            upcomingRecurring = []
            return
        }

        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.isRecurring == true
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            upcomingRecurring = transactions
                .filter { tx in
                    guard tx.isRecurrenceActive() else { return false }
                    if let id = tx.fromContoId, contiIDs.contains(id) { return true }
                    if let id = tx.toContoId, contiIDs.contains(id) { return true }
                    return false
                }
                .compactMap { tx -> (transaction: FinanceTransaction, nextDate: Date)? in
                    guard let next = tx.nextRecurrenceDate() else { return nil }
                    return (transaction: tx, nextDate: next)
                }
                .sorted { $0.nextDate < $1.nextDate }
                .prefix(5)
                .map { $0 }
        } catch {
            upcomingRecurring = []
        }
    }
}

// MARK: - Budget Snapshot

struct BudgetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let spent: Decimal
    let limit: Decimal
    let percentage: Double
    let daysRemaining: Int

    var barColor: Color {
        if percentage >= 1.0 { return .red }
        if percentage >= 0.8 { return .orange }
        return .green
    }
}

// MARK: - Financial Health Result

struct FinancialHealthResult {
    let score: Double
    let savingsPoints: Double
    let budgetPoints: Double
    let incomePoints: Double
    let spendingPoints: Double

    var label: String {
        switch score {
        case 80...: return "Ottimo"
        case 60..<80: return "Buono"
        case 40..<60: return "Sufficiente"
        default: return "Critico"
        }
    }

    var color: Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }

    static var empty: FinancialHealthResult {
        FinancialHealthResult(score: 0, savingsPoints: 0, budgetPoints: 0, incomePoints: 0, spendingPoints: 0)
    }
}

// MARK: - Spending Anomaly

enum AnomalySeverity {
    case low, medium, high

    var color: Color {
        switch self {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct SpendingAnomaly: Identifiable {
    let id = UUID()
    let categoryName: String
    let categoryColor: String
    let icon: String
    let amount: Decimal
    let average: Decimal
    let deviationPercent: Double
    let severity: AnomalySeverity

    var title: String { categoryName }
    var detail: String {
        "Media: \(average.currencyFormatted)/mese"
    }
}

// MARK: - Category Trend Data

struct CategoryTrendData: Identifiable {
    let id = UUID()
    let name: String
    let color: String
    let icon: String
    let monthlyAmounts: [Decimal]
    let currentMonth: Decimal
    let isIncreasing: Bool
}

// MARK: - Health Component Row

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

// MARK: - Month Comparison Row

private struct MonthComparisonRow: View {
    let label: String
    let current: Decimal
    let previous: Decimal
    let color: Color
    var invertDelta: Bool = false

    private var delta: Double {
        guard previous != 0 else { return 0 }
        return NSDecimalNumber(decimal: (current - previous) / abs(previous) * 100).doubleValue
    }

    /// Whether the delta is "good" (green arrow) or "bad" (red arrow)
    private var isDeltaPositive: Bool {
        invertDelta ? delta <= 0 : delta >= 0
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(current.currencyFormatted)
                    .font(.subheadline.weight(.semibold))

                if previous != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: isDeltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                        Text(String(format: "%.0f%%", abs(delta)))
                            .font(.caption2.weight(.bold))
                        Text("vs " + previous.currencyFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(isDeltaPositive ? .green : .red)
                }
            }
        }
    }
}

// MARK: - Unified Card Style

private extension View {
    func unifiedCard() -> some View {
        self
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Unified Action Button

private struct UnifiedActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(color)
                    }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Unified Stat Cell

private struct UnifiedStatCell: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Preview

#Preview {
    UnifiedDashboardView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
