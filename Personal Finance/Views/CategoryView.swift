//
//  CategoryView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

struct CategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var showingCreateCategory = false
    @State private var selectedType: CategoryType = .expense
    @State private var categoryToEdit: FinanceCategory?
    
    // Get categories for selected account
    private var categories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true } ?? []
    }
    
    private var incomeCategories: [FinanceCategory] {
        categories.filter { $0.type == .income }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    private var expenseCategories: [FinanceCategory] {
        categories.filter { $0.type == .expense }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Type Selector
                typeSelector
                
                // Categories List
                if categories.isEmpty {
                    emptyStateView
                } else {
                    categoryList
                }
            }
            .navigationTitle("Categorie")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showingCreateCategory) {
            CreateCategoryView(initialType: selectedType)
        }
        .sheet(item: $categoryToEdit) { category in
            EditCategoryView(category: category)
        }
    }
    
    // MARK: - Type Selector
    
    private var typeSelector: some View {
        Picker("Tipo Categoria", selection: $selectedType) {
            Text("Spese (\(expenseCategories.count))").tag(CategoryType.expense)
            Text("Entrate (\(incomeCategories.count))").tag(CategoryType.income)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Category List
    
    private var categoryList: some View {
        List {
            let filteredCategories = selectedType == .expense ? expenseCategories : incomeCategories
            
            ForEach(filteredCategories, id: \.id) { category in
                CategoryListRow(category: category, onEdit: { category in
                    categoryToEdit = category
                })
                .swipeActions(edge: .trailing) {
                    Button("Elimina", role: .destructive) {
                        deleteCategory(category)
                    }
                    
                    Button("Modifica") {
                        categoryToEdit = category
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "tag")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Nessuna Categoria")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Crea le tue categorie per organizzare meglio le transazioni")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Crea Prima Categoria") {
                showingCreateCategory = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func deleteCategory(_ category: FinanceCategory) {
        // Check if category is used in any transactions
        if let transactions = category.transactions, !transactions.isEmpty {
            // In a real app, you might want to show a confirmation dialog
            print("Cannot delete category with existing transactions")
            return
        }
        
        modelContext.delete(category)
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting category: \(error)")
        }
    }
}

// MARK: - Category List Row

struct CategoryListRow: View {
    let category: FinanceCategory
    let onEdit: (FinanceCategory) -> Void
    
    // Calculate category usage statistics
    private var transactionCount: Int {
        category.transactions?.count ?? 0
    }
    
    private var totalAmount: Decimal {
        category.transactions?.reduce(0) { $0 + ($1.amount ?? 0) } ?? 0
    }
    
    var body: some View {
        Button {
            onEdit(category)
        } label: {
            HStack {
                // Category Icon
                VStack {
                    Image(systemName: category.icon ?? "tag")
                        .foregroundColor(Color(hex: category.color ?? "#007AFF"))
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .frame(width: 44, height: 44)
                .background(Color(hex: category.color ?? "#007AFF").opacity(0.1))
                .cornerRadius(22)
                
                // Category Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name ?? "Categoria Sconosciuta")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if transactionCount > 0 {
                        HStack {
                            Text("\(transactionCount) transazioni")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if totalAmount > 0 {
                                Text("• \(totalAmount.currencyFormatted)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Nessuna transazione")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Category Type Badge
                HStack {
                    Text(category.type?.displayName ?? "")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Category View

struct CreateCategoryView: View {
    let initialType: CategoryType
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    
    @State private var categoryName = ""
    @State private var selectedType: CategoryType = .expense
    @State private var selectedIcon = "tag"
    @State private var selectedColor = "#007AFF"
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    
    private let availableColors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#32ADE6", "#5856D6", "#AF52DE", "#FF2D92",
        "#8E8E93", "#000000"
    ]
    
    private let commonIcons = [
        // General
        "tag", "star", "heart", "flag",
        // Finance
        "dollarsign.circle", "creditcard", "banknote", "chart.line.uptrend.xyaxis",
        // Food & Dining
        "fork.knife", "cup.and.saucer", "cart", "wineglass",
        // Transportation
        "car", "bus", "airplane", "bicycle",
        // Home & Utilities
        "house", "lightbulb", "drop", "flame",
        // Health & Fitness
        "cross.case", "heart.text.square", "figure.walk",
        // Entertainment
        "gamecontroller", "tv", "music.note", "camera",
        // Shopping
        "bag", "gift", "tshirt", "creditcard.fill",
        // Work & Education
        "briefcase", "book", "graduationcap", "laptopcomputer",
        // Others
        "phone", "envelope", "mappin", "clock"
    ]
    
    private var isFormValid: Bool {
        !categoryName.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Dettagli Categoria") {
                    TextField("Nome Categoria", text: $categoryName)
                    
                    Picker("Tipo", selection: $selectedType) {
                        Text("Spesa").tag(CategoryType.expense)
                        Text("Entrata").tag(CategoryType.income)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                appearanceSection
                
                previewSection
            }
            .navigationTitle("Nuova Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        saveCategory()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .onAppear {
            selectedType = initialType
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
    }
    
    private var appearanceSection: some View {
        Section("Aspetto") {
            // Icon Selection
            HStack {
                Text("Icona")
                Spacer()
                Button {
                    showingIconPicker = true
                } label: {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(Color(hex: selectedColor) ?? .accentColor)
                        Text("Cambia")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Color Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Colore")
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 44))
                ], spacing: 12) {
                    ForEach(availableColors, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color) ?? Color.accentColor)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                )
                        }
                    }
                }
            }
        }
    }
    
    private var previewSection: some View {
        Section("Anteprima") {
            HStack {
                Image(systemName: selectedIcon)
                    .foregroundColor(Color(hex: selectedColor) ?? .accentColor)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: selectedColor).opacity(0.1))
                    .cornerRadius(22)
                
                VStack(alignment: .leading) {
                    Text(categoryName.isEmpty ? "Nome Categoria" : categoryName)
                        .font(.headline)
                    Text(selectedType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    private func saveCategory() {
        let category = Category(
            name: categoryName,
            type: selectedType,
            color: selectedColor,
            icon: selectedIcon
        )
        
        category.account = appState.selectedAccount
        modelContext.insert(category)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving category: \(error)")
        }
    }
}

// MARK: - Edit Category View

struct EditCategoryView: View {
    let category: FinanceCategory
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var categoryName = ""
    @State private var selectedType: CategoryType = .expense
    @State private var selectedIcon = "tag"
    @State private var selectedColor = "#007AFF"
    @State private var showingIconPicker = false
    
    private let availableColors = [
        "#007AFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#32ADE6", "#5856D6", "#AF52DE", "#FF2D92",
        "#8E8E93", "#000000"
    ]
    
    private var isFormValid: Bool {
        !categoryName.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Dettagli Categoria") {
                    TextField("Nome Categoria", text: $categoryName)
                    
                    Picker("Tipo", selection: $selectedType) {
                        Text("Spesa").tag(CategoryType.expense)
                        Text("Entrata").tag(CategoryType.income)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(true) // Cannot change type if category has transactions
                }
                
                appearanceSection
                
                statistictsSection
                
            }
            .navigationTitle("Modifica Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        updateCategory()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
        .onAppear {
            loadCategoryData()
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
    }
    
    private var appearanceSection: some View {
        Section("Aspetto") {
            // Icon Selection
            HStack {
                Text("Icona")
                Spacer()
                Button {
                    showingIconPicker = true
                } label: {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(Color(hex: selectedColor))
                        Text("Cambia")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            // Color Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Colore")
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 44))
                ], spacing: 12) {
                    ForEach(availableColors, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color) ?? .blue)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                )
                        }
                    }
                }
            }
        }
    }
    
    private var statistictsSection: some View {
        Section("Statistiche") {
            HStack {
                Text("Transazioni")
                Spacer()
                Text("\(category.transactions?.count ?? 0)")
                    .foregroundColor(.secondary)
            }
            
            if let transactions = category.transactions, !transactions.isEmpty {
                let totalAmount = transactions.reduce(0) { $0 + ($1.amount ?? 0) }
                HStack {
                    Text("Importo Totale")
                    Spacer()
                    Text(totalAmount.currencyFormatted)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func loadCategoryData() {
        categoryName = category.name ?? ""
        selectedType = category.type ?? .expense
        selectedIcon = category.icon ?? "tag"
        selectedColor = category.color ?? "#007AFF"
    }
    
    private func updateCategory() {
        category.name = categoryName
        category.type = selectedType
        category.icon = selectedIcon
        category.color = selectedColor
        category.updatedAt = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error updating category: \(error)")
        }
    }
}

// MARK: - Icon Picker View

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    
    private let commonIcons = [
        // General
        "tag", "star", "heart", "flag", "bookmark",
        // Finance
        "dollarsign.circle", "creditcard", "banknote", "chart.line.uptrend.xyaxis", "wallet.pass",
        // Food & Dining
        "fork.knife", "cup.and.saucer", "cart", "wineglass", "birthday.cake",
        // Transportation
        "car", "bus", "airplane", "bicycle", "tram",
        // Home & Utilities
        "house", "lightbulb", "drop", "flame", "bolt",
        // Health & Fitness
        "cross.case", "heart.text.square", "figure.walk", "pills", "stethoscope",
        // Entertainment
        "gamecontroller", "tv", "music.note", "camera", "headphones",
        // Shopping
        "bag", "gift", "tshirt", "creditcard.fill", "basket",
        // Work & Education
        "briefcase", "book", "graduationcap", "laptopcomputer", "pencil",
        // Others
        "phone", "envelope", "mappin", "clock", "calendar"
    ]
    
    var body: some View {
        NavigationView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 60))
            ], spacing: 20) {
                ForEach(commonIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .frame(width: 44, height: 44)
                                .background(selectedIcon == icon ? Color.accentColor : Color(.systemGray5))
                                .cornerRadius(22)
                            
                            Text(icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .navigationTitle("Seleziona Icona")
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
    CategoryView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
