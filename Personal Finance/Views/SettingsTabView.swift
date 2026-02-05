//
//  SettingsTabView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(DataStorageManager.self) private var dataStorageManager
    
    @Query private var accounts: [Account]
    @State private var showingAccountCreation = false
    @State private var showingCSVImport = false
    @State private var showingCSVExport = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                accountSection
                
                // App Settings
                appSettingsSection
                
                // Data Management
                dataManagementSection
                
                // About
                aboutSection
            }
            .navigationTitle("Impostazioni")
        }
        .sheet(isPresented: $showingAccountCreation) {
            CreateAccountView()
        }
        .sheet(isPresented: $showingCSVImport) {
            CSVImportView()
        }
        .sheet(isPresented: $showingCSVExport) {
            CSVExportView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        Section("Account") {
            // Current Account Info
            if let selectedAccount = appState.selectedAccount {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.columns.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedAccount.name ?? "Account Sconosciuto")
                                .font(.headline)
                            
                            Text("\(selectedAccount.activeConti.count) conti • \(selectedAccount.totalBalance.currencyFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Cambia") {
                            appState.presentAccountSelection()
                        }
                        .foregroundColor(.accentColor)
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Switch Account
            Button {
                appState.presentAccountSelection()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Cambia Account")
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
            
            // Create New Account
            Button {
                showingAccountCreation = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Nuovo Account")
                    
                    Spacer()
                }
            }
            .foregroundColor(.primary)
            
            // Manage Accounts
            NavigationLink {
                AccountManagementView()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Gestisci Account")
                }
            }
        }
    }
    
    // MARK: - App Settings Section
    
    private var appSettingsSection: some View {
        Section("Impostazioni App") {
            // Cloud Sync
            HStack {
                Image(systemName: "icloud")
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading) {
                    Text("Sincronizzazione iCloud")
                    Text("Sincronizza i dati tra i tuoi dispositivi")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { dataStorageManager.isCloudSyncEnabled },
                    set: { dataStorageManager.isCloudSyncEnabled = $0 }
                ))
            }
            
            // Notifications (placeholder)
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading) {
                        Text("Notifiche")
                        Text("Gestisci avvisi e promemoria")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // App Icon (placeholder)
            NavigationLink {
                AppIconSettingsView()
            } label: {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Icona App")
                }
            }
        }
    }
    
    // MARK: - Data Management Section
    
    private var dataManagementSection: some View {
        Section("Gestione Dati") {
            // Import CSV
            Button {
                showingCSVImport = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    Text("Importa da CSV")

                    Spacer()
                }
            }
            .foregroundColor(.primary)

            // Export CSV
            Button {
                showingCSVExport = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.green)
                        .frame(width: 24)

                    Text("Esporta in CSV")

                    Spacer()
                }
            }
            .foregroundColor(.primary)

            // Backup & Restore
            NavigationLink {
                BackupRestoreView()
            } label: {
                HStack {
                    Image(systemName: "externaldrive")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)

                    Text("Backup e Ripristino")
                }
            }

            // Erase Data
            NavigationLink {
                EraseDataView()
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 24)

                    Text("Cancella Dati")
                }
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section("Info") {
            // Privacy Policy
            Button {
                // Open privacy policy URL
                if let url = URL(string: "https://francescobianco.cc/privacy") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "hand.raised")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Privacy Policy")
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
            
            // Terms of Service
            Button {
                // Open terms URL
                if let url = URL(string: "https://francescobianco.cc/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Termini di Servizio")
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
            
            // About
            Button {
                showingAbout = true
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    
                    Text("Informazioni")
                    
                    Spacer()
                }
            }
            .foregroundColor(.primary)
        }
    }
}

// MARK: - Account Management View

