//
//  MainTabView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    var body: some View {
        ZStack {
            TabView(selection: Binding(
                get: { appState.selectedTab },
                set: { appState.selectTab($0) }
            )) {
                DashboardView()
                    .tabItem {
                        Image(systemName: appState.selectedTab == .dashboard ? "house.fill" : "house")
                        Text("Dashboard")
                    }
                    .tag(AppTab.dashboard)
                
                TransactionListView()
                    .tabItem {
                        Image(systemName: appState.selectedTab == .transactions ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                        Text("Transazioni")
                    }
                    .tag(AppTab.transactions)
                
                BudgetView()
                    .tabItem {
                        Image(systemName: appState.selectedTab == .budgets ? "chart.pie.fill" : "chart.pie")
                        Text("Budget")
                    }
                    .tag(AppTab.budgets)
                
                CategoryView()
                    .tabItem {
                        Image(systemName: appState.selectedTab == .categories ? "tag.fill" : "tag")
                        Text("Categorie")
                    }
                    .tag(AppTab.categories)
                
                SettingsTabView()
                    .tabItem {
                        Image(systemName: appState.selectedTab == .settings ? "gearshape.fill" : "gearshape")
                        Text("Impostazioni")
                    }
                    .tag(AppTab.settings)
            }
            
            // Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionButton {
                        appState.presentQuickTransaction()
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90) // Above tab bar
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showingQuickTransaction },
            set: { _ in appState.dismissQuickTransaction() }
        )) {
            QuickTransactionModal()
        }
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.1), value: false)
    }
}

// MARK: - Quick Transaction Modal

