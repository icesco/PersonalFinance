//
//  DashboardView.swift
//  Personal Finance
//
//  Dashboard principale con grafici e query efficienti
//

import SwiftUI
import SwiftData
import Charts
import FinanceCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Fetched data
    @State private var monthlyIncome: Decimal = 0
    @State private var monthlyExpenses: Decimal = 0
    @State private var recentTransactions: [FinanceTransaction] = []
    @State private var spendingByCategory: [SpendingCategory] = []
    @State private var balanceHistory: [BalanceDataPoint] = []

    private var account: Account? { appState.selectedAccount }

    private var monthlySavings: Decimal { monthlyIncome - monthlyExpenses }
    private var totalBalance: Decimal { account?.totalBalance ?? 0 }
    private var isPositive: Bool { monthlySavings >= 0 }

    // Experience level computed properties
    private var experienceLevel: UserExperienceLevel {
        appState.experienceLevelManager.currentLevel
    }

    var body: some View {
        // Check dashboard style preference
        if appState.dashboardStyle == .crypto {
            CryptoDashboardView()
        } else {
            classicDashboardContent
        }
    }

    private var classicDashboardContent: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    balanceHeroSection

                    // Charts - only for standard and advanced
                    if experienceLevel.showDetailedMetrics {
                        chartsSection
                    }

                    // Monthly stats - for standard and advanced
                    if experienceLevel.showDetailedMetrics {
                        monthlyStatsSection
                    }

                    contiSection

                    recentTransactionsSection
                }
                .padding()
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    accountSwitcher
                }
            }
            .onAppear { loadDashboardData() }
            .onChange(of: appState.selectedAccount) { _, _ in loadDashboardData() }
            .onChange(of: appState.dataRefreshTrigger) { _, _ in loadDashboardData() }
        }
    }

    // MARK: - Data Loading

    private func loadDashboardData() {
        guard let account = account else {
            resetData()
            return
        }

        let contiIDs = Set(account.activeConti.map { $0.id })
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        // Load monthly transactions for income/expenses
        loadMonthlyTotals(contiIDs: contiIDs, startOfMonth: startOfMonth, endOfMonth: endOfMonth)

        // Load recent transactions (last 5)
        loadRecentTransactions(contiIDs: contiIDs)

        // Load spending by category
        loadSpendingByCategory(contiIDs: contiIDs, startOfMonth: startOfMonth, endOfMonth: endOfMonth)

        // Load balance history
        loadBalanceHistory(contiIDs: contiIDs)
    }

    private func resetData() {
        monthlyIncome = 0
        monthlyExpenses = 0
        recentTransactions = []
        spendingByCategory = []
        balanceHistory = []
    }

    private func loadMonthlyTotals(contiIDs: Set<UUID>, startOfMonth: Date, endOfMonth: Date) {
        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            // Filter by conti using denormalized indexed IDs
            let filtered = transactions.filter { transaction in
                if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                return false
            }

            // Calculate income: only count if toConto is in the filtered set
            monthlyIncome = filtered
                .filter { transaction in
                    guard transaction.type == .income else { return false }
                    if let toId = transaction.toContoId, contiIDs.contains(toId) {
                        return true
                    }
                    return false
                }
                .reduce(0) { $0 + ($1.amount ?? 0) }

            // Calculate expenses: only count if fromConto is in the filtered set
            monthlyExpenses = filtered
                .filter { transaction in
                    guard transaction.type == .expense else { return false }
                    if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                        return true
                    }
                    return false
                }
                .reduce(0) { $0 + ($1.amount ?? 0) }
        } catch {
            monthlyIncome = 0
            monthlyExpenses = 0
        }
    }

    private func loadRecentTransactions(contiIDs: Set<UUID>) {
        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 20 // Fetch a bit more, then filter

        do {
            let transactions = try modelContext.fetch(descriptor)

            let limit = experienceLevel.dashboardTransactionLimit

            recentTransactions = transactions
                .filter { transaction in
                    if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                    if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                    return false
                }
                .prefix(limit)
                .map { $0 }
        } catch {
            recentTransactions = []
        }
    }

    private func loadSpendingByCategory(contiIDs: Set<UUID>, startOfMonth: Date, endOfMonth: Date) {
        var descriptor = FetchDescriptor<FinanceTransaction>()
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= startOfMonth && transaction.date < endOfMonth
        }

        do {
            let transactions = try modelContext.fetch(descriptor)

            // Only include expenses where fromConto is in the filtered set
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
                let amount = expense.amount ?? 0

                if let existing = categoryTotals[name] {
                    categoryTotals[name] = (existing.amount + amount, color, icon)
                } else {
                    categoryTotals[name] = (amount, color, icon)
                }
            }

            let total = categoryTotals.values.reduce(Decimal(0)) { $0 + $1.amount }

            spendingByCategory = categoryTotals.map { name, data in
                let percentage = total > 0 ? (data.amount / total) * 100 : 0
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

    private func loadBalanceHistory(contiIDs: Set<UUID>) {
        let calendar = Calendar.current
        var data: [BalanceDataPoint] = []
        let currentBalance = totalBalance

        for i in (0..<6).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }

            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

            var descriptor = FetchDescriptor<FinanceTransaction>()
            descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
                transaction.date >= startOfMonth && transaction.date < endOfMonth
            }

            do {
                let transactions = try modelContext.fetch(descriptor)

                let filtered = transactions.filter { transaction in
                    if let id = transaction.fromContoId, contiIDs.contains(id) { return true }
                    if let id = transaction.toContoId, contiIDs.contains(id) { return true }
                    return false
                }

                // Calculate income: only count if toConto is in the filtered set
                let monthIncome = filtered
                    .filter { transaction in
                        guard transaction.type == .income else { return false }
                        guard let toId = transaction.toContoId else { return false }
                        return contiIDs.contains(toId)
                    }
                    .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

                // Calculate expenses: only count if fromConto is in the filtered set
                let monthExpenses = filtered
                    .filter { transaction in
                        guard transaction.type == .expense else { return false }
                        guard let fromId = transaction.fromContoId else { return false }
                        return contiIDs.contains(fromId)
                    }
                    .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

                let estimatedBalance = i == 0 ? currentBalance : currentBalance - (monthIncome - monthExpenses) * Decimal(i)
                data.append(BalanceDataPoint(date: monthDate, balance: estimatedBalance))
            } catch {
                data.append(BalanceDataPoint(date: monthDate, balance: currentBalance))
            }
        }

        balanceHistory = data
    }

    // MARK: - Balance Hero Section

    private var balanceHeroSection: some View {
        VStack(spacing: 16) {
            // Insights - only for standard and advanced
            if experienceLevel.showDetailedMetrics {
                HStack {
                    Circle()
                        .fill(isPositive ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(isPositive ? "Stai risparmiando" : "Attenzione: spese elevate")
                        .font(.subheadline)
                        .foregroundStyle(isPositive ? .green : .red)

                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(experienceLevel.balanceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(totalBalance.currencyFormatted)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(totalBalance >= 0 ? .primary : .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Monthly savings - only for standard and advanced
            if experienceLevel.showDetailedMetrics {
                HStack {
                    Image(systemName: monthlySavings >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(abs(monthlySavings).currencyFormatted) questo mese")
                        .font(.callout)
                }
                .foregroundStyle(monthlySavings >= 0 ? .green : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        let columns = horizontalSizeClass == .regular
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 16) {
            balanceTrendChart
            spendingDistributionChart
        }
    }

    private var balanceTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Andamento Saldo").font(.headline)

            if balanceHistory.isEmpty {
                ContentUnavailableView {
                    Label("Nessun dato", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("I dati appariranno qui")
                }
                .frame(height: 180)
            } else {
                Chart(balanceHistory) { item in
                    LineMark(
                        x: .value("Mese", item.date, unit: .month),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Mese", item.date, unit: .month),
                        y: .value("Saldo", item.balance)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.1).gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let decimal = value.as(Decimal.self) {
                                Text(formatCompact(decimal)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var spendingDistributionChart: some View {
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
                        innerRadius: .ratio(0.5),
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
                            Text(item.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(item.percentage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Monthly Stats Section

    private var monthlyStatsSection: some View {
        HStack(spacing: 12) {
            StatCardView(title: "Entrate", value: monthlyIncome.currencyFormatted, icon: "arrow.down.circle.fill", color: .green)
            StatCardView(title: "Uscite", value: monthlyExpenses.currencyFormatted, icon: "arrow.up.circle.fill", color: .red)
            StatCardView(
                title: "Risparmi",
                value: monthlySavings.currencyFormatted,
                icon: monthlySavings >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                color: monthlySavings >= 0 ? .green : .red
            )
        }
    }

    // MARK: - Conti Section

    private var contiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I tuoi conti").font(.headline)

            if appState.activeConti(for: account).isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il tuo primo conto")
                }
            } else {
                ForEach(appState.activeConti(for: account), id: \.id) { conto in
                    NavigationLink {
                        TransactionListView(initialConto: conto)
                    } label: {
                        ContoRowView(conto: conto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Recent Transactions Section

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ultimi \(experienceLevel.transactionsLabel.lowercased())")
                    .font(.headline)
                Spacer()
                Button("Vedi tutte") { appState.selectTab(.transactions) }
                    .font(.subheadline)
            }

            if recentTransactions.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna transazione", systemImage: "list.bullet")
                } description: {
                    Text("Le tue transazioni appariranno qui")
                }
            } else {
                ForEach(recentTransactions, id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)
                    if transaction.id != recentTransactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Account Switcher

    private var accountSwitcher: some View {
        Button {
            appState.presentAccountSelection()
        } label: {
            HStack(spacing: 4) {
                Text(account?.name ?? "Account").font(.subheadline)
                Image(systemName: "chevron.down").font(.caption)
            }
        }
    }

    private func formatCompact(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if abs(doubleValue) >= 1000 {
            return String(format: "%.0fk", doubleValue / 1000)
        }
        return String(format: "%.0f", doubleValue)
    }
}

// MARK: - Data Models

struct BalanceDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let balance: Decimal
}

struct SpendingCategory: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let color: String
    let icon: String
    let percentage: String
}

// MARK: - Supporting Views

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.subheadline).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct ContoRowView: View {
    let conto: Conto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conto.type?.icon ?? "creditcard")
                .font(.title3).frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Conto").font(.subheadline).fontWeight(.medium)
                Text(conto.type?.displayName ?? "").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(conto.balance.currencyFormatted)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(conto.balance >= 0 ? .primary : .red)
        }
        .padding(.vertical, 8)
    }
}

struct TransactionRowView: View {
    let transaction: FinanceTransaction

    private var isIncome: Bool { transaction.type == .income }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.icon ?? (isIncome ? "arrow.down.circle" : "arrow.up.circle"))
                .font(.title3)
                .foregroundStyle(Color(hex: transaction.category?.color ?? (isIncome ? "#4CAF50" : "#F44336")))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                    .font(.subheadline).lineLimit(1)

                Text(transaction.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isIncome ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
