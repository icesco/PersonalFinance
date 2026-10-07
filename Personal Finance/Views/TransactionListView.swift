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
    /// Pushed from another screen: reuse that navigation stack instead of nesting a new one.
    var isPushed = false
    /// Title shown when pushed, e.g. the category being reviewed.
    var pushedTitle: String? = nil

    // Filter states
    @State private var selectedMonth: Date = Date()
    @State private var selectedType: TransactionTypeFilter = .all
    @State private var selectedConto: Conto? = nil
    @State private var selectedCategories: Set<UUID> = []
    @State private var showingRecurring = false
    @State private var showingCategoryFilter = false
    @Query private var allCategories: [FinanceCategory]
    @State private var selectedTimeframe: TransactionTimeframe = .month
    #if os(macOS)
    @State private var desktopSelection: Set<UUID> = []
    @State private var desktopDetail: FinanceTransaction?
    #endif
    @State private var transactionToEdit: FinanceTransaction?
    @State private var transactionToDelete: FinanceTransaction?
    @State private var showingDeleteAlert = false
    @State private var showingDeleteError = false

    // Selection mode
    @State private var isInSelectionMode = false
    @State private var selectedTransactions: Set<UUID> = []
    @State private var showingBatchDeleteAlert = false

    // Loaded pages and whole-period totals
    @State private var transactions: [FinanceTransaction] = []
    @State private var summary = TransactionListSummary()
    @State private var hasLoaded = false
    @State private var didApplyInitialFilters = false
    @State private var isScrolledDown = false
    private let pageSize = 40

    private var currency: String { selectedConto?.account?.currency ?? account?.currency ?? "EUR" }
    private var account: Account? { appState.selectedAccount }

    private var availableConti: [Conto] {
        appState.activeConti(for: account)
    }

    private var availableCategories: [FinanceCategory] {
        account?.categories?.filter { $0.isActive == true } ?? []
    }

    private var hasMoreTransactions: Bool {
        transactions.count < summary.count
    }

    /// Every filter the store evaluates; any change reloads from the first page.
    private var currentQuery: TransactionListQuery {
        let contoIDs: Set<UUID>
        if let selectedConto {
            contoIDs = [selectedConto.id]
        } else if let scopeContoIDs {
            contoIDs = scopeContoIDs
        } else {
            contoIDs = Set(availableConti.map(\.id))
        }
        return TransactionListQuery(
            interval: initialInterval ?? selectedTimeframe.interval(containing: selectedMonth),
            contoIDs: contoIDs,
            type: selectedType.transactionType,
            categoryIDs: CategoryHierarchy(categories: allCategories).expanding(selectedCategories)
        )
    }

    private var showContoInCell: Bool {
        selectedConto == nil
    }

    private var periodIncome: Decimal { summary.income }
    private var periodExpenses: Decimal { summary.expenses }

    private var activeFiltersCount: Int {
        var count = 0
        if selectedType != .all { count += 1 }
        if selectedConto != nil { count += 1 }
        if !selectedCategories.isEmpty { count += 1 }
        return count
    }

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack { content }
                .transactionButtonRoot(.transactions, isActive: !isInSelectionMode)
        }
    }

    private var content: some View {
            VStack(spacing: 0) {
                if !hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    transactionList

                    if isInSelectionMode {
                        selectionBottomBar
                    }
                }
            }
            .themedBackground()
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let initialInterval {
                        Text("\(initialInterval.start.formatted(date: .abbreviated, time: .omitted)) – \(initialInterval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .padding(.top, 4)
                    } else {
                        compactPeriodHeader
                    }
                    unifiedFiltersBar
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(isPushed || initialConto != nil ? .visible : .hidden, for: .navigationBar)
            #endif
            .financePresentation(isPresented: $showingRecurring, title: "Ricorrenze", width: 800) {
                NavigationStack {
                    RecurringManagementView(contoIDs: contoIDsForQuery)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                FinanceTaskDoneButton()
                            }
                        }
                }
            }
            .sheet(isPresented: $showingCategoryFilter) {
                CategoryFilterSheet(
                    categories: availableCategories,
                    selectedCategories: $selectedCategories
                )
            }
            .financePresentation(item: $transactionToEdit, title: "Modifica movimento") { transaction in
                EditTransactionView(transaction: transaction)
            }
            .onAppear {
                guard !didApplyInitialFilters else {
                    reload(keepingLoadedRows: true)
                    return
                }
                didApplyInitialFilters = true
                if let conto = initialConto, selectedConto == nil {
                    selectedConto = conto
                }
                if let initialCategoryID, selectedCategories.isEmpty {
                    selectedCategories = [initialCategoryID]
                }
                if expensesOnly { selectedType = .expense }
                reload()
            }
            .onChange(of: currentQuery) { _, _ in reload() }
            .onChange(of: appState.dataRefreshTrigger) { _, _ in reload(keepingLoadedRows: true) }
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

    private var navigationTitle: String {
        if isPushed, initialCategoryID != nil {
            return selectedCategories.isEmpty ? "Movimenti" : categoryFilterTitle
        }
        return pushedTitle ?? initialConto?.name ?? (isPushed ? "Movimenti" : desktopTitle)
    }

    private var desktopTitle: String {
        #if os(macOS)
        "Movimenti"
        #else
        ""
        #endif
    }

    private var contoIDsForQuery: Set<UUID> {
        if let conto = selectedConto {
            return [conto.id]
        }
        return Set(availableConti.map { $0.id })
    }

    // MARK: - Compact Period Header

    private var isAtCurrentPeriod: Bool {
        selectedTimeframe.interval(containing: selectedMonth).end > Date()
    }

    private var periodBalance: Decimal {
        periodIncome - periodExpenses
    }

    private var summaryTitle: String {
        initialInterval != nil ? "Bilancio del periodo" : selectedTimeframe.balanceTitle
    }

    /// Future-dated rows sort first, so the first loaded page is enough to tell.
    private var includesFutureTransactions: Bool {
        transactions.first.map { $0.date > Date() } ?? false
    }

    private var compactPeriodHeader: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button {
                    selectedMonth = selectedTimeframe.moving(selectedMonth, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 44, height: 44)

                Spacer()

                Menu {
                    Picker("Granularità", selection: $selectedTimeframe) {
                        ForEach(TransactionTimeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.displayName).tag(timeframe)
                        }
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(selectedTimeframe.title(containing: selectedMonth))
                                .font(.system(.title3, design: .serif, weight: .semibold))
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                        if let subtitle = selectedTimeframe.subtitle(containing: selectedMonth) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }.frame(minHeight: 44)
                }
                .accessibilityIdentifier("transactions-period-menu")

                Spacer()

                Button {
                    selectedMonth = selectedTimeframe.moving(selectedMonth, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 44, height: 44)
                .disabled(isAtCurrentPeriod)
                .opacity(isAtCurrentPeriod ? 0.4 : 1)

            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var periodSummary: some View {
        PeriodSummaryCard(
            title: summaryTitle,
            summary: summary,
            currency: currency,
            includesFuture: includesFutureTransactions
        )
    }

    // MARK: - Unified Filters Bar

    private var unifiedFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 0) {
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
                            .frame(minHeight: 30)
                    }
                    .tint(selectedType == .all ? nil : ForgiaPalette.accent)

                    Menu {
                        Button("Tutti i conti") { selectedConto = nil }
                        ForEach(availableConti, id: \.id) { conto in
                            Button(conto.name ?? "Conto") { selectedConto = conto }
                        }
                        if let conto = selectedConto ?? initialConto {
                            Divider()
                            NavigationLink {
                                BalanceHistoryView(bookID: conto.account?.id, contoID: conto.id)
                            } label: {
                                Label("Saldo storico del conto", systemImage: "chart.xyaxis.line")
                            }
                        }
                    } label: {
                        Label(selectedConto?.name ?? "Conto", systemImage: "creditcard")
                            .font(.subheadline.weight(selectedConto == nil ? .regular : .semibold))
                            .frame(minHeight: 30)
                    }
                    .tint(selectedConto == nil ? nil : ForgiaPalette.accent)

                    categoryFilterButton
                    if activeFiltersCount > 0 {
                        Button { clearAllFilters() } label: {
                            Label("Azzera", systemImage: "xmark.circle")
                                .font(.subheadline)
                                .frame(minHeight: 30)
                        }
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .foregroundStyle(ForgiaPalette.accent)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
        .padding(.vertical, 6)
    }

    private var categoryFilterButton: some View {
        Button { showingCategoryFilter = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag").font(.caption)
                Text(categoryFilterTitle)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .frame(minHeight: 30)
            .fontWeight(selectedCategories.isEmpty ? .regular : .semibold)
            .foregroundStyle(selectedCategories.isEmpty ? Color.primary : ForgiaPalette.accent)
        }
        .tint(selectedCategories.isEmpty ? nil : ForgiaPalette.accent)
        .accessibilityIdentifier("transactions-category-filter")
    }

    private var categoryFilterTitle: String {
        guard !selectedCategories.isEmpty else { return "Categorie" }
        if selectedCategories.count == 1,
           let category = allCategories.first(where: { selectedCategories.contains($0.id) }) {
            return category.displayPath
        }
        return "Categorie · \(selectedCategories.count)"
    }

    // MARK: - Sectioning Logic

    /// Short periods read best day by day; longer ones by month.
    private var groupsByDay: Bool {
        let interval = currentQuery.interval
        return interval.duration <= 32 * 24 * 3600
    }

    private var sectionedTransactions: [TransactionSection] {
        let calendar = Calendar.current
        let locale = Locale(identifier: "it_IT")
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        let upcoming = transactions.filter { $0.date >= startOfTomorrow }.sorted { $0.date < $1.date }
        var sections: [TransactionSection] = []
        if !upcoming.isEmpty {
            sections.append(TransactionSection(id: "upcoming", title: "In arrivo", transactions: upcoming, isUpcoming: true))
        }

        // Pages arrive newest first, so equal keys are always adjacent.
        for transaction in transactions where transaction.date < startOfTomorrow {
            let key = groupsByDay
                ? calendar.startOfDay(for: transaction.date)
                : calendar.dateInterval(of: .month, for: transaction.date)!.start
            let id = key.ISO8601Format()
            if sections.last?.id == id {
                sections[sections.count - 1].transactions.append(transaction)
                continue
            }
            let title: String
            if !groupsByDay {
                title = key.formatted(.dateTime.month(.wide).year().locale(locale)).localizedCapitalized
            } else if key == startOfToday {
                title = "Oggi"
            } else if calendar.isDateInYesterday(key) {
                title = "Ieri"
            } else {
                // Italian keeps month names lowercase: capitalize only the weekday.
                let text = key.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
                title = text.prefix(1).uppercased() + text.dropFirst()
            }
            sections.append(TransactionSection(id: id, title: title, transactions: [transaction], isUpcoming: false))
        }
        return sections
    }

    // MARK: - Transaction List

    private static let summaryRowID = "period-summary"

    /// One list for every state, so the summary card survives period changes and can animate.
    @ViewBuilder private var transactionList: some View {
        #if os(macOS)
        desktopTable
        #else
        groupedTransactionList
        #endif
    }

    #if os(macOS)
    private var desktopTable: some View {
        VStack(spacing: 0) {
            periodSummary.padding(16)
            HStack {
                Button("Ricorrenze", systemImage: "repeat") { showingRecurring = true }
                Spacer()
                Button(isInSelectionMode ? "Fine selezione" : "Seleziona") {
                    isInSelectionMode.toggle()
                    selectedTransactions.removeAll()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Table(transactions, selection: Binding(
                get: { isInSelectionMode ? selectedTransactions : desktopSelection },
                set: { if isInSelectionMode { selectedTransactions = $0 } else { desktopSelection = $0 } }
            )) {
                TableColumn("Data") { transaction in
                    Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(transaction.date > Date() ? Color.accentColor : Color.primary)
                }.width(min: 90, ideal: 110)
                TableColumn("Descrizione") { transaction in
                    Text(transaction.transactionDescription.flatMap { $0.isEmpty ? nil : $0 } ?? transaction.type.displayName)
                        .lineLimit(1)
                }.width(min: 130, ideal: 230)
                TableColumn("Tipo") { transaction in
                    Text(transaction.type.displayName)
                }.width(min: 70, ideal: 90)
                TableColumn("Categoria") { transaction in
                    Text(transaction.category?.name ?? "—").lineLimit(1)
                }.width(min: 90, ideal: 130)
                TableColumn("Conto") { transaction in
                    Text(transaction.fromConto?.name ?? transaction.toConto?.name ?? "—").lineLimit(1)
                }.width(min: 90, ideal: 130)
                TableColumn("Importo") { transaction in
                    Text(transaction.amount ?? 0, format: .currency(code: currency))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 90, ideal: 110)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let transaction = transactions.first(where: { ids.contains($0.id) }) {
                    Button("Apri movimento") { desktopDetail = transaction }
                    Button("Modifica…") { transactionToEdit = transaction }
                    Divider()
                    Button("Elimina…", role: .destructive) {
                        transactionToDelete = transaction
                        showingDeleteAlert = true
                    }
                }
            } primaryAction: { ids in
                if !isInSelectionMode, let transaction = transactions.first(where: { ids.contains($0.id) }) {
                    desktopDetail = transaction
                }
            }
            .financeEmptyOverlay(isPresented: transactions.isEmpty) { emptyState }
            HStack {
                let selected = transactions.first { desktopSelection.contains($0.id) }
                Button("Apri", systemImage: "arrow.up.forward.square") { desktopDetail = selected }
                    .disabled(isInSelectionMode || desktopSelection.count != 1)
                Button("Modifica…", systemImage: "pencil") { transactionToEdit = selected }
                    .disabled(isInSelectionMode || desktopSelection.count != 1)
                Button("Elimina…", systemImage: "trash", role: .destructive) {
                    transactionToDelete = selected
                    showingDeleteAlert = true
                }
                .disabled(isInSelectionMode || desktopSelection.count != 1)
                Spacer()
                Text("\(transactions.count) di \(summary.count) movimenti").foregroundStyle(.secondary)
                if hasMoreTransactions { Button("Carica altri movimenti") { loadNextPage() } }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .padding(12)
        }
        .financePresentation(item: $desktopDetail, title: "Movimento") { transaction in
            NavigationStack { TransactionDetailView(transaction: transaction, showsCloseButton: true) }
        }
        .onChange(of: currentQuery) { _, _ in desktopSelection.removeAll() }
    }
    #endif

    private var groupedTransactionList: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    periodSummary
                        .listRowBackground(
                            PeriodSummaryCard.background(balance: summary.balance)
                                .animation(.smooth, value: summary.balance >= 0)
                        )
                        .accessibilityIdentifier("transactions-period-summary")
                        .id(Self.summaryRowID)
                } footer: {
                    TransactionListActions(isSelecting: $isInSelectionMode, searchContoIDs: scopeContoIDs,
                                           showsSelection: !transactions.isEmpty) {
                        selectedTransactions.removeAll()
                    } showRecurring: {
                        showingRecurring = true
                    }
                }
                if transactions.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                }
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
                                        TransactionCell(transaction: transaction, showConto: showContoInCell,
                                                        showDate: section.isUpcoming || !groupsByDay)
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(ForgiaPalette.surface)
                            } else {
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionCell(transaction: transaction, showConto: showContoInCell,
                                                    showDate: section.isUpcoming || !groupsByDay)
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
            // Rows swap without animation (only the card animates); a scrolled list returns to the card.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, scrolled in
                isScrolledDown = scrolled
            }
            .onChange(of: currentQuery.interval) { _, _ in
                // At rest the card is already in place; only bring it back when the list was scrolled.
                guard isScrolledDown else { return }
                proxy.scrollTo(Self.summaryRowID, anchor: .top)
            }

        }
    }

    /// Loads the next page as soon as the end of the list scrolls into view.
    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 12)
        .listRowBackground(Color.clear)
        .accessibilityLabel("Caricamento di altre transazioni")
        .id(transactions.count)
        .onAppear { loadNextPage() }
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
                Text("Nessuna transazione nel periodo selezionato")
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

    /// Reloads totals and the first page. After an edit, keeps as many rows as were loaded.
    private func reload(keepingLoadedRows: Bool = false) {
        let query = currentQuery
        let limit = keepingLoadedRows ? max(transactions.count, pageSize) : pageSize
        if !keepingLoadedRows { selectedTransactions.removeAll() }
        do {
            summary = try query.summary(in: modelContext)
            transactions = try query.fetchPage(in: modelContext, offset: 0, limit: limit)
        } catch {
            print("Error fetching transactions: \(error)")
            summary = TransactionListSummary()
            transactions = []
        }
        hasLoaded = true
    }

    private func loadNextPage() {
        guard hasMoreTransactions else { return }
        do {
            transactions += try currentQuery.fetchPage(in: modelContext, offset: transactions.count, limit: pageSize)
        } catch {
            print("Error fetching transactions: \(error)")
        }
    }

    private func clearAllFilters() {
        withAnimation {
            selectedType = .all
            selectedConto = nil
            selectedCategories = []
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
            reload(keepingLoadedRows: true)
            appState.triggerDataRefresh()
        } catch {
            showingDeleteError = true
        }
    }

    private func deleteTransaction(_ transaction: FinanceTransaction) {
        do {
            try TransactionDeletion(context: modelContext).delete(ids: [transaction.id])
            reload(keepingLoadedRows: true)
            appState.triggerDataRefresh()
        } catch {
            showingDeleteError = true
        }
    }
}

