import SwiftUI
import SwiftData
import FinanceCore

struct FinancialInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var selectedPeriod: AnalysisPeriod = .month
    @State private var showingSavingsGoals = false
    
    // Computed properties for financial analysis
    private var account: Account? {
        appState.selectedAccount
    }
    
    private var transactions: [FinanceTransaction] {
        guard let account = account else { return [] }
        let range = selectedPeriod.dateRange
        
        return account.conti?.flatMap { conto in
            conto.allTransactions.filter { transaction in
                guard let date = transaction.date else { return false }
                return date >= range.start && date < range.end
            }
        } ?? []
    }
    
    private var analysis: FinancialAnalysis {
        let totalIncome = transactions.filter { $0.type == .income }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        
        let totalExpenses = transactions.filter { $0.type == .expense }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        
        let totalSavings = totalIncome - totalExpenses
        
        // Category analysis
        let expensesByCategory = Dictionary(grouping: transactions.filter { $0.type == .expense }) { $0.category }
        let categoryAnalysis = expensesByCategory.compactMap { (category, transactions) -> CategoryAnalysis? in
            guard let cat = category else { return nil }
            let amount = transactions.reduce(0) { $0 + ($1.amount ?? 0) }
            let percentage = totalExpenses > 0 ? Double(truncating: amount as NSDecimalNumber) / Double(truncating: totalExpenses as NSDecimalNumber) * 100 : 0
            
            return CategoryAnalysis(
                category: cat,
                amount: amount,
                percentage: percentage,
                transactionCount: transactions.count,
                trend: .stable // For now, would need historical data for actual trend
            )
        }.sorted { $0.amount > $1.amount }
        
        // 50/30/20 rule analysis
        let necessitiesCategories = ["Casa", "Utenze", "Alimentari", "Trasporti", "Salute"]
        let wantsCategories = ["Intrattenimento", "Abbigliamento", "Regali", "Altro"]
        
        let necessities = categoryAnalysis
            .filter { necessitiesCategories.contains($0.category.name ?? "") }
            .reduce(0) { $0 + $1.amount }
        
        let wants = categoryAnalysis
            .filter { wantsCategories.contains($0.category.name ?? "") }
            .reduce(0) { $0 + $1.amount }
        
        let rule502010 = Rule502010Analysis(
            necessities: necessities,
            wants: wants,
            savings: totalSavings,
            totalIncome: totalIncome
        )
        
        return FinancialAnalysis(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalSavings: totalSavings,
            categories: categoryAnalysis,
            rule502010: rule502010,
            period: selectedPeriod
        )
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Period selector
                    periodSelector
                    
                    // Financial overview
                    overviewSection
                    
                    // 50/30/20 Rule section
                    rule502010Section
                    
                    // Top spending categories
                    if !analysis.categories.isEmpty {
                        topCategoriesSection
                    }
                    
                    // Savings goals
                    savingsGoalsSection
                    
                    // Financial tips
                    financialTipsSection
                }
                .padding()
            }
            .navigationTitle("Analisi Finanziaria")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSavingsGoals = true
                    } label: {
                        Image(systemName: "target")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSavingsGoals) {
            SavingsGoalsManagementView()
        }
    }
    
    // MARK: - Period Selector
    
    private var periodSelector: some View {
        Picker("Periodo", selection: $selectedPeriod) {
            ForEach(AnalysisPeriod.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Panoramica Finanziaria")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                FinancialOverviewCard(
                    title: "Entrate",
                    amount: analysis.totalIncome,
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
                
                FinancialOverviewCard(
                    title: "Spese",
                    amount: analysis.totalExpenses,
                    icon: "arrow.up.circle.fill",
                    color: .red
                )
                
                FinancialOverviewCard(
                    title: "Risparmi",
                    amount: analysis.totalSavings,
                    icon: analysis.totalSavings >= 0 ? "plus.circle.fill" : "minus.circle.fill",
                    color: analysis.totalSavings >= 0 ? .green : .red
                )
                
                FinancialOverviewCard(
                    title: "Tasso Risparmio",
                    percentage: analysis.savingsRate,
                    icon: "percent",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - 50/30/20 Rule Section
    
    private var rule502010Section: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Regola 50/30/20")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    // Show rule explanation
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                }
            }
            
            VStack(spacing: 12) {
                // Necessities (50%)
                Rule502010ProgressBar(
                    title: "Necessità",
                    idealPercentage: 50,
                    actualPercentage: analysis.rule502010.necessitiesPercentage,
                    amount: analysis.rule502010.necessities,
                    status: analysis.rule502010.necessitiesStatus,
                    description: "Casa, cibo, trasporti, salute"
                )
                
                // Wants (30%)
                Rule502010ProgressBar(
                    title: "Desideri",
                    idealPercentage: 30,
                    actualPercentage: analysis.rule502010.wantsPercentage,
                    amount: analysis.rule502010.wants,
                    status: analysis.rule502010.wantsStatus,
                    description: "Intrattenimento, shopping, hobby"
                )
                
                // Savings (20%)
                Rule502010ProgressBar(
                    title: "Risparmi",
                    idealPercentage: 20,
                    actualPercentage: analysis.rule502010.savingsPercentage,
                    amount: analysis.rule502010.savings,
                    status: analysis.rule502010.savingsStatus,
                    description: "Risparmi, investimenti, fondi"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Top Categories Section
    
    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Principali Categorie di Spesa")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(analysis.categories.prefix(5), id: \.category.id) { categoryAnalysis in
                    TopCategoryRow(
                        category: categoryAnalysis.category,
                        amount: categoryAnalysis.amount,
                        percentage: categoryAnalysis.percentage,
                        trend: categoryAnalysis.trend
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Savings Goals Section
    
    private var savingsGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Obiettivi di Risparmio")
                    .font(.headline)
                
                Spacer()
                
                Button("Gestisci") {
                    showingSavingsGoals = true
                }
                .foregroundColor(.accentColor)
            }
            
            if let goals = account?.savingsGoals?.filter({ $0.isActive == true }), !goals.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(goals.prefix(3), id: \.id) { goal in
                        SavingsGoalProgressRow(goal: goal)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Nessun Obiettivo")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Crea il tuo primo obiettivo di risparmio")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Crea Obiettivo") {
                        showingSavingsGoals = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Financial Tips Section
    
    private var financialTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consigli Finanziari")
                .font(.headline)
            
            LazyVStack(spacing: 12) {
                ForEach(generateFinancialTips(), id: \.id) { tip in
                    FinancialTipCard(tip: tip)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2)
    }
    
    // MARK: - Helper Methods
    
    private func generateFinancialTips() -> [FinancialTip] {
        var tips: [FinancialTip] = []
        
        // Tip based on savings rate
        if analysis.savingsRate < 10 {
            tips.append(FinancialTip(
                id: "savings_low",
                title: "Aumenta i tuoi Risparmi",
                description: "Cerca di risparmiare almeno il 20% delle tue entrate per costruire un futuro finanziario solido.",
                icon: "arrow.up.circle.fill",
                color: .orange,
                priority: .high
            ))
        }
        
        // Tip based on 50/30/20 rule
        if analysis.rule502010.necessitiesStatus == .overBudget {
            tips.append(FinancialTip(
                id: "necessities_high",
                title: "Controlla le Spese Essenziali",
                description: "Le tue spese essenziali superano il 50% del reddito. Cerca modi per ridurle.",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                priority: .high
            ))
        }
        
        // Tip based on top spending category
        if let topCategory = analysis.categories.first, topCategory.percentage > 30 {
            tips.append(FinancialTip(
                id: "category_high",
                title: "Monitora \(topCategory.category.name ?? "Categoria")",
                description: "Questa categoria rappresenta il \(String(format: "%.1f", topCategory.percentage))% delle tue spese. Considera se puoi ottimizzarla.",
                icon: "chart.pie.fill",
                color: .blue,
                priority: .medium
            ))
        }
        
        // General tip
        tips.append(FinancialTip(
            id: "budget_track",
            title: "Monitora Regolarmente",
            description: "Controlla le tue finanze almeno una volta a settimana per rimanere sulla buona strada.",
            icon: "calendar",
            color: .green,
            priority: .low
        ))
        
        return tips.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
}

// MARK: - Supporting Views and Models

struct FinancialOverviewCard: View {
    let title: String
    let amount: Decimal?
    let percentage: Double?
    let icon: String
    let color: Color
    
    init(title: String, amount: Decimal, icon: String, color: Color) {
        self.title = title
        self.amount = amount
        self.percentage = nil
        self.icon = icon
        self.color = color
    }
    
    init(title: String, percentage: Double, icon: String, color: Color) {
        self.title = title
        self.amount = nil
        self.percentage = percentage
        self.icon = icon
        self.color = color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let amount = amount {
                Text(amount.currencyFormatted)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let percentage = percentage {
                Text("\(percentage, specifier: "%.1f")%")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct Rule502010ProgressBar: View {
    let title: String
    let idealPercentage: Double
    let actualPercentage: Double
    let amount: Decimal
    let status: BudgetStatus
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(amount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: status.color))
            }
            
            HStack {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(actualPercentage, specifier: "%.1f")% / \(idealPercentage, specifier: "%.0f")%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color(hex: status.color) ?? .blue)
                        .frame(
                            width: geometry.size.width * min(actualPercentage / idealPercentage, 1.0),
                            height: 8
                        )
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

struct TopCategoryRow: View {
    let category: FinanceCategory
    let amount: Decimal
    let percentage: Double
    let trend: TrendDirection
    
    var body: some View {
        HStack {
            Image(systemName: category.icon ?? "tag")
                .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name ?? "Categoria Sconosciuta")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("\(percentage, specifier: "%.1f")% del totale")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: trend.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(amount.currencyFormatted)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

struct SavingsGoalProgressRow: View {
    let goal: SavingsGoal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: goal.category?.icon ?? "target")
                    .foregroundColor(.accentColor)
                
                Text(goal.name ?? "Obiettivo")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(goal.progressPercentage, specifier: "%.0f")%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * min(goal.progressPercentage / 100, 1.0),
                            height: 6
                        )
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
            
            HStack {
                Text((goal.currentAmount ?? 0).currencyFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text((goal.targetAmount ?? 0).currencyFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct FinancialTipCard: View {
    let tip: FinancialTip
    
    var body: some View {
        HStack {
            Image(systemName: tip.icon)
                .foregroundColor(tip.color)
                .font(.title2)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(tip.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct FinancialTip {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let priority: TipPriority
}

enum TipPriority: Int, CaseIterable {
    case high = 3
    case medium = 2
    case low = 1
}

struct SavingsGoalsManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var showingCreateGoal = false
    @State private var goalToEdit: SavingsGoal?
    @State private var goalToDelete: SavingsGoal?
    @State private var showingDeleteAlert = false
    @State private var showingProgressUpdate = false
    @State private var selectedGoal: SavingsGoal?
    
    private var activeGoals: [SavingsGoal] {
        appState.selectedAccount?.savingsGoals?.filter { $0.isActive == true } ?? []
    }
    
    private var completedGoals: [SavingsGoal] {
        appState.selectedAccount?.savingsGoals?.filter { $0.status == .completed } ?? []
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if activeGoals.isEmpty {
                        EmptyGoalsView {
                            showingCreateGoal = true
                        }
                    } else {
                        // Active Goals Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Obiettivi Attivi")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(activeGoals, id: \.id) { goal in
                                    SavingsGoalCard(goal: goal) { action in
                                        switch action {
                                        case .edit:
                                            goalToEdit = goal
                                        case .delete:
                                            goalToDelete = goal
                                            showingDeleteAlert = true
                                        case .addProgress:
                                            selectedGoal = goal
                                            showingProgressUpdate = true
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Completed Goals Section
                        if !completedGoals.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Obiettivi Completati")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                LazyVStack(spacing: 8) {
                                    ForEach(completedGoals, id: \.id) { goal in
                                        CompletedGoalRow(goal: goal)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .navigationTitle("Obiettivi di Risparmio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateGoal) {
            CreateSavingsGoalView()
        }
        .sheet(item: $goalToEdit) { goal in
            EditSavingsGoalView(goal: goal)
        }
        .sheet(item: $selectedGoal) { goal in
            UpdateProgressView(goal: goal)
        }
        .alert("Elimina Obiettivo", isPresented: $showingDeleteAlert) {
            Button("Elimina", role: .destructive) {
                if let goal = goalToDelete {
                    deleteGoal(goal)
                }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Sei sicuro di voler eliminare questo obiettivo di risparmio?")
        }
    }
    
    private func deleteGoal(_ goal: SavingsGoal) {
        goal.isActive = false
        goal.updatedAt = Date()
        try? modelContext.save()
        goalToDelete = nil
    }
}

// MARK: - Supporting Views

struct EmptyGoalsView: View {
    let onCreateTap: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("Nessun Obiettivo")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Crea il tuo primo obiettivo di risparmio per iniziare a monitorare i tuoi progressi")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Crea Obiettivo") {
                onCreateTap()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

enum GoalAction {
    case edit, delete, addProgress
}

struct SavingsGoalCard: View {
    let goal: SavingsGoal
    let onAction: (GoalAction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name ?? "Obiettivo Sconosciuto")
                        .font(.headline)
                    
                    if let description = goal.goalDescription, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    if let category = goal.category {
                        Image(systemName: category.icon)
                            .foregroundColor(.accentColor)
                    }
                    
                    Menu {
                        Button("Aggiungi Progresso") {
                            onAction(.addProgress)
                        }
                        
                        Button("Modifica") {
                            onAction(.edit)
                        }
                        
                        Button("Elimina", role: .destructive) {
                            onAction(.delete)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(goal.currentAmount?.currencyFormatted ?? "€0,00")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(goal.targetAmount?.currencyFormatted ?? "€0,00")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                            .cornerRadius(4)
                        
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(
                                width: geometry.size.width * CGFloat(goal.progressPercentage / 100),
                                height: 8
                            )
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("\(Int(goal.progressPercentage))% completato")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let days = goal.daysUntilTarget {
                        if days > 0 {
                            Text("\(days) giorni rimanenti")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Scaduto")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            // Quick Action Button
            if !goal.isCompleted {
                Button("Aggiungi Progresso") {
                    onAction(.addProgress)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Obiettivo Completato!")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CompletedGoalRow: View {
    let goal: SavingsGoal
    
    var body: some View {
        HStack {
            if let category = goal.category {
                Image(systemName: category.icon)
                    .foregroundColor(.green)
                    .frame(width: 24)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name ?? "Obiettivo Sconosciuto")
                    .font(.subheadline)
                    .strikethrough()
                
                Text(goal.targetAmount?.currencyFormatted ?? "€0,00")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .opacity(0.7)
    }
}

#Preview {
    FinancialInsightsView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}