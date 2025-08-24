import SwiftUI
import SwiftData
import FinanceCore

// MARK: - Create Savings Goal View

struct CreateSavingsGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var name = ""
    @State private var targetAmount: Decimal = 0
    @State private var goalDescription = ""
    @State private var selectedCategory: SavingsGoalCategory = .other
    @State private var hasTargetDate = false
    @State private var targetDate = Date().addingTimeInterval(365 * 24 * 60 * 60) // 1 year from now
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Informazioni Obiettivo") {
                    TextField("Nome obiettivo", text: $name)
                    
                    HStack {
                        Text("Importo target")
                        Spacer()
                        DecimalField(placeholder: "€0,00", value: $targetAmount)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Categoria", selection: $selectedCategory) {
                        ForEach(SavingsGoalCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.displayName)
                            }
                            .tag(category)
                        }
                    }
                    
                    TextField("Descrizione (opzionale)", text: $goalDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Scadenza") {
                    Toggle("Imposta data target", isOn: $hasTargetDate)
                    
                    if hasTargetDate {
                        DatePicker("Data target", selection: $targetDate, displayedComponents: .date)
                    }
                }
                
                if isValid {
                    Section("Anteprima") {
                        GoalPreviewCard(
                            name: name,
                            targetAmount: targetAmount,
                            category: selectedCategory,
                            targetDate: hasTargetDate ? targetDate : nil,
                            description: goalDescription.isEmpty ? nil : goalDescription
                        )
                    }
                }
            }
            .navigationTitle("Nuovo Obiettivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        createGoal()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func createGoal() {
        guard let account = appState.selectedAccount else { return }
        
        let goal = SavingsGoal(
            name: name.trimmingCharacters(in: .whitespaces),
            targetAmount: targetAmount,
            targetDate: hasTargetDate ? targetDate : nil,
            category: selectedCategory,
            goalDescription: goalDescription.trimmingCharacters(in: .whitespaces).isEmpty ? nil : goalDescription
        )
        
        goal.account = account
        modelContext.insert(goal)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving goal: \(error)")
        }
    }
}

// MARK: - Edit Savings Goal View

struct EditSavingsGoalView: View {
    let goal: SavingsGoal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String
    @State private var targetAmount: Decimal
    @State private var goalDescription: String
    @State private var selectedCategory: SavingsGoalCategory
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var selectedStatus: SavingsGoalStatus
    
    init(goal: SavingsGoal) {
        self.goal = goal
        _name = State(initialValue: goal.name ?? "")
        _targetAmount = State(initialValue: goal.targetAmount ?? 0)
        _goalDescription = State(initialValue: goal.goalDescription ?? "")
        _selectedCategory = State(initialValue: goal.category ?? .other)
        _hasTargetDate = State(initialValue: goal.targetDate != nil)
        _targetDate = State(initialValue: goal.targetDate ?? Date().addingTimeInterval(365 * 24 * 60 * 60))
        _selectedStatus = State(initialValue: goal.status ?? .active)
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Informazioni Obiettivo") {
                    TextField("Nome obiettivo", text: $name)
                    
                    HStack {
                        Text("Importo target")
                        Spacer()
                        DecimalField(placeholder: "€0,00", value: $targetAmount)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Categoria", selection: $selectedCategory) {
                        ForEach(SavingsGoalCategory.allCases, id: \.self) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.displayName)
                            }
                            .tag(category)
                        }
                    }
                    
                    Picker("Stato", selection: $selectedStatus) {
                        ForEach(SavingsGoalStatus.allCases, id: \.self) { status in
                            Text(status.displayName)
                                .tag(status)
                        }
                    }
                    
                    TextField("Descrizione", text: $goalDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Scadenza") {
                    Toggle("Data target", isOn: $hasTargetDate)
                    
                    if hasTargetDate {
                        DatePicker("Data target", selection: $targetDate, displayedComponents: .date)
                    }
                }
                
                Section("Progresso Attuale") {
                    HStack {
                        Text("Importo attuale")
                        Spacer()
                        Text(goal.currentAmount?.currencyFormatted ?? "€0,00")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Percentuale completamento")
                        Spacer()
                        Text("\(Int(goal.progressPercentage))%")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Modifica Obiettivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func saveChanges() {
        goal.name = name.trimmingCharacters(in: .whitespaces)
        goal.targetAmount = targetAmount
        goal.goalDescription = goalDescription.trimmingCharacters(in: .whitespaces).isEmpty ? nil : goalDescription
        goal.category = selectedCategory
        goal.targetDate = hasTargetDate ? targetDate : nil
        goal.status = selectedStatus
        goal.updatedAt = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving changes: \(error)")
        }
    }
}

