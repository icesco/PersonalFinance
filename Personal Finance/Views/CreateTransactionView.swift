import SwiftUI
import SwiftData
import FinanceCore

struct CreateTransactionView: View {
    let conto: Conto?
    let transactionType: TransactionType
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState
    @State private var place = PlaceDraft()
    @State private var loadingLocation = false
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var loadingAttachment = false
    @State private var saveError: String?
    @State private var foreignAmount: ForeignAmountDraft?
    @State private var showingConversion = false
    @State private var amountText = ""
    @State private var showingCalculator = false
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var includeTime = false
    @State private var selectedCategory: FinanceCategory?
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurrenceFrequency = .monthly
    @State private var recurrenceEndDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasEndDate = false
    
    // For transfers
    @State private var fromConto: Conto?
    @State private var toConto: Conto?
    @State private var destinationAmountText = ""
    
    @Query private var categories: [FinanceCategory]
    @Query private var allConti: [Conto]
    
    private var amountCurrency: String { fromConto?.account?.currency ?? conto?.account?.currency ?? "EUR" }
    private var amount: Decimal {
        get { BalanceInput.parse(amountText, currency: amountCurrency) ?? 0 }
        nonmutating set { amountText = NSDecimalNumber(decimal: newValue).stringValue }
    }
    private var destinationAmount: Decimal {
        get { BalanceInput.parse(destinationAmountText, currency: toConto?.account?.currency ?? "EUR") ?? 0 }
        nonmutating set { destinationAmountText = NSDecimalNumber(decimal: newValue).stringValue }
    }

    private var filteredCategories: [FinanceCategory] {
        guard let bookID = conto?.account?.id else { return [] }
        return categories.filter { $0.isActive == true && $0.account?.id == bookID }
    }
    
    private var calculatedNewBalance: Decimal {
        guard let conto = conto else { return 0 }
        
        switch transactionType {
        case .income:
            return conto.balance + amount
        case .expense:
            return conto.balance - amount
        case .transfer:
            // For transfers, show the balance change based on whether this conto is source or destination
            if let fromConto = fromConto, fromConto.id == conto.id {
                return conto.balance - amount
            } else if let toConto = toConto, toConto.id == conto.id {
                return conto.balance + (hasDifferentCurrencies ? destinationAmount : amount)
            }
            return conto.balance
        }
    }
    
    private var activeConti: [Conto] {
        return allConti.filter { $0.isActive == true }
    }
    
    private var hasDifferentCurrencies: Bool {
        guard let from = fromConto, let to = toConto else { return false }
        return (from.account?.currency ?? "EUR") != (to.account?.currency ?? "EUR")
    }

    private var effectiveRecurrenceEndDate: Date? {
        RecurrenceSchedule.inclusiveEnd(anchor: selectedDate, lastDay: recurrenceEndDate)
    }

    private var isFormInvalid: Bool {
        if loadingLocation || amount <= 0 || loadingAttachment { return true }
        if isRecurring && hasEndDate && effectiveRecurrenceEndDate == nil { return true }
        
        if transactionType == .transfer {
            return fromConto == nil || toConto == nil || fromConto?.id == toConto?.id || (hasDifferentCurrencies && destinationAmount <= 0)
        }
        
        return false
    }
    
