import SwiftUI
import SwiftData
import FinanceCore

struct CreateContoView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var contoName = ""
    @State private var selectedType: ContoType = .checking
    @State private var initialBalance = ""
    @State private var saveError: String?
    private var parsedBalance: Decimal? { BalanceInput.parse(initialBalance, currency: account.currency ?? "EUR") }
    @State private var description = ""
    @State private var logoData: Data?
    @State private var loadingLogo = false
    @State private var selectedColor = AccountPalette.fallback
    @State private var creditLimit: Decimal?
    @State private var statementClosingDay: Int?
    @State private var paymentDueDay: Int?
    @State private var annualInterestRate: Decimal?
    @State private var savingsGoal: Decimal?
    @State private var linkedGoalID: UUID?
    @State private var rateDate = Calendar.current.startOfDay(for: Date())
    @Query private var goals: [SavingsGoal]
    
    init(account: Account) {
        self.account = account
        _selectedColor = State(initialValue: AccountPalette.suggestedColor(used: (account.conti ?? []).map(\.displayColorHex)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Conto") {
                    TextField("Nome Conto", text: $contoName)
                        .accessibilityIdentifier("conto-name")
                    
                    Picker("Tipo", selection: $selectedType) {
                        ForEach(ContoType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    
                    HStack {
                        Text("Saldo Iniziale")
                        Spacer()
                        Text(account.currency ?? "EUR").foregroundStyle(.secondary)
                        Button {
                            let value = initialBalance.trimmingCharacters(in: .whitespacesAndNewlines)
                            if value.hasPrefix("-") { initialBalance = String(value.dropFirst()) }
                            else { initialBalance = "-" + (value.hasPrefix("+") ? String(value.dropFirst()) : value) }
                        } label: {
                            Image(systemName: "plus.forwardslash.minus")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cambia segno del saldo")
                        .accessibilityIdentifier("conto-balance-sign")
                        TextField("0,00", text: $initialBalance)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("conto-initial-balance")
                    }
                    if parsedBalance == nil {
                        Text("Inserisci un saldo valido nella valuta del libro, senza separatori delle migliaia.")
                            .foregroundStyle(.red)
                    }
                    if let saveError { Text(saveError).foregroundStyle(.red) }
                }
                
                ContoTypeSpecificFieldsView(
                    selectedType: selectedType,
                    currency: account.currency ?? "EUR",
                    creditLimit: $creditLimit,
                    statementClosingDay: $statementClosingDay,
                    paymentDueDay: $paymentDueDay,
                    annualInterestRate: $annualInterestRate,
                    savingsGoal: $savingsGoal
                )

                if selectedType == .savings {
                    Section("Collegamento al risparmio") {
                        DatePicker("Tasso valido dal", selection: $rateDate, in: ...Date(), displayedComponents: .date)
                        Picker("Obiettivo collegato", selection: $linkedGoalID) {
                            Text("Nuovo obiettivo dal valore indicato").tag(nil as UUID?)
                            ForEach(goals.filter { $0.account?.id == account.id }) { goal in
                                Text(goal.name ?? "Obiettivo").tag(Optional(goal.id))
                            }
                        }
                        Text("I versamenti e i prelievi aggiornano automaticamente l’obiettivo. Il saldo iniziale è incluso; gli interessi restano separati. Senza importo o selezione non viene creato un obiettivo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Personalizzazione") {
                    ContoLogoEditor(data: $logoData, loading: $loadingLogo, symbol: selectedType.icon, color: selectedColor, accountName: contoName)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colore")
                        AccountColorGrid(selection: $selectedColor)
                    }

                    TextField("Descrizione (opzionale)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section {
                    Text("Il conto rappresenta un singolo strumento finanziario (conto corrente, carta di credito, conto risparmio, ecc.) all'interno del tuo account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuovo Conto")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        createConto()
                    }
                    .disabled(contoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedBalance == nil || loadingLogo || (savingsGoal != nil && (savingsGoal ?? 0) <= 0))
                    .accessibilityIdentifier("conto-save")
                }
            }
            .onChange(of: selectedType) {
                creditLimit = nil
                statementClosingDay = nil
                paymentDueDay = nil
                annualInterestRate = nil
                savingsGoal = nil
            }
        }
    }

    private func createConto() {
        guard let balance = parsedBalance, !contoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveError = nil
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        do {
            let accountID = account.id
            guard let savedAccount = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountID })).first else {
                saveError = "Il libro non è più disponibile. Chiudi questa schermata e seleziona un altro libro."
                return
            }
            let conto = Conto(
                name: contoName.trimmingCharacters(in: .whitespacesAndNewlines),
                type: selectedType,
                initialBalance: balance,
                contoDescription: description.isEmpty ? nil : description,
                color: selectedColor,
                creditLimit: selectedType == .credit ? creditLimit : nil,
                statementClosingDay: selectedType == .credit ? statementClosingDay : nil,
                paymentDueDay: selectedType == .credit ? paymentDueDay : nil,
                annualInterestRate: selectedType == .investment ? annualInterestRate : nil,
                savingsGoal: selectedType == .savings ? savingsGoal : nil
            )

            conto.logoData = logoData
            conto.account = savedAccount
            context.insert(conto)
            if selectedType == .savings {
                if let rate = annualInterestRate, conto.savingsRates.last?.annualPercent != rate { try conto.setSavingsRate(rate, effectiveDate: rateDate) }
                try SavingsAccountEdits.linkGoal(conto: conto, existingID: linkedGoalID, target: savingsGoal, context: context)
            }
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Non è stato possibile salvare il conto. I dati inseriti restano qui: riprova."
        }
    }
}

