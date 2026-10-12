import SwiftUI
import SwiftData
import FinanceCore

struct BudgetTransactionListView: View {
    let account: Account
    @State private var selectedBudgetID: UUID?
    @State private var selectedCadence: BudgetPeriod?
    @State private var timeframe: TransactionTimeframe
    @State private var date = Date()
    @State private var order = BudgetTransactionOrder.newest

    init(account: Account, initialBudget: FinanceBudget? = nil) {
        self.account = account
        _selectedBudgetID = State(initialValue: initialBudget?.id)
        let initialTimeframe: TransactionTimeframe
        switch initialBudget?.period {
        case .weekly: initialTimeframe = .week
        case .quarterly: initialTimeframe = .quarter
        case .yearly: initialTimeframe = .year
        default: initialTimeframe = .month
        }
        _timeframe = State(initialValue: initialTimeframe)
    }

    private var budgets: [FinanceBudget] {
        (account.budgets ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    private var availableBudgets: [FinanceBudget] {
        budgets.filter { selectedCadence == nil || $0.period == selectedCadence }
    }
    private var selectedBudgets: [FinanceBudget] {
        availableBudgets.filter { selectedBudgetID == nil || $0.id == selectedBudgetID }
    }

    var body: some View {
        BudgetTransactionResults(budgets: selectedBudgets, interval: timeframe.interval(containing: date),
                                 order: order, currency: account.currency ?? "EUR")
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    periodControls
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            Picker("Budget", selection: $selectedBudgetID) {
                                Text("Tutti i budget").tag(UUID?.none)
                                ForEach(availableBudgets) { budget in
                                    Text((budget.name ?? "Budget") + (budget.isActive == false ? " · disattivato" : ""))
                                        .tag(Optional(budget.id))
                                }
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("budget-list-filter")
                            Picker("Periodicità del budget", selection: $selectedCadence) {
                                Text("Ogni periodicità").tag(BudgetPeriod?.none)
                                ForEach(BudgetPeriod.allCases, id: \.self) { period in
                                    Text(period.displayName).tag(Optional(period))
                                }
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("budget-list-cadence")
                            Picker("Ordina transazioni", selection: $order) {
                                ForEach(BudgetTransactionOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("budget-list-order")
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.vertical, 8)
                .background(ForgiaPalette.surface)
            }
            .navigationTitle("Transazioni dei budget")
            .toolbarTitleDisplayMode(.inline)
            .onChange(of: selectedCadence) { _, _ in
                if let id = selectedBudgetID, !availableBudgets.contains(where: { $0.id == id }) {
                    selectedBudgetID = nil
                }
            }
    }

    private var periodControls: some View {
        HStack(spacing: 8) {
            Button {
                date = timeframe.moving(date, by: -1)
            } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Periodo precedente")
                .accessibilityIdentifier("budget-list-previous")
            VStack(spacing: 2) {
                Text("Periodo delle transazioni")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(timeframe.title(containing: date).localizedCapitalized)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Picker("Periodo", selection: $timeframe) {
                    ForEach(TransactionTimeframe.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("budget-list-timeframe")
            }
            .frame(maxWidth: .infinity)
            Button {
                date = timeframe.moving(date, by: 1)
            } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Periodo successivo")
                .accessibilityIdentifier("budget-list-next")
        }
        .padding(.horizontal, 12)
    }
}

private enum BudgetTransactionOrder: String, CaseIterable {
    case newest = "Più recenti"
    case largest = "Importi maggiori"
}

private struct BudgetTransactionResults: View {
    let budgets: [FinanceBudget]
    let interval: DateInterval
    let order: BudgetTransactionOrder
    let currency: String
    @Query private var candidates: [FinanceTransaction]

    init(budgets: [FinanceBudget], interval: DateInterval, order: BudgetTransactionOrder, currency: String) {
        self.budgets = budgets
        self.interval = interval
        self.order = order
        self.currency = currency
        let start = interval.start
        let end = interval.end
        let expense = TransactionType.expense.rawValue
        _candidates = Query(filter: #Predicate<FinanceTransaction> {
            $0.date >= start && $0.date < end && $0.typeRaw == expense
        })
    }

    var body: some View {
        let expenses = BudgetService.recordedExpenses(for: budgets, period: (interval.start, interval.end), transactions: candidates)
        let sorted = order == .newest ? expenses : expenses.sorted {
            if $0.amount != $1.amount { return ($0.amount ?? 0) > ($1.amount ?? 0) }
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spese nel periodo").font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    Text(BudgetPeriodText.range(interval))
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .accessibilityIdentifier("budget-list-date-range")
                    Text(expenses.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }.formatted(.currency(code: currency)))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("budget-list-total")
                    Text(expenses.count == 1 ? "1 transazione" : "\(expenses.count) transazioni").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                        .accessibilityIdentifier("budget-list-count")
                }
                .listRowBackground(ForgiaPalette.sageSurface)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(budgetPeriodExplanation)
                        .accessibilityIdentifier("budget-list-period-context")
                    Text("Una spesa presente in più budget viene contata una sola volta. Sono incluse le spese future già registrate nel periodo scelto.")
                }
            }
            if sorted.isEmpty {
                ContentUnavailableView("Nessuna transazione", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Non ci sono spese per i budget e il periodo selezionati."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(sorted) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            CompactTransactionRow(transaction: transaction, currency: currency, showsFuture: true)
                        }
                        .accessibilityIdentifier("budget-list-expense-\(transaction.id)")
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(ForgiaPalette.surface)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .themedBackground()
    }

    private var budgetPeriodExplanation: String {
        guard budgets.count == 1, let budget = budgets.first, let period = budget.period,
              let budgetInterval = period.interval(containing: interval.start) else {
            return "Il totale segue il periodo delle transazioni scelto. Ogni budget mantiene il proprio limite e la propria cadenza."
        }
        let limit = (budget.amount ?? 0).formatted(.currency(code: currency))
        let rule = "\(budget.name ?? "Budget"): limite di \(limit) \(BudgetPeriodText.frequency(for: period))."
        if interval == budgetInterval {
            return "\(rule) Le transazioni mostrate coprono un periodo completo di questo budget."
        }
        if interval.end <= budgetInterval.end {
            return "\(rule) Stai vedendo una parte del periodo del budget: \(BudgetPeriodText.range(budgetInterval))."
        }
        return "\(rule) Il periodo delle transazioni scelto comprende più periodi di questo budget."
    }
}
