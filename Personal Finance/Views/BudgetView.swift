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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var showingCreateBudget = false
    @State private var selectedBudget: FinanceBudget?
    @State private var showingSaveError = false
    
    // Get budgets for selected account
    private var budgets: [FinanceBudget] {
        appState.selectedAccount?.budgets?.filter { $0.isActive == true } ?? []
    }
    
    var body: some View {
        NavigationStack {
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
                    archivedBudgetsSection
                    
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fine") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateBudget = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuovo budget")
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showingCreateBudget) {
            if let account = appState.selectedAccount {
                CreateBudgetView(account: account)
            }
        }
        .sheet(item: $selectedBudget) { budget in
            BudgetDetailView(budget: budget)
        }
        .alert("Impossibile salvare", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: { Text("La modifica non è stata salvata. Riprova.") }
    }
    
    // MARK: - Budget Overview Header
    
    private var budgetOverviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(budgets.count == 1 ? "1 budget attivo" : "\(budgets.count) budget attivi")
                .font(.title2.bold())
            Text("Ogni limite si riferisce al proprio periodo e alle categorie scelte. Una spesa può rientrare in più budget: confronta il residuo di ciascuno.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    private var archivedBudgetsSection: some View {
        let archived = (appState.selectedAccount?.budgets ?? []).filter { $0.isActive == false }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        return Group {
            if !archived.isEmpty {
                DisclosureGroup("Budget disattivati (\(archived.count))") {
                    ForEach(archived, id: \.id) { budget in
                        HStack {
                            Text(budget.name ?? "Budget")
                            Spacer()
                            Button("Riattiva") {
                                do { try BudgetEdits(context: modelContext).setActive(true, for: budget) }
                                catch { showingSaveError = true }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Riattiva \(budget.name ?? "budget")")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
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
                Text("Nessun budget attivo")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Crea un budget per tenere traccia delle tue spese")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Crea budget") {
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
    @ScaledMetric(relativeTo: .caption) private var categoryMinimumWidth: CGFloat = 80
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
                        
                        Text(budget.currentSpent.formatted(.currency(code: budget.account?.currency ?? "EUR")))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(progressColor)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Budget")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text((budget.amount ?? 0).formatted(.currency(code: budget.account?.currency ?? "EUR")))
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
                            GridItem(.adaptive(minimum: categoryMinimumWidth))
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
                .fixedSize(horizontal: false, vertical: true)
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
    let account: Account
    let budget: FinanceBudget?
    @State private var showingSaveError = false

    init(account: Account, budget: FinanceBudget? = nil) {
        self.account = account
        self.budget = budget
        _budgetName = State(initialValue: budget?.name ?? "")
        _budgetAmount = State(initialValue: budget?.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _selectedPeriod = State(initialValue: budget?.period ?? .monthly)
        _alertThreshold = State(initialValue: budget?.alertThreshold ?? 0.8)
        _selectedCategories = State(initialValue: Set(budget?.categories ?? []))
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var budgetName = ""
    @State private var budgetAmount = ""
    @State private var selectedPeriod: BudgetPeriod = .monthly
    @State private var alertThreshold = 0.8
    @State private var selectedCategories: Set<FinanceCategory> = []
    
    private var availableCategories: [FinanceCategory] {
        (account.categories ?? []).filter { $0.isActive == true || selectedCategories.contains($0) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var isFormValid: Bool {
        !budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (BalanceInput.parse(budgetAmount, currency: account.currency ?? "EUR") ?? 0) > 0 &&
        !selectedCategories.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Dettagli Budget") {
                    TextField("Nome Budget", text: $budgetName)
                    
                    CurrencyAmountField(title: "Importo", text: $budgetAmount,
                                        currency: account.currency ?? "EUR", identifier: "budget-amount")

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
                
            }
            .navigationTitle(budget == nil ? "Nuovo Budget" : "Modifica Budget")
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text("Il budget non è stato salvato. Controlla i dati e riprova.") }
            .toolbarTitleDisplayMode(.inline)
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
        guard isFormValid else { return }
        do {
            try BudgetEdits(context: modelContext).apply(
                to: budget, account: account, name: budgetName, amountText: budgetAmount,
                period: selectedPeriod, threshold: alertThreshold,
                categories: selectedCategories.sorted { $0.id.uuidString < $1.id.uuidString }
            )
            dismiss()
        } catch {
            showingSaveError = true
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
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(category.name ?? "Categoria")
        .accessibilityValue(isSelected ? "Selezionata" : "Non selezionata")
        .accessibilityIdentifier("budget-category-\(category.name ?? "")")
    }
}

// MARK: - Budget Detail View

struct BudgetDetailView: View {
    @ScaledMetric(relativeTo: .caption) private var categoryMinimumWidth: CGFloat = 100
    let budget: FinanceBudget
    @Environment(\.modelContext) private var modelContext
    @State private var showingEdit = false
    @State private var confirmingArchive = false
    @State private var showingSaveError = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Budget Overview
                    VStack(spacing: 16) {
                        Text(budget.currentSpent.formatted(.currency(code: budget.account?.currency ?? "EUR")))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(budget.isOverBudget ? .red : .primary)
                        
                        Text("di \((budget.amount ?? 0).formatted(.currency(code: budget.account?.currency ?? "EUR")))")
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
                            value: budget.remainingAmount.formatted(.currency(code: budget.account?.currency ?? "EUR")),
                            icon: "wallet.pass", color: budget.remainingAmount >= 0 ? .green : .red
                        )
                        
                        StatCardView(
                            title: "Giorni Rimasti",
                            value: "\(budget.daysRemaining)",
                            icon: "calendar", color: .blue
                        )
                        
                        StatCardView(
                            title: "Margine al giorno",
                            value: budget.dailySuggestedSpending.formatted(.currency(code: budget.account?.currency ?? "EUR")),
                            icon: "chart.bar", color: .orange
                        )
                        
                        let projection = budget.spendingOutlook().projectedTotal
                        StatCardView(
                            title: "Stima fine periodo",
                            value: projection?.formatted(.currency(code: budget.account?.currency ?? "EUR")) ?? "—",
                            icon: "chart.line.uptrend.xyaxis",
                            color: projection.map { $0 > (budget.amount ?? 0) ? Color.red : Color.primary } ?? .secondary
                        )
                    }
                    
                    Text("Il margine considera tutte le spese registrate nel periodo, anche future. La stima usa il ritmo delle spese variabili dei giorni conclusi e le ricorrenti già registrate; non aggiunge ricorrenze ancora da registrare. Disponibile dopo il primo giorno completo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Categories
                    if !(budget.categories ?? []).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Categorie Incluse")
                                .font(.headline)

                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: categoryMinimumWidth))
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
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingEdit) {
                if let account = budget.account { CreateBudgetView(account: account, budget: budget) }
            }
            .confirmationDialog("Disattivare questo budget?", isPresented: $confirmingArchive, titleVisibility: .visible) {
                Button("Disattiva budget", role: .destructive) {
                    do {
                        try BudgetEdits(context: modelContext).setActive(false, for: budget)
                        dismiss()
                    } catch { showingSaveError = true }
                }
            } message: {
                Text("Non riceverai più avvisi per questo budget. Le transazioni restano e potrai riattivarlo dai budget disattivati.")
            }
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text("Il budget non è stato disattivato. Riprova.") }

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Modifica", systemImage: "pencil") { showingEdit = true }
                        Button("Disattiva budget", systemImage: "archivebox", role: .destructive) { confirmingArchive = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Azioni budget")
                }
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
