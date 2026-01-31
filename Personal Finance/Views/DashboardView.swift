//
//  DashboardView.swift
//  Personal Finance
//
//  Dashboard principale con grafici d'impatto
//

import SwiftUI
import SwiftData
import Charts
import FinanceCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Computed data
    private var account: Account? { appState.selectedAccount }

    private var allTransactions: [FinanceTransaction] {
        appState.allTransactions(for: account)
    }

    private var monthlyIncome: Decimal {
        calculateMonthlyIncome()
    }

    private var monthlyExpenses: Decimal {
        calculateMonthlyExpenses()
    }

    private var monthlySavings: Decimal {
        monthlyIncome - monthlyExpenses
    }

    private var totalBalance: Decimal {
        account?.totalBalance ?? 0
    }

    private var isPositive: Bool {
        monthlySavings >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Hero: Saldo totale con indicatore
                    balanceHeroSection

                    // Grafici in grid adattiva
                    chartsSection

                    // Entrate / Uscite / Risparmi
                    monthlyStatsSection

                    // I tuoi conti
                    contiSection

                    // Ultime transazioni
                    recentTransactionsSection
                }
                .padding()
                .padding(.bottom, 100) // Spazio per FAB
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    accountSwitcher
                }
            }
        }
    }

    // MARK: - Balance Hero Section

    private var balanceHeroSection: some View {
        VStack(spacing: 16) {
            // Indicatore stato finanziario
            HStack {
                Circle()
                    .fill(isPositive ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(isPositive ? "Stai risparmiando" : "Attenzione: spese elevate")
                    .font(.subheadline)
                    .foregroundStyle(isPositive ? .green : .red)

                Spacer()
            }

            // Saldo totale
            VStack(alignment: .leading, spacing: 4) {
                Text("Saldo Totale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(totalBalance.currencyFormatted)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(totalBalance >= 0 ? .primary : .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Variazione mensile
            HStack {
                Image(systemName: monthlySavings >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(monthlySavings).currencyFormatted) questo mese")
                    .font(.callout)
            }
            .foregroundStyle(monthlySavings >= 0 ? .green : .red)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            // Andamento saldo
            balanceTrendChart

            // Distribuzione spese
            spendingDistributionChart
        }
    }

    private var balanceTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Andamento Saldo")
                .font(.headline)

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
                            Text(formatCompact(decimal))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 180)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var spendingDistributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dove vanno i soldi")
                .font(.headline)

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

                // Legenda
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
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Monthly Stats Section

    private var monthlyStatsSection: some View {
        HStack(spacing: 12) {
            StatCardView(
                title: "Entrate",
                value: monthlyIncome.currencyFormatted,
                icon: "arrow.down.circle.fill",
                color: .green
            )

            StatCardView(
                title: "Uscite",
                value: monthlyExpenses.currencyFormatted,
                icon: "arrow.up.circle.fill",
                color: .red
            )

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
            Text("I tuoi conti")
                .font(.headline)

            if appState.activeConti(for: account).isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il tuo primo conto")
                }
            } else {
                ForEach(appState.activeConti(for: account), id: \.id) { conto in
                    ContoRowView(conto: conto)
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
                Text("Ultime transazioni")
                    .font(.headline)

                Spacer()

                Button("Vedi tutte") {
                    appState.selectTab(.transactions)
                }
                .font(.subheadline)
            }

            if allTransactions.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna transazione", systemImage: "list.bullet")
                } description: {
                    Text("Le tue transazioni appariranno qui")
                }
            } else {
                ForEach(allTransactions.prefix(5), id: \.id) { transaction in
                    TransactionRowView(transaction: transaction)

                    if transaction.id != allTransactions.prefix(5).last?.id {
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
                Text(account?.name ?? "Account")
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }

    // MARK: - Data Calculations

    private func calculateMonthlyIncome() -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        return allTransactions
            .filter { transaction in
                guard let date = transaction.date,
                      transaction.type == .income else { return false }
                return date >= startOfMonth
            }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private func calculateMonthlyExpenses() -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        return allTransactions
            .filter { transaction in
                guard let date = transaction.date,
                      transaction.type == .expense else { return false }
                return date >= startOfMonth
            }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var balanceHistory: [BalanceDataPoint] {
        // Genera dati per gli ultimi 6 mesi
        let calendar = Calendar.current
        var data: [BalanceDataPoint] = []
        let currentBalance = totalBalance

        for i in (0..<6).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }

            // Calcola il saldo approssimativo per quel mese
            // basandosi sulle transazioni
            let monthTransactions = allTransactions.filter { transaction in
                guard let transactionDate = transaction.date else { return false }
                let transactionMonth = calendar.component(.month, from: transactionDate)
                let transactionYear = calendar.component(.year, from: transactionDate)
                let targetMonth = calendar.component(.month, from: date)
                let targetYear = calendar.component(.year, from: date)
                return transactionMonth == targetMonth && transactionYear == targetYear
            }

            let monthIncome = monthTransactions
                .filter { $0.type == .income }
                .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

            let monthExpenses = monthTransactions
                .filter { $0.type == .expense }
                .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

            // Stima semplificata del saldo
            let estimatedBalance = i == 0 ? currentBalance : currentBalance - (monthIncome - monthExpenses) * Decimal(i)

            data.append(BalanceDataPoint(date: date, balance: estimatedBalance))
        }

        return data
    }

    private var spendingByCategory: [SpendingCategory] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        // Raggruppa le spese per categoria
        var categoryTotals: [String: (amount: Decimal, color: String, icon: String)] = [:]

        let expenses = allTransactions.filter { transaction in
            guard let date = transaction.date,
                  transaction.type == .expense else { return false }
            return date >= startOfMonth
        }

        for expense in expenses {
            let categoryName = expense.category?.name ?? "Altro"
            let categoryColor = expense.category?.color ?? "#9E9E9E"
            let categoryIcon = expense.category?.icon ?? "questionmark.circle"
            let amount = expense.amount ?? 0

            if let existing = categoryTotals[categoryName] {
                categoryTotals[categoryName] = (existing.amount + amount, categoryColor, categoryIcon)
            } else {
                categoryTotals[categoryName] = (amount, categoryColor, categoryIcon)
            }
        }

        let total = categoryTotals.values.reduce(Decimal(0)) { $0 + $1.amount }

        return categoryTotals.map { name, data in
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
    }

    private func formatCompact(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if abs(doubleValue) >= 1000 {
            return String(format: "%.0fk", doubleValue / 1000)
        }
        return String(format: "%.0f", doubleValue)
    }
}

// MARK: - Data Models for Charts

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
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Conto")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(conto.type?.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(conto.balance.currencyFormatted)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(conto.balance >= 0 ? .primary : .red)
        }
        .padding(.vertical, 8)
    }
}

struct TransactionRowView: View {
    let transaction: FinanceTransaction

    private var isIncome: Bool {
        transaction.type == .income
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icona categoria
            Image(systemName: transaction.category?.icon ?? (isIncome ? "arrow.down.circle" : "arrow.up.circle"))
                .font(.title3)
                .foregroundStyle(Color(hex: transaction.category?.color ?? (isIncome ? "#4CAF50" : "#F44336")))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                    .font(.subheadline)
                    .lineLimit(1)

                if let date = transaction.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                .font(.subheadline)
                .fontWeight(.semibold)
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