// MARK: - Category Filter Sheet

struct CategoryFilterSheet: View {
    let categories: [FinanceCategory]
    @Binding var selectedCategories: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    private var hierarchy: CategoryHierarchy { CategoryHierarchy(categories: categories) }

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
                } footer: {
                    Text("Una categoria principale include tutte le sue sottocategorie. Tocca una sottocategoria per restringere i risultati.")
                }

                let hierarchy = hierarchy
                ForEach(Array(hierarchy.roots.enumerated()), id: \.element.id) { index, root in
                    let children = hierarchy.children(of: root)
                    let rootSelected = selectedCategories.contains(root.id)
                    Section {
                        categoryRow(root) {
                            CategoryTreeRow(category: root, level: .macro(childCount: children.count),
                                            subtitle: children.isEmpty ? nil : "Include le sottocategorie") {
                                checkmark(selected: rootSelected)
                            }
                        }
                        .categoryTreeRowStyle(isMacro: true)
                        ForEach(Array(children.enumerated()), id: \.element.id) { childIndex, child in
                            categoryRow(child, includedByParent: rootSelected) {
                                CategoryTreeRow(category: child, level: .child(isLast: childIndex == children.count - 1)) {
                                    checkmark(selected: selectedCategories.contains(child.id), included: rootSelected)
                                }
                            }
                            .categoryTreeRowStyle(isMacro: false)
                        }
                    } header: {
                        if index == 0 { Text("Seleziona categorie") }
                    }
                }
            }
            .navigationTitle("Categorie e sottocategorie")
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

    private func categoryRow(_ category: FinanceCategory, includedByParent: Bool = false,
                             @ViewBuilder label: () -> some View) -> some View {
        Button { toggleCategory(category) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityLabel(category.displayPath)
            .accessibilityValue(includedByParent ? "Inclusa nella categoria principale" : "")
            .accessibilityHint(includedByParent ? "Tocca per mostrare solo questa sottocategoria" : "")
            .accessibilityAddTraits(selectedCategories.contains(category.id) || includedByParent ? .isSelected : [])
    }

    @ViewBuilder
    private func checkmark(selected: Bool, included: Bool = false) -> some View {
        if selected {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(ForgiaPalette.accent)
        } else if included {
            Image(systemName: "checkmark.circle").font(.title3).foregroundStyle(.tertiary)
        } else {
            Image(systemName: "circle").font(.title3).foregroundStyle(.quaternary)
        }
    }

    private func toggleCategory(_ category: FinanceCategory) {
        selectedCategories = hierarchy.toggling(category, in: selectedCategories)
    }
}

