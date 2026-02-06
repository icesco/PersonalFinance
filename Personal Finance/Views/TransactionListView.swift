//
//  TransactionListView.swift
//  Personal Finance
//
//  Lista transazioni con query SwiftData efficienti
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

    // Filter states
    @State private var searchText = ""
    @State private var selectedMonth: Date = Date()
    @State private var selectedType: TransactionTypeFilter = .all
    @State private var selectedConto: Conto? = nil
    @State private var selectedCategories: Set<UUID> = []
    @State private var showingRecurring = false
    @State private var showingCategoryFilter = false
    @State private var showingTransferSheet = false
    @State private var selectedTimeframe: TransactionTimeframe = .month
    @State private var showSummaryDetail = false
    @State private var isSearching = false

    // Fetched data
    @State private var transactions: [FinanceTransaction] = []
    @State private var totalCount: Int = 0
    @State private var isLoading = false

    // Pagination
    @State private var currentLimit: Int = 30
    private let pageSize: Int = 30

    private var account: Account? { appState.selectedAccount }

    private var availableConti: [Conto] {
        appState.activeConti(for: account)
    }

    private var availableCategories: [FinanceCategory] {
        account?.categories?.filter { $0.isActive == true } ?? []
    }

    private var hasMoreTransactions: Bool {
        transactions.count >= currentLimit && transactions.count < totalCount
    }

    private var showContoInCell: Bool {
        selectedConto == nil
    }

    // Monthly totals (calculated from fetched transactions)
    private var periodIncome: Decimal {
        transactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var periodExpenses: Decimal {
        transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }

    private var activeFiltersCount: Int {
        var count = 0
        if selectedType != .all { count += 1 }
        if selectedConto != nil { count += 1 }
        if !selectedCategories.isEmpty { count += 1 }
        return count
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading && transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Cerca...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarMenu
                }
            }
            .safeAreaBar(edge: horizontalSizeClass == .compact ? .bottom : .top) {
                VStack(spacing: 0) {
                    compactPeriodHeader
                    unifiedFiltersBar
                }
                .padding(.bottom, horizontalSizeClass == .compact ? 8 : 0)
            }
            .sheet(isPresented: $showingRecurring) {
                RecurringTransactionsSheet(
                    contoIDs: contoIDsForQuery,
                    showConto: showContoInCell
                )
            }
            .sheet(isPresented: $showingCategoryFilter) {
                CategoryFilterSheet(
                    categories: availableCategories,
                    selectedCategories: $selectedCategories
                )
            }
            .sheet(isPresented: $showingTransferSheet) {
                CreateTransactionView(conto: availableConti.first, transactionType: .transfer)
            }
            .onAppear {
                if let conto = initialConto, selectedConto == nil {
                    selectedConto = conto
                }
                fetchTransactions()
            }
            .onChange(of: selectedMonth) { _, _ in resetAndFetch() }
            .onChange(of: selectedTimeframe) { _, _ in resetAndFetch() }
            .onChange(of: selectedType) { _, _ in resetAndFetch() }
            .onChange(of: selectedConto) { _, _ in resetAndFetch() }
            .onChange(of: selectedCategories) { _, _ in resetAndFetch() }
            .onChange(of: searchText) { _, _ in resetAndFetch() }
        }
    }

    private var navigationTitle: String {
        selectedConto?.name ?? "Transazioni"
    }

    private var contoIDsForQuery: Set<UUID> {
        if let conto = selectedConto {
            return [conto.id]
        }
        return Set(availableConti.map { $0.id })
    }

    // MARK: - Toolbar Menu

    private var toolbarMenu: some View {
        Menu {
            Button {
                withAnimation { showSummaryDetail.toggle() }
            } label: {
                Label(
                    showSummaryDetail ? "Nascondi dettagli" : "Mostra dettagli",
                    systemImage: showSummaryDetail ? "eye.slash" : "eye"
                )
            }

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

            // Transfer button - only show if there are at least 2 conti
            if availableConti.count >= 2 {
                Button {
                    showingTransferSheet = true
                } label: {
                    Label("Nuovo Trasferimento", systemImage: "arrow.left.arrow.right.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    // MARK: - Compact Period Header

    private var isAtCurrentPeriod: Bool {
        let granularity: Calendar.Component = selectedTimeframe == .month ? .month : .year
        return Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: granularity)
    }

    private var periodBalance: Decimal {
        periodIncome - periodExpenses
    }

    private var balanceExplanation: String {
        let hasFuture = transactions.contains { $0.date > Date() }
        if selectedTimeframe == .month {
            return hasFuture
                ? "Bilancio previsto a fine mese, incluse transazioni future"
                : "Bilancio del mese"
        } else {
            return hasFuture
                ? "Bilancio previsto per l'anno, incluse transazioni future"
                : "Bilancio dell'anno"
        }
    }

    private var compactPeriodHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Back chevron
                Button {
                    let component: Calendar.Component = selectedTimeframe == .month ? .month : .year
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: component, value: -1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                // Timeframe menu (M/A)
                Menu {
                    ForEach(TransactionTimeframe.allCases, id: \.self) { timeframe in
                        Button {
                            withAnimation { selectedTimeframe = timeframe }
                        } label: {
                            HStack {
                                Text(timeframe.displayName)
                                if selectedTimeframe == timeframe {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(selectedTimeframe == .month ? "M" : "A")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer()

                // Period label
                if selectedTimeframe == .month {
                    Text(selectedMonth, format: .dateTime.month(.wide).year())
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(selectedMonth, format: .dateTime.year())
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                // Balance capsule (tap to show detail)
                Button {
                    withAnimation { showSummaryDetail.toggle() }
                } label: {
                    Text((periodBalance >= 0 ? "+" : "") + periodBalance.currencyFormatted)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(periodBalance >= 0 ? Color.green : Color.red)
                        .clipShape(Capsule())
                }

                // Forward chevron
                Button {
                    let component: Calendar.Component = selectedTimeframe == .month ? .month : .year
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: component, value: 1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isAtCurrentPeriod)
                .opacity(isAtCurrentPeriod ? 0.4 : 1)
            }
            .padding(.horizontal)

            // Expandable summary detail row
            if showSummaryDetail {
                VStack(spacing: 6) {
                    HStack(spacing: 16) {
                        Label("+\(periodIncome.currencyFormatted)", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Label("-\(periodExpenses.currencyFormatted)", systemImage: "arrow.up.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                    }
                    Text(balanceExplanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Unified Filters Bar

    private var unifiedFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Type filters
                ForEach(TransactionTypeFilter.allCases, id: \.self) { type in
                    FilterChip(title: type.displayNameShort, isSelected: selectedType == type) {
                        withAnimation { selectedType = type }
                    }
                }

                Divider().frame(height: 24).padding(.horizontal, 2)

                // Conto filters
                FilterChip(title: "Tutti", isSelected: selectedConto == nil) {
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

                Divider().frame(height: 24).padding(.horizontal, 2)

                // Category filter
                categoryFilterButton
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private var categoryFilterButton: some View {
        Button { showingCategoryFilter = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag").font(.caption)
                Text(selectedCategories.isEmpty ? "Cat." : "\(selectedCategories.count)")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .fontWeight(selectedCategories.isEmpty ? .regular : .semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selectedCategories.isEmpty ? Color(.systemGray5) : Color.accentColor)
            .foregroundColor(selectedCategories.isEmpty ? .primary : .white)
            .clipShape(Capsule())
        }
    }

    // MARK: - Sectioning Logic

    private var sectionedTransactions: [TransactionSection] {
        if selectedTimeframe == .year {
            return buildYearSections()
        } else {
            return buildMonthSections()
        }
    }

    private func buildMonthSections() -> [TransactionSection] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let isCurrentMonth = calendar.isDate(selectedMonth, equalTo: now, toGranularity: .month)
        let isFutureMonth = startOfMonth > now

        if isCurrentMonth {
            let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
            let upcoming = transactions.filter { $0.date >= startOfTomorrow }.sorted { $0.date < $1.date }
            let past = transactions.filter { $0.date < startOfTomorrow }.sorted { $0.date > $1.date }

            var sections: [TransactionSection] = []
            if !upcoming.isEmpty {
                sections.append(TransactionSection(id: "upcoming", title: "In Arrivo", transactions: upcoming, isUpcoming: true))
            }
            if !past.isEmpty {
                sections.append(TransactionSection(id: "past", title: "Passate", transactions: past, isUpcoming: false))
            }
            return sections
        } else if isFutureMonth {
            return [TransactionSection(id: "upcoming", title: "In Arrivo", transactions: transactions.sorted { $0.date < $1.date }, isUpcoming: true)]
        } else {
            return [TransactionSection(id: "past", title: "Passate", transactions: transactions.sorted { $0.date > $1.date }, isUpcoming: false)]
        }
    }

    private func buildYearSections() -> [TransactionSection] {
        let calendar = Calendar.current
        let now = Date()
        let startOfTomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)

        // Group by (year, month)
        let grouped = Dictionary(grouping: transactions) { transaction in
            let comps = calendar.dateComponents([.year, .month], from: transaction.date)
            return comps
        }

        // Sort month groups newest-first
        let sortedKeys = grouped.keys.sorted { a, b in
            let dateA = calendar.date(from: a)!
            let dateB = calendar.date(from: b)!
            return dateA > dateB
        }

        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "MMMM yyyy"
            return f
        }()

        var sections: [TransactionSection] = []

        for key in sortedKeys {
            guard let monthTransactions = grouped[key] else { continue }
            let monthDate = calendar.date(from: key)!
            let monthName = monthFormatter.string(from: monthDate).localizedCapitalized
            let isCurrentMonth = calendar.isDate(monthDate, equalTo: now, toGranularity: .month)
            let isFutureMonth = monthDate > now && !isCurrentMonth

            if isCurrentMonth {
                let upcoming = monthTransactions.filter { $0.date >= startOfTomorrow }.sorted { $0.date < $1.date }
                let past = monthTransactions.filter { $0.date < startOfTomorrow }.sorted { $0.date > $1.date }

                if !upcoming.isEmpty {
                    sections.append(TransactionSection(
                        id: "upcoming-\(key.year!)-\(key.month!)",
                        title: "\(monthName) \u{00B7} In Arrivo",
                        transactions: upcoming,
                        isUpcoming: true
                    ))
                }
                if !past.isEmpty {
                    sections.append(TransactionSection(
                        id: "past-\(key.year!)-\(key.month!)",
                        title: "\(monthName) \u{00B7} Passate",
                        transactions: past,
                        isUpcoming: false
                    ))
                }
            } else if isFutureMonth {
                sections.append(TransactionSection(
                    id: "upcoming-\(key.year!)-\(key.month!)",
                    title: "\(monthName) \u{00B7} In Arrivo",
                    transactions: monthTransactions.sorted { $0.date < $1.date },
                    isUpcoming: true
                ))
            } else {
                sections.append(TransactionSection(
                    id: "past-\(key.year!)-\(key.month!)",
                    title: monthName,
                    transactions: monthTransactions.sorted { $0.date > $1.date },
                    isUpcoming: false
                ))
            }
        }

        return sections
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        List {
            ForEach(sectionedTransactions) { section in
                Section {
                    ForEach(section.transactions, id: \.id) { transaction in
                        TransactionCell(transaction: transaction, showConto: showContoInCell)
                            .swipeActions(edge: .trailing) {
                                Button("Elimina", role: .destructive) {
                                    deleteTransaction(transaction)
                                }
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        if section.isUpcoming {
                            Image(systemName: "clock")
                                .font(.caption)
                        }
                        Text(section.title)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(section.isUpcoming ? .blue : .secondary)
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
            loadMore()
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text("Carica altre transazioni")
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .listRowBackground(Color(.systemGroupedBackground))
        .disabled(isLoading)
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
                Text(selectedTimeframe == .year
                     ? "Nessuna transazione per questo anno"
                     : "Nessuna transazione per questo mese")
            }
        } actions: {
            VStack(spacing: 12) {
                Button("Aggiungi transazione") {
                    appState.presentQuickTransaction()
                }
                .buttonStyle(.borderedProminent)

                if activeFiltersCount > 0 {
                    Button("Rimuovi filtri") { clearAllFilters() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchTransactions() {
        guard let account = account else {
            transactions = []
            totalCount = 0
            return
        }

        isLoading = true

        let calendar = Calendar.current
        let periodStart: Date
        let periodEnd: Date

        if selectedTimeframe == .year {
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: selectedMonth))!
            periodStart = yearStart
            periodEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)!
        } else {
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
            periodStart = startOfMonth
            periodEnd = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        }

        // Get conto IDs to filter
        let contoIDs: Set<UUID>
        if let conto = selectedConto {
            contoIDs = [conto.id]
        } else {
            contoIDs = Set(account.activeConti.map { $0.id })
        }

        // Build fetch descriptor with predicate
        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        // Base predicate: date range (date is non-optional now)
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= periodStart && transaction.date < periodEnd
        }

        descriptor.fetchLimit = currentLimit

        do {
            // Fetch from database
            var results = try modelContext.fetch(descriptor)

            // Filter by conti (in-memory, but dataset is already reduced by date)
            results = results.filter { transaction in
                if let fromContoId = transaction.fromContoId, contoIDs.contains(fromContoId) {
                    return true
                }
                if let toContoId = transaction.toContoId, contoIDs.contains(toContoId) {
                    return true
                }
                return false
            }

            // Filter by type
            if selectedType != .all {
                results = results.filter { transaction in
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
                results = results.filter { transaction in
                    guard let categoryId = transaction.category?.id else { return false }
                    return selectedCategories.contains(categoryId)
                }
            }

            // Filter by search text
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                results = results.filter { transaction in
                    let descMatch = transaction.transactionDescription?.lowercased().contains(searchLower) ?? false
                    let catMatch = transaction.category?.name?.lowercased().contains(searchLower) ?? false
                    let contoMatch = (transaction.fromConto?.name?.lowercased().contains(searchLower) ?? false) ||
                                     (transaction.toConto?.name?.lowercased().contains(searchLower) ?? false)
                    return descMatch || catMatch || contoMatch
                }
            }

            // Count total (for pagination indicator)
            // For accurate count, fetch without limit
            var countDescriptor = FetchDescriptor<FinanceTransaction>()
            countDescriptor.predicate = descriptor.predicate
            totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? results.count

            transactions = results
        } catch {
            print("Error fetching transactions: \(error)")
            transactions = []
        }

        isLoading = false
    }

    private func resetAndFetch() {
        currentLimit = selectedTimeframe == .year ? pageSize * 4 : pageSize
        fetchTransactions()
    }

    private func loadMore() {
        currentLimit += pageSize
        fetchTransactions()
    }

    private func clearAllFilters() {
        withAnimation {
            selectedType = .all
            selectedConto = nil
            selectedCategories = []
            searchText = ""
        }
    }

    private func deleteTransaction(_ transaction: FinanceTransaction) {
        modelContext.delete(transaction)
        try? modelContext.save()
        fetchTransactions()

        // Notify dashboard to refresh
        appState.triggerDataRefresh()
    }
}

// MARK: - Recurring Transactions Sheet (with Query)

struct RecurringTransactionsSheet: View {
    let contoIDs: Set<UUID>
    let showConto: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var transactions: [FinanceTransaction] = []

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
            .onAppear { fetchRecurring() }
        }
    }

    private func fetchRecurring() {
        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.isRecurring == true
        }

        do {
            var results = try modelContext.fetch(descriptor)

            // Filter by conti
            results = results.filter { transaction in
                if let fromContoId = transaction.fromContoId, contoIDs.contains(fromContoId) {
                    return true
                }
                if let toContoId = transaction.toContoId, contoIDs.contains(toContoId) {
                    return true
                }
                return false
            }

            transactions = results
        } catch {
            transactions = []
        }
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
                            Text("Tutte le categorie").foregroundStyle(.primary)
                            Spacer()
                            if selectedCategories.isEmpty {
                                Image(systemName: "checkmark")
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
                        Button("Azzera") { selectedCategories.removeAll() }
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: FinanceCategory) -> some View {
        Button { toggleCategory(category) } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon ?? "tag")
                    .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                    .frame(width: 24)
                Text(category.name ?? "Categoria").foregroundStyle(.primary)
                Spacer()
                if selectedCategories.contains(category.id) {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func toggleCategory(_ category: FinanceCategory) {
        if selectedCategories.contains(category.id) {
            selectedCategories.remove(category.id)
        } else {
            selectedCategories.insert(category.id)
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
                    Image(systemName: icon).font(.caption)
                }
                Text(title).font(.subheadline)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
    private var contoName: String? { transaction.fromConto?.name ?? transaction.toConto?.name }

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
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)

                HStack(spacing: 4) {
                    Text(transaction.date, format: .dateTime.day().month(.abbreviated))
                    if showConto, let conto = contoName {
                        Text("•")
                        Text(conto)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(isIncome ? .green : .red)

                if transaction.isRecurring == true {
                    HStack(spacing: 2) {
                        Image(systemName: "repeat")
                        Text(transaction.recurrenceFrequency?.displayName ?? "")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var tableRow: some View {
        HStack {
            Text(transaction.date, format: .dateTime.day().month(.abbreviated))
                .font(.subheadline).frame(width: 80, alignment: .leading)

            Text(transaction.transactionDescription ?? "-")
                .font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let icon = transaction.category?.icon {
                    Image(systemName: icon).font(.caption)
                        .foregroundStyle(Color(hex: transaction.category?.color ?? "#007AFF"))
                }
                Text(transaction.category?.name ?? "-").font(.subheadline).lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            if showConto {
                Text(contoName ?? "-").font(.subheadline).lineLimit(1).frame(width: 100, alignment: .leading)
            }

            Text((isIncome ? "+" : "-") + (transaction.amount ?? 0).currencyFormatted)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(isIncome ? .green : .red)
                .frame(width: 100, alignment: .trailing)

            if transaction.isRecurring == true {
                Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary).frame(width: 24)
            } else {
                Spacer().frame(width: 24)
            }
        }
        .padding(.vertical, 4)
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

    var displayNameShort: String {
        switch self {
        case .all: return "Tutte"
        case .income: return "Ent."
        case .expense: return "Usc."
        case .transfer: return "Trasf."
        }
    }
}

// MARK: - Transaction Timeframe

enum TransactionTimeframe: String, CaseIterable {
    case month, year

    var displayName: String {
        switch self {
        case .month: return "Mese"
        case .year: return "Anno"
        }
    }
}

// MARK: - Transaction Section

private struct TransactionSection: Identifiable {
    let id: String
    let title: String
    let transactions: [FinanceTransaction]
    let isUpcoming: Bool
}

// MARK: - Preview

#Preview {
    TransactionListView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
