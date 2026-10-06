//
//  TransactionSearchView.swift
//  Personal Finance
//
//  Ricerca movimenti su tutte le date del libro: filtri in alto, campo di ricerca di sistema
//

import SwiftUI
import SwiftData
import FinanceCore

struct TransactionSearchView: View {
    /// Conti in cui cercare; `nil` usa i conti attivi del libro selezionato.
    var scopeContoIDs: Set<UUID>? = nil

    @Environment(AppStateManager.self) private var appState
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]

    @State private var criteria = SearchCriteria()
    @State private var isSearchPresented = false
    @State private var didPresentSearch = false
    @State private var showingCategoryFilter = false
    @State private var limit = pageSize

    private static let pageSize = 60

    private var account: Account? { appState.selectedAccount }
    private var currency: String { account?.currency ?? "EUR" }
    private var availableConti: [Conto] { appState.activeConti(for: account) }
    private var availableCategories: [FinanceCategory] {
        account?.categories?.filter { $0.isActive == true } ?? []
    }
    private var selectedConto: Conto? {
        availableConti.first { $0.id == criteria.contoID }
    }

    var body: some View {
        let results = filteredTransactions
        List {
            if !criteria.isActive {
                idleState
            } else if results.isEmpty {
                noResultsState
            } else {
                Section {
                    ResultsSummary(results: results, currency: currency)
                        .listRowBackground(ForgiaPalette.surface)
                }
                ForEach(sections(for: Array(results.prefix(limit)))) { section in
                    Section {
                        ForEach(section.transactions, id: \.id) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    TransactionCell(transaction: transaction, showConto: criteria.contoID == nil)
                                    if !criteria.sort.groupsByMonth {
                                        Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                                            .font(.caption)
                                            .foregroundStyle(ForgiaPalette.mutedText)
                                    }
                                }
                            }
                            .listRowBackground(ForgiaPalette.surface)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }
                }
                if results.count > limit {
                    Button {
                        limit += Self.pageSize
                    } label: {
                        Text("Mostra altri risultati")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .tint(ForgiaPalette.accent)
                    .listRowBackground(ForgiaPalette.surface)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .themedBackground()
        .safeAreaBar(edge: .top, spacing: 0) { filtersBar }
        .navigationTitle("Cerca")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $criteria.query, isPresented: $isSearchPresented, prompt: "Descrizione, note, conto, importo…")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .toolbar(.visible, for: .navigationBar)
        // Field at the bottom, within thumb reach; the filters keep the top of the screen.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
        #endif
        .sheet(isPresented: $showingCategoryFilter) {
            CategoryFilterSheet(categories: availableCategories, selectedCategories: $criteria.categoryIDs)
        }
        .onChange(of: criteria) { _, _ in limit = Self.pageSize }
        .onChange(of: appState.selectedAccount?.id) { _, _ in criteria = SearchCriteria() }
        .onAppear {
            // Open straight into typing the first time, without stealing focus on every return from a detail.
            guard !didPresentSearch else { return }
            didPresentSearch = true
            isSearchPresented = true
        }
    }

    // MARK: - Filtering

    private var filteredTransactions: [FinanceTransaction] {
        guard criteria.isActive else { return [] }
        let contoIDs: Set<UUID> = criteria.contoID.map { [$0] } ?? scopeContoIDs ?? Set(availableConti.map(\.id))
        let interval = criteria.period.interval()

        let matches = transactions.filter { transaction in
            let inScope = transaction.fromContoId.map(contoIDs.contains) == true
                || transaction.toContoId.map(contoIDs.contains) == true
            guard inScope else { return false }
            if let interval, transaction.date < interval.start || transaction.date >= interval.end { return false }
            if !criteria.type.includes(transaction.type) { return false }
            if !criteria.categoryIDs.isEmpty {
                guard let categoryID = transaction.category?.id, criteria.categoryIDs.contains(categoryID) else { return false }
            }
            return TransactionSearch.matches(
                query: criteria.query,
                fields: [transaction.transactionDescription, transaction.notes,
                         transaction.category?.name, transaction.fromConto?.name, transaction.toConto?.name],
                amount: transaction.amount ?? 0
            )
        }

        switch criteria.sort {
        case .newest: return matches
        case .oldest: return matches.reversed()
        case .highestAmount: return matches.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        case .lowestAmount: return matches.sorted { ($0.amount ?? 0) < ($1.amount ?? 0) }
        }
    }

    private func sections(for transactions: [FinanceTransaction]) -> [ResultSection] {
        guard criteria.sort.groupsByMonth else {
            return [ResultSection(id: "all", title: nil, transactions: transactions)]
        }
        let calendar = Calendar.current
        var sections: [ResultSection] = []
        for transaction in transactions {
            let month = calendar.dateInterval(of: .month, for: transaction.date)!.start
            let id = month.ISO8601Format()
            if sections.last?.id == id {
                sections[sections.count - 1].transactions.append(transaction)
            } else {
                let title = month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "it_IT"))).localizedCapitalized
                sections.append(ResultSection(id: id, title: title, transactions: [transaction]))
            }
        }
        return sections
    }

    // MARK: - Filters Bar

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 6) {
                    filterMenu(
                        title: criteria.period == .all ? "Periodo" : criteria.period.displayName,
                        icon: "calendar", isActive: criteria.period != .all
                    ) {
                        Picker("Periodo", selection: $criteria.period) {
                            ForEach(TransactionSearchPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }

                    filterMenu(
                        title: criteria.type == .all ? "Tipo" : criteria.type.displayName,
                        icon: "line.3.horizontal.decrease", isActive: criteria.type != .all
                    ) {
                        Picker("Tipo di movimento", selection: $criteria.type) {
                            ForEach(TransactionTypeFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }

                    if scopeContoIDs == nil || (scopeContoIDs?.count ?? 0) > 1 {
                        filterMenu(title: selectedConto?.name ?? "Conto", icon: "creditcard", isActive: criteria.contoID != nil) {
                            Picker("Conto", selection: $criteria.contoID) {
                                Text("Tutti i conti").tag(UUID?.none)
                                ForEach(availableConti.filter { scopeContoIDs?.contains($0.id) ?? true }, id: \.id) { conto in
                                    Text(conto.name ?? "Conto").tag(Optional(conto.id))
                                }
                            }
                        }
                    }

                    Button { showingCategoryFilter = true } label: {
                        Label(criteria.categoryIDs.isEmpty ? "Categorie" : "Categorie · \(criteria.categoryIDs.count)", systemImage: "tag")
                            .font(.subheadline.weight(criteria.categoryIDs.isEmpty ? .regular : .semibold))
                            .frame(minHeight: 30)
                    }
                    .tint(criteria.categoryIDs.isEmpty ? nil : ForgiaPalette.accent)
                    .disabled(availableCategories.isEmpty)

                    filterMenu(title: criteria.sort.displayName, icon: "arrow.up.arrow.down", isActive: criteria.sort != .newest) {
                        Picker("Ordina per", selection: $criteria.sort) {
                            ForEach(TransactionSearchSort.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }

                    if criteria.activeFiltersCount > 0 {
                        Button {
                            withAnimation { criteria.clearFilters() }
                        } label: {
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
        .accessibilityIdentifier("transaction-search-filters")
    }

    private func filterMenu<Content: View>(
        title: String, icon: String, isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .frame(minHeight: 30)
        }
        .tint(isActive ? ForgiaPalette.accent : nil)
    }

    // MARK: - States

    private var idleState: some View {
        ContentUnavailableView {
            Label("Cerca tra i movimenti", systemImage: "magnifyingglass")
        } description: {
            Text("Scrivi una descrizione, una nota, una categoria, un conto o un importo come 12,50. Usa i filtri in alto per restringere il periodo o il tipo.")
        }
        .foregroundStyle(ForgiaPalette.mutedText)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var noResultsState: some View {
        Group {
            if criteria.hasQuery {
                ContentUnavailableView.search(text: criteria.query)
            } else {
                ContentUnavailableView("Nessun movimento", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Nessun movimento corrisponde ai filtri selezionati."))
            }
        }
        .listRowBackground(Color.clear)
        if criteria.activeFiltersCount > 0 {
            Button("Rimuovi filtri") { withAnimation { criteria.clearFilters() } }
                .frame(maxWidth: .infinity)
                .tint(ForgiaPalette.accent)
                .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Search Criteria

private struct SearchCriteria: Equatable {
    var query = ""
    var period: TransactionSearchPeriod = .all
    var type: TransactionTypeFilter = .all
    var contoID: UUID?
    var categoryIDs: Set<UUID> = []
    var sort: TransactionSearchSort = .newest

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var activeFiltersCount: Int {
        [period != .all, type != .all, contoID != nil, !categoryIDs.isEmpty, sort != .newest].filter { $0 }.count
    }

    /// Sorting alone does not start a search: it only reorders results.
    var isActive: Bool {
        hasQuery || period != .all || type != .all || contoID != nil || !categoryIDs.isEmpty
    }

    mutating func clearFilters() {
        self = SearchCriteria(query: query)
    }
}

private extension TransactionTypeFilter {
    func includes(_ type: TransactionType) -> Bool {
        switch self {
        case .all: true
        case .income: type == .income
        case .expense: type == .expense
        case .transfer: type == .transfer
        }
    }
}

private struct ResultSection: Identifiable {
    let id: String
    let title: String?
    var transactions: [FinanceTransaction]
}

// MARK: - Results Summary

private struct ResultsSummary: View {
    let results: [FinanceTransaction]
    let currency: String

    var body: some View {
        let income = results.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        let expenses = results.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                count
                Spacer(minLength: 8)
                totals(income: income, expenses: expenses)
            }
            VStack(alignment: .leading, spacing: 8) {
                count
                totals(income: income, expenses: expenses)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transaction-search-summary")
    }

    private var count: some View {
        Text(results.count == 1 ? "1 risultato" : "\(results.count) risultati")
            .font(.subheadline.weight(.semibold))
    }

    private func totals(income: Decimal, expenses: Decimal) -> some View {
        HStack(spacing: 6) {
            if income > 0 {
                Text("+" + income.formatted(.currency(code: currency)))
                    .foregroundStyle(ForgiaPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ForgiaPalette.sageSurface, in: Capsule())
            }
            if expenses > 0 {
                Text("-" + expenses.formatted(.currency(code: currency)))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ForgiaPalette.apricotSurface, in: Capsule())
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }
}

// MARK: - Entry Point

/// Su iPhone apre la ricerca nello stack dei movimenti; su iPad e Mac passa al tab dedicato.
struct TransactionSearchLink: View {
    var scopeContoIDs: Set<UUID>? = nil

    @Environment(AppStateManager.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesSearchTab: Bool {
        guard scopeContoIDs == nil else { return false }
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        if usesSearchTab {
            Button { appState.selectTab(.search) } label: { label }
        } else {
            NavigationLink { TransactionSearchView(scopeContoIDs: scopeContoIDs) } label: { label }
        }
    }

    private var label: some View {
        Label("Cerca", systemImage: "magnifyingglass")
    }
}

#Preview {
    NavigationStack {
        TransactionSearchView()
    }
    .environment(AppStateManager())
    .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