// MARK: - Transaction Cell

struct TransactionCell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let transaction: FinanceTransaction
    let showConto: Bool
    /// Off under day headers, where the date would only repeat the section title.
    var showDate = true

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

                if showDate || (showConto && contoName != nil) {
                    HStack(spacing: 4) {
                        if showDate {
                            Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT"))))
                        }
                        if showConto, let conto = contoName {
                            if showDate { Text("•") }
                            Text(conto)
                        }
                    }
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
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
                Text(transaction.category?.displayPath ?? "-").font(.subheadline).lineLimit(1)
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

    var transactionType: TransactionType? {
        switch self {
        case .all: nil
        case .income: .income
        case .expense: .expense
        case .transfer: .transfer
        }
    }


}

// MARK: - Transaction Timeframe

enum TransactionTimeframe: String, CaseIterable {
    case week, month, quarter, halfYear, year

    var displayName: String {
        switch self {
        case .week: "Settimana"
        case .month: "Mese"
        case .quarter: "Trimestre"
        case .halfYear: "Semestre"
        case .year: "Anno"
        }
    }

    var balanceTitle: String {
        switch self {
        case .week: "Bilancio della settimana"
        case .month: "Bilancio del mese"
        case .quarter: "Bilancio del trimestre"
        case .halfYear: "Bilancio del semestre"
        case .year: "Bilancio dell’anno"
        }
    }

