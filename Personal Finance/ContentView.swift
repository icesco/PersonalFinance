//
//  ContentView.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appState = AppStateManager()
    @Query private var accounts: [Account]
    
    var body: some View {
        ZStack {
            if accounts.isEmpty {
                // Show account creation for first-time users
                AccountSelectionModal()
                    .environment(appState)
            } else if appState.requiresAccountSelection(accounts: accounts) {
                // Show account selection modal
                AccountSelectionModal()
                    .environment(appState)
            } else {
                // Show main tab interface
                MainTabView()
                    .environment(appState)
                    .sheet(isPresented: Binding(
                        get: { appState.showingAccountSelection },
                        set: { _ in appState.dismissAccountSelection() }
                    )) {
                        AccountSelectionModal()
                            .environment(appState)
                    }
                    .sheet(isPresented: Binding(
                        get: { appState.showingAccountCreation },
                        set: { _ in appState.dismissAccountCreation() }
                    )) {
                        CreateAccountView { newAccount in
                            appState.selectAccount(newAccount)
                        }
                        .environment(appState)
                    }
            }
        }
        .onAppear {
            initializeAppState()
        }
        .onChange(of: accounts) { _, newAccounts in
            // Handle account changes (creation, deletion)
            appState.loadSelectedAccount(from: newAccounts)
            
            // If no accounts exist after deletion, this will trigger the account creation flow
        }
    }
    
    private func initializeAppState() {
        // Load the selected account from persistence
        appState.loadSelectedAccount(from: accounts)
        
        // Create default account if none exists
        if accounts.isEmpty {
            createDefaultAccount()
        }
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
        // All categories
        for (name, color, icon) in Category.defaultCategories {
            let category = Category(name: name, color: color, icon: icon)
            category.account = account
            modelContext.insert(category)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
