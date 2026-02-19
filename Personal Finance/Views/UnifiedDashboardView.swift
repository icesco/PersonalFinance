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
    @Environment(AppStateManager.self) private var appState

    @Query private var allAccounts: [Account]

    @State private var viewModel = DashboardViewModel()
    @State private var spendingByCategory: [SpendingCategory] = []

    @State private var transactionToDetail: FinanceTransaction?
    @State private var transactionToEdit: FinanceTransaction?

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
                    // 1. Balance Hero
                    balanceHeroSection

                    // 2. Quick Actions
                    quickActionsSection

                    // 3. Monthly Stats (standard/advanced)
                    if experienceLevel.showDetailedMetrics {
                        monthlyStatsSection
                    }

                    // 4. Dove Vanno i Soldi (always visible)
                    spendingDistributionSection

                    // 5. Andamento Saldo (standard/advanced)
                    if experienceLevel.showDetailedMetrics {
                        balanceTrendSection
                    }

                    // 6. I Tuoi Conti (standard/advanced)
                    if experienceLevel.showDetailedMetrics {
                        contiSection
                    }

                    // 7. Ultime Transazioni
                    recentTransactionsSection
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