    private var monthCount: Int {
        switch self {
        case .week, .month: 1
        case .quarter: 3
        case .halfYear: 6
        case .year: 12
        }
    }

    /// Calendar-aligned, half-open ranges; never fixed multiples of seconds.
    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        if self == .week { return calendar.dateInterval(of: .weekOfYear, for: date)! }
        let yearStart = calendar.dateInterval(of: .year, for: date)!.start
        let month = calendar.component(.month, from: date)
        let offset = ((month - 1) / monthCount) * monthCount
        let start = calendar.date(byAdding: .month, value: offset, to: yearStart)!
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: monthCount, to: start)!)
    }

    func moving(_ date: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        let start = interval(containing: date, calendar: calendar).start
        return calendar.date(byAdding: self == .week ? .weekOfYear : .month,
                             value: self == .week ? offset : offset * monthCount, to: start)!
    }

    /// What a non-obvious period covers: the months of a quarter or semester, the week number.
    func subtitle(containing date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "it_IT")) -> String? {
        let range = interval(containing: date, calendar: calendar)
        switch self {
        case .week:
            return "Settimana \(calendar.component(.weekOfYear, from: range.start))"
        case .quarter, .halfYear:
            let first = range.start.formatted(.dateTime.month(.wide).locale(locale))
            let last = range.end.addingTimeInterval(-1).formatted(.dateTime.month(.wide).locale(locale))
            return "\(first) – \(last)".localizedCapitalized
        case .month, .year:
            return nil
        }
    }

    func title(containing date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "it_IT")) -> String {
        let range = interval(containing: date, calendar: calendar)
        let year = date.formatted(.dateTime.year().locale(locale))
        switch self {
        case .week:
            return "\(range.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(range.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))"
        case .month: return date.formatted(.dateTime.month(.wide).year().locale(locale))
        case .quarter: return "\((calendar.component(.month, from: date) - 1) / 3 + 1)° trimestre · \(year)"
        case .halfYear: return "\((calendar.component(.month, from: date) - 1) / 6 + 1)° semestre · \(year)"
        case .year: return year
        }
    }
}

