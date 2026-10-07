import SwiftUI
import SwiftData
import FinanceCore

struct EditTransactionView: View {
    let transaction: FinanceTransaction
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

    @State private var place = PlaceDraft()
    @State private var loadingLocation = false
    @State private var foreignAmount: ForeignAmountDraft?
    @State private var showingConversion = false
    @State private var amountText = ""
    @State private var description = ""
    @State private var notes = ""
    @State private var isSavingsInterest = false
    @State private var selectedDate = Date()
    @State private var includeTime = false
    @State private var selectedCategory: FinanceCategory?
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurrenceFrequency = .monthly
    @State private var recurrenceEndDate = Date()
    @State private var saveError: String?
    @State private var hasEndDate = false

    // For transfers
    @State private var fromConto: Conto?
    @State private var toConto: Conto?
    @State private var destinationAmountText = ""

    @Query private var categories: [FinanceCategory]
    @Query private var allConti: [Conto]

    private var amountCurrency: String { fromConto?.account?.currency ?? transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR" }
    private var amount: Decimal {
        get { BalanceInput.parse(amountText, currency: amountCurrency) ?? 0 }
        nonmutating set { amountText = NSDecimalNumber(decimal: newValue).stringValue }
    }
    private var destinationAmount: Decimal {
        get { BalanceInput.parse(destinationAmountText, currency: toConto?.account?.currency ?? "EUR") ?? 0 }
        nonmutating set { destinationAmountText = NSDecimalNumber(decimal: newValue).stringValue }
    }

    private var filteredCategories: [FinanceCategory] {
        guard let bookID = (transaction.type == .income ? transaction.toConto : transaction.fromConto)?.account?.id else { return [] }
        return categories.filter { $0.isActive == true && $0.account?.id == bookID }
    }

    private var activeConti: [Conto] {
        allConti.filter { $0.isActive == true }
    }

    private var hasDifferentCurrencies: Bool {
        guard let from = fromConto, let to = toConto else { return false }
        return (from.account?.currency ?? "EUR") != (to.account?.currency ?? "EUR")
    }

    private var effectiveRecurrenceEndDate: Date? {
        RecurrenceSchedule.inclusiveEnd(anchor: selectedDate, lastDay: recurrenceEndDate)
    }

    private var isFormInvalid: Bool {
        if loadingLocation || amount <= 0 { return true }
        if isRecurring && hasEndDate && effectiveRecurrenceEndDate == nil { return true }

        if transaction.type == .transfer {
            return fromConto == nil || toConto == nil || fromConto?.id == toConto?.id || (hasDifferentCurrencies && destinationAmount <= 0)
        }

        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Transazione") {
                    CurrencyAmountField(title: transaction.type == .transfer ? "Importo Trasferimento" :
                                            transaction.type == .income ? "Importo Entrata" : "Importo Spesa",
                                        text: $amountText, currency: amountCurrency,
                                        identifier: "edit-transaction-amount")

                    if transaction.type != .transfer {
                        Button("Importo in valuta estera", systemImage: "arrow.left.arrow.right") { showingConversion = true }
                    }
                    if transaction.type == .transfer {
                        Picker("Da Conto", selection: $fromConto) {
                            Text("Seleziona conto").tag(nil as Conto?)
                            ForEach(activeConti, id: \.id) { conto in
                                ContoPickerLabel(conto: conto)
                                .tag(conto as Conto?)
                            }
                        }

                        Picker("A Conto", selection: $toConto) {
                            Text("Seleziona conto").tag(nil as Conto?)
                            ForEach(activeConti.filter { $0.id != fromConto?.id }, id: \.id) { conto in
                                ContoPickerLabel(conto: conto)
                                .tag(conto as Conto?)
                            }
                        }
                    }

                    if hasDifferentCurrencies {
                        CurrencyAmountField(title: "Importo ricevuto", text: $destinationAmountText,
                                            currency: toConto?.account?.currency ?? "EUR",
                                            identifier: "edit-transaction-destination-amount")
                        Text("Inserisci i due importi effettivi: l'addebito nella valuta del conto di partenza e l'accredito nella valuta di destinazione.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    TextField("Descrizione", text: $description)

                    Toggle("Includi orario", isOn: $includeTime)

                    if includeTime {
                        DatePicker("Data e Ora", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    } else {
                        DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                    }

                    if transaction.type != .transfer && !filteredCategories.isEmpty {
                        Picker("Categoria", selection: $selectedCategory) {
                            Text("Nessuna categoria").tag(nil as FinanceCategory?)
                            ForEach(filteredCategories, id: \.id) { category in
                                HStack {
                                    Image(systemName: category.icon ?? "tag")
                                        .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                                    Text(category.name ?? "Category")
                                }
                                .tag(category as FinanceCategory?)
                            }
                        }
                    }
                }

                if transaction.type == .expense && amount > 0 {
                    Section {
                        if let category = selectedCategory, let book = transaction.fromConto?.account {
                            ExpenseBudgetCheckView(amount: amount, categoryID: category.id, accountID: book.id,
                                                   date: selectedDate, currency: book.currency ?? "EUR", isRecurring: isRecurring,
                                                   excludingTransactionID: transaction.id)
                        } else {
                            Text("Seleziona una categoria per confrontare la spesa con i budget del libro.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if transaction.type == .income && transaction.toConto?.type == .savings {
                    Section("Risparmio") {
                        Toggle("Interessi accreditati", isOn: $isSavingsInterest)
                        Text("Aumentano il saldo senza essere conteggiati come capitale versato.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section { TransactionPlaceEditor(place: $place, isLocating: $loadingLocation) }

                Section("Dettagli Aggiuntivi") {
                    TextField("Note (opzionale)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)

                    Toggle("Transazione Ricorrente", isOn: $isRecurring)

                    if isRecurring {
                        Picker("Frequenza", selection: $selectedFrequency) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }

                        Toggle("Data di fine", isOn: $hasEndDate)

                        if hasEndDate {
                            DatePicker("Fine ricorrenza", selection: $recurrenceEndDate,
                                       in: Calendar.current.startOfDay(for: selectedDate)..., displayedComponents: .date)
                            if effectiveRecurrenceEndDate == nil {
                                Text("La fine della ricorrenza non può precedere la data iniziale.")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if transaction.type == .expense, amount > 0, let category = selectedCategory, let book = transaction.fromConto?.account {
                    ExpenseBudgetCheckView(amount: amount, categoryID: category.id, accountID: book.id,
                                           date: selectedDate, currency: book.currency ?? "EUR", isRecurring: isRecurring,
                                           excludingTransactionID: transaction.id, compact: true)
                        .padding(12)
                        .background(.regularMaterial)
                }
            }
            .sheet(isPresented: $showingConversion) {
                CurrencyConversionSheet(targetCurrency: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR", transactionDate: selectedDate, existing: foreignAmount) { value in
                    foreignAmount = value; amount = value.converted ?? 0
                }
            }
            .onChange(of: amount) { _, value in
                if let foreignAmount, value != foreignAmount.converted { self.foreignAmount = nil }
            }
            .navigationTitle("Modifica Transazione")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        updateTransaction()
                    }
                    .disabled(isFormInvalid)
                    #if os(macOS)
                    .keyboardShortcut("s", modifiers: .command)
                    #endif
                }
            }
            .alert("Impossibile salvare", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear {
                loadTransactionData()
            }
        }
    }

    private func loadTransactionData() {
        foreignAmount = ForeignAmountDraft.load(transaction)
        place = PlaceDraft(transaction: transaction)
        amount = transaction.amount ?? Decimal(0)
        description = transaction.transactionDescription ?? ""
        notes = transaction.notes ?? ""
        isSavingsInterest = transaction.isSavingsInterest == true
        selectedDate = transaction.date
        selectedCategory = transaction.category
        isRecurring = transaction.isRecurring ?? false
        selectedFrequency = transaction.recurrenceFrequency ?? .monthly
        recurrenceEndDate = transaction.recurrenceEndDate ?? Calendar.current.date(byAdding: .year, value: 1, to: max(Date(), selectedDate))!
        hasEndDate = transaction.recurrenceEndDate != nil

        // Check if time component is non-zero
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: transaction.date)
        includeTime = (components.hour != 0 || components.minute != 0)

        // Transfer conti
        fromConto = transaction.fromConto
        toConto = transaction.toConto
        destinationAmount = transaction.destinationAmount ?? transaction.amount ?? 0
    }

    private func updateTransaction() {
        guard !isFormInvalid else { return }
        let oldForeign = ForeignAmountDraft.load(transaction)
        let oldPlace = PlaceDraft(transaction: transaction)
        let oldDestinationAmount = transaction.destinationAmount
        let oldAmount = transaction.amount
        let oldDate = transaction.date
        let oldDescription = transaction.transactionDescription
        let oldNotes = transaction.notes
        let oldInterest = transaction.isSavingsInterest
        let oldRecurring = transaction.isRecurring
        let oldFrequency = transaction.recurrenceFrequency
        let oldEnd = transaction.recurrenceEndDate
        let oldUpdated = transaction.updatedAt
        let oldCategory = transaction.category
        let oldFrom = transaction.fromConto
        let oldTo = transaction.toConto
        if let foreignAmount { foreignAmount.apply(to: transaction) } else { ForeignAmountDraft.clear(transaction) }
        place.apply(to: transaction)
        transaction.amount = amount
        transaction.date = selectedDate
        transaction.transactionDescription = description.isEmpty ? nil : description
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.isSavingsInterest = transaction.type == .income && transaction.toConto?.type == .savings && isSavingsInterest
        transaction.isRecurring = isRecurring
        transaction.recurrenceFrequency = isRecurring ? selectedFrequency : nil
        transaction.recurrenceEndDate = isRecurring && hasEndDate
            ? effectiveRecurrenceEndDate : nil
        transaction.updatedAt = Date()

        // Use setters to keep denormalized IDs in sync
        if transaction.type == .transfer {
            transaction.destinationAmount = hasDifferentCurrencies ? destinationAmount : nil
            transaction.setFromConto(fromConto)
            transaction.setToConto(toConto)
        } else {
            transaction.setCategory(selectedCategory)
        }

        do {
            try modelContext.save()
            appState.triggerDataRefresh()
            dismiss()
        } catch {
            if let oldForeign { oldForeign.apply(to: transaction) } else { ForeignAmountDraft.clear(transaction) }
            oldPlace.apply(to: transaction)
            transaction.destinationAmount = oldDestinationAmount
            transaction.amount = oldAmount
            transaction.date = oldDate
            transaction.transactionDescription = oldDescription
            transaction.notes = oldNotes
            transaction.isSavingsInterest = oldInterest
            transaction.isRecurring = oldRecurring
            transaction.recurrenceFrequency = oldFrequency
            transaction.recurrenceEndDate = oldEnd
            transaction.updatedAt = oldUpdated
            transaction.setCategory(oldCategory)
            transaction.setFromConto(oldFrom)
            transaction.setToConto(oldTo)
            saveError = error.localizedDescription
        }
    }
}

#if DEBUG
struct EditExpenseBudgetFixture: View {
    enum Entry { case edit, create, quick, recurrence }
    let entry: Entry
    @State private var appState: AppStateManager

    init(entry: Entry = .edit) {
        self.entry = entry
        let state = AppStateManager()
        state.selectAccount(Self.data.transaction.fromConto!.account!)
        _appState = State(initialValue: state)
    }
    private static let data: (container: ModelContainer, transaction: FinanceTransaction) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Libro demo", currency: "EUR")
        let conto = Conto(name: "Conto demo", type: .checking, initialBalance: 500)
        conto.account = book; book.conti = [conto]
        let category = FinanceCategory(name: "Cibo", color: "#008080", icon: "cart")
        category.account = book
        let budget = Budget(name: "Spese mensili", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]
        let original = FinanceTransaction(amount: 60, type: .expense, date: Date())
        original.setFromConto(conto); original.setCategory(category)
        let other = FinanceTransaction(amount: 30, type: .expense, date: Date())
        other.setFromConto(conto); other.setCategory(category)
        container.mainContext.insert(book); container.mainContext.insert(category)
        container.mainContext.insert(budget); container.mainContext.insert(original); container.mainContext.insert(other)
        try! container.mainContext.save()
        return (container, original)
    }()
    var body: some View {
        Group {
            switch entry {
            case .edit:
                EditTransactionView(transaction: Self.data.transaction)
            case .create:
                CreateTransactionView(conto: Self.data.transaction.fromConto, transactionType: .expense)
            case .quick:
                QuickTransactionModal()
            case .recurrence:
                RecurrenceSaveFixture(conto: Self.data.transaction.fromConto!)
            }
        }
        .modelContainer(Self.data.container)
        .environment(appState)
    }
}
private struct RecurrenceSaveFixture: View {
    let conto: Conto
    @State private var showingCreation = true
    @Query(filter: #Predicate<FinanceTransaction> { $0.isRecurring == true }) private var saved: [FinanceTransaction]

    var body: some View {
        NavigationStack {
            List {
                Button("Nuova ricorrenza") { showingCreation = true }
                ForEach(saved) { transaction in
                    VStack(alignment: .leading) {
                        Text("Ricorrenza salvata")
                        Text(transaction.date, format: .dateTime.day().month().year())
                        if let end = transaction.recurrenceEndDate {
                            Text("Fine: \(end, format: .dateTime.day().month().year().hour().minute().second())")
                        } else {
                            Text("Senza fine")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreation) {
                CreateTransactionView(conto: conto, transactionType: .expense)
            }
        }
    }
}
#endif