// MARK: - Edit Conto View

struct EditContoView: View {
    let conto: Conto
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var saveError: String?
    @State private var loaded = false
    @State private var contoName = ""
    @State private var selectedType: ContoType = .checking
    @State private var description = ""
    @State private var logoData: Data?
    @State private var loadingLogo = false
    @State private var selectedColor = AccountPalette.fallback
    @State private var creditLimit: Decimal?
    @State private var statementClosingDay: Int?
    @State private var paymentDueDay: Int?
    @State private var annualInterestRate: Decimal?
    @State private var savingsGoal: Decimal?
    @State private var linkedGoalID: UUID?
    @State private var rateDate = Calendar.current.startOfDay(for: Date())
    @Query private var goals: [SavingsGoal]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Conto") {
                    TextField("Nome Conto", text: $contoName)
                    
                    Picker("Tipo", selection: $selectedType) {
                        ForEach(ContoType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    
                    TextField("Descrizione (opzionale)", text: $description)
                }
                
                ContoTypeSpecificFieldsView(
                    selectedType: selectedType,
                    currency: conto.account?.currency ?? "EUR",
                    creditLimit: $creditLimit,
                    statementClosingDay: $statementClosingDay,
                    paymentDueDay: $paymentDueDay,
                    annualInterestRate: $annualInterestRate,
                    savingsGoal: $savingsGoal
                )

                if selectedType == .savings {
                    Section("Collegamento al risparmio") {
                        DatePicker("Tasso valido dal", selection: $rateDate, in: ...Date(), displayedComponents: .date)
                        Picker("Obiettivo collegato", selection: $linkedGoalID) {
                            Text("Nuovo obiettivo dal valore indicato").tag(nil as UUID?)
                            ForEach(goals.filter { $0.account?.id == conto.account?.id }) { goal in
                                Text(goal.name ?? "Obiettivo").tag(Optional(goal.id))
                            }
                        }
                        Text("I versamenti e i prelievi aggiornano automaticamente l’obiettivo. Il saldo iniziale è incluso; gli interessi restano separati. Senza importo o selezione non viene creato un obiettivo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Personalizzazione") {
                    ContoLogoEditor(data: $logoData, loading: $loadingLogo, symbol: selectedType.icon, color: selectedColor, accountName: contoName)
                    AccountColorGrid(selection: $selectedColor)
                }

                if selectedType == .savings {
                    SavingsAccountSummary(conto: conto, allowsActions: false)
                }
                Section("Saldo Corrente") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saldo attuale")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(conto.balance.formatted(.currency(code: conto.account?.currency ?? "EUR")))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(conto.balance >= 0 ? .primary : .red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Modifica Conto")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        updateConto()
                    }
                    .disabled(contoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingLogo || (savingsGoal != nil && (savingsGoal ?? 0) <= 0))
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loadContoData()
            loaded = true
        }
        .alert("Impossibile salvare il conto", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
    
    private func loadContoData() {
        contoName = conto.name ?? ""
        selectedType = conto.type ?? .checking
        description = conto.contoDescription ?? ""
        logoData = conto.logoData
        selectedColor = conto.displayColorHex
        creditLimit = conto.creditLimit
        statementClosingDay = conto.statementClosingDay
        paymentDueDay = conto.paymentDueDay
        annualInterestRate = conto.savingsRates.last?.annualPercent ?? conto.annualInterestRate
        savingsGoal = conto.linkedSavingsGoal?.targetAmount ?? conto.savingsGoal
        linkedGoalID = conto.savingsGoalID
        rateDate = Calendar.current.startOfDay(for: Date())
    }

    private func updateConto() {
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        let id = conto.id
        do {
            guard let target = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == id })).first else {
                saveError = "Il conto non è più disponibile."
                return
            }
            target.name = contoName.trimmingCharacters(in: .whitespacesAndNewlines)
            target.type = selectedType
            target.contoDescription = description.isEmpty ? nil : description
            target.color = selectedColor
            target.logoData = logoData
            target.creditLimit = selectedType == .credit ? creditLimit : nil
            target.statementClosingDay = selectedType == .credit ? statementClosingDay : nil
            target.paymentDueDay = selectedType == .credit ? paymentDueDay : nil
            target.annualInterestRate = selectedType == .investment ? annualInterestRate : (selectedType == .savings ? target.annualInterestRate : nil)
            target.savingsGoal = selectedType == .savings ? savingsGoal : nil
            target.updatedAt = Date()
            if selectedType == .savings {
                if let rate = annualInterestRate, target.savingsRates.last?.annualPercent != rate {
                    try target.setSavingsRate(rate, effectiveDate: rateDate)
                } else if annualInterestRate == nil && !target.savingsRates.isEmpty {
                    try target.setSavingsRate(0, effectiveDate: rateDate)
                }
                try SavingsAccountEdits.linkGoal(conto: target, existingID: linkedGoalID, target: savingsGoal, context: context)
            } else { target.savingsGoalID = nil }
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveError = "Non è stato possibile salvare il conto. I dati inseriti restano qui: riprova."
        }
    }

}

