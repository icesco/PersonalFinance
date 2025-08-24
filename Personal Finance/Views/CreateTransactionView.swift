import SwiftUI
import SwiftData
import FinanceCore

struct CreateTransactionView: View {
    let conto: Conto?
    let transactionType: TransactionType
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var navigationRouter
    @State private var amount: Decimal = 0
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var includeTime = false
    @State private var selectedCategory: FinanceCategory?
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurrenceFrequency = .monthly
    @State private var recurrenceEndDate: Date?
    @State private var hasEndDate = false
    
    // For transfers
    @State private var fromConto: Conto?
    @State private var toConto: Conto?
    
    @Query private var categories: [FinanceCategory]
    @Query private var allConti: [Conto]
    
    private var filteredCategories: [FinanceCategory] {
        return categories.filter { $0.isActive == true }
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
                return conto.balance + amount
            }
            return conto.balance
        }
    }
    
    private var activeConti: [Conto] {
        return allConti.filter { $0.isActive == true }
    }
    
    private var isFormInvalid: Bool {
        if amount <= 0 { return true }
        
        if transactionType == .transfer {
            return fromConto == nil || toConto == nil || fromConto?.id == toConto?.id
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
                    HStack {
                        Text(transactionType == .transfer ? "Importo Trasferimento" : 
                             transactionType == .income ? "Importo Entrata" : "Importo Spesa")
                        Spacer()
                        TextField("0,00", value: $amount, format: .currency(code: conto?.account?.currency ?? "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if transactionType == .transfer {
                        // Transfer-specific fields
                        Picker("Da Conto", selection: $fromConto) {
                            Text("Seleziona conto").tag(nil as Conto?)
                            ForEach(activeConti, id: \.id) { conto in
                                HStack {
                                    Image(systemName: conto.type?.icon ?? "creditcard")
                                    Text("\(conto.name ?? "Conto") - \(conto.balance.currencyFormatted)")
                                }
                                .tag(conto as Conto?)
                            }
                        }
                        
                        Picker("A Conto", selection: $toConto) {
                            Text("Seleziona conto").tag(nil as Conto?)
                            ForEach(activeConti.filter { $0.id != fromConto?.id }, id: \.id) { conto in
                                HStack {
                                    Image(systemName: conto.type?.icon ?? "creditcard")
                                    Text("\(conto.name ?? "Conto") - \(conto.balance.currencyFormatted)")
                                }
                                .tag(conto as Conto?)
                            }
                        }
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
                                        .foregroundStyle(Color(hex: category.color ?? "#007AFF") ?? .blue)
                                    Text(category.name ?? "Category")
                                }
                                .tag(category as FinanceCategory?)
                            }
                        }
                    }
                }
                
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
                            DatePicker("Fine ricorrenza", selection: Binding(
                                get: { recurrenceEndDate ?? Date().addingTimeInterval(365 * 24 * 60 * 60) },
                                set: { recurrenceEndDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
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
                                        Text("Saldo attuale: \(fromConto.balance.currencyFormatted)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Nuovo saldo:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text((fromConto.balance - amount).currencyFormatted)
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
                                        Text("Saldo attuale: \(toConto.balance.currencyFormatted)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Nuovo saldo:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text((toConto.balance + amount).currencyFormatted)
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
                                Text("Saldo attuale: \(conto.balance.currencyFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Nuovo saldo:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(calculatedNewBalance.currencyFormatted)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(calculatedNewBalance >= 0 ? .primary : Color.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(transactionType.displayName)
            .navigationBarTitleDisplayMode(.inline)
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
                }
            }
        }
    }
    
    private func createTransaction() {
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
                recurrenceEndDate: isRecurring && hasEndDate ? recurrenceEndDate : nil
            )
            
            transaction.fromConto = fromConto
            transaction.toConto = toConto
            // No category for transfers
            
            modelContext.insert(transaction)
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
                recurrenceEndDate: isRecurring && hasEndDate ? recurrenceEndDate : nil
            )
            
            transaction.category = selectedCategory
            
            if transactionType == .income {
                transaction.toConto = conto
            } else {
                transaction.fromConto = conto
            }
            
            modelContext.insert(transaction)
        }
        
        try? modelContext.save()
        
        // Update statistics for affected accounts
        Task {
            do {
                if transactionType == .transfer {
                    // Update statistics for both accounts involved in transfer
                    if let fromAccount = fromConto?.account {
                        try await StatisticsService.updateStatistics(for: fromAccount, in: modelContext)
                    }
                    if let toAccount = toConto?.account, toAccount.id != fromConto?.account?.id {
                        try await StatisticsService.updateStatistics(for: toAccount, in: modelContext)
                    }
                } else {
                    // Update statistics for the single account
                    if let account = conto?.account {
                        try await StatisticsService.updateStatistics(for: account, in: modelContext)
                    }
                }
            } catch {
                print("Failed to update statistics: \(error)")
            }
        }
        
        dismiss()
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
    }
}
