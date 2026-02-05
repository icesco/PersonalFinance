//
//  EraseDataView.swift
//  Personal Finance
//
//  Created by Claude on 05/02/26.
//

import SwiftUI
import SwiftData
import FinanceCore

struct EraseDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Query private var accounts: [Account]

    @State private var showingFactoryResetAlert = false
    @State private var showingFactoryResetConfirmation = false
    @State private var showingAccountEraseAlert = false
    @State private var showingAccountEraseConfirmation = false
    @State private var accountToErase: Account?
    @State private var confirmationText = ""

    private let factoryResetConfirmationWord = "ELIMINA TUTTO"
    private let accountEraseConfirmationWord = "ELIMINA"

    var body: some View {
        List {
            // Warning Section
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attenzione")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("Le operazioni di cancellazione sono irreversibili. I dati eliminati non possono essere recuperati.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Single Account Erase Section
            Section {
                ForEach(accounts, id: \.id) { account in
                    Button {
                        accountToErase = account
                        showingAccountEraseAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "building.columns")
                                .foregroundColor(.orange)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name ?? "Account Sconosciuto")
                                    .foregroundColor(.primary)

                                Text("\(account.activeConti.count) conti • \((account.categories ?? []).count) categorie")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Cancella Dati Account")
            } footer: {
                Text("Elimina tutti i dati (conti, transazioni, categorie, budget) da un singolo account, mantenendo l'account stesso.")
            }

            // Factory Reset Section
            Section {
                Button {
                    showingFactoryResetAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .frame(width: 24)

                        Text("Ripristino di Fabbrica")
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.red)
            } footer: {
                Text("Elimina tutti gli account e i relativi dati. Verrà ricreato un account predefinito vuoto.")
            }
        }
        .navigationTitle("Cancella Dati")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cancellare i Dati dell'Account?", isPresented: $showingAccountEraseAlert) {
            Button("Annulla", role: .cancel) {
                accountToErase = nil
            }
            Button("Continua", role: .destructive) {
                showingAccountEraseConfirmation = true
            }
        } message: {
            if let account = accountToErase {
                Text("Stai per cancellare tutti i dati di \"\(account.name ?? "Account")\". L'account rimarrà, ma sarà vuoto.")
            }
        }
        .alert("Ripristino di Fabbrica?", isPresented: $showingFactoryResetAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Continua", role: .destructive) {
                showingFactoryResetConfirmation = true
            }
        } message: {
            Text("Stai per eliminare TUTTI gli account e i dati associati. Questa operazione è irreversibile.")
        }
        .sheet(isPresented: $showingAccountEraseConfirmation) {
            confirmationSheet(
                title: "Conferma Cancellazione",
                message: "Per confermare, digita \"\(accountEraseConfirmationWord)\" nel campo sottostante:",
                confirmationWord: accountEraseConfirmationWord,
                onConfirm: {
                    if let account = accountToErase {
                        eraseAccountData(account)
                    }
                    accountToErase = nil
                }
            )
        }
        .sheet(isPresented: $showingFactoryResetConfirmation) {
            confirmationSheet(
                title: "Conferma Ripristino",
                message: "Per confermare il ripristino di fabbrica, digita \"\(factoryResetConfirmationWord)\" nel campo sottostante:",
                confirmationWord: factoryResetConfirmationWord,
                onConfirm: eraseAllData
            )
        }
    }

    // MARK: - Confirmation Sheet

    private func confirmationSheet(
        title: String,
        message: String,
        confirmationWord: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                TextField(confirmationWord, text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 40)

                Button {
                    onConfirm()
                    confirmationText = ""
                } label: {
                    Text("Conferma Eliminazione")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(confirmationText == confirmationWord ? Color.red : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(confirmationText != confirmationWord)
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        confirmationText = ""
                        showingAccountEraseConfirmation = false
                        showingFactoryResetConfirmation = false
                    }
                }
            }
        }
    }

    // MARK: - Data Erasure Functions

    private func eraseAccountData(_ account: Account) {
        // Delete all Conti (cascade deletes Transactions)
        for conto in account.conti ?? [] {
            modelContext.delete(conto)
        }

        // Delete all Categories
        for category in account.categories ?? [] {
            modelContext.delete(category)
        }

        // Delete all Budgets
        for budget in account.budgets ?? [] {
            modelContext.delete(budget)
        }

        // Delete all SavingsGoals
        for savingsGoal in account.savingsGoals ?? [] {
            modelContext.delete(savingsGoal)
        }

        // Recreate default categories for the account
        createDefaultCategories(for: account)

        do {
            try modelContext.save()
        } catch {
            print("Error erasing account data: \(error)")
        }
    }

    private func eraseAllData() {
        // Delete all accounts (cascade deletes everything)
        for account in accounts {
            modelContext.delete(account)
        }

        // Clear selected account
        UserDefaults.standard.removeObject(forKey: "selectedAccountID")
        appState.selectedAccount = nil

        do {
            try modelContext.save()
        } catch {
            print("Error erasing all data: \(error)")
        }

        // Create default account
        createDefaultAccount()
    }

    private func createDefaultAccount() {
        let account = Account(name: "Account Principale", currency: "EUR")
        modelContext.insert(account)

        // Create default categories
        createDefaultCategories(for: account)

        // Create a default checking account
        let checkingAccount = Conto(
            name: "Conto Corrente",
            type: .checking,
            initialBalance: 0
        )
        checkingAccount.account = account
        modelContext.insert(checkingAccount)

        do {
            try modelContext.save()
            appState.selectAccount(account)
        } catch {
            print("Error creating default account: \(error)")
        }
    }

    private func createDefaultCategories(for account: Account) {
        for (name, color, icon) in Category.defaultCategories {
            let category = Category(name: name, color: color, icon: icon)
            category.account = account
            modelContext.insert(category)
        }
    }
}

#Preview {
    NavigationView {
        EraseDataView()
    }
    .environment(AppStateManager())
    .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