// MARK: - Transaction Section

private struct TransactionSection: Identifiable {
    let id: String
    let title: String
    var transactions: [FinanceTransaction]
    let isUpcoming: Bool
}

// MARK: - Preview

#Preview {
    TransactionListView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
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

private struct TransactionListActions: View {
    @Binding var isSelecting: Bool
    let searchContoIDs: Set<UUID>?
    /// Selecting makes no sense on an empty list.
    var showsSelection = true
    let clearSelection: () -> Void
    let showRecurring: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TransactionSearchLink(scopeContoIDs: searchContoIDs) {
                ActionTile(title: "Cerca", symbol: "magnifyingglass", fill: ForgiaPalette.sageSurface)
            }
            .accessibilityIdentifier("transactions-open-search")

            Button(action: showRecurring) {
                ActionTile(title: "Ricorrenti", symbol: "repeat", fill: ForgiaPalette.apricotSurface)
            }

            if showsSelection {
                Button {
                    withAnimation {
                        isSelecting.toggle()
                        clearSelection()
                    }
                } label: {
                    ActionTile(title: isSelecting ? "Fine" : "Seleziona",
                               symbol: isSelecting ? "xmark" : "checkmark.circle",
                               fill: ForgiaPalette.canvas, isActive: isSelecting)
                }
                .accessibilityLabel(isSelecting ? "Fine selezione" : "Seleziona")
            }
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .padding(.top, 4)
        // Footers are inset further than rows: line the tiles up with the card above.
        .padding(.horizontal, -16)
    }
}

/// Same shape as the quick actions in Oggi, so list shortcuts read as first-class actions.
private struct ActionTile: View {
    let title: String
    let symbol: String
    let fill: Color
    var isActive = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? ForgiaPalette.onAccent : ForgiaPalette.accent)
                .frame(width: 40, height: 40)
                .background(isActive ? ForgiaPalette.onAccent.opacity(0.18) : fill, in: Circle())
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? ForgiaPalette.onAccent : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
        .background(isActive ? ForgiaPalette.accent : ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ForgiaPalette.border, lineWidth: isActive ? 0 : 0.7) }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