    init(conto: Conto?, transactionType: TransactionType) {
        self.conto = conto
        self.transactionType = transactionType
        
        // Initialize transfer conti
        if transactionType == .transfer {
            _fromConto = State(initialValue: conto)
            _toConto = State(initialValue: nil)
        } else {
            _fromConto = State(initialValue: nil)
            _toConto = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Transazione") {
                    CurrencyAmountField(title: transactionType == .transfer ? "Importo Trasferimento" :
                                            transactionType == .income ? "Importo Entrata" : "Importo Spesa",
                                        text: $amountText, currency: amountCurrency,
                                        identifier: "create-transaction-amount")
                    
                    if transactionType != .transfer {
                        Button("Importo in valuta estera", systemImage: "arrow.left.arrow.right") { showingConversion = true }
                        if let foreignAmount {
                            Text("Originale: \(foreignAmount.originalAmount.formatted(.currency(code: foreignAmount.originalCurrency)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Calcolatrice", systemImage: "plus.forwardslash.minus") { showingCalculator = true }

                    if transactionType == .transfer {
                        // Transfer-specific fields
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
                                            identifier: "create-transaction-destination-amount")
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
                    
                    if transactionType != .transfer && !filteredCategories.isEmpty {
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
                
                Section { TransactionPlaceEditor(place: $place, isLocating: $loadingLocation) }
                Section { DraftAttachmentsView(attachments: $attachmentDrafts, onSelectAmount: { amount = $0 }, loading: $loadingAttachment) }

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
                
                if transactionType == .expense, amount > 0,
                   let category = selectedCategory, let account = conto?.account {
                    ExpenseBudgetCheckView(
                        amount: amount, categoryID: category.id, accountID: account.id,
                        date: selectedDate, currency: account.currency ?? "EUR", isRecurring: isRecurring
                    )
                }

                Section {
                    if transactionType == .transfer {
                        // Transfer summary
                        if let fromConto = fromConto, let toConto = toConto {
                            VStack(spacing: 12) {
                                // From conto
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Da: \(fromConto.name ?? "Unknown Conto")")
                                            .font(.subheadline.weight(.medium))
                                        Text("Saldo attuale: \(fromConto.balance.formatted(.currency(code: fromConto.account?.currency ?? "EUR")))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Nuovo saldo:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text((fromConto.balance - amount).formatted(.currency(code: fromConto.account?.currency ?? "EUR")))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle((fromConto.balance - amount) >= 0 ? .primary : Color.red)
                                    }
                                }
                                
                                // To conto
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("A: \(toConto.name ?? "Unknown Conto")")
                                            .font(.subheadline.weight(.medium))
                                        Text("Saldo attuale: \(toConto.balance.formatted(.currency(code: toConto.account?.currency ?? "EUR")))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Nuovo saldo:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text((toConto.balance + (hasDifferentCurrencies ? destinationAmount : amount)).formatted(.currency(code: toConto.account?.currency ?? "EUR")))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    } else if let conto = conto {
                        // Regular transaction summary
                        HStack {
                            Image(systemName: transactionType.icon)
                                .foregroundStyle(transactionType == .income ? .green : Color.red)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(transactionType.displayName) su \(conto.name ?? "Unknown Conto")")
                                    .font(.subheadline.weight(.medium))
                                Text("Saldo attuale: \(conto.balance.formatted(.currency(code: conto.account?.currency ?? "EUR")))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Nuovo saldo:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(calculatedNewBalance.formatted(.currency(code: conto.account?.currency ?? "EUR")))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(calculatedNewBalance >= 0 ? .primary : Color.red)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if transactionType == .expense, amount > 0,
                   let category = selectedCategory, let book = conto?.account {
                    ExpenseBudgetCheckView(amount: amount, categoryID: category.id, accountID: book.id,
                                           date: selectedDate, currency: book.currency ?? "EUR",
                                           isRecurring: isRecurring, compact: true)
                        .padding(12)
                        .background(.regularMaterial)
                }
            }
            .sheet(isPresented: $showingConversion) {
                CurrencyConversionSheet(targetCurrency: fromConto?.account?.currency ?? conto?.account?.currency ?? "EUR", transactionDate: selectedDate, existing: foreignAmount) { value in
                    foreignAmount = value; amount = value.converted ?? 0
                }
            }
            .onChange(of: amount) { _, value in
                if let foreignAmount, value != foreignAmount.converted { self.foreignAmount = nil }
            }
            .sheet(isPresented: $showingCalculator) {
                AmountCalculatorView(initialAmount: amount, currency: fromConto?.account?.currency ?? conto?.account?.currency ?? "EUR") { amount = $0 }
            }
            .alert("Impossibile salvare", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .navigationTitle(transactionType.displayName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        createTransaction()
                    }
                    .disabled(isFormInvalid)
                    #if os(macOS)
                    .keyboardShortcut("s", modifiers: .command)
                    #endif
                }
            }
        }
    }
    
    private func createTransaction() {
        guard !isFormInvalid else { return }
        var created: FinanceTransaction?
        if transactionType == .transfer {
            // Create transfer transaction
            guard let fromConto = fromConto, let toConto = toConto else { return }
            
            let transaction = FinanceTransaction(
                amount: amount,
                type: .transfer,
                date: selectedDate,
                transactionDescription: description.isEmpty ? "Trasferimento da \(fromConto.name ?? "Conto") a \(toConto.name ?? "Conto")" : description,
                notes: notes.isEmpty ? nil : notes,
                isRecurring: isRecurring,
                recurrenceFrequency: isRecurring ? selectedFrequency : nil,
                recurrenceEndDate: isRecurring && hasEndDate ? effectiveRecurrenceEndDate : nil
            )
            
            transaction.destinationAmount = hasDifferentCurrencies ? destinationAmount : nil
            transaction.setFromConto(fromConto)
            transaction.setToConto(toConto)
            // No category for transfers

            foreignAmount?.apply(to: transaction)
            place.apply(to: transaction)
            transaction.attachments = attachmentDrafts.map { $0.model() }
            modelContext.insert(transaction)
            created = transaction
        } else {
            // Create regular transaction
            guard let conto = conto else { return }

            let transaction = FinanceTransaction(
                amount: amount,
                type: transactionType,
                date: selectedDate,
                transactionDescription: description.isEmpty ? nil : description,
                notes: notes.isEmpty ? nil : notes,
                isRecurring: isRecurring,
                recurrenceFrequency: isRecurring ? selectedFrequency : nil,
                recurrenceEndDate: isRecurring && hasEndDate ? effectiveRecurrenceEndDate : nil
            )

            transaction.setCategory(selectedCategory)

            if transactionType == .income {
                transaction.setToConto(conto)
            } else {
                transaction.setFromConto(conto)
            }
            
            foreignAmount?.apply(to: transaction)
            place.apply(to: transaction)
            transaction.attachments = attachmentDrafts.map { $0.model() }
            modelContext.insert(transaction)
            created = transaction
        }
        
        do {
            try modelContext.save()
            appState.triggerDataRefresh()
            dismiss()
        } catch {
            if let created { modelContext.delete(created) }
            saveError = error.localizedDescription
        }
    }
}

struct CreateTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        let conto = Conto(name: "Test Conto", type: .checking, initialBalance: 1000)
        conto.account = account
        container.mainContext.insert(conto)
        
        let category = FinanceCategory(name: "Food")
        category.account = account
        container.mainContext.insert(category)
        
        return CreateTransactionView(conto: conto, transactionType: .expense)
            .modelContainer(container)
            .environment(AppStateManager())
    }
}
