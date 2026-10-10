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
    @State private var isSavingsInterest = false
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
    
    init(conto: Conto?, transactionType: TransactionType, savingsInterest: Bool = false) {
        _isSavingsInterest = State(initialValue: savingsInterest)
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
    
    private var amountInvalid: Bool {
        !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount <= 0
    }

    private var typeTint: Color {
        transactionType == .income ? ForgiaPalette.sageSurface : transactionType == .expense ? ForgiaPalette.apricotSurface : ForgiaPalette.canvas
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if transactionType != .transfer {
                        VoiceTransactionEntryButton(onComplete: { dismiss() })
                    }
                    amountCard

                    if transactionType == .transfer && hasDifferentCurrencies {
                        receivedAmountCard
                    }

                    FormCard(title: "Dettagli") { detailsRows }
                    if transactionType == .income && conto?.type == .savings {
                        FormCard(title: "Risparmio") {
                            Toggle("Interessi accreditati", isOn: $isSavingsInterest)
                            Text("Aumentano il saldo senza essere conteggiati come capitale versato.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if transactionType == .expense && amount > 0 {
                        if let category = selectedCategory, let account = conto?.account {
                            ExpenseBudgetCheckView(amount: amount, categoryID: category.id, accountID: account.id,
                                                   date: selectedDate, currency: account.currency ?? "EUR", isRecurring: isRecurring)
                        } else {
                            Label("Scegli una categoria per confrontare la spesa con i budget del libro.", systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(ForgiaPalette.mutedText)
                        }
                    }

                    balanceImpact

                    FormCard(title: "Ricorrenza") { recurrenceRows }

                    TransactionPlaceEditor(place: $place, isLocating: $loadingLocation, cardStyle: true)

                    DraftAttachmentsView(attachments: $attachmentDrafts, onSelectAmount: { amount = $0 }, loading: $loadingAttachment,
                                         cardStyle: true)

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
                CurrencyConversionSheet(targetCurrency: fromConto?.account?.currency ?? conto?.account?.currency ?? "EUR", transactionDate: selectedDate, existing: foreignAmount) { value in
                    foreignAmount = value; amount = value.converted ?? 0
                }
            }
            .onChange(of: amount) { _, value in
                if let foreignAmount, value != foreignAmount.converted { self.foreignAmount = nil }
            }
            .sheet(isPresented: $showingCalculator) {
                AmountCalculatorView(initialAmount: amount, currency: amountCurrency) { amount = $0 }
            }
            .alert("Impossibile salvare", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .navigationTitle(transactionType == .transfer ? "Nuovo trasferimento" : transactionType == .income ? "Nuova entrata" : "Nuova spesa")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: createTransaction)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(isFormInvalid)
                }
                #endif
            }
        }
    }

    // MARK: - Cards

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(transactionType == .transfer ? "IMPORTO TRASFERITO" : "IMPORTO")
                    .font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer()
                Button { showingCalculator = true } label: {
                    Label("Calcolatrice", systemImage: "plus.forwardslash.minus")
                }
                .font(.subheadline)
                .tint(ForgiaPalette.accent)
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
                    .accessibilityIdentifier("create-transaction-amount")
            }
            .font(.system(size: 45, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.7)

            if amountInvalid {
                Text("Inserisci un importo positivo valido per questa valuta, senza separatori delle migliaia.")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("create-transaction-amount-invalid")
            }

            if transactionType != .transfer {
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
                                        identifier: "create-transaction-destination-amount")
                    Text("L'addebito è nella valuta del conto di partenza, l'accredito in quella di destinazione.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var detailsRows: some View {
        if transactionType == .transfer {
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
                CategoryPickerMenu(categories: filteredCategories, type: transactionType, selection: $selectedCategory) {
                    FormSelectionLabel(title: "Categoria", value: selectedCategory?.displayPath ?? "Seleziona una categoria",
                                       isPlaceholder: selectedCategory == nil)
                }
                .accessibilityLabel("Categoria")
            }
            FormRowDivider()
        }

        FormRow(icon: "text.alignleft") {
            TextField(transactionType == .transfer ? "Descrizione (opzionale)" : "Descrizione", text: $description)
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
        RecurrenceEditorRows(
            isRecurring: $isRecurring,
            frequency: $selectedFrequency,
            hasEndDate: $hasEndDate,
            endDate: $recurrenceEndDate,
            startDate: selectedDate
        )
    }

    /// Current and resulting balance of every account the movement touches.
    @ViewBuilder
    private var balanceImpact: some View {
        if transactionType == .transfer {
            if let fromConto, let toConto {
                FormCard(title: "Effetto sui saldi") {
                    balanceRow(conto: fromConto, icon: "minus", tint: ForgiaPalette.apricotSurface,
                               after: fromConto.balance - amount)
                    FormRowDivider()
                    balanceRow(conto: toConto, icon: "plus", tint: ForgiaPalette.sageSurface,
                               after: toConto.balance + (hasDifferentCurrencies ? destinationAmount : amount))
                }
            }
        } else if let conto {
            FormCard(title: "Effetto sul saldo") {
                balanceRow(conto: conto, icon: transactionType == .income ? "plus" : "minus", tint: typeTint,
                           after: calculatedNewBalance)
            }
        }
    }

    private func balanceRow(conto: Conto, icon: String, tint: Color, after: Decimal) -> some View {
        let currency = conto.account?.currency ?? "EUR"
        return FormRow(icon: icon, tint: tint) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conto.name ?? "Conto")
                    .font(.body)
                    .lineLimit(1)
                Text("Ora \(conto.balance.formatted(.currency(code: currency)))")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Dopo")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(after.formatted(.currency(code: currency)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(after >= 0 ? Color.primary : Color.red)
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: after).doubleValue))
                    .animation(.snappy, value: after)
            }
        }
        .accessibilityElement(children: .combine)
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
        Button(action: createTransaction) {
            Text(transactionType == .transfer ? "Salva trasferimento" : transactionType == .income ? "Salva entrata" : "Salva spesa")
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

            transaction.isSavingsInterest = transactionType == .income && conto.type == .savings && isSavingsInterest
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
