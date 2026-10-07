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

    private var amountInvalid: Bool {
        !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount <= 0
    }

    private var typeTint: Color {
        transaction.type == .income ? ForgiaPalette.sageSurface : transaction.type == .expense ? ForgiaPalette.apricotSurface : ForgiaPalette.canvas
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    amountCard

                    if transaction.type == .transfer && hasDifferentCurrencies {
                        receivedAmountCard
                    }

                    FormCard(title: "Dettagli") { detailsRows }
                    if transaction.type == .income && transaction.toConto?.type == .savings {
                        FormCard(title: "Risparmio") {
                            Toggle("Interessi accreditati", isOn: $isSavingsInterest)
                            Text("Aumentano il saldo senza essere conteggiati come capitale versato.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if transaction.type == .expense && amount > 0 {
                        if let category = selectedCategory, let book = transaction.fromConto?.account {
                            ExpenseBudgetCheckView(amount: amount, categoryID: category.id, accountID: book.id,
                                                   date: selectedDate, currency: book.currency ?? "EUR", isRecurring: isRecurring,
                                                   excludingTransactionID: transaction.id)
                        } else {
                            Label("Scegli una categoria per confrontare la spesa con i budget del libro.", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }

                    FormCard(title: "Ricorrenza") { recurrenceRows }

                    TransactionPlaceEditor(place: $place, isLocating: $loadingLocation, cardStyle: true)

                    FormCard(title: "Note") {
                        FormRow(icon: "note.text") {
                            TextField("Aggiungi una nota (opzionale)", text: $notes, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .background(ForgiaPalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            #if !os(macOS)
            .safeAreaBar(edge: .bottom, spacing: 0) { saveBar }
            #endif
            .sheet(isPresented: $showingConversion) {
                CurrencyConversionSheet(targetCurrency: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR", transactionDate: selectedDate, existing: foreignAmount) { value in
                    foreignAmount = value; amount = value.converted ?? 0
                }
            }
            .onChange(of: amount) { _, value in
                if let foreignAmount, value != foreignAmount.converted { self.foreignAmount = nil }
            }
            .navigationTitle("Modifica movimento")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: updateTransaction)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(isFormInvalid)
                }
                #endif
            }
            .alert("Impossibile salvare", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear {
                loadTransactionData()
            }
        }
    }

    // MARK: - Cards

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(transaction.type == .transfer ? "IMPORTO TRASFERITO" : "IMPORTO")
                    .font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer()
                Label(transaction.type.displayName, systemImage: transaction.type == .income ? "arrow.down.left"
                      : transaction.type == .expense ? "arrow.up.right" : "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(typeTint, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amountCurrency)
                    .font(.headline)
                    .foregroundStyle(ForgiaPalette.accent)
                TextField("0,00", text: $amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Importo")
                    .accessibilityIdentifier("edit-transaction-amount")
            }
            .font(.system(size: 45, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.7)

            if amountInvalid {
                Text("Inserisci un importo positivo valido per questa valuta, senza separatori delle migliaia.")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("edit-transaction-amount-invalid")
            }

            if transaction.type != .transfer {
                Button("Importo in valuta estera", systemImage: "arrow.left.arrow.right") { showingConversion = true }
                    .font(.subheadline)
                    .tint(ForgiaPalette.accent)
                if let foreignAmount {
                    Text("\(foreignAmount.originalAmount.formatted(.currency(code: foreignAmount.originalCurrency))) · cambio \(foreignAmount.rate.formatted())")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var receivedAmountCard: some View {
        FormCard(title: "Accredito") {
            FormRow(icon: "arrow.down.to.line", tint: ForgiaPalette.sageSurface) {
                VStack(alignment: .leading, spacing: 4) {
                    CurrencyAmountField(title: "Importo ricevuto", text: $destinationAmountText,
                                        currency: toConto?.account?.currency ?? "EUR",
                                        identifier: "edit-transaction-destination-amount")
                    Text("L'addebito è nella valuta del conto di partenza, l'accredito in quella di destinazione.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var detailsRows: some View {
        if transaction.type == .transfer {
            FormRow(icon: "arrow.up.right", tint: ForgiaPalette.apricotSurface) {
                contoMenu(title: "Dal conto", selection: $fromConto, options: activeConti)
            }
            FormRowDivider()
            FormRow(icon: "arrow.down.left", tint: ForgiaPalette.sageSurface) {
                contoMenu(title: "Al conto", selection: $toConto, options: activeConti.filter { $0.id != fromConto?.id })
            }
            FormRowDivider()
        } else if !filteredCategories.isEmpty {
            FormRow(icon: selectedCategory?.icon ?? "tag", tint: typeTint) {
                CategoryPickerMenu(categories: filteredCategories, type: transaction.type, selection: $selectedCategory) {
                    FormSelectionLabel(title: "Categoria", value: selectedCategory?.displayPath ?? "Nessuna categoria",
                                       isPlaceholder: selectedCategory == nil)
                }
                .accessibilityLabel("Categoria")
            }
            FormRowDivider()
        }

        FormRow(icon: "text.alignleft") {
            TextField("Descrizione", text: $description)
                .accessibilityLabel("Descrizione")
        }
        FormRowDivider()
        FormRow(icon: "calendar") {
            Text("Data")
            Spacer(minLength: 8)
            DatePicker("Data", selection: $selectedDate,
                       displayedComponents: includeTime ? [.date, .hourAndMinute] : .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(ForgiaPalette.accent)
        }
        FormRowDivider()
        FormRow(icon: "clock") {
            Toggle("Includi orario", isOn: $includeTime.animation())
                .tint(ForgiaPalette.accent)
        }
    }

    @ViewBuilder
    private var recurrenceRows: some View {
        FormRow(icon: "arrow.triangle.2.circlepath", tint: ForgiaPalette.sageSurface) {
            Toggle("Movimento ricorrente", isOn: $isRecurring.animation())
                .tint(ForgiaPalette.accent)
        }
        if isRecurring {
            FormRowDivider()
            FormRow(icon: "calendar.badge.clock") {
                Text("Frequenza")
                Spacer(minLength: 8)
                Picker("Frequenza", selection: $selectedFrequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .labelsHidden()
                .tint(ForgiaPalette.accent)
            }
            FormRowDivider()
            FormRow(icon: "flag.checkered") {
                Toggle("Data di fine", isOn: $hasEndDate.animation())
                    .tint(ForgiaPalette.accent)
            }
            if hasEndDate {
                FormRowDivider()
                FormRow(icon: "calendar.badge.minus") {
                    Text("Fine ricorrenza")
                    Spacer(minLength: 8)
                    DatePicker("Fine ricorrenza", selection: $recurrenceEndDate,
                               in: Calendar.current.startOfDay(for: selectedDate)..., displayedComponents: .date)
                        .labelsHidden()
                        .tint(ForgiaPalette.accent)
                }
                if effectiveRecurrenceEndDate == nil {
                    Text("La fine della ricorrenza non può precedere la data iniziale.")
                        .font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func contoMenu(title: String, selection: Binding<Conto?>, options: [Conto]) -> some View {
        Menu {
            Picker(title, selection: selection) {
                Text("Seleziona conto").tag(nil as Conto?)
                ForEach(options, id: \.id) { conto in
                    ContoPickerLabel(conto: conto).tag(conto as Conto?)
                }
            }
        } label: {
            FormSelectionLabel(title: title, value: selection.wrappedValue?.name ?? "Seleziona conto",
                               isPlaceholder: selection.wrappedValue == nil)
        }
        .accessibilityLabel(title)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: updateTransaction) {
                Text("Salva modifiche")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(isFormInvalid ? ForgiaPalette.border : ForgiaPalette.accent,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(isFormInvalid ? ForgiaPalette.mutedText : ForgiaPalette.onAccent)
            }
            .disabled(isFormInvalid)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
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
