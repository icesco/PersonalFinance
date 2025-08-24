import SwiftUI
import SwiftData
import FinanceCore

struct CreateAccountView: View {
    let onAccountCreated: ((Account) -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var navigationRouter
    @State private var accountName = ""
    @State private var currency = "EUR"
    
    private let currencies = ["EUR", "USD", "GBP", "CHF", "JPY"]
    
    init(onAccountCreated: ((Account) -> Void)? = nil) {
        self.onAccountCreated = onAccountCreated
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli Account") {
                    TextField("Nome Account", text: $accountName)
                    
                    Picker("Valuta", selection: $currency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                }
                
                Section {
                    Text("L'account rappresenta il contenitore principale per tutti i tuoi conti (corrente, risparmio, carte di credito, ecc.) e permette di tenere traccia del tuo patrimonio complessivo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuovo Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        createAccount()
                    }
                    .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createAccount() {
        let account = Account(
            name: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency
        )
        
        modelContext.insert(account)
        
        // Create default categories for the new account
        createDefaultCategories(for: account)
        
        try? modelContext.save()
        
        // Call the callback if provided
        onAccountCreated?(account)
        
        // Update navigation router to select the new account if no callback provided
        if onAccountCreated == nil {
            navigationRouter.selectAccount(account)
        }
        
        dismiss()
    }
    
    private func createDefaultCategories(for account: Account) {
        // All categories
        for (name, color, icon) in Category.defaultCategories {
            let category = Category(name: name, color: color, icon: icon)
            category.account = account
            modelContext.insert(category)
        }
    }
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        return CreateAccountView()
            .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
    }
}