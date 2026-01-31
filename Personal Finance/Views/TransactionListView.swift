//
//  TransactionListView.swift
//  Personal Finance
//
//  Lista transazioni unificata con filtri e paginazione
//

import SwiftUI
import SwiftData
import FinanceCore

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Optional: pre-selected conto filter (for navigation from Dashboard)
    var initialConto: Conto? = nil

    @State private var searchText = ""
    @State private var selectedMonth: Date = Date()
    @State private var selectedType: TransactionTypeFilter = .all
    @State private var selectedConto: Conto? = nil
    @State private var selectedCategories: Set<UUID> = []
    @State private var showingRecurring = false
    @State private var showingCategoryFilter = false

    // Pagination
    @State private var displayedCount: Int = 30
    private let pageSize: Int = 30

    private var account: Account? { appState.selectedAccount }

    private var availableConti: [Conto] {
        appState.activeConti(for: account)
    }

    private var availableCategories: [FinanceCategory] {
        account?.categories?.filter { $0.isActive == true } ?? []
    }

    // All transactions (before pagination)
    private var allFilteredTransactions: [FinanceTransaction] {
        var transactions: [FinanceTransaction]

        // Filter by conto if selected
        if let conto = selectedConto {
            transactions = conto.allTransactions
        } else {
            transactions = appState.allTransactions(for: account)
        }

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

        // Filter by categories
        if !selectedCategories.isEmpty {
            transactions = transactions.filter { transaction in
                guard let categoryId = transaction.category?.id else { return false }
                return selectedCategories.contains(categoryId)
            }
        }

        // Search filter
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                let descMatch = transaction.transactionDescription?.localizedCaseInsensitiveContains(searchText) ?? false
                let catMatch = transaction.category?.name?.localizedCaseInsensitiveContains(searchText) ?? false
                let contoMatch = (transaction.fromConto?.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                                 (transaction.toConto?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
                return descMatch || catMatch || contoMatch
            }
        }

        // Sort by date descending
        return transactions.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // Paginated transactions for display
    private var displayedTransactions: [FinanceTransaction] {
        Array(allFilteredTransactions.prefix(displayedCount))
    }

    private var hasMoreTransactions: Bool {
        displayedCount < allFilteredTransactions.count
    }

    // Show conto in cell only when viewing all conti
    private var showContoInCell: Bool {
        selectedConto == nil
    }

    // Recurring transactions
    private var recurringTransactions: [FinanceTransaction] {
        if let conto = selectedConto {
            return conto.allTransactions.filter { $0.isRecurring == true }
        }
        return appState.allTransactions(for: account).filter { $0.isRecurring == true }
    }

    // Monthly totals (based on filtered transactions)
    private var monthlyIncome: Decimal {
        allFilteredTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var monthlyExpenses: Decimal {
        allFilteredTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    // Active filters count (for badge)
    private var activeFiltersCount: Int {
        var count = 0
        if selectedType != .all { count += 1 }
        if selectedConto != nil { count += 1 }
        if !selectedCategories.isEmpty { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month selector + Summary
                monthSelectorHeader

                // Filters bar
                filtersBar

                // Transaction list with pagination
                if displayedTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .searchable(text: $searchText, prompt: "Cerca...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingRecurring = true
                        } label: {
                            Label("Ricorrenti", systemImage: "repeat")
                        }

                        if activeFiltersCount > 0 {
                            Divider()
                            Button(role: .destructive) {
                                clearAllFilters()
                            } label: {
                                Label("Rimuovi filtri", systemImage: "xmark.circle")
                            }
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
                RecurringTransactionsSheet(transactions: recurringTransactions, showConto: showContoInCell)
            }
            .sheet(isPresented: $showingCategoryFilter) {
                CategoryFilterSheet(
                    categories: availableCategories,
                    selectedCategories: $selectedCategories
                )
            }
            .onAppear {
                if let conto = initialConto, selectedConto == nil {
                    selectedConto = conto
                }
            }
            .onChange(of: selectedMonth) { _, _ in resetPagination() }
            .onChange(of: selectedType) { _, _ in resetPagination() }
            .onChange(of: selectedConto) { _, _ in resetPagination() }
            .onChange(of: selectedCategories) { _, _ in resetPagination() }
            .onChange(of: searchText) { _, _ in resetPagination() }
        }
    }

    private var navigationTitle: String {
        if let conto = selectedConto {
            return conto.name ?? "Transazioni"
        }
        return "Transazioni"
    }

    // MARK: - Month Selector Header

    private var monthSelectorHeader: some View {
        VStack(spacing: 12) {
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

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("Uscite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("-\(monthlyExpenses.currencyFormatted)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                Divider().frame(height: 30)

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

    // MARK: - Filters Bar

    private var filtersBar: some View {
        VStack(spacing: 8) {
            // Row 1: Type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TransactionTypeFilter.allCases, id: \.self) { type in
                        FilterChip(
                            title: type.displayName,
                            isSelected: selectedType == type
                        ) {
                            withAnimation { selectedType = type }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Row 2: Conto + Category filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Conto filter chips
                    FilterChip(
                        title: "Tutti i conti",
                        isSelected: selectedConto == nil
                    ) {
                        withAnimation { selectedConto = nil }
                    }

                    ForEach(availableConti, id: \.id) { conto in
                        FilterChip(
                            title: conto.name ?? "Conto",
                            icon: conto.type?.icon,
                            isSelected: selectedConto?.id == conto.id
                        ) {
                            withAnimation { selectedConto = conto }
                        }
                    }

                    Divider().frame(height: 24)

                    // Category filter button
                    categoryFilterButton
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var categoryFilterButton: some View {
        Button {
            showingCategoryFilter = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.caption)
                if selectedCategories.isEmpty {
                    Text("Categorie")
                } else {
                    Text("\(selectedCategories.count) categorie")
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .fontWeight(selectedCategories.isEmpty ? .regular : .semibold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selectedCategories.isEmpty ? Color(.systemGray5) : Color.accentColor)
            .foregroundStyle(selectedCategories.isEmpty ? .primary : .white)
            .clipShape(Capsule())
        }
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        List {
            ForEach(displayedTransactions, id: \.id) { transaction in
                TransactionCell(
                    transaction: transaction,
                    showConto: showContoInCell
                )
                .swipeActions(edge: .trailing) {
                    Button("Elimina", role: .destructive) {
                        deleteTransaction(transaction)
                    }
                }
            }

            if hasMoreTransactions {
                loadMoreRow
            }
        }
        .listStyle(.plain)
    }

    private var loadMoreRow: some View {
        Button {
            loadMoreTransactions()
        } label: {
            HStack {
                Spacer()
                Text("Carica altre \(min(pageSize, allFilteredTransactions.count - displayedCount)) transazioni")
                    .font(.subheadline)
                    .foregroundStyle(.accent)
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .listRowBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nessuna transazione", systemImage: "list.bullet.rectangle")
        } description: {
            if !selectedCategories.isEmpty {
                Text("Nessuna transazione per le categorie selezionate")
            } else if selectedConto != nil {
                Text("Nessuna transazione per questo conto")
            } else {
                Text("Nessuna transazione per questo mese")
            }
        } actions: {
            VStack(spacing: 12) {
                Button("Aggiungi transazione") {
                    appState.presentQuickTransaction()
                }
                .buttonStyle(.borderedProminent)

                if activeFiltersCount > 0 {
                    Button("Rimuovi filtri") {
                        clearAllFilters()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadMoreTransactions() {
        withAnimation { displayedCount += pageSize }
    }

    private func resetPagination() {
        displayedCount = pageSize
    }

    private func clearAllFilters() {
        withAnimation {
            selectedType = .all
            selectedConto = nil
            selectedCategories = []
        }
    }

    private func deleteTransaction(_ transaction: FinanceTransaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
    }
}

// MARK: - Category Filter Sheet

struct CategoryFilterSheet: View {
    let categories: [FinanceCategory]
    @Binding var selectedCategories: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    private var sortedCategories: [FinanceCategory] {
        categories.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedCategories.removeAll()
                    } label: {
                        HStack {
                            Text("Tutte le categorie")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategories.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                }

                Section("Seleziona categorie") {
                    ForEach(sortedCategories, id: \.id) { category in
                        categoryRow(category)
                    }
                }
            }
            .navigationTitle("Filtra per Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }

                ToolbarItem(placement: .cancellationAction) {
                    if !selectedCategories.isEmpty {
                        Button("Azzera") {
                            selectedCategories.removeAll()
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: FinanceCategory) -> some View {
        Button {
            toggleCategory(category)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon ?? "tag")
                    .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                    .frame(width: 24)

                Text(category.name ?? "Categoria")
                    .foregroundStyle(.primary)

                Spacer()

                if let id = category.id, selectedCategories.contains(id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    private func toggleCategory(_ category: FinanceCategory) {
        guard let id = category.id else { return }
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Transaction Cell

struct TransactionCell: View {
    let transaction: FinanceTransaction
    let showConto: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIncome: Bool { transaction.type == .income }
    private var contoName: String? {
        transaction.fromConto?.name ?? transaction.toConto?.name
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            tableRow
        } else {
            compactRow
        }
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.icon ?? (isIncome ? "arrow.down.circle" : "arrow.up.circle"))
                .font(.title3)
                .foregroundStyle(Color(hex: transaction.category?.color ?? (isIncome ? "#4CAF50" : "#F44336")))
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let date = transaction.date {
                        Text(date, format: .dateTime.day().month(.abbreviated))
                    }
                    if showConto, let conto = contoName {
                        Text("•")
                        Text(conto)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

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

    private var tableRow: some View {
        HStack {
            if let date = transaction.date {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.subheadline)
                    .frame(width: 80, alignment: .leading)
            }

            Text(transaction.transactionDescription ?? "-")
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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

            if showConto {
                Text(contoName ?? "-")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
            }

            Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isIncome ? .green : .red)
                .frame(width: 100, alignment: .trailing)

            if transaction.isRecurring == true {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Spacer().frame(width: 24)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recurring Transactions Sheet

struct RecurringTransactionsSheet: View {
    let transactions: [FinanceTransaction]
    let showConto: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna ricorrente", systemImage: "repeat")
                    } description: {
                        Text("Le transazioni ricorrenti appariranno qui")
                    }
                } else {
                    List(transactions, id: \.id) { transaction in
                        TransactionCell(transaction: transaction, showConto: showConto)
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