struct QuickTransactionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var selectedConto: Conto?
    @State private var selectedCategory: FinanceCategory?
    @State private var amount: String = ""
    @State private var description: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedDate = Date()
    @State private var includeTime = false
    @State private var showingContoSelection = false
    @State private var showingCategorySelection = false
    
    // For transfers
    @State private var fromConto: Conto?
    @State private var toConto: Conto?
    @State private var showingFromContoSelection = false
    @State private var showingToContoSelection = false
    
    private var availableConti: [Conto] {
        appState.activeConti(for: appState.selectedAccount)
    }
    
    private var availableCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { 
            $0.isActive == true 
        } ?? []
    }
    
    private var isFormValid: Bool {
        let amountValue = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        
        if transactionType == .transfer {
            return fromConto != nil && 
                   toConto != nil && 
                   fromConto?.id != toConto?.id && 
                   !amount.isEmpty && 
                   amountValue > 0
        } else {
            return selectedConto != nil && 
                   selectedCategory != nil && 
                   !amount.isEmpty && 
                   amountValue > 0
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Tipo Transazione") {
                    Picker("Tipo", selection: $transactionType) {
                        Text("Spesa").tag(TransactionType.expense)
                        Text("Entrata").tag(TransactionType.income)
                        Text("Trasferimento").tag(TransactionType.transfer)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Dettagli") {
                    if transactionType == .transfer {
                        // From Conto Selection
                        Button {
                            showingFromContoSelection = true
                        } label: {
                            HStack {
                                Text("Da Conto")
                                Spacer()
                                if let conto = fromConto {
                                    Text(conto.name ?? "Sconosciuto")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Seleziona conto origine")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        
                        // To Conto Selection
                        Button {
                            showingToContoSelection = true
                        } label: {
                            HStack {
                                Text("A Conto")
                                Spacer()
                                if let conto = toConto {
                                    Text(conto.name ?? "Sconosciuto")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Seleziona conto destinazione")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    } else {
                        // Regular transaction - Conto Selection
                        Button {
                            showingContoSelection = true
                        } label: {
                            HStack {
                                Text("Conto")
                                Spacer()
                                if let conto = selectedConto {
                                    Text(conto.name ?? "Sconosciuto")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Seleziona conto")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        
                        // Category Selection
                        Button {
                            showingCategorySelection = true
                        } label: {
                            HStack {
                                Text("Categoria")
                                Spacer()
                                if let category = selectedCategory {
                                    HStack {
                                        if let icon = category.icon, !icon.isEmpty {
                                            Image(systemName: icon)
                                                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                                        }
                                        Text(category.name ?? "Sconosciuta")
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("Seleziona categoria")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    
                    // Amount
                    HStack {
                        Text("Importo")
                        Spacer()
                        TextField("0,00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    // Description
                    TextField("Descrizione (opzionale)", text: $description)
                    
                    // Date/Time section
                    Toggle("Includi orario", isOn: $includeTime)
                    
                    if includeTime {
                        DatePicker("Data e Ora", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    } else {
                        DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Nuova Transazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveTransaction()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .sheet(isPresented: $showingContoSelection) {
            ContoSelectionSheet(
                conti: availableConti,
                selectedConto: $selectedConto
            )
        }
        .sheet(isPresented: $showingCategorySelection) {
            CategorySelectionSheet(
                categories: availableCategories,
                selectedCategory: $selectedCategory
            )
        }
        .sheet(isPresented: $showingFromContoSelection) {
            ContoSelectionSheet(
                conti: availableConti,
                selectedConto: $fromConto
            )
        }
        .sheet(isPresented: $showingToContoSelection) {
            ContoSelectionSheet(
                conti: availableConti.filter { $0.id != fromConto?.id },
                selectedConto: $toConto
            )
        }
        .onAppear {
            transactionType = appState.quickTransactionType
            
            // Pre-select first conto if available
            if selectedConto == nil && !availableConti.isEmpty {
                selectedConto = availableConti.first
            }
        }
        .onChange(of: transactionType) { _, _ in
            // Reset category when transaction type changes
            selectedCategory = nil
            // Reset transfer conti when switching away from transfer
            if transactionType != .transfer {
                fromConto = nil
                toConto = nil
            }
        }
    }
    
    private func saveTransaction() {
        guard let amountDecimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) else {
            return
        }
        
        if transactionType == .transfer {
            // Handle transfer transaction
            guard let fromConto = fromConto, let toConto = toConto else { return }
            
            let transaction = FinanceTransaction(
                amount: amountDecimal,
                type: .transfer,
                date: selectedDate,
                transactionDescription: description.isEmpty ? "Trasferimento da \(fromConto.name ?? "Conto") a \(toConto.name ?? "Conto")" : description
            )
            
            transaction.fromConto = fromConto
            transaction.toConto = toConto
            // No category for transfers
            
            modelContext.insert(transaction)
        } else {
            // Handle regular transaction
            guard let conto = selectedConto, let category = selectedCategory else { return }
            
            let transaction = FinanceTransaction(
                amount: amountDecimal,
                type: transactionType,
                date: selectedDate,
                transactionDescription: description.isEmpty ? nil : description
            )
            
            transaction.category = category
            
            switch transactionType {
            case .expense:
                transaction.fromConto = conto
            case .income:
                transaction.toConto = conto
            case .transfer:
                break // Already handled above
            }
            
            modelContext.insert(transaction)
        }
        
        do {
            try modelContext.save()
            
            // Update statistics for affected accounts
            Task {
                do {
                    if transactionType == .transfer {
                        // Update statistics for both accounts involved in transfer
                        if let fromAccount = fromConto?.account {
                            try await StatisticsService.updateStatistics(for: fromAccount, in: modelContext)
                        }
                        if let toAccount = toConto?.account, toAccount.id != fromConto?.account?.id {
                            try await StatisticsService.updateStatistics(for: toAccount, in: modelContext)
                        }
                    } else {
                        // Update statistics for the single account
                        if let account = selectedConto?.account {
                            try await StatisticsService.updateStatistics(for: account, in: modelContext)
                        }
                    }
                } catch {
                    print("Failed to update statistics: \(error)")
                }
            }
            
            dismiss()
        } catch {
            print("Error saving transaction: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct ContoSelectionSheet: View {
    let conti: [Conto]
    @Binding var selectedConto: Conto?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(conti, id: \.id) { conto in
                Button {
                    selectedConto = conto
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: conto.type?.icon ?? "questionmark.circle")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text(conto.name ?? "Sconosciuto")
                                .font(.headline)
                            Text(conto.type?.displayName ?? "Tipo sconosciuto")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(conto.balance.currencyFormatted)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Seleziona Conto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CategorySelectionSheet: View {
    let categories: [FinanceCategory]
    @Binding var selectedCategory: FinanceCategory?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(categories, id: \.id) { category in
                Button {
                    selectedCategory = category
                    dismiss()
                } label: {
                    HStack {
                        if let icon = category.icon, !icon.isEmpty {
                            Image(systemName: icon)
                                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                                .frame(width: 24)
                        }
                        
                        Text(category.name ?? "Sconosciuta")
                            .font(.headline)
                        
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Seleziona Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
        }
    }
}


#Preview {
    MainTabView()
        .environment(AppStateManager())
}