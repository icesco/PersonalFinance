import SwiftUI
import SwiftData
import FinanceCore

struct CreateTransactionView: View {
    let conto: Conto
    let transactionType: TransactionType
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var navigationRouter
    @State private var amount: Decimal = 0
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var selectedCategory: FinanceCategory?
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurrenceFrequency = .monthly
    @State private var recurrenceEndDate: Date?
    @State private var hasEndDate = false
    
    @Query private var categories: [FinanceCategory]
    
    private var filteredCategories: [FinanceCategory] {
        let categoryType: CategoryType = transactionType == .income ? .income : .expense
        return categories.filter { $0.type == categoryType && ($0.isActive == true) }
    }
    
    private var calculatedNewBalance: Decimal {
        transactionType == .income ? conto.balance + amount : conto.balance - amount
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Transazione") {
                    HStack {
                        Text(transactionType == .income ? "Importo Entrata" : "Importo Spesa")
                        Spacer()
                        TextField("0,00", value: $amount, format: .currency(code: conto.account?.currency ?? "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    TextField("Descrizione", text: $description)
                    
                    DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                    
                    if !filteredCategories.isEmpty {
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
                    .disabled(amount <= 0)
                }
            }
        }
    }
    
    private func createTransaction() {
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
        
        try? modelContext.save()
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
        
        let category = FinanceCategory(name: "Food", type: .expense)
        category.account = account
        container.mainContext.insert(category)
        
        return CreateTransactionView(conto: conto, transactionType: .expense)
            .modelContainer(container)
    }
}