// MARK: - Update Progress View

struct UpdateProgressView: View {
    let goal: SavingsGoal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var progressAmount: Decimal = 0
    @State private var notes = ""
    @State private var progressDate = Date()
    
    private var newTotal: Decimal {
        (goal.currentAmount ?? 0) + progressAmount
    }
    
    private var newPercentage: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        return min(Double(truncating: newTotal as NSDecimalNumber) / Double(truncating: target as NSDecimalNumber), 1.0) * 100
    }
    
    private var isValid: Bool {
        progressAmount > 0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Obiettivo") {
                    HStack {
                        if let category = goal.category {
                            Image(systemName: category.icon)
                                .foregroundColor(.accentColor)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(goal.name ?? "Obiettivo Sconosciuto")
                                .font(.headline)
                            Text("Target: \(goal.targetAmount?.currencyFormatted ?? "€0,00")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(goal.currentAmount?.currencyFormatted ?? "€0,00")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(Int(goal.progressPercentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Aggiungi Progresso") {
                    HStack {
                        Text("Importo")
                        Spacer()
                        DecimalField(placeholder: "€0,00", value: $progressAmount)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    DatePicker("Data", selection: $progressDate, displayedComponents: .date)
                    
                    TextField("Note (opzionale)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                if isValid {
                    Section("Nuovo Totale") {
                        HStack {
                            Text("Nuovo importo")
                            Spacer()
                            Text(newTotal.currencyFormatted)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        
                        HStack {
                            Text("Nuova percentuale")
                            Spacer()
                            Text("\(Int(newPercentage))%")
                                .fontWeight(.medium)
                                .foregroundColor(newPercentage >= 100 ? .green : .primary)
                        }
                        
                        if newPercentage >= 100 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Obiettivo completato!")
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aggiungi Progresso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveProgress()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func saveProgress() {
        goal.addProgress(amount: progressAmount)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving progress: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct GoalPreviewCard: View {
    let name: String
    let targetAmount: Decimal
    let category: SavingsGoalCategory
    let targetDate: Date?
    let description: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    
                    if let description = description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("€0,00")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(targetAmount.currencyFormatted)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                    .cornerRadius(4)
                
                HStack {
                    Text("0% completato")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let targetDate = targetDate {
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
                        Text("\(days) giorni rimanenti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct DecimalField: View {
    let placeholder: String
    @Binding var value: Decimal
    
    @State private var textValue = ""
    
    var body: some View {
        TextField(placeholder, text: $textValue, prompt: Text(placeholder))
            .keyboardType(.decimalPad)
            .onAppear {
                textValue = value == 0 ? "" : "\(value)"
            }
            .onChange(of: textValue) { _, newValue in
                if newValue.isEmpty {
                    value = 0
                } else if let decimal = Decimal(string: newValue.replacingOccurrences(of: ",", with: ".")) {
                    value = decimal
                }
            }
            .onChange(of: value) { _, newValue in
                if newValue == 0 {
                    textValue = ""
                } else {
                    textValue = "\(newValue)"
                }
            }
    }
}

#Preview {
    CreateSavingsGoalView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
