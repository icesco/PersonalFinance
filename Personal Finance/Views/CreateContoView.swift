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
    @State private var selectedColor = "#007AFF"
    @State private var creditLimit: Decimal?
    @State private var statementClosingDay: Int?
    @State private var paymentDueDay: Int?
    @State private var annualInterestRate: Decimal?
    @State private var savingsGoal: Decimal?
    
    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#A2845E", "#8E8E93"
    ]
    
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

                Section("Personalizzazione") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colore")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 8)], spacing: 8) {
                            ForEach(colors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
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
                    .disabled(contoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedBalance == nil)
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

            conto.account = savedAccount
            context.insert(conto)
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
    
    @State private var contoName = ""
    @State private var selectedType: ContoType = .checking
    @State private var description = ""
    @State private var selectedColor = "#007AFF"
    @State private var showingColorPicker = false
    @State private var creditLimit: Decimal?
    @State private var statementClosingDay: Int?
    @State private var paymentDueDay: Int?
    @State private var annualInterestRate: Decimal?
    @State private var savingsGoal: Decimal?
    
    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#A2845E", "#8E8E93"
    ]
    
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

                Section("Personalizzazione") {
                    HStack {
                        Text("Colore")
                        Spacer()
                        Button {
                            showingColorPicker = true
                        } label: {
                            Circle()
                                .fill(Color(hex: selectedColor))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
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
                    .disabled(contoName.isEmpty)
                }
            }
        }
        .onAppear {
            loadContoData()
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerView(selectedColor: $selectedColor)
        }
    }
    
    private func loadContoData() {
        contoName = conto.name ?? ""
        selectedType = conto.type ?? .checking
        description = conto.contoDescription ?? ""
        selectedColor = conto.color ?? "#007AFF"
        creditLimit = conto.creditLimit
        statementClosingDay = conto.statementClosingDay
        paymentDueDay = conto.paymentDueDay
        annualInterestRate = conto.annualInterestRate
        savingsGoal = conto.savingsGoal
    }

    private func updateConto() {
        conto.name = contoName
        conto.type = selectedType
        conto.contoDescription = description.isEmpty ? nil : description
        conto.color = selectedColor
        conto.creditLimit = selectedType == .credit ? creditLimit : nil
        conto.statementClosingDay = selectedType == .credit ? statementClosingDay : nil
        conto.paymentDueDay = selectedType == .credit ? paymentDueDay : nil
        conto.annualInterestRate = selectedType == .investment ? annualInterestRate : nil
        conto.savingsGoal = selectedType == .savings ? savingsGoal : nil
        conto.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error updating conto: \(error)")
        }
    }
}

// MARK: - Color Picker View

struct ColorPickerView: View {
    @Binding var selectedColor: String
    @Environment(\.dismiss) private var dismiss
    
    private let colors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#AF52DE", "#FF2D92",
        "#A2845E", "#8E8E93"
    ]
    
    var body: some View {
        NavigationView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 60))
            ], spacing: 20) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        selectedColor = color
                        dismiss()
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                            )
                            .overlay(
                                selectedColor == color ?
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                : nil
                            )
                    }
                }
            }
            .padding()
            .navigationTitle("Seleziona Colore")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CreateContoView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        return CreateContoView(account: account)
            .modelContainer(container)
    }
}
