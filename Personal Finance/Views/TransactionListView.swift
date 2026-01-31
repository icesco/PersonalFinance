//
//  TransactionListView.swift
//  Personal Finance
//
//  Lista transazioni stile Excel - semplice e chiara
//

import SwiftUI
import SwiftData
import FinanceCore

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var selectedMonth: Date = Date()
    @State private var selectedType: TransactionTypeFilter = .all
    @State private var showingRecurring = false

    private var account: Account? { appState.selectedAccount }

    // Filtered transactions
    private var filteredTransactions: [FinanceTransaction] {
        var transactions = appState.allTransactions(for: account)

        // Filter by month
        let calendar = Calendar.current
        transactions = transactions.filter { transaction in
            guard let date = transaction.date else { return false }
            let transMonth = calendar.component(.month, from: date)
            let transYear = calendar.component(.year, from: date)
            let selectedMonthComp = calendar.component(.month, from: selectedMonth)
            let selectedYearComp = calendar.component(.year, from: selectedMonth)
            return transMonth == selectedMonthComp && transYear == selectedYearComp
        }

        // Filter by type
        if selectedType != .all {
            transactions = transactions.filter { transaction in
                switch selectedType {
                case .income: return transaction.type == .income
                case .expense: return transaction.type == .expense
                case .transfer: return transaction.type == .transfer
                case .all: return true
                }
            }
        }

        // Search filter
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                let descMatch = transaction.transactionDescription?.localizedCaseInsensitiveContains(searchText) ?? false
                let catMatch = transaction.category?.name?.localizedCaseInsensitiveContains(searchText) ?? false
                return descMatch || catMatch
            }
        }

        return transactions
    }

    // Recurring transactions
    private var recurringTransactions: [FinanceTransaction] {
        appState.allTransactions(for: account).filter { $0.isRecurring == true }
    }

    // Monthly totals
    private var monthlyIncome: Decimal {
        filteredTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var monthlyExpenses: Decimal {
        filteredTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month selector + Summary
                monthSelectorHeader

                // Type filter
                typeFilterBar

                // Transaction list
                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transazioni")
            .searchable(text: $searchText, prompt: "Cerca...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingRecurring = true
                        } label: {
                            Label("Ricorrenti", systemImage: "repeat")
                        }

                        Divider()

                        Button {
                            appState.presentQuickTransaction(type: .expense)
                        } label: {
                            Label("Nuova Spesa", systemImage: "minus.circle")
                        }

                        Button {
                            appState.presentQuickTransaction(type: .income)
                        } label: {
                            Label("Nuova Entrata", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingRecurring) {
                RecurringTransactionsSheet(transactions: recurringTransactions)
            }
        }
    }

    // MARK: - Month Selector Header

    private var monthSelectorHeader: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button {
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Spacer()

                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
            }
            .padding(.horizontal)

            // Monthly summary
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Entrate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("+\(monthlyIncome.currencyFormatted)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                Divider()
                    .frame(height: 30)

                VStack(spacing: 4) {
                    Text("Uscite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(monthlyExpenses.currencyFormatted)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                Divider()
                    .frame(height: 30)

                VStack(spacing: 4) {
                    Text("Bilancio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let balance = monthlyIncome - monthlyExpenses
                    Text(balance.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(balance >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Type Filter Bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TransactionTypeFilter.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.displayName,
                        isSelected: selectedType == type
                    ) {
                        withAnimation {
                            selectedType = type
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Transaction List (Excel-style)

    private var transactionList: some View {
        List {
            // Header row (Excel-style)
            if horizontalSizeClass == .regular {
                Section {
                    HStack {
                        Text("Data")
                            .frame(width: 100, alignment: .leading)
                        Text("Descrizione")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Categoria")
                            .frame(width: 120, alignment: .leading)
                        Text("Conto")
                            .frame(width: 100, alignment: .leading)
                        Text("Importo")
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color(.systemGray5))
                }
            }

            // Transaction rows
            ForEach(filteredTransactions, id: \.id) { transaction in
                if horizontalSizeClass == .regular {
                    // iPad: Table-style row
                    ExcelTransactionRow(transaction: transaction)
                        .swipeActions(edge: .trailing) {
                            Button("Elimina", role: .destructive) {
                                deleteTransaction(transaction)
                            }
                        }
                } else {
                    // iPhone: Compact row
                    CompactTransactionRow(transaction: transaction)
                        .swipeActions(edge: .trailing) {
                            Button("Elimina", role: .destructive) {
                                deleteTransaction(transaction)
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nessuna transazione", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Non ci sono transazioni per questo mese")
        } actions: {
            Button("Aggiungi transazione") {
                appState.presentQuickTransaction()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func deleteTransaction(_ transaction: FinanceTransaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Excel-style Transaction Row (iPad)

struct ExcelTransactionRow: View {
    let transaction: FinanceTransaction

    private var isIncome: Bool { transaction.type == .income }

    var body: some View {
        HStack {
            // Date
            if let date = transaction.date {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.subheadline)
                    .frame(width: 100, alignment: .leading)
            }

            // Description
            Text(transaction.transactionDescription ?? "-")
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Category
            HStack(spacing: 4) {
                if let icon = transaction.category?.icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: transaction.category?.color ?? "#007AFF"))
                }
                Text(transaction.category?.name ?? "-")
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            // Account
            Text(transaction.fromConto?.name ?? transaction.toConto?.name ?? "-")
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // Amount
            Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isIncome ? .green : .red)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compact Transaction Row (iPhone)

struct CompactTransactionRow: View {
    let transaction: FinanceTransaction

    private var isIncome: Bool { transaction.type == .income }

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: transaction.category?.icon ?? (isIncome ? "arrow.down.circle" : "arrow.up.circle"))
                .font(.title3)
                .foregroundStyle(Color(hex: transaction.category?.color ?? (isIncome ? "#4CAF50" : "#F44336")))
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let date = transaction.date {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                    }
                    Text("•")
                    Text(transaction.fromConto?.name ?? transaction.toConto?.name ?? "")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Amount + recurring indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isIncome ? .green : .red)

                if transaction.isRecurring == true {
                    HStack(spacing: 2) {
                        Image(systemName: "repeat")
                        Text(transaction.recurrenceFrequency?.displayName ?? "")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recurring Transactions Sheet

struct RecurringTransactionsSheet: View {
    let transactions: [FinanceTransaction]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna ricorrente", systemImage: "repeat")
                    } description: {
                        Text("Le transazioni ricorrenti (abbonamenti, mutuo, etc.) appariranno qui")
                    }
                } else {
                    List(transactions, id: \.id) { transaction in
                        CompactTransactionRow(transaction: transaction)
                    }
                }
            }
            .navigationTitle("Transazioni Ricorrenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Filter Enum

enum TransactionTypeFilter: CaseIterable {
    case all, income, expense, transfer

    var displayName: String {
        switch self {
        case .all: return "Tutte"
        case .income: return "Entrate"
        case .expense: return "Uscite"
        case .transfer: return "Trasferimenti"
        }
    }
}

// MARK: - Preview

#Preview {
    TransactionListView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
