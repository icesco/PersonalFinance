import SwiftUI
import SwiftData
import FinanceCore

struct EditTransactionView: View {
    let transaction: FinanceTransaction
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

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
        categories.filter { $0.isActive == true }
    }

    private var activeConti: [Conto] {
        allConti.filter { $0.isActive == true }
    }

    private var isFormInvalid: Bool {
        if amount <= 0 { return true }

        if transaction.type == .transfer {
            return fromConto == nil || toConto == nil || fromConto?.id == toConto?.id
        }

        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Transazione") {
                    HStack {
                        Text(transaction.type == .transfer ? "Importo Trasferimento" :
                             transaction.type == .income ? "Importo Entrata" : "Importo Spesa")
                        Spacer()
                        TextField("0,00", value: $amount, format: .currency(code: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if transaction.type == .transfer {
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

                    if transaction.type != .transfer && !filteredCategories.isEmpty {
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
            }
            .navigationTitle("Modifica Transazione")
            .navigationBarTitleDisplayMode(.inline)
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
                }
            }
            .onAppear {
                loadTransactionData()
            }
        }
    }

    private func loadTransactionData() {
        amount = transaction.amount ?? Decimal(0)
        description = transaction.transactionDescription ?? ""
        notes = transaction.notes ?? ""
        selectedDate = transaction.date
        selectedCategory = transaction.category
        isRecurring = transaction.isRecurring ?? false
        selectedFrequency = transaction.recurrenceFrequency ?? .monthly
        recurrenceEndDate = transaction.recurrenceEndDate
        hasEndDate = transaction.recurrenceEndDate != nil

        // Check if time component is non-zero
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: transaction.date)
        includeTime = (components.hour != 0 || components.minute != 0)

        // Transfer conti
        fromConto = transaction.fromConto
        toConto = transaction.toConto
    }

    private func updateTransaction() {
        transaction.amount = amount
        transaction.date = selectedDate
        transaction.transactionDescription = description.isEmpty ? nil : description
        transaction.notes = notes.isEmpty ? nil : notes
        transaction.isRecurring = isRecurring
        transaction.recurrenceFrequency = isRecurring ? selectedFrequency : nil
        transaction.recurrenceEndDate = isRecurring && hasEndDate ? recurrenceEndDate : nil
        transaction.updatedAt = Date()

        // Use setters to keep denormalized IDs in sync
        if transaction.type == .transfer {
            transaction.setFromConto(fromConto)
            transaction.setToConto(toConto)
        } else {
            transaction.setCategory(selectedCategory)
        }

        try? modelContext.save()
        appState.triggerDataRefresh()
        dismiss()
    }
}
