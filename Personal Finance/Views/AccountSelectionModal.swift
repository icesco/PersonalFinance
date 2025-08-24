//
//  AccountSelectionModal.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct AccountSelectionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @Query private var accounts: [Account]
    @State private var showingAccountCreation = false
    
    // Check if this is the initial selection (no account selected)
    private var isInitialSelection: Bool {
        appState.selectedAccount == nil
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if accounts.isEmpty {
                    emptyStateView
                } else {
                    accountListView
                }
            }
            .navigationTitle(isInitialSelection ? "Seleziona Account" : "Cambia Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isInitialSelection {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAccountCreation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .interactiveDismissDisabled(isInitialSelection) // Prevent dismissal if no account is selected
        }
        .sheet(isPresented: $showingAccountCreation) {
            CreateAccountView { newAccount in
                // Auto-select the newly created account
                appState.selectAccount(newAccount)
            }
        }
    }
    
    // MARK: - Account List View
    
    private var accountListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Header Information
                if isInitialSelection {
                    VStack(spacing: 12) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        
                        Text("Benvenuto in Personal Finance")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Seleziona un account per iniziare a gestire le tue finanze")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 24)
                }
                
                // Account Cards
                ForEach(accounts.filter { $0.isActive == true }, id: \.id) { account in
                    AccountSelectionCard(account: account) {
                        appState.selectAccount(account)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("Nessun Account")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Crea il tuo primo account per iniziare a gestire le tue finanze personali")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Crea Primo Account") {
                showingAccountCreation = true
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Account Selection Card

struct AccountSelectionCard: View {
    let account: Account
    let onSelect: () -> Void
    
    @Environment(AppStateManager.self) private var appState
    
    private var isSelected: Bool {
        account.id == appState.selectedAccount?.id
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "building.columns.fill")
                        .font(.title2)
                        .foregroundColor(isSelected ? .white : .accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name ?? "Account Sconosciuto")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .primary)
                        
                        Text(account.currency ?? "EUR")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                
                // Account Statistics
                VStack(spacing: 12) {
                    // Balance
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saldo Totale")
                                .font(.caption)
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                            
                            Text(account.totalBalance.currencyFormatted)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(isSelected ? .white : (account.totalBalance >= 0 ? .primary : .red))
                        }
                        
                        Spacer()
                    }
                    
                    // Account Info
                    HStack {
                        AccountInfoChip(
                            title: "Conti",
                            value: "\(account.activeConti.count)",
                            isSelected: isSelected
                        )
                        
                        AccountInfoChip(
                            title: "Categorie",
                            value: "\(account.categories?.filter { $0.isActive == true }.count ?? 0)",
                            isSelected: isSelected
                        )
                        
                        AccountInfoChip(
                            title: "Budget",
                            value: "\(account.budgets?.filter { $0.isActive == true }.count ?? 0)",
                            isSelected: isSelected
                        )
                        
                        Spacer()
                    }
                }
                
                // Creation Date
                if let createdAt = account.createdAt {
                    Text("Creato il \(DateFormatter.longDate.string(from: createdAt))")
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                    .shadow(color: .black.opacity(isSelected ? 0.2 : 0.05), radius: isSelected ? 8 : 2, x: 0, y: isSelected ? 4 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Account Info Chip

struct AccountInfoChip: View {
    let title: String
    let value: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.2) : Color(.systemGray6))
        )
    }
}


#Preview {
    AccountSelectionModal()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}