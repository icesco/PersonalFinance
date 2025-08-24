//
//  TransactionListView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var searchText = ""
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var selectedTypeFilter: TransactionTypeFilter = .all
    @State private var showingFilters = false
    
    // Filtered transactions
    private var filteredTransactions: [FinanceTransaction] {
        var transactions = appState.allTransactions(for: appState.selectedAccount)
        
        // Apply search filter
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                let descriptionMatch = transaction.transactionDescription?.localizedCaseInsensitiveContains(searchText) ?? false
                let categoryMatch = transaction.category?.name?.localizedCaseInsensitiveContains(searchText) ?? false
                let notesMatch = transaction.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                return descriptionMatch || categoryMatch || notesMatch
            }
        }
        
        // Apply time filter
        switch selectedTimeFilter {
        case .all:
            break
        case .today:
            transactions = transactions.filter { $0.date?.isToday == true }
        case .thisWeek:
            transactions = transactions.filter { $0.date?.isThisWeek == true }
        case .thisMonth:
            transactions = transactions.filter { $0.date?.isThisMonth == true }
        case .last30Days:
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            transactions = transactions.filter { 
                guard let date = $0.date else { return false }
                return date >= thirtyDaysAgo 
            }
        }
        
        // Apply type filter
        switch selectedTypeFilter {
        case .all:
            break
        case .income:
            transactions = transactions.filter { $0.type == .income }
        case .expense:
            transactions = transactions.filter { $0.type == .expense }
        case .transfer:
            transactions = transactions.filter { $0.type == .transfer }
        }
        
        return transactions
    }
    
    // Group transactions by date
    private var groupedTransactions: [Date: [FinanceTransaction]] {
        Dictionary(grouping: filteredTransactions) { transaction in
            Calendar.current.startOfDay(for: transaction.date ?? Date.distantPast)
        }
    }
    
    // Sorted dates for section headers
    private var sortedDates: [Date] {
        groupedTransactions.keys.sorted { $0 > $1 }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                searchAndFilterBar
                
                if filteredTransactions.isEmpty {
                    emptyStateView
                } else {
                    // Transaction List
                    List {
                        ForEach(sortedDates, id: \.self) { date in
                            Section {
                                if let transactions = groupedTransactions[date] {
                                    ForEach(transactions, id: \.id) { transaction in
                                        TransactionListRow(transaction: transaction)
                                            .swipeActions(edge: .trailing) {
                                                Button("Elimina", role: .destructive) {
                                                    deleteTransaction(transaction)
                                                }
                                            }
                                    }
                                }
                            } header: {
                                TransactionSectionHeader(
                                    date: date,
                                    transactions: groupedTransactions[date] ?? []
                                )
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Transazioni")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            appState.presentQuickTransaction(type: .expense)
                        } label: {
                            Label("Nuova Spesa", systemImage: "minus.circle")
                        }
                        
                        Button {
                            appState.presentQuickTransaction(type: .income)
                        } label: {
                            Label("Nuova Entrata", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Cerca transazioni...")
        .sheet(isPresented: $showingFilters) {
            TransactionFiltersSheet(
                timeFilter: $selectedTimeFilter,
                typeFilter: $selectedTypeFilter
            )
        }
    }
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        HStack {
            // Filter Button
            Button {
                showingFilters = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filtri")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(20)
            }
            .foregroundColor(.primary)
            
            Spacer()
            
            // Active filters indicator
            if selectedTimeFilter != .all || selectedTypeFilter != .all {
                Text("\(filteredTransactions.count) risultati")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Nessuna Transazione")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(searchText.isEmpty ? 
                     "Le tue transazioni appariranno qui quando le aggiungerai" :
                     "Nessuna transazione trovata per '\(searchText)'")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if searchText.isEmpty {
                Button("Aggiungi Prima Transazione") {
                    appState.presentQuickTransaction()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func deleteTransaction(_ transaction: FinanceTransaction) {
        modelContext.delete(transaction)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting transaction: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct TransactionListRow: View {
    let transaction: FinanceTransaction
    
    var body: some View {
        HStack {
            // Transaction Icon & Category Color
            VStack {
                if let category = transaction.category,
                   let icon = category.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: transaction.type?.icon ?? "questionmark.circle")
                        .foregroundColor(transaction.type == .expense ? .red : .green)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(.systemGray6))
            .cornerRadius(20)
            
            // Transaction Details
            VStack(alignment: .leading, spacing: 4) {
                // Description or Category
                if let description = transaction.transactionDescription, !description.isEmpty {
                    Text(description)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(transaction.category?.name ?? "Categoria Sconosciuta")
                        .font(.headline)
                        .lineLimit(1)
                }
                
                // Account and time
                HStack(spacing: 4) {
                    // Account name
                    if let contoName = transaction.fromConto?.name ?? transaction.toConto?.name {
                        Text(contoName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let date = transaction.date {
                        Text("• \(DateFormatter.timeOnly.string(from: date))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Notes if present
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing) {
                Text(transaction.displayAmount.currencyFormatted)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(transaction.type == .expense ? .red : .green)
                
                if transaction.isRecurring == true {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransactionSectionHeader: View {
    let date: Date
    let transactions: [FinanceTransaction]
    
    private var dailyTotal: Decimal {
        transactions.reduce(0) { sum, transaction in
            switch transaction.type {
            case .expense:
                return sum - (transaction.amount ?? 0)
            case .income:
                return sum + (transaction.amount ?? 0)
            case .transfer:
                return sum // Transfers don't affect total balance
            case .none:
                return sum
            }
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatter.fullDate.string(from: date))
                    .font(.headline)
                
                Text("\(transactions.count) transazioni")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if dailyTotal != 0 {
                Text(dailyTotal.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(dailyTotal >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransactionFiltersSheet: View {
    @Binding var timeFilter: TimeFilter
    @Binding var typeFilter: TransactionTypeFilter
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Periodo") {
                    Picker("Periodo", selection: $timeFilter) {
                        ForEach(TimeFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                
                Section("Tipo Transazione") {
                    Picker("Tipo", selection: $typeFilter) {
                        ForEach(TransactionTypeFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Filtri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ripristina") {
                        timeFilter = .all
                        typeFilter = .all
                    }
                }
            }
        }
    }
}

// MARK: - Filter Enums

enum TimeFilter: CaseIterable {
    case all, today, thisWeek, thisMonth, last30Days
    
    var displayName: String {
        switch self {
        case .all: return "Tutte"
        case .today: return "Oggi"
        case .thisWeek: return "Questa Settimana"
        case .thisMonth: return "Questo Mese"
        case .last30Days: return "Ultimi 30 Giorni"
        }
    }
}

enum TransactionTypeFilter: CaseIterable {
    case all, income, expense, transfer
    
    var displayName: String {
        switch self {
        case .all: return "Tutte"
        case .income: return "Entrate"
        case .expense: return "Spese"
        case .transfer: return "Trasferimenti"
        }
    }
}

// MARK: - DateFormatter Extensions

extension DateFormatter {
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
    
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    TransactionListView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}