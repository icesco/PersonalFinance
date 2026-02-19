//
//  UnifiedDashboardView.swift
//  Personal Finance
//
//  Unified dashboard combining clarity of Classic with visual appeal of Crypto.
//  Scrollable single-page layout with system cards on a subtle accent gradient.
//
//  Section views are in Views/Dashboard/Widgets/.
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
    @State private var dailyFlow: [Date: DailyFlow] = [:]
    @State private var healthScore: FinancialHealthResult = .empty
    @State private var spendingAnomalies: [SpendingAnomaly] = []
    @State private var categoryTrends: [CategoryTrendData] = []
    @State private var cashFlowForecast: [CashFlowWeek] = []
    @State private var weekdaySpending: [WeekdaySpending] = []
    @State private var incomeVsExpensesData: [MonthlyIncomeExpense] = []
    @State private var topPayeesData: [PayeeData] = []
    @State private var savingsGoalData: SavingsGoalData = .empty
    @State private var cachedPastData: [BalanceDataPoint] = []
    @State private var cachedFutureData: [BalanceDataPoint] = []
    @State private var cachedYDomain: ClosedRange<Decimal> = 0...1
    @State private var cachedTotalBalance: Decimal = 0
    @State private var cachedAbsoluteChange: Decimal = 0
    @State private var cachedPercentageChange: Double = 0
    @State private var cachedMonthlySavings: Decimal = 0
    @State private var cachedSavingsRate: Double = 0
    @State private var cachedConti: [Conto] = []

    @State private var transactionToDetail: FinanceTransaction?
    @State private var transactionToEdit: FinanceTransaction?
    @State private var showingCustomization = false
    @State private var widgetDetail: UnifiedWidgetDetail?
    @State private var currentMonthTransactions: [FinanceTransaction] = []

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

    private var displayName: String {
        if appState.showAllAccounts { return "Tutti i Libri" }
        if let libro = appState.selectedAccount {
            if appState.showAllConti { return libro.name ?? "Libro" }
            else if let conto = appState.selectedConto { return conto.name ?? "Account" }
        }
        return "Libro"
    }

    /// Coalesced fingerprint for `.task(id:)` — a single value change triggers one reload
    /// instead of multiple onChange handlers firing separately.
    private var dataFingerprint: String {
        let aid = appState.selectedAccount?.id.uuidString ?? "all"
        let cid = appState.selectedConto?.id.uuidString ?? "all"
        return "\(aid)-\(cid)-\(appState.showAllAccounts)-\(appState.showAllConti)-\(appState.dataRefreshTrigger)-\(viewModel.selectedPeriod.rawValue)-\(viewModel.selectedMonth.timeIntervalSince1970)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Pinned: always visible, full width
                    BalanceHeroSection(
                        totalBalance: cachedTotalBalance,
                        percentageChange: cachedPercentageChange,
                        absoluteChange: cachedAbsoluteChange
                    )
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
            .environment(\.cardTint, theme.color)
            .background {
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
            .task(id: dataFingerprint) { loadAllData() }
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
            .sheet(item: $widgetDetail) { detail in
                NavigationStack {
                    switch detail {
                    case .heatmap:
                        HeatmapDetailView(
                            dailyFlow: dailyFlow,
                            transactions: currentMonthTransactions,
                            referenceDate: viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date()
                        )
                    case .spendingDistribution:
                        SpendingDistributionDetailView(categories: spendingByCategory)
                    case .balanceTrend:
                        BalanceTrendDetailView(
                            pastData: cachedPastData,
                            futureData: cachedFutureData,
                            yDomain: cachedYDomain,
                            themeColor: theme.color
                        )
                    case .financialHealth:
                        FinancialHealthDetailView(healthScore: healthScore)
                    case .topExpenses:
                        TopExpensesDetailView(
                            expenses: currentMonthTransactions
                                .filter { $0.type == .expense }
                                .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) },
                            onTapTransaction: { tx in
                                widgetDetail = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    transactionToDetail = tx
                                }
                            }
                        )
                    }
                }
                .environment(\.cardTint, theme.color)
            }
        }
    }

    // MARK: - Quick Actions (uses appState bindings, stays inline)

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

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: DashboardSection) -> some View {
        switch section {
        case .monthlyStats:
            MonthlyStatsSection(
                income: viewModel.monthlyIncome,
                expenses: viewModel.monthlyExpenses,
                savings: cachedMonthlySavings
            )
        case .spendingDistribution:
            SpendingDistributionSection(
                categories: spendingByCategory,
                onExpand: { widgetDetail = .spendingDistribution }
            )
        case .savingsRate:
            SavingsRateSection(
                savingsRate: cachedSavingsRate,
                monthlyIncome: viewModel.monthlyIncome,
                monthlyExpenses: viewModel.monthlyExpenses
            )
        case .topExpenses:
            TopExpensesSection(
                expenses: topExpenses,
                onTapTransaction: { transactionToDetail = $0 },
                onExpand: { widgetDetail = .topExpenses }
            )
        case .monthComparison:
            MonthComparisonSection(trend: viewModel.monthlyExpensesTrend)
        case .balanceTrend:
            BalanceTrendSection(
                pastData: cachedPastData,
                futureData: cachedFutureData,
                yDomain: cachedYDomain,
                useWeeklyAxis: viewModel.selectedPeriod.useWeeklyAxis,
                axisStrideCount: viewModel.selectedPeriod.axisStrideCount,
                themeColor: theme.color,
                onExpand: { widgetDetail = .balanceTrend }
            )
        case .contiList:
            ContiListSection(conti: cachedConti)
        case .recentTransactions:
            RecentTransactionsSection(
                transactions: viewModel.recentTransactions,
                onViewAll: { appState.selectTab(.transactions) },
                onTapTransaction: { transactionToDetail = $0 },
                onEditTransaction: { transactionToEdit = $0 }
            )
        case .activeBudgets:
            ActiveBudgetsSection(budgets: budgetSnapshots)
        case .spendingPace:
            SpendingPaceSection(
                monthlyExpenses: viewModel.monthlyExpenses,
                periodAverageExpenses: viewModel.periodAverageExpenses
            )
        case .upcomingRecurring:
            UpcomingRecurringSection(items: upcomingRecurring)
        case .financialHealth:
            FinancialHealthSection(
                healthScore: healthScore,
                onExpand: { widgetDetail = .financialHealth }
            )
        case .expenseHeatmap:
            ExpenseHeatmapSection(
                dailyFlow: dailyFlow,
                referenceDate: viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : Date(),
                onExpand: { widgetDetail = .heatmap }
            )
        case .spendingAnomalies:
            SpendingAnomaliesSection(anomalies: spendingAnomalies)
        case .categorySparklines:
            CategorySparklinesSection(trends: categoryTrends)
        case .cashFlowForecast:
            CashFlowForecastSection(forecast: cashFlowForecast)
        case .spendingByWeekday:
            SpendingByWeekdaySection(data: weekdaySpending, themeColor: theme.color)
        case .incomeVsExpensesTimeline:
            IncomeVsExpensesSection(data: incomeVsExpensesData)
        case .topPayees:
            TopPayeesSection(payees: topPayeesData, themeColor: theme.color)
        case .savingsGoal:
            SavingsGoalSection(data: savingsGoalData, themeColor: theme.color)
        }
    }

    // MARK: - Toolbar: Period Selector

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    private static let fullMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    private var periodLabel: String {
        if viewModel.selectedPeriod == .oneMonth {
            return Self.shortMonthFormatter.string(from: viewModel.selectedMonth).capitalized
        }
        return viewModel.selectedPeriod.rawValue
    }

    private var periodSelector: some View {
        Menu {
            Menu {
                ForEach(availableMonths, id: \.self) { month in
                    Button {
                        viewModel.selectedPeriod = .oneMonth
                        viewModel.selectedMonth = month
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

            ForEach(ChartPeriod.allCases.filter { $0 != .oneMonth }) { period in
                Button {
                    viewModel.selectedPeriod = period
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

    private var monthYearFormatter: DateFormatter { Self.fullMonthFormatter }

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
        let conti = allDisplayedConti
        let accounts = displayedAccounts
        let contiIDs = Set(conti.map(\.id))

        // 1. View model (balance history, monthly totals, trend)
        viewModel.loadDashboardData(
            displayedAccounts: accounts,
            allDisplayedConti: conti,
            showAllAccounts: appState.showAllAccounts,
            showAllConti: appState.showAllConti,
            modelContext: modelContext
        )

        // 2. Pre-compute balance split once (Fix #3: was computed 4x per body eval)
        let (past, future) = BalanceCalculator.splitBalanceHistory(
            history: viewModel.balanceHistory,
            today: Date(),
            period: viewModel.selectedPeriod,
            selectedMonth: viewModel.selectedMonth
        )
        // 3. Single transaction fetch for all widget processing (~10 fetches → 1)
        let allTransactions: [FinanceTransaction]
        do {
            allTransactions = try modelContext.fetch(FetchDescriptor<FinanceTransaction>())
        } catch {
            withAnimation(.easeOut(duration: 0.5)) { resetWidgetData() }
            return
        }

        // 4. Budgets (separate entity, needs own fetch)
        loadBudgets(accountIDs: Set(accounts.map(\.id)))

        // 5. Common date calculations
        let calendar = Calendar.current
        let now = Date()
        let referenceDate = viewModel.selectedPeriod == .oneMonth ? viewModel.selectedMonth : now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        // 6. Pre-filter reusable subsets (computed once, shared across widgets)
        let relevant = allTransactions.filter { tx in
            if let id = tx.fromContoId, contiIDs.contains(id) { return true }
            if let id = tx.toContoId, contiIDs.contains(id) { return true }
            return false
        }
        let relevantExpenses = relevant.filter { $0.type == .expense }
        let currentMonthExpenses = relevantExpenses.filter {
            $0.date >= startOfMonth && $0.date < endOfMonth
        }
        let monthTransactions = relevant.filter {
            ($0.type == .income || $0.type == .expense) && $0.date >= startOfMonth && $0.date < endOfMonth
        }
        let relevantRecurring = relevant.filter { $0.isRecurring == true }

        // 7. Animate all state changes so Charts, bars, and numbers transition smoothly
        withAnimation(.easeOut(duration: 0.5)) {
            cachedPastData = past
            cachedFutureData = future
            cachedYDomain = BalanceCalculator.chartYDomain(dataPoints: past + future)

            let balance = conti.reduce(Decimal(0)) { $0 + $1.balance }
            cachedTotalBalance = balance
            cachedAbsoluteChange = viewModel.absoluteChange(currentTotal: balance)
            cachedPercentageChange = viewModel.percentageChange(currentTotal: balance)
            cachedMonthlySavings = viewModel.monthlyIncome - viewModel.monthlyExpenses
            cachedSavingsRate = viewModel.monthlyIncome > 0
                ? (cachedMonthlySavings / viewModel.monthlyIncome * 100).doubleValue : 0
            cachedConti = conti

            guard !contiIDs.isEmpty else {
                resetWidgetData()
                return
            }

            currentMonthTransactions = monthTransactions
            processSpendingByCategory(from: currentMonthExpenses)
            processTopExpenses(from: currentMonthExpenses)
            processDailyFlow(from: monthTransactions, calendar: calendar)
            processTopPayees(from: currentMonthExpenses)
            processSpendingAnomalies(
                from: relevantExpenses, calendar: calendar, now: now,
                startOfMonth: startOfMonth, endOfMonth: endOfMonth
            )
            processCategoryTrends(from: relevantExpenses, calendar: calendar, now: now)
            processWeekdaySpending(from: relevantExpenses, calendar: calendar, now: now)
            processCashFlowForecast(
                relevant: relevant, relevantRecurring: relevantRecurring,
                contiIDs: contiIDs, calendar: calendar, now: now
            )
            processUpcomingRecurring(from: relevantRecurring)

            computeHealthScore()
            processIncomeVsExpenses()
            processSavingsGoal(calendar: calendar, now: now)
        }
    }

    private func resetWidgetData() {
        spendingByCategory = []
        topExpenses = []
        budgetSnapshots = []
        upcomingRecurring = []
        dailyFlow = [:]
        healthScore = .empty
        spendingAnomalies = []
        categoryTrends = []
        cashFlowForecast = []
        weekdaySpending = []
        incomeVsExpensesData = []
        topPayeesData = []
        savingsGoalData = .empty
        currentMonthTransactions = []
    }

    // MARK: - Budget Loading (separate entity)

    private func loadBudgets(accountIDs: Set<UUID>) {
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
                let percentage = (spent / limit).doubleValue
                return BudgetSnapshot(
                    id: budget.id, name: name, spent: spent, limit: limit,
                    percentage: percentage, daysRemaining: budget.daysRemaining
                )
            }
        } catch {
            budgetSnapshots = []
        }
    }

    // MARK: - Widget Processing (from pre-fetched data)

    private func processSpendingByCategory(from expenses: [FinanceTransaction]) {
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
                name: name, amount: data.amount, color: data.color, icon: data.icon,
                percentage: String(format: "%.0f%%", percentage.doubleValue)
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func processTopExpenses(from expenses: [FinanceTransaction]) {
        topExpenses = Array(
            expenses
                .sorted { ($0.amount ?? Decimal(0)) > ($1.amount ?? Decimal(0)) }
                .prefix(5)
        )
    }

    private func processDailyFlow(from transactions: [FinanceTransaction], calendar: Calendar) {
        var grouped: [Date: DailyFlow] = [:]
        for tx in transactions {
            let day = calendar.startOfDay(for: tx.date)
            let amount = tx.amount ?? Decimal(0)
            if tx.type == .income {
                grouped[day, default: DailyFlow()].income += amount
            } else {
                grouped[day, default: DailyFlow()].expenses += amount
            }
        }
        dailyFlow = grouped
    }

    private func processTopPayees(from expenses: [FinanceTransaction]) {
        var payeeMap: [String: (total: Decimal, count: Int)] = [:]
        for tx in expenses {
            let name = tx.transactionDescription ?? tx.category?.name ?? "Altro"
            let existing = payeeMap[name] ?? (total: Decimal(0), count: 0)
            payeeMap[name] = (total: existing.total + (tx.amount ?? Decimal(0)), count: existing.count + 1)
        }
        topPayeesData = payeeMap.map { PayeeData(name: $0.key, totalAmount: $0.value.total, transactionCount: $0.value.count) }
            .sorted { $0.totalAmount > $1.totalAmount }.prefix(7).map { $0 }
    }

    private func processSpendingAnomalies(
        from relevantExpenses: [FinanceTransaction],
        calendar: Calendar,
        now: Date,
        startOfMonth: Date,
        endOfMonth: Date
    ) {
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else {
            spendingAnomalies = []
            return
        }

        let expenses = relevantExpenses.filter { $0.date >= threeMonthsAgo && $0.date < endOfMonth }

        var currentByCategory: [String: Decimal] = [:]
        var categoryMeta: [String: (color: String, icon: String)] = [:]

        for expense in expenses {
            let catName = expense.category?.name ?? "Altro"
            if categoryMeta[catName] == nil {
                categoryMeta[catName] = (
                    color: expense.category?.color ?? "#9E9E9E",
                    icon: expense.category?.icon ?? "questionmark.circle"
                )
            }
            if expense.date >= startOfMonth && expense.date < endOfMonth {
                currentByCategory[catName, default: Decimal(0)] += expense.amount ?? Decimal(0)
            }
        }

        let historicalMonths = max(1, calendar.dateComponents([.month], from: threeMonthsAgo, to: startOfMonth).month ?? 1)
        var historicalTotalByCategory: [String: Decimal] = [:]
        for expense in expenses where expense.date < startOfMonth {
            let catName = expense.category?.name ?? "Altro"
            historicalTotalByCategory[catName, default: Decimal(0)] += expense.amount ?? Decimal(0)
        }

        var anomalies: [SpendingAnomaly] = []
        for (catName, currentAmount) in currentByCategory {
            let avg = (historicalTotalByCategory[catName] ?? Decimal(0)) / Decimal(historicalMonths)
            guard avg > 0 else { continue }
            let ratio = ( currentAmount / avg).doubleValue
            if ratio > 1.5 {
                let meta = categoryMeta[catName] ?? (color: "#9E9E9E", icon: "questionmark.circle")
                let severity: AnomalySeverity
                if ratio > 3.0 { severity = .high }
                else if ratio > 2.0 { severity = .medium }
                else { severity = .low }

                anomalies.append(SpendingAnomaly(
                    categoryName: catName, categoryColor: meta.color, icon: meta.icon,
                    amount: currentAmount, average: avg,
                    deviationPercent: (ratio - 1.0) * 100, severity: severity
                ))
            }
        }
        spendingAnomalies = anomalies.sorted { $0.deviationPercent > $1.deviationPercent }.prefix(5).map { $0 }
    }

    private func processCategoryTrends(from relevantExpenses: [FinanceTransaction], calendar: Calendar, now: Date) {
        let monthsBack = 6
        guard let startDate = calendar.date(byAdding: .month, value: -monthsBack + 1, to: now) else { categoryTrends = []; return }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
        let endOfCurrentMonth = calendar.date(byAdding: .month, value: 1,
            to: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)!

        let expenses = relevantExpenses.filter { $0.date >= start && $0.date < endOfCurrentMonth }

        var data: [String: (color: String, icon: String, months: [Int: Decimal])] = [:]
        for expense in expenses {
            let catName = expense.category?.name ?? "Altro"
            let amount = expense.amount ?? Decimal(0)
            let monthIndex = calendar.dateComponents([.month], from: start, to: expense.date).month ?? 0
            if data[catName] == nil {
                data[catName] = (color: expense.category?.color ?? "#9E9E9E", icon: expense.category?.icon ?? "questionmark.circle", months: [:])
            }
            data[catName]!.months[monthIndex, default: Decimal(0)] += amount
        }

        categoryTrends = data.map { catName, info in
            let amounts = (0..<monthsBack).map { info.months[$0] ?? Decimal(0) }
            let currentMonth = amounts.last ?? Decimal(0)
            let previousMonth = amounts.count >= 2 ? amounts[amounts.count - 2] : Decimal(0)
            return CategoryTrendData(name: catName, color: info.color, icon: info.icon,
                monthlyAmounts: amounts, currentMonth: currentMonth, isIncreasing: currentMonth > previousMonth)
        }
        .filter { $0.monthlyAmounts.contains { $0 > 0 } }
        .sorted { $0.currentMonth > $1.currentMonth }
        .prefix(8).map { $0 }
    }

    private func processWeekdaySpending(from relevantExpenses: [FinanceTransaction], calendar: Calendar, now: Date) {
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else { weekdaySpending = []; return }

        let expenses = relevantExpenses.filter { $0.date >= threeMonthsAgo }
        var totals: [Int: Decimal] = [:]

        for tx in expenses {
            let weekday = calendar.component(.weekday, from: tx.date)
            totals[weekday, default: Decimal(0)] += tx.amount ?? Decimal(0)
        }

        let totalDays = calendar.dateComponents([.day], from: threeMonthsAgo, to: now).day ?? 90
        let weeksInPeriod = max(1, totalDays / 7)
        let dayNames = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
        let fullNames = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]
        let mondayOrder = [2, 3, 4, 5, 6, 7, 1]

        weekdaySpending = mondayOrder.enumerated().map { index, weekday in
            WeekdaySpending(weekday: weekday, label: dayNames[index], fullName: fullNames[index],
                amount: (totals[weekday] ?? Decimal(0)) / Decimal(weeksInPeriod))
        }
    }

    private func processCashFlowForecast(
        relevant: [FinanceTransaction],
        relevantRecurring: [FinanceTransaction],
        contiIDs: Set<UUID>,
        calendar: Calendar,
        now: Date
    ) {
        let today = calendar.startOfDay(for: now)
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else { cashFlowForecast = []; return }

        let historicalTx = relevant.filter { $0.date >= threeMonthsAgo }

        let weeks = max(1.0, abs(threeMonthsAgo.timeIntervalSince(now)) / (7 * 86400))
        var histWeeklyIncome = Decimal(0)
        var histWeeklyExpenses = Decimal(0)

        for tx in historicalTx {
            let amount = tx.amount ?? Decimal(0)
            if tx.type == .income, let toId = tx.toContoId, contiIDs.contains(toId) {
                histWeeklyIncome += amount
            } else if tx.type == .expense, let fromId = tx.fromContoId, contiIDs.contains(fromId) {
                histWeeklyExpenses += amount
            }
        }
        histWeeklyIncome /= Decimal(weeks)
        histWeeklyExpenses /= Decimal(weeks)

        let weekLabels = ["Sett. 1", "Sett. 2", "Sett. 3", "Sett. 4"]
        var forecast: [CashFlowWeek] = []

        for weekIndex in 0..<4 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex, to: today),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: weekIndex + 1, to: today) else { continue }

            var weekIncome = histWeeklyIncome
            var weekExpenses = histWeeklyExpenses

            for tx in relevantRecurring {
                guard tx.isRecurrenceActive(),
                      let nextDate = tx.nextRecurrenceDate(),
                      nextDate >= weekStart && nextDate < weekEnd else { continue }

                let amount = tx.amount ?? Decimal(0)
                if tx.type == .income { weekIncome += amount }
                else if tx.type == .expense { weekExpenses += amount }
            }

            forecast.append(CashFlowWeek(label: weekLabels[weekIndex], projectedIncome: weekIncome, projectedExpenses: weekExpenses))
        }
        cashFlowForecast = forecast
    }

    private func processUpcomingRecurring(from recurring: [FinanceTransaction]) {
        upcomingRecurring = recurring
            .filter { $0.isRecurrenceActive() }
            .compactMap { tx -> (transaction: FinanceTransaction, nextDate: Date)? in
                guard let next = tx.nextRecurrenceDate() else { return nil }
                return (transaction: tx, nextDate: next)
            }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(5).map { $0 }
    }

    // MARK: - Derived Processing (no fetch needed)

    private func computeHealthScore() {
        var savingsPoints: Double = 0
        if viewModel.monthlyIncome > 0 {
            let rate = ( cachedMonthlySavings / viewModel.monthlyIncome).doubleValue
            savingsPoints = min(30, max(0, rate * 150))
        }

        var budgetPoints: Double = 25
        if !budgetSnapshots.isEmpty {
            let underBudget = budgetSnapshots.filter { $0.percentage < 1.0 }.count
            budgetPoints = 25 * Double(underBudget) / Double(budgetSnapshots.count)
        }

        var incomePoints: Double = 10
        let trend = viewModel.monthlyExpensesTrend
        if trend.count >= 3 {
            let incomes = trend.suffix(6).map { $0.income.doubleValue }
            let mean = incomes.reduce(0, +) / Double(incomes.count)
            if mean > 0 {
                let variance = incomes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(incomes.count)
                let cv = sqrt(variance) / mean
                incomePoints = min(20, max(0, 20 * (1 - cv * 2)))
            }
        }

        var spendingPoints: Double = 12.5
        if trend.count >= 2 {
            let recentExpenses = trend.suffix(3).map { $0.expenses.doubleValue }
            if recentExpenses.count >= 2, let last = recentExpenses.last, let first = recentExpenses.first, first > 0 {
                let changeRate = (last - first) / first
                spendingPoints = min(25, max(0, 25 * (1 - changeRate)))
            }
        }

        healthScore = FinancialHealthResult(
            score: savingsPoints + budgetPoints + incomePoints + spendingPoints,
            savingsPoints: savingsPoints,
            budgetPoints: budgetPoints,
            incomePoints: incomePoints,
            spendingPoints: spendingPoints
        )
    }

    private func processIncomeVsExpenses() {
        let trend = viewModel.monthlyExpensesTrend
        guard trend.count >= 2 else { incomeVsExpensesData = []; return }
        incomeVsExpensesData = trend.suffix(6).map {
            MonthlyIncomeExpense(label: $0.month, income: $0.income, expenses: $0.expenses)
        }
    }

    private func processSavingsGoal(calendar: Calendar, now: Date) {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: now)
        let daysRemaining = daysInMonth - dayOfMonth

        let trend = viewModel.monthlyExpensesTrend
        var monthlyTarget = Decimal(0)
        if trend.count >= 3 {
            let positiveSavings = trend.suffix(3).map { $0.income - $0.expenses }.filter { $0 > 0 }
            if !positiveSavings.isEmpty {
                monthlyTarget = positiveSavings.reduce(Decimal(0), +) / Decimal(positiveSavings.count)
            }
        }

        let currentSavings = viewModel.monthlyIncome - viewModel.monthlyExpenses
        let progressPercent = monthlyTarget > 0
            ? ( currentSavings / monthlyTarget * 100).doubleValue : 0
        let remaining = max(Decimal(0), monthlyTarget - currentSavings)
        let dailySavingsRate = dayOfMonth > 0 ? currentSavings / Decimal(dayOfMonth) : Decimal(0)
        let projectedEndOfMonth = dailySavingsRate * Decimal(daysInMonth)

        savingsGoalData = SavingsGoalData(
            monthlyTarget: monthlyTarget, currentSavings: currentSavings,
            progressPercent: progressPercent, remaining: remaining,
            daysRemaining: daysRemaining, projectedEndOfMonth: projectedEndOfMonth,
            onTrack: projectedEndOfMonth >= monthlyTarget
        )
    }
}

// MARK: - Preview

#Preview {
    UnifiedDashboardView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
