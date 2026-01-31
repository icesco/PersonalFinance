import SwiftUI
import SwiftData
import FinanceCore

struct CreateTransferView: View {
    let fromConto: Conto
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var navigationRouter
    @State private var amount: Decimal = 0
    @State private var description = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var selectedToConto: Conto?
    
    @Query private var allConti: [Conto]
    
    private var availableConti: [Conto] {
        allConti.filter { $0.id != fromConto.id && ($0.isActive == true) && $0.account?.id == fromConto.account?.id }
    }
    
    private var newFromBalance: Decimal {
        fromConto.balance - amount
    }
    
    private var newToBalance: Decimal {
        (selectedToConto?.balance ?? 0) + amount
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Trasferimento") {
                    HStack {
                        Text("Importo")
                        Spacer()
                        TextField("0,00", value: $amount, format: .currency(code: fromConto.account?.currency ?? "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    if !availableConti.isEmpty {
                        Picker("Verso Conto", selection: $selectedToConto) {
                            Text("Seleziona conto destinazione").tag(nil as Conto?)
                            ForEach(availableConti, id: \.id) { conto in
                                HStack {
                                    Image(systemName: conto.type?.icon ?? "questionmark.circle")
                                    Text(conto.name ?? "Unknown Conto")
                                    Spacer()
                                    Text(conto.balance.currencyFormatted)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(conto as Conto?)
                            }
                        }
                    } else {
                        Text("Nessun altro conto disponibile")
                            .foregroundStyle(.secondary)
                    }
                    
                    TextField("Descrizione", text: $description)
                    
                    DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                }
                
                Section("Dettagli Aggiuntivi") {
                    TextField("Note (opzionale)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                if let toConto = selectedToConto {
                    Section("Riepilogo Trasferimento") {
                        VStack(spacing: 12) {
                            // From account
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: fromConto.type?.icon ?? "questionmark.circle")
                                            .foregroundStyle(.red)
                                        Text("Da: \(fromConto.name ?? "Unknown Conto")")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    
                                    HStack {
                                        Text("Saldo attuale:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(fromConto.balance.currencyFormatted)
                                            .font(.caption)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("-\(amount.currencyFormatted)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.red)
                                    
                                    Text("Nuovo: \(newFromBalance.currencyFormatted)")
                                        .font(.caption)
                                        .foregroundStyle(newFromBalance >= 0 ? .secondary : Color.red)
                                }
                            }
                            
                            Divider()
                            
                            // To account
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: toConto.type?.icon ?? "questionmark.circle")
                                            .foregroundStyle(.green)
                                        Text("A: \(toConto.name ?? "Unknown Conto")")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    
                                    HStack {
                                        Text("Saldo attuale:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(toConto.balance.currencyFormatted)
                                            .font(.caption)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("+\(amount.currencyFormatted)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.green)
                                    
                                    Text("Nuovo: \(newToBalance.currencyFormatted)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trasferimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Trasferisci") {
                        createTransfer()
                    }
                    .disabled(amount <= 0 || selectedToConto == nil)
                }
            }
        }
    }
    
    private func createTransfer() {
        guard let toConto = selectedToConto else { return }

        let transfer = FinanceTransaction.createTransfer(
            amount: amount,
            fromConto: fromConto,
            toConto: toConto,
            date: selectedDate,
            transactionDescription: description.isEmpty ? nil : description,
            notes: notes.isEmpty ? nil : notes
        )

        modelContext.insert(transfer)
        try? modelContext.save()
        dismiss()
    }
}

struct CreateTransferView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! FinanceCoreModule.createModelContainer(inMemory: true)
        let account = Account(name: "Test Account")
        container.mainContext.insert(account)
        
        let fromConto = Conto(name: "Checking", type: .checking, initialBalance: 1000)
        fromConto.account = account
        container.mainContext.insert(fromConto)
        
        let toConto = Conto(name: "Savings", type: .savings, initialBalance: 500)
        toConto.account = account
        container.mainContext.insert(toConto)
        
        return CreateTransferView(fromConto: fromConto)
            .modelContainer(container)
    }
}