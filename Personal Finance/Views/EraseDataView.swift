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
                Text("Elimina Account")
            } footer: {
                Text("Elimina un account e tutti i suoi dati (conti, transazioni, categorie, budget).")
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
        .alert("Eliminare l'Account?", isPresented: $showingAccountEraseAlert) {
            Button("Annulla", role: .cancel) {
                accountToErase = nil
            }
            Button("Continua", role: .destructive) {
                showingAccountEraseConfirmation = true
            }
        } message: {
            if let account = accountToErase {
                Text("Stai per eliminare \"\(account.name ?? "Account")\" e tutti i suoi dati. Questa operazione è irreversibile.")
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
        .sheet(isPresented: $showingAccountEraseConfirmation, onDismiss: {
            accountToErase = nil
        }) {
            if let account = accountToErase {
                TimedConfirmationSheet(
                    title: "Elimina Account",
                    message: "L'account \"\(account.name ?? "Account")\" e tutti i dati associati verranno eliminati permanentemente.",
                    delaySeconds: 3,
                    onConfirm: {
                        eraseAccount(account)
                        showingAccountEraseConfirmation = false
                    },
                    onCancel: {
                        showingAccountEraseConfirmation = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingFactoryResetConfirmation) {
            TimedConfirmationSheet(
                title: "Ripristino di Fabbrica",
                message: "Tutti gli account e i dati associati verranno eliminati permanentemente. Verrà ricreato un account predefinito vuoto.",
                delaySeconds: 5,
                onConfirm: {
                    eraseAllData()
                    showingFactoryResetConfirmation = false
                },
                onCancel: {
                    showingFactoryResetConfirmation = false
                }
            )
        }
    }

    // MARK: - Data Erasure Functions

    private func eraseAccount(_ account: Account) {
        let isLastAccount = accounts.count <= 1
        let wasSelected = appState.selectedAccount?.id == account.id

        // Clear all references BEFORE deleting to prevent SwiftData access to invalidated objects
        if wasSelected {
            appState.selectedConto = nil
            appState.selectedAccount = nil
            UserDefaults.standard.removeObject(forKey: "selectedAccountID")
            UserDefaults.standard.removeObject(forKey: "selectedContoID")
        }

        // Delete the account (cascade deletes conti, transactions, categories, budgets, etc.)
        modelContext.delete(account)

        do {
            try modelContext.save()
        } catch {
            print("Error erasing account: \(error)")
        }

        // If no accounts remain, create a default one
        if isLastAccount {
            createDefaultAccount()
        } else if wasSelected {
            // Select the first remaining account
            if let firstAccount = accounts.first(where: { $0.id != account.id }) {
                appState.selectAccount(firstAccount)
            }
        }
    }

    private func eraseAllData() {
        // Clear all references BEFORE deleting to prevent SwiftData access to invalidated objects
        appState.selectedConto = nil
        appState.selectedAccount = nil
        UserDefaults.standard.removeObject(forKey: "selectedAccountID")
        UserDefaults.standard.removeObject(forKey: "selectedContoID")

        // Delete all accounts (cascade deletes everything)
        for account in accounts {
            modelContext.delete(account)
        }

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

// MARK: - Timed Confirmation Sheet

struct TimedConfirmationSheet: View {
    let title: String
    let message: String
    let delaySeconds: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isReady = false
    @State private var timerStarted = false

    var body: some View {
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

                // Timed confirmation button
                Button(action: onConfirm) {
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isReady ? Color.red : Color.red.opacity(0.3))

                        // Progress fill
                        if !isReady {
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.5))
                                    .frame(width: geometry.size.width * progress)
                                    .animation(.linear(duration: 0.05), value: progress)
                            }
                        }

                        // Label
                        HStack {
                            Spacer()
                            if isReady {
                                Text("Conferma Eliminazione")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            } else {
                                Text("Attendi \(remainingSeconds)s...")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 50)
                }
                .disabled(!isReady)
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onCancel)
                }
            }
            .onAppear {
                startTimer()
            }
        }
    }

    private var remainingSeconds: Int {
        max(0, delaySeconds - Int(progress * CGFloat(delaySeconds)))
    }

    private func startTimer() {
        guard !timerStarted else { return }
        timerStarted = true

        let totalSteps = delaySeconds * 20 // 20 updates per second
        let stepInterval = 1.0 / Double(totalSteps) * Double(delaySeconds)

        for step in 0...totalSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval * Double(step)) {
                withAnimation(.linear(duration: stepInterval)) {
                    progress = CGFloat(step) / CGFloat(totalSteps)
                }
                if step == totalSteps {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReady = true
                    }
                }
            }
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

#Preview("Timed Button") {
    TimedConfirmationSheet(
        title: "Elimina Account",
        message: "L'account \"Test\" verrà eliminato permanentemente.",
        delaySeconds: 3,
        onConfirm: {},
        onCancel: {}
    )
}
