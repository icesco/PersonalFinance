import SwiftUI
import SwiftData
import FinanceCore

/// Accounts, limits and expected movements share the same explicit book scope.
struct FinancePlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataStorageManager.self) private var storage
    @Query private var memberships: [SharedBookMembership]
    @Query private var resolutions: [RecurrenceResolution]
    @Environment(AppStateManager.self) private var appState
    @Query private var accounts: [Account]
    @Query(filter: #Predicate<FinanceTransaction> { $0.isRecurring == true })
    private var recurring: [FinanceTransaction]
    @State private var selectedOccurrence: Occurrence?
    @State private var resolutionError: String?
    @State private var showingBudgets = false
    @State private var creatingContoFor: Account?
    @State private var editingConto: Conto?
    @State private var selectedTransaction: FinanceTransaction?

    private var books: [Account] {
        let selected = appState.showAllAccounts
            ? accounts.filter { $0.isActive == true }
            : appState.selectedAccount.map { [$0] } ?? []
        return selected.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private struct Occurrence: Identifiable {
        struct ID: Hashable { let transaction: UUID; let date: Date }
        let transaction: FinanceTransaction
        let date: Date
        let currency: String
        var id: ID { ID(transaction: transaction.id, date: date) }
    }

    private var occurrences: [Occurrence] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
        let overdueStart = Calendar.current.date(byAdding: .day, value: -30, to: start) ?? start
        let resolvedKeys = Set(resolutions.map(\.key))
        let conti = books.flatMap(\.activeConti)
        let currencies = Dictionary(uniqueKeysWithValues: conti.map {
            ($0.id, $0.account?.currency ?? "EUR")
        })
        return recurring.flatMap { transaction -> [Occurrence] in
            let contoID = transaction.type == .income ? transaction.toContoId : transaction.fromContoId
            guard let contoID, let currency = currencies[contoID] else { return [] }
            // The seed is already recorded; show only subsequent, unrecorded occurrences.
            return transaction.recurrenceDates(after: max(overdueStart.addingTimeInterval(-1), transaction.date), through: end)
                .filter { $0 < end && !resolvedKeys.contains(RecurrenceResolution.key(sourceID: transaction.id, date: $0)) }
                .map { Occurrence(transaction: transaction, date: $0, currency: currency) }
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.transaction.id.uuidString < $1.transaction.id.uuidString
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { appState.presentAccountSelection() } label: {
                        Label(appState.showAllAccounts ? "Tutti i libri" : books.first?.name ?? "Scegli libro",
                              systemImage: "books.vertical")
                    }
                }

                Section("Budget") {
                    if !appState.showAllAccounts, appState.selectedAccount != nil {
                        Button { showingBudgets = true } label: {
                            Label("Budget e limiti di spesa", systemImage: "chart.bar.xaxis")
                        }
                        .accessibilityIdentifier("planning-budgets")
                    } else {
                        Button("Scegli un libro per gestire i budget") { appState.presentAccountSelection() }
                    }
                }

                Section {
                    NavigationLink("Inviti ai libri condivisi") { SharedInvitationsView() }
                }

                ForEach(books) { book in
                    Section(books.count > 1 ? "Conti · \(book.name ?? "Libro")" : "Conti") {
                        ForEach(book.activeConti) { conto in
                            NavigationLink {
                                TransactionListView(initialConto: conto)
                            } label: {
                                HStack {
                                    Label(conto.name ?? "Conto", systemImage: conto.type?.icon ?? "creditcard")
                                    Spacer()
                                    Text(conto.displayBalance, format: .currency(code: book.currency ?? "EUR"))
                                        .monospacedDigit()
                                }
                            }
                            .contextMenu {
                                Button("Modifica conto") { editingConto = conto }
                            }
                            .swipeActions {
                                Button("Modifica") { editingConto = conto }.tint(.blue)
                            }
                        }
                        Button { creatingContoFor = book } label: {
                            Label("Nuovo conto", systemImage: "plus")
                        }
                        NavigationLink {
                            SharedBookView(book: book)
                        } label: {
                            SharedBookStatusLabel(status: storage.isCloudSyncEnabled && !storage.isMigrating && memberships.contains(where: { $0.localBookID == book.id })
                                                  ? storage.sharedBookAutomaticRefresh.statuses[book.id] : nil)
                        }
                        .accessibilityIdentifier("planning-share-book")
                    }
                }

                Section {
                    NavigationLink("Gestisci ricorrenze") {
                        RecurringManagementView(contoIDs: Set(books.flatMap(\.activeConti).map(\.id)))
                    }
                    NavigationLink("Scadenze gestite") {
                        ResolvedRecurrencesView(contoIDs: Set(books.flatMap(\.activeConti).map(\.id)))
                    }
                    if _recurring.fetchError != nil || _resolutions.fetchError != nil {
                        Label("Impossibile caricare le ricorrenti", systemImage: "exclamationmark.triangle")
                    } else if occurrences.isEmpty {
                        Text("Nessuna scadenza da gestire nei 30 giorni passati e nei prossimi 30.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(occurrences) { occurrence in
                            Button { selectedOccurrence = occurrence } label: {
                                occurrenceRow(occurrence)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("occurrence-\(RecurrenceResolution.key(sourceID: occurrence.transaction.id, date: occurrence.date))")
                        }
                    }
                } header: {
                    Text("Scadenze da gestire")
                } footer: {
                    Text("Scadenze dei 30 giorni passati e dei prossimi 30. Tocca per registrare o saltare una singola scadenza. Quelle future restano previsioni finché non vengono registrate.")
                }
            }
            .navigationTitle("Pianifica")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { appState.presentQuickTransaction() } label: {
                        Label("Nuova spesa", systemImage: "plus")
                    }
                }
            }
            .confirmationDialog("Gestisci scadenza", isPresented: Binding(
                get: { selectedOccurrence != nil }, set: { if !$0 { selectedOccurrence = nil } }
            ), titleVisibility: .visible) {
                if let occurrence = selectedOccurrence {
                    if occurrence.date <= Date() {
                        Button("Registra movimento") { resolve(occurrence, skip: false) }
                    }
                    Button("Salta questa scadenza") { resolve(occurrence, skip: true) }
                    Button("Modifica ricorrenza originale") { selectedTransaction = occurrence.transaction }
                }
            } message: { Text("La registrazione usa importo, conto e categoria della ricorrenza originale.") }
            .alert("Scadenza non aggiornata", isPresented: Binding(get: { resolutionError != nil }, set: { if !$0 { resolutionError = nil } })) {
                Button("OK") { resolutionError = nil }
            } message: { Text(resolutionError ?? "") }
            .sheet(isPresented: $showingBudgets) { BudgetView() }
            .sheet(item: $creatingContoFor) { CreateContoView(account: $0) }
            .sheet(item: $editingConto) { EditContoView(conto: $0) }
            .sheet(item: $selectedTransaction) { transaction in
                NavigationStack { TransactionDetailView(transaction: transaction) }
            }
        }
    }

    private func resolve(_ occurrence: Occurrence, skip: Bool) {
        do {
            if skip {
                try RecurrenceOccurrenceService.skip(source: occurrence.transaction, scheduledDate: occurrence.date, context: modelContext)
            } else {
                _ = try RecurrenceOccurrenceService.record(source: occurrence.transaction, scheduledDate: occurrence.date, context: modelContext)
            }
            appState.triggerDataRefresh()
        } catch {
            resolutionError = "Non è stato possibile aggiornare la scadenza. Potrebbe essere già stata gestita o modificata. Riapri la schermata e riprova."
        }
        selectedOccurrence = nil
    }

    private func occurrenceRow(_ occurrence: Occurrence) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.transaction.transactionDescription ?? occurrence.transaction.category?.name ?? "Ricorrenza")
                    .font(.headline)
                Text(occurrence.date, format: .dateTime.day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(occurrence.transaction.amount ?? 0, format: .currency(code: occurrence.currency))
                    .monospacedDigit()
                Text(occurrence.transaction.type == .income ? "Entrata prevista" :
                     occurrence.transaction.type == .transfer ? "Trasferimento previsto" : "Uscita prevista")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
