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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    // Optional: pre-selected conto filter (for navigation from Dashboard)
    var initialConto: Conto? = nil
    var initialCategoryID: UUID? = nil
    var initialInterval: DateInterval? = nil
    var expensesOnly = false
    var scopeContoIDs: Set<UUID>? = nil

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
    @State private var transactionToEdit: FinanceTransaction?
    @State private var transactionToDelete: FinanceTransaction?
    @State private var showingDeleteAlert = false
    @State private var showingDeleteError = false

    // Selection mode
    @State private var isInSelectionMode = false
    @State private var selectedTransactions: Set<UUID> = []
    @State private var showingBatchDeleteAlert = false

    // Fetched data
    @State private var transactions: [FinanceTransaction] = []
    @State private var totalCount: Int = 0
    @State private var matchingIncome: Decimal = 0
    @State private var matchingExpenses: Decimal = 0
    @State private var isLoading = false

    // Pagination
    @State private var currentLimit: Int = 30
    private let pageSize: Int = 30

    private var currency: String { selectedConto?.account?.currency ?? account?.currency ?? "EUR" }
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
    private var periodIncome: Decimal { matchingIncome }
    private var periodExpenses: Decimal { matchingExpenses }

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
                if let initialInterval {
                    Text("\(initialInterval.start.formatted(date: .abbreviated, time: .omitted)) – \(initialInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline).padding()
                } else {
                    compactPeriodHeader
                }
                unifiedFiltersBar
                if isSearching {
                    TransactionSearchField(text: $searchText) {
                        searchText = ""
                        isSearching = false
                    }
                }
                if isLoading && transactions.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if transactions.isEmpty {
                    emptyState
                } else {
                    transactionList

                    if isInSelectionMode {
                        selectionBottomBar
                    }
                }
            }
            .themedBackground()
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { isSearching.toggle() }
                        if !isSearching { searchText = "" }
                    } label: { Label("Cerca movimenti", systemImage: "magnifyingglass") }
                }
                ToolbarItem(placement: .primaryAction) {
                    toolbarMenu
                }
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
            .sheet(item: $transactionToEdit) { transaction in
                EditTransactionView(transaction: transaction)
            }
            .onAppear {
                if let conto = initialConto, selectedConto == nil {
                    selectedConto = conto
                }
                if let initialCategoryID, selectedCategories.isEmpty {
                    selectedCategories = [initialCategoryID]
                }
                if expensesOnly { selectedType = .expense }
                fetchTransactions()
            }
            .onChange(of: selectedMonth) { _, _ in resetAndFetch() }
            .onChange(of: selectedTimeframe) { _, _ in resetAndFetch() }
            .onChange(of: selectedType) { _, _ in resetAndFetch() }
            .onChange(of: selectedConto) { _, _ in resetAndFetch() }
            .onChange(of: selectedCategories) { _, _ in resetAndFetch() }
            .onChange(of: searchText) { _, _ in resetAndFetch() }
            .onChange(of: appState.dataRefreshTrigger) { _, _ in fetchTransactions() }
        }
    }

    private var navigationTitle: String {
        selectedConto?.name ?? "Movimenti"
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
            if let conto = selectedConto ?? initialConto {
                NavigationLink {
                    BalanceHistoryView(bookID: conto.account?.id, contoID: conto.id)
                } label: {
                    Label("Saldo storico del conto", systemImage: "chart.xyaxis.line")
                }
            }
            Button {
                withAnimation {
                    isInSelectionMode.toggle()
                    if !isInSelectionMode {
                        selectedTransactions.removeAll()
                    }
                }
            } label: {
                Label(
                    isInSelectionMode ? "Fine selezione" : "Seleziona",
                    systemImage: isInSelectionMode ? "xmark.circle" : "checkmark.circle"
                )
            }

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
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    let component: Calendar.Component = selectedTimeframe == .month ? .month : .year
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: component, value: -1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(ForgiaPalette.surface, in: Circle())
                }

                Spacer()

                if selectedTimeframe == .month {
                    Text(selectedMonth.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "it_IT"))).localizedCapitalized)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                } else {
                    Text(selectedMonth, format: .dateTime.year())
                        .font(.system(.title3, design: .serif, weight: .semibold))
                }

                Spacer()

                Button {
                    let component: Calendar.Component = selectedTimeframe == .month ? .month : .year
                    withAnimation {
                        selectedMonth = Calendar.current.date(byAdding: component, value: 1, to: selectedMonth) ?? selectedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(ForgiaPalette.surface, in: Circle())
                }
                .disabled(isAtCurrentPeriod)
                .opacity(isAtCurrentPeriod ? 0.4 : 1)

                Menu {
                    ForEach(TransactionTimeframe.allCases, id: \.self) { timeframe in
                        Button {
                            withAnimation { selectedTimeframe = timeframe }
                        } label: {
                            Label(timeframe.displayName, systemImage: selectedTimeframe == timeframe ? "checkmark" : "calendar")
                        }
                    }
                } label: {
                    Text(selectedTimeframe.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(ForgiaPalette.surface, in: Capsule())
                }
            }

            let summaryLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
            summaryLayout {
                Text(balanceExplanation)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Button {
                    withAnimation { showSummaryDetail.toggle() }
                } label: {
                    Text((periodBalance >= 0 ? "+" : "") + periodBalance.formatted(.currency(code: currency)))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(periodBalance >= 0 ? ForgiaPalette.accent : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(periodBalance >= 0 ? ForgiaPalette.sageSurface : ForgiaPalette.apricotSurface, in: Capsule())
                }
            }

            // Expandable summary detail row
            if showSummaryDetail {
                VStack(spacing: 6) {
                    HStack(spacing: 16) {
                        Label("+\(periodIncome.formatted(.currency(code: currency)))", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ForgiaPalette.accent)
                        Label("-\(periodExpenses.formatted(.currency(code: currency)))", systemImage: "arrow.up.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text(balanceExplanation)
                        .font(.caption2)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(ForgiaPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Unified Filters Bar

    private var unifiedFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    Picker("Tipo di movimento", selection: $selectedType) {
                        ForEach(TransactionTypeFilter.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } label: {
                    Label(selectedType == .all ? "Tipo" : selectedType.displayName, systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(selectedType == .all ? ForgiaPalette.surface : ForgiaPalette.sageSurface, in: Capsule())
                }

                Menu {
                    Button("Tutti i conti") { selectedConto = nil }
                    ForEach(availableConti, id: \.id) { conto in
                        Button(conto.name ?? "Conto") { selectedConto = conto }
                    }
                } label: {
                    Label(selectedConto?.name ?? "Conto", systemImage: "creditcard")
                        .font(.subheadline.weight(selectedConto == nil ? .regular : .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedConto == nil ? ForgiaPalette.surface : ForgiaPalette.sageSurface, in: Capsule())
                }

                categoryFilterButton
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
    }

    private var categoryFilterButton: some View {
        Button { showingCategoryFilter = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag").font(.caption)
                Text(selectedCategories.isEmpty ? "Categorie" : "\(selectedCategories.count)")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .fontWeight(selectedCategories.isEmpty ? .regular : .semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selectedCategories.isEmpty ? ForgiaPalette.surface : ForgiaPalette.sageSurface)
            .foregroundStyle(selectedCategories.isEmpty ? Color.primary : ForgiaPalette.accent)
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
                        if isInSelectionMode {
                            Button {
                                toggleSelection(transaction)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedTransactions.contains(transaction.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedTransactions.contains(transaction.id) ? Color.accentColor : .secondary)
                                    TransactionCell(transaction: transaction, showConto: showContoInCell)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(ForgiaPalette.surface)
                        } else {
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionCell(transaction: transaction, showConto: showContoInCell)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    transactionToEdit = transaction
                                } label: {
                                    Label("Modifica", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Elimina", role: .destructive) {
                                    transactionToDelete = transaction
                                    showingDeleteAlert = true
                                }
                            }
                            .contextMenu {
                                Button {
                                    transactionToEdit = transaction
                                } label: {
                                    Label("Modifica", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    transactionToDelete = transaction
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                            .listRowBackground(ForgiaPalette.surface)
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
                    .foregroundStyle(section.isUpcoming ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                }
            }

            if hasMoreTransactions {
                loadMoreRow
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .alert("Elimina Transazione", isPresented: $showingDeleteAlert) {
            Button("Elimina", role: .destructive) {
                if let transaction = transactionToDelete {
                    deleteTransaction(transaction)
                }
                transactionToDelete = nil
            }
            Button("Annulla", role: .cancel) {
                transactionToDelete = nil
            }
        } message: {
            Text("Sei sicuro di voler eliminare questa transazione? Questa azione non può essere annullata.")
        }
        .alert("Impossibile eliminare", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Non è stato possibile completare la cancellazione. Aggiorna l’elenco e riprova.")
        }
        .alert("Elimina Transazioni", isPresented: $showingBatchDeleteAlert) {
            Button("Elimina \(selectedTransactions.count)", role: .destructive) {
                deleteSelectedTransactions()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Sei sicuro di voler eliminare \(selectedTransactions.count) transazioni? Questa azione non può essere annullata.")
        }
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
        .listRowBackground(ForgiaPalette.surface)
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
        guard account != nil || scopeContoIDs != nil else {
            transactions = []
            matchingIncome = 0
            matchingExpenses = 0
            totalCount = 0
            return
        }

        isLoading = true

        let calendar = Calendar.current
        let periodStart: Date
        let periodEnd: Date

        if let initialInterval {
            periodStart = initialInterval.start
            periodEnd = initialInterval.end
        } else if selectedTimeframe == .year {
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
        } else if let scopeContoIDs {
            contoIDs = scopeContoIDs
        } else {
            contoIDs = Set(account?.activeConti.map { $0.id } ?? [])
        }

        // Build fetch descriptor with predicate
        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        // Base predicate: date range (date is non-optional now)
        descriptor.predicate = #Predicate<FinanceTransaction> { transaction in
            transaction.date >= periodStart && transaction.date < periodEnd
        }

        // Filter the bounded period before paginating so categories cannot lose matches.

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

            totalCount = results.count
            matchingIncome = results.filter { $0.type == .income }.reduce(0) { $0 + ($1.amount ?? 0) }
            matchingExpenses = results.filter { $0.type == .expense }.reduce(0) { $0 + ($1.amount ?? 0) }
            transactions = Array(results.prefix(currentLimit))
        } catch {
            print("Error fetching transactions: \(error)")
            transactions = []
        }

        isLoading = false
    }

    private func resetAndFetch() {
        selectedTransactions.removeAll()
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

    // MARK: - Selection Mode

    private var selectionBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(selectedTransactions.count == transactions.count ? "Deseleziona tutto" : "Seleziona tutto") {
                    if selectedTransactions.count == transactions.count {
                        selectedTransactions.removeAll()
                    } else {
                        selectedTransactions = Set(transactions.map { $0.id })
                    }
                }
                .font(.subheadline)

                Spacer()

                Text("\(selectedTransactions.count) selezionate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Elimina", role: .destructive) {
                    showingBatchDeleteAlert = true
                }
                .font(.subheadline.weight(.semibold))
                .disabled(selectedTransactions.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func toggleSelection(_ transaction: FinanceTransaction) {
        if selectedTransactions.contains(transaction.id) {
            selectedTransactions.remove(transaction.id)
        } else {
            selectedTransactions.insert(transaction.id)
        }
    }

    private func deleteSelectedTransactions() {
        do {
            try TransactionDeletion(context: modelContext).delete(ids: selectedTransactions)
            selectedTransactions.removeAll()
            isInSelectionMode = false
            fetchTransactions()
            appState.triggerDataRefresh()
        } catch {
            showingDeleteError = true
        }
    }

    private func deleteTransaction(_ transaction: FinanceTransaction) {
        do {
            try TransactionDeletion(context: modelContext).delete(ids: [transaction.id])
            fetchTransactions()
            appState.triggerDataRefresh()
        } catch {
            showingDeleteError = true
        }
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
            .toolbarTitleDisplayMode(.inline)
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
            .toolbarTitleDisplayMode(.inline)
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

// MARK: - Transaction Cell

struct TransactionCell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let transaction: FinanceTransaction
    let showConto: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIncome: Bool { transaction.type == .income }
    private var isTransfer: Bool { transaction.type == .transfer }
    private var contoName: String? { transaction.fromConto?.name ?? transaction.toConto?.name }
    private var amountText: String {
        (isTransfer ? "" : isIncome ? "+" : "−") + (transaction.amount ?? 0).formatted(.currency(code: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR"))
    }
    private var iconName: String {
        transaction.category?.icon ?? (isTransfer ? "arrow.left.arrow.right" : isIncome ? "arrow.down.left" : "arrow.up.right")
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            AccessibleTransactionRow(transaction: transaction, showConto: showConto, amount: amountText)
        } else if horizontalSizeClass == .regular {
            tableRow
        } else {
            compactRow
        }
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isIncome ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                .frame(width: 44, height: 44)
                .background(isIncome ? ForgiaPalette.sageSurface : ForgiaPalette.canvas)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                    .font(.body.weight(.medium)).lineLimit(1)

                HStack(spacing: 4) {
                    Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))
                    if showConto, let conto = contoName {
                        Text("•")
                        Text(conto)
                    }
                }
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isIncome ? ForgiaPalette.accent : Color.primary)

                if transaction.isRecurring == true {
                    HStack(spacing: 2) {
                        Image(systemName: "repeat")
                        Text(transaction.recurrenceFrequency?.displayName ?? "")
                    }
                    .font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var tableRow: some View {
        HStack {
            Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))
                .font(.subheadline).frame(width: 80, alignment: .leading)

            Text(transaction.transactionDescription ?? "-")
                .font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if let icon = transaction.category?.icon {
                    Image(systemName: icon).font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                Text(transaction.category?.name ?? "-").font(.subheadline).lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            if showConto {
                Text(contoName ?? "-").font(.subheadline).lineLimit(1).frame(width: 100, alignment: .leading)
            }

            Text(amountText)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(isIncome ? ForgiaPalette.accent : Color.primary)
                .frame(width: 100, alignment: .trailing)

            if transaction.isRecurring == true {
                Image(systemName: "repeat").font(.caption).foregroundStyle(ForgiaPalette.mutedText).frame(width: 24)
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

private struct TransactionSearchField: View {
    @Binding var text: String
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cerca movimenti", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.search)
            Button(action: close) { Label("Chiudi ricerca", systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 12)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear { focused = true }
    }
}

private struct AccessibleTransactionRow: View {
    let transaction: FinanceTransaction
    let showConto: Bool
    let amount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transaction.transactionDescription ?? transaction.category?.name ?? "Transazione")
                .font(.body.weight(.medium))
            Text(amount)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(transaction.type == .income ? ForgiaPalette.accent : Color.primary)
            Text(transaction.date, format: .dateTime.day().month(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
            if showConto, let name = transaction.fromConto?.name ?? transaction.toConto?.name {
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            if transaction.isRecurring == true {
                Label(transaction.recurrenceFrequency?.displayName ?? "Ricorrente", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
