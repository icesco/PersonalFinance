//
//  DashboardView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    // Recent transactions (last 5)
    private var recentTransactions: [FinanceTransaction] {
        Array(appState.allTransactions(for: appState.selectedAccount).prefix(5))
    }
    
    // Account statistics
    private var totalBalance: Decimal {
        appState.selectedAccount?.totalBalance ?? 0
    }
    
    private var monthlyIncome: Decimal {
        let startOfMonth = Date().startOfMonth
        let endOfMonth = Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth) ?? Date()
        
        return appState.allTransactions(for: appState.selectedAccount)
            .filter { transaction in
                guard let date = transaction.date,
                      transaction.type == .income else { return false }
                return date >= startOfMonth && date < endOfMonth
            }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    private var monthlyExpenses: Decimal {
        let startOfMonth = Date().startOfMonth
        let endOfMonth = Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth) ?? Date()
        
        return appState.allTransactions(for: appState.selectedAccount)
            .filter { transaction in
                guard let date = transaction.date,
                      transaction.type == .expense else { return false }
                return date >= startOfMonth && date < endOfMonth
            }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Account Header
                    accountHeaderSection
                    
                    // Quick Stats
                    quickStatsSection
                    
                    // Account Overview Cards
                    contiOverviewSection
                    
                    // Recent Transactions
                    recentTransactionsSection
                    
                    // Quick Actions
                    quickActionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 100) // Space for floating button
            }
            .navigationTitle("Dashboard")
            .background(Color(.systemGroupedBackground))
        }
    }
    
    // MARK: - Account Header Section
    
    private var accountHeaderSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saldo Totale")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(totalBalance.currencyFormatted)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(totalBalance >= 0 ? .primary : .red)
                }
                
                Spacer()
                
                Button {
                    appState.presentAccountSelection()
                } label: {
                    HStack {
                        Text(appState.selectedAccount?.name ?? "Nessun Account")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                    }
                }
                .foregroundColor(.accentColor)
            }
            
            if let account = appState.selectedAccount {
                Text("\(account.activeConti.count) conti attivi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Quick Stats Section
    
    private var quickStatsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Entrate Mese",
                value: monthlyIncome.currencyFormatted,
                color: .green,
                icon: "arrow.down.circle.fill"
            )
            
            StatCard(
                title: "Spese Mese",
                value: monthlyExpenses.currencyFormatted,
                color: .red,
                icon: "arrow.up.circle.fill"
            )
        }
    }
    
    // MARK: - Conti Overview Section
    
    private var contiOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I Tuoi Conti")
                .font(.headline)
                .padding(.horizontal)
            
            if appState.activeConti(for: appState.selectedAccount).isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: "Nessun Conto",
                    description: "Aggiungi il tuo primo conto per iniziare"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appState.activeConti(for: appState.selectedAccount), id: \.id) { conto in
                        ContoCard(conto: conto)
                    }
                }
            }
        }
    }
    
    // MARK: - Recent Transactions Section
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transazioni Recenti")
                    .font(.headline)
                
                Spacer()
                
                Button("Vedi Tutte") {
                    appState.selectTab(.transactions)
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            
            if recentTransactions.isEmpty {
                EmptyStateView(
                    icon: "list.bullet",
                    title: "Nessuna Transazione",
                    description: "Le tue transazioni appariranno qui"
                )
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(recentTransactions, id: \.id) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Azioni Rapide")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionCard(
                    title: "Nuova Spesa",
                    icon: "minus.circle",
                    color: .red
                ) {
                    appState.presentQuickTransaction(type: .expense)
                }
                
                QuickActionCard(
                    title: "Nuova Entrata",
                    icon: "plus.circle",
                    color: .green
                ) {
                    appState.presentQuickTransaction(type: .income)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ContoCard: View {
    let conto: Conto
    
    var body: some View {
        HStack {
            Image(systemName: conto.type?.icon ?? "questionmark.circle")
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Conto Sconosciuto")
                    .font(.headline)
                
                Text(conto.type?.displayName ?? "Tipo sconosciuto")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(conto.balance.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(conto.balance >= 0 ? .primary : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}


struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter
    }()
}

#Preview {
    DashboardView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}