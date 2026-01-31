//
//  BudgetView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var showingCreateBudget = false
    @State private var selectedBudget: FinanceBudget?
    
    // Get budgets for selected account
    private var budgets: [FinanceBudget] {
        appState.selectedAccount?.budgets?.filter { $0.isActive == true } ?? []
    }
    
    // Calculate total budget amounts and spent
    private var totalBudgetAmount: Decimal {
        budgets.reduce(0) { $0 + ($1.amount ?? 0) }
    }
    
    private var totalSpent: Decimal {
        budgets.reduce(0) { $0 + $1.currentSpent }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Budget Overview Header
                    budgetOverviewHeader
                    
                    // Budget Progress Summary
                    if !budgets.isEmpty {
                        budgetProgressSummary
                    }
                    
                    // Individual Budget Cards
                    budgetCardsSection
                    
                    // Empty State or Create Button
                    if budgets.isEmpty {
                        emptyStateView
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100) // Space for floating button
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateBudget = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showingCreateBudget) {
            CreateBudgetView()
        }
        .sheet(item: $selectedBudget) { budget in
            BudgetDetailView(budget: budget)
        }
    }
    
    // MARK: - Budget Overview Header
    
    private var budgetOverviewHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget Totale")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(totalBudgetAmount.currencyFormatted)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Speso")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(totalSpent.currencyFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(totalSpent > totalBudgetAmount ? .red : .orange)
                }
            }
            
            // Overall progress bar
            if totalBudgetAmount > 0 {
                let progress = min(1.0, Double(truncating: NSDecimalNumber(decimal: totalSpent / totalBudgetAmount)))
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: progress > 0.8 ? .red : .accentColor))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Budget Progress Summary
    
    private var budgetProgressSummary: some View {
        HStack(spacing: 12) {
            // On Track Budgets
            let onTrackCount = budgets.filter { !$0.shouldAlert && !$0.isOverBudget }.count
            StatCardView(
                title: "In Target",
                value: "\(onTrackCount)",
                icon: "checkmark.circle.fill", color: .green
            )
            
            // Warning Budgets
            let warningCount = budgets.filter { $0.shouldAlert && !$0.isOverBudget }.count
            StatCardView(
                title: "Attenzione",
                value: "\(warningCount)",
                icon: "exclamationmark.triangle.fill", color: .orange
            )
            
            // Over Budget
            let overBudgetCount = budgets.filter { $0.isOverBudget }.count
            StatCardView(
                title: "Superato",
                value: "\(overBudgetCount)",
                icon: "xmark.circle.fill", color: .red
            )
        }
    }
    
    // MARK: - Budget Cards Section
    
    private var budgetCardsSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(budgets.sorted { ($0.name ?? "") < ($1.name ?? "") }, id: \.id) { budget in
                BudgetCard(budget: budget) {
                    selectedBudget = budget
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.pie")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Nessun Budget")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Crea il tuo primo budget per tenere traccia delle tue spese")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Crea Primo Budget") {
                showingCreateBudget = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Budget Card

struct BudgetCard: View {
    let budget: FinanceBudget
    let onTap: () -> Void
    
    private var progressPercentage: Double {
        budget.spentPercentage
    }
    
    private var progressColor: Color {
        if budget.isOverBudget {
            return .red
        } else if budget.shouldAlert {
            return .orange
        } else {
            return .green
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budget.name ?? "Budget Sconosciuto")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(budget.period?.displayName ?? "Periodo sconosciuto")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status Icon
                    Image(systemName: budget.isOverBudget ? "xmark.circle.fill" : 
                                    budget.shouldAlert ? "exclamationmark.triangle.fill" : 
                                    "checkmark.circle.fill")
                        .foregroundColor(progressColor)
                        .font(.title3)
                }
                
                // Amount Information
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speso")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(budget.currentSpent.currencyFormatted)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(progressColor)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Budget")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text((budget.amount ?? 0).currencyFormatted)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: min(1.0, progressPercentage))
                        .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    
                    HStack {
                        Text("\(Int(progressPercentage * 100))% utilizzato")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if budget.daysRemaining > 0 {
                            Text("\(budget.daysRemaining) giorni rimasti")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Periodo terminato")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Categories
                if !(budget.categories ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Categorie")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80))
                        ], spacing: 4) {
                            ForEach((budget.categories ?? []).prefix(3), id: \.id) { category in
                                CategoryChip(category: category)
                            }

                            if (budget.categories ?? []).count > 3 {
                                Text("+\((budget.categories ?? []).count - 3)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: FinanceCategory
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = category.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(category.name ?? "")
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundColor(Color(hex: category.color ?? "#007AFF"))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: category.color ?? "#007AFF").opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Create Budget View

struct CreateBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var budgetName = ""
    @State private var budgetAmount = ""
    @State private var selectedPeriod: BudgetPeriod = .monthly
    @State private var alertThreshold = 0.8
    @State private var selectedCategories: Set<FinanceCategory> = []
    @State private var includeRecurringTransactions = true
    
    private var availableCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { 
            $0.isActive == true 
        } ?? []
    }
    
    private var isFormValid: Bool {
        !budgetName.isEmpty && 
        !budgetAmount.isEmpty && 
        (Decimal(string: budgetAmount.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 &&
        !selectedCategories.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Dettagli Budget") {
                    TextField("Nome Budget", text: $budgetName)
                    
                    HStack {
                        Text("Importo")
                        Spacer()
                        TextField("0,00", text: $budgetAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Periodo", selection: $selectedPeriod) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                }
                
                Section("Soglia Avviso") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Avvisami al \(Int(alertThreshold * 100))%")
                            Spacer()
                        }
                        
                        Slider(value: $alertThreshold, in: 0.5...1.0, step: 0.05)
                    }
                }
                
                Section("Categorie") {
                    if availableCategories.isEmpty {
                        Text("Nessuna categoria di spesa disponibile")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(availableCategories, id: \.id) { category in
                            CategorySelectionRow(
                                category: category,
                                isSelected: selectedCategories.contains(category)
                            ) {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            }
                        }
                    }
                }
                
                Section("Opzioni") {
                    Toggle("Includi transazioni ricorrenti", isOn: $includeRecurringTransactions)
                }
            }
            .navigationTitle("Nuovo Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveBudget()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
    
    private func saveBudget() {
        guard let amountDecimal = Decimal(string: budgetAmount.replacingOccurrences(of: ",", with: ".")) else {
            return
        }
        
        let budget = FinanceBudget(
            name: budgetName,
            amount: amountDecimal,
            period: selectedPeriod,
            alertThreshold: alertThreshold,
            includeRecurringTransactions: includeRecurringTransactions
        )
        
        budget.account = appState.selectedAccount
        modelContext.insert(budget)
        
        // Add selected categories
        for category in selectedCategories {
            budget.addCategory(category)
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving budget: \(error)")
        }
    }
}

// MARK: - Category Selection Row

struct CategorySelectionRow: View {
    let category: FinanceCategory
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                HStack(spacing: 12) {
                    if let icon = category.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                            .frame(width: 24)
                    }
                    
                    Text(category.name ?? "Categoria Sconosciuta")
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Budget Detail View

struct BudgetDetailView: View {
    let budget: FinanceBudget
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Budget Overview
                    VStack(spacing: 16) {
                        Text(budget.currentSpent.currencyFormatted)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(budget.isOverBudget ? .red : .primary)
                        
                        Text("di \((budget.amount ?? 0).currencyFormatted)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        ProgressView(value: min(1.0, budget.spentPercentage))
                            .progressViewStyle(LinearProgressViewStyle(
                                tint: budget.isOverBudget ? .red : budget.shouldAlert ? .orange : .green
                            ))
                            .scaleEffect(x: 1, y: 3, anchor: .center)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    
                    // Budget Stats
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatCardView(
                            title: "Rimanente",
                            value: budget.remainingAmount.currencyFormatted,
                            icon: "wallet.pass", color: budget.remainingAmount >= 0 ? .green : .red
                        )
                        
                        StatCardView(
                            title: "Giorni Rimasti",
                            value: "\(budget.daysRemaining)",
                            icon: "calendar", color: .blue
                        )
                        
                        StatCardView(
                            title: "Media Giornaliera",
                            value: budget.dailySuggestedSpending.currencyFormatted,
                            icon: "chart.bar", color: .orange
                        )
                        
                        StatCardView(
                            title: "Proiezione",
                            value: budget.projectedSpending.currencyFormatted,
                            icon: "chart.line.uptrend.xyaxis", color: budget.projectedSpending > (budget.amount ?? 0) ? .red : .green
                        )
                    }
                    
                    // Categories
                    if !(budget.categories ?? []).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Categorie Incluse")
                                .font(.headline)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 100))
                            ], spacing: 8) {
                                ForEach(budget.categories ?? [], id: \.id) { category in
                                    CategoryChip(category: category)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle(budget.name ?? "Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    BudgetView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
