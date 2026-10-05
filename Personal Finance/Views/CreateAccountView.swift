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
    @State private var showingSaveError = false
    
    private let currencies = Locale.commonISOCurrencyCodes.sorted()
    
    init(onAccountCreated: ((Account) -> Void)? = nil) {
        self.onAccountCreated = onAccountCreated
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "books.vertical")
                            .font(.title)
                            .foregroundStyle(ForgiaPalette.accent)
                            .padding(16)
                            .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 20))
                        Text("Uno spazio per le tue finanze")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Riunisci conti, spese e budget in un libro.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nome del libro").font(.subheadline.weight(.medium))
                            TextField("Ad esempio, Personale o Famiglia", text: $accountName)
                                .textFieldStyle(.plain)
                                .padding(14)
                                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("new-book-name")
                        }
                        HStack {
                            Text("Valuta del libro").font(.subheadline.weight(.medium))
                            Spacer()
                            Picker("Valuta del libro", selection: $currency) {
                                ForEach(currencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(14)
                        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                        Text("Conti e budget di questo libro useranno la valuta scelta.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(action: createAccount) {
                        Text("Crea libro")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ForgiaPalette.accent)
                    .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: 480)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .themedBackground()
            .navigationTitle("Nuovo libro")
            .toolbarTitleDisplayMode(.inline)
            .alert("Impossibile creare il libro", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text("Il libro non è stato salvato. Controlla i dati e riprova.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                

            }
        }
    }
    
    private func createAccount() {
        do {
            let account = try AccountCreation(context: modelContext).create(name: accountName, currency: currency)
            if let onAccountCreated {
                onAccountCreated(account)
            } else {
                navigationRouter.selectAccount(account)
            }
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        return CreateAccountView()
            .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
    }
}