struct AccountManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Query private var accounts: [Account]
    
    @State private var showingAccountCreation = false
    @State private var accountToEdit: Account?
    
    var body: some View {
        List {
            ForEach(accounts, id: \.id) { account in
                AccountManagementRow(account: account) {
                    accountToEdit = account
                }
                .swipeActions(edge: .trailing) {
                    if accounts.count > 1 {
                        Button("Elimina", role: .destructive) {
                            deleteAccount(account)
                        }
                    }
                    
                    Button("Modifica") {
                        accountToEdit = account
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Gestisci Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAccountCreation = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAccountCreation) {
            CreateAccountView()
        }
        .sheet(item: $accountToEdit) { account in
            EditAccountView(account: account)
        }
    }
    
    private func deleteAccount(_ account: Account) {
        // Cannot delete if it's the only account or the selected account
        guard accounts.count > 1, account.id != appState.selectedAccount?.id else { return }
        
        modelContext.delete(account)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting account: \(error)")
        }
    }
}

// MARK: - Account Management Row

struct AccountManagementRow: View {
    let account: Account
    let onEdit: () -> Void
    
    @Environment(AppStateManager.self) private var appState
    
    var body: some View {
        Button(action: onEdit) {
            HStack {
                Image(systemName: "building.columns.fill")
                    .foregroundColor(account.id == appState.selectedAccount?.id ? .accentColor : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(account.name ?? "Account Sconosciuto")
                            .font(.headline)
                        
                        if account.id == appState.selectedAccount?.id {
                            Text("ATTUALE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack {
                        Text("\(account.activeConti.count) conti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• \(account.currency ?? "EUR")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let createdAt = account.createdAt {
                            Text("• \(DateFormatter.monthYear.string(from: createdAt))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(account.totalBalance.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(account.totalBalance >= 0 ? .primary : .red)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Account View

struct EditAccountView: View {
    let account: Account
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var accountName = ""
    @State private var accountCurrency = "EUR"
    
    private let availableCurrencies = ["EUR", "USD", "GBP", "JPY", "CHF", "CAD", "AUD"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Dettagli Account") {
                    TextField("Nome Account", text: $accountName)
                    
                    Picker("Valuta", selection: $accountCurrency) {
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                }
                
                Section("Statistiche") {
                    HStack {
                        Text("Conti Attivi")
                        Spacer()
                        Text("\(account.activeConti.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Saldo Totale")
                        Spacer()
                        Text(account.totalBalance.currencyFormatted)
                            .foregroundColor(.secondary)
                    }
                    
                    if let createdAt = account.createdAt {
                        HStack {
                            Text("Creato")
                            Spacer()
                            Text(DateFormatter.longDate.string(from: createdAt))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Modifica Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        updateAccount()
                    }
                    .disabled(accountName.isEmpty)
                }
            }
        }
        .onAppear {
            accountName = account.name ?? ""
            accountCurrency = account.currency ?? "EUR"
        }
    }
    
    private func updateAccount() {
        account.name = accountName
        account.currency = accountCurrency
        account.updatedAt = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error updating account: \(error)")
        }
    }
}

// MARK: - Placeholder Views

struct NotificationSettingsView: View {
    var body: some View {
        List {
            Section("Avvisi Budget") {
                Toggle("Soglia Budget Raggiunta", isOn: .constant(true))
                Toggle("Budget Superato", isOn: .constant(true))
            }
            
            Section("Promemoria") {
                Toggle("Transazioni Ricorrenti", isOn: .constant(false))
                Toggle("Backup Settimanale", isOn: .constant(true))
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppIconSettingsView: View {
    var body: some View {
        Text("Impostazioni icona app - Coming Soon")
            .navigationTitle("Icona App")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct BackupRestoreView: View {
    var body: some View {
        List {
            Section("Backup") {
                Button("Crea Backup Locale") {
                    // Implement backup
                }
                
                Button("Backup su iCloud") {
                    // Implement iCloud backup
                }
            }
            
            Section("Ripristino") {
                Button("Ripristina da Backup") {
                    // Implement restore
                }
            }
        }
        .navigationTitle("Backup e Ripristino")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image("logo-forgia")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(spacing: 8) {
                    Text("Forgia")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Versione 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Forgia il tuo futuro finanziario. Gestisci entrate, spese e budget con consapevolezza per costruire una solida base di risparmio.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Text("Sviluppato da Francesco Bianco")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Visita il Sito Web") {
                        if let url = URL(string: "https://francescobianco.cc") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(.accentColor)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Informazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") {
                        // Dismiss
                    }
                }
            }
        }
    }
}

// MARK: - DateFormatter Extensions

extension DateFormatter {
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()
    
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()
}

#Preview {
    SettingsTabView()
        .environment(AppStateManager())
        .environment(DataStorageManager.shared)
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}