// MARK: - Color Picker View

struct ColorPickerView: View {
    @Binding var selectedColor: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView { AccountColorGrid(selection: $selectedColor).padding() }
                .navigationTitle("Seleziona Colore")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { dismiss() }
                    }
                }
        }
    }
}

struct AccountColorGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 14) {
            ForEach(AccountPalette.swatches) { swatch in
                Button { selection = swatch.hex } label: {
                    VStack(spacing: 6) {
                        Circle().fill(Color(hex: swatch.hex)).frame(width: 36, height: 36)
                            .overlay {
                                if selection == swatch.hex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                        Text(LocalizedStringKey(swatch.name)).font(.caption2).foregroundStyle(.primary).lineLimit(1)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(swatch.name)))
                .accessibilityAddTraits(selection == swatch.hex ? .isSelected : [])
            }
        }
        ColorPicker("Colore personalizzato", selection: Binding(
            get: { Color(hex: selection) },
            set: { color in
                let components = color.colorComponents
                let red = Int((min(max(components.red, 0), 1) * 255).rounded())
                let green = Int((min(max(components.green, 0), 1) * 255).rounded())
                let blue = Int((min(max(components.blue, 0), 1) * 255).rounded())
                selection = String(format: "#%02X%02X%02X", red, green, blue)
            }
        ), supportsOpacity: false)
        .accessibilityIdentifier("conto-custom-color")
        if !AccountPalette.swatches.contains(where: { $0.hex.caseInsensitiveCompare(selection) == .orderedSame }) {
            Text(selection.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct AccountPaletteVisualFixture: View {
    @State private var selection = ProcessInfo.processInfo.arguments.contains("UITEST_CUSTOM_ACCOUNT_COLOR") ? "#D27C9A" : AccountPalette.fallback
    var body: some View {
        NavigationStack {
            Form {
                Section("Palette dei conti · dati demo") {
                    AccountColorGrid(selection: $selection)
                }
                Section("Anteprima") {
                    Label { Text("Conto corrente") } icon: {
                        Image(systemName: "creditcard").foregroundStyle(Color(hex: selection))
                    }
                    Label { Text("Risparmi") } icon: {
                        Image(systemName: "banknote").foregroundStyle(Color(hex: AccountPalette.petrolio))
                    }
                    Label { Text("Contanti") } icon: {
                        Image(systemName: "dollarsign.circle").foregroundStyle(Color(hex: AccountPalette.ocra))
                    }
                }
            }.navigationTitle("Colori dei conti")
        }
    }
}
#endif

struct CreateContoView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        return CreateContoView(account: account)
            .modelContainer(container)
    }
}
