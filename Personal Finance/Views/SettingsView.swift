//
//  SettingsView.swift
//  Personal Finance
//
//  Impostazioni con gestione conti e categorie
//

import SwiftUI
import SwiftData
import FinanceCore

struct SettingsView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    // MARK: - State
    @State private var showingAddConto = false

    // MARK: - Computed Properties
    private var account: Account? { appState.selectedAccount }

    private var categoryCount: Int {
        account?.categories?.filter { $0.isActive == true }.count ?? 0
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                // Personalizzazione section
                appearanceSection

                // Conti section
                contiSection

                // Categorie section (NavigationLink)
                categoriesSection

                // Info section
                infoSection
            }
            .navigationTitle("Impostazioni")
            .sheet(isPresented: $showingAddConto) {
                AddContoSheet()
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                ExperienceLevelSelectionView()
            } label: {
                HStack {
                    Label("Modalità", systemImage: "slider.horizontal.3")

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: appState.experienceLevelManager.currentLevel.icon)
                            .foregroundStyle(appState.experienceLevelManager.currentLevel.iconColor)

                        Text(appState.experienceLevelManager.currentLevel.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                ThemeSelectionView()
            } label: {
                HStack {
                    Label("Tema", systemImage: "paintbrush.fill")

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.themeManager.currentTheme.color)
                            .frame(width: 20, height: 20)

                        Text(appState.themeManager.currentTheme.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Personalizzazione")
        } footer: {
            Text("Personalizza l'aspetto e il livello di dettaglio dell'app")
        }
    }

    // MARK: - Conti Section

    private var contiSection: some View {
        Section {
            if let conti = account?.conti, !conti.isEmpty {
                ForEach(conti.filter { $0.isActive == true }, id: \.id) { conto in
                    ContoSettingsRow(conto: conto)
                }
                .onDelete(perform: deleteConti)
            } else {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il tuo primo conto")
                }
            }

            Button {
                showingAddConto = true
            } label: {
                Label("Aggiungi Conto", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("I tuoi Conti")
        } footer: {
            Text("I conti rappresentano dove tieni i tuoi soldi (conto corrente, carta, contanti...)")
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        Section {
            NavigationLink {
                CategoryManagementView()
            } label: {
                HStack {
                    Label("Categorie", systemImage: "tag")

                    Spacer()

                    Text("\(categoryCount)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Organizzazione")
        } footer: {
            Text("Le categorie ti aiutano a organizzare le tue spese e entrate")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            HStack {
                Text("Account")
                Spacer()
                Text(account?.name ?? "Nessuno")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Valuta")
                Spacer()
                Text(account?.currency ?? "EUR")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Versione")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Informazioni")
        }
    }

    // MARK: - Actions

    private func deleteConti(at offsets: IndexSet) {
        guard let conti = account?.conti?.filter({ $0.isActive == true }) else { return }
        for index in offsets {
            let conto = conti[index]
            conto.isActive = false
        }
        try? modelContext.save()
    }
}

// MARK: - Category Management View

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var showingAddCategory = false
    @State private var editingCategory: FinanceCategory?

    private var account: Account? { appState.selectedAccount }

    private var categories: [FinanceCategory] {
        account?.categories?
            .filter { $0.isActive == true && $0.parentCategoryId == nil }
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        List {
            if categories.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna categoria", systemImage: "tag")
                } description: {
                    Text("Aggiungi la tua prima categoria")
                }
            } else {
                ForEach(categories, id: \.id) { category in
                    CategorySettingsRow(category: category) {
                        editingCategory = category
                    }
                }
                .onDelete(perform: deleteCategories)
            }
        }
        .navigationTitle("Categorie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet()
        }
        .sheet(item: $editingCategory) { category in
            EditCategorySheet(category: category)
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            let category = categories[index]
            // Soft delete
            category.isActive = false
        }
        try? modelContext.save()
    }
}

// MARK: - Conto Settings Row

struct ContoSettingsRow: View {
    let conto: Conto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conto.type?.icon ?? "creditcard")
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(conto.name ?? "Conto")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(conto.type?.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(conto.balance.currencyFormatted)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(conto.balance >= 0 ? Color.primary : Color.red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Settings Row

struct CategorySettingsRow: View {
    let category: FinanceCategory
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                Image(systemName: category.icon ?? "tag")
                    .font(.title3)
                    .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                    .frame(width: 32)

                Text(category.name ?? "Categoria")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Add Conto Sheet

struct AddContoSheet: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    // MARK: - State
    @State private var name = ""
    @State private var type: ContoType = .checking
    @State private var initialBalance = ""

    // MARK: - Computed Properties
    private var isValid: Bool {
        !name.isEmpty
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Nome del conto", text: $name)

                    Picker("Tipo", selection: $type) {
                        ForEach(ContoType.allCases, id: \.self) { contoType in
                            HStack {
                                Image(systemName: contoType.icon)
                                Text(contoType.displayName)
                            }
                            .tag(contoType)
                        }
                    }
                }

                Section("Saldo iniziale") {
                    HStack {
                        Text("€")
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $initialBalance)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Nuovo Conto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveConto() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func saveConto() {
        guard let account = appState.selectedAccount else { return }

        let balance = Decimal(string: initialBalance.replacingOccurrences(of: ",", with: ".")) ?? 0
        let conto = Conto(name: name, type: type, initialBalance: balance)
        conto.account = account

        modelContext.insert(conto)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Add Category Sheet

struct AddCategorySheet: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    // MARK: - State
    @State private var name = ""
    @State private var selectedIcon = "tag"
    @State private var selectedColor = "#007AFF"
    @State private var parentCategory: FinanceCategory?

    // MARK: - Constants
    private let icons = [
        "tag", "cart", "car", "house", "fork.knife", "tshirt",
        "gamecontroller", "airplane", "gift", "heart", "book",
        "briefcase", "banknote", "creditcard", "phone", "tv",
        "bolt", "drop", "leaf", "pawprint", "figure.run"
    ]

    private let colors = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500", "#FFCC00",
        "#AF52DE", "#5856D6", "#FF2D55", "#00C7BE", "#8E8E93"
    ]

    // MARK: - Computed Properties
    private var parentCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true && $0.parentCategoryId == nil } ?? []
    }

    private var isValid: Bool {
        !name.isEmpty
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                iconSection
                colorSection
                previewSection
            }
            .navigationTitle("Nuova Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveCategory() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Dettagli") {
            TextField("Nome categoria", text: $name)

            Picker("Categoria padre (opzionale)", selection: $parentCategory) {
                Text("Nessuna (categoria principale)").tag(nil as FinanceCategory?)
                ForEach(parentCategories, id: \.id) { cat in
                    Text(cat.name ?? "").tag(cat as FinanceCategory?)
                }
            }
        }
    }

    private var iconSection: some View {
        Section("Icona") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundStyle(selectedIcon == icon ? Color.accentColor : Color.primary)
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Colore") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .fontWeight(.bold)
                                }
                            }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Anteprima") {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: selectedColor))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: selectedColor).opacity(0.15))
                    .clipShape(Circle())

                Text(name.isEmpty ? "Nome categoria" : name)
                    .font(.headline)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
            }
        }
    }

    private func saveCategory() {
        guard let account = appState.selectedAccount else { return }

        let category = FinanceCategory(
            name: name,
            color: selectedColor,
            icon: selectedIcon,
            parentCategoryId: parentCategory?.id
        )
        category.account = account

        modelContext.insert(category)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit Category Sheet

struct EditCategorySheet: View {
    // MARK: - Properties
    let category: FinanceCategory

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State
    @State private var name: String = ""
    @State private var selectedIcon: String = "tag"
    @State private var selectedColor: String = "#007AFF"

    // MARK: - Constants
    private let icons = [
        "tag", "cart", "car", "house", "fork.knife", "tshirt",
        "gamecontroller", "airplane", "gift", "heart", "book",
        "briefcase", "banknote", "creditcard", "phone", "tv",
        "bolt", "drop", "leaf", "pawprint", "figure.run"
    ]

    private let colors = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500", "#FFCC00",
        "#AF52DE", "#5856D6", "#FF2D55", "#00C7BE", "#8E8E93"
    ]

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                iconSection
                colorSection
                previewSection
            }
            .navigationTitle("Modifica Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveChanges() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = category.name ?? ""
                selectedIcon = category.icon ?? "tag"
                selectedColor = category.color ?? "#007AFF"
            }
        }
    }

    private var detailsSection: some View {
        Section("Dettagli") {
            TextField("Nome categoria", text: $name)
        }
    }

    private var iconSection: some View {
        Section("Icona") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundStyle(selectedIcon == icon ? Color.accentColor : Color.primary)
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Colore") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .fontWeight(.bold)
                                }
                            }
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Anteprima") {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: selectedColor))
                    .frame(width: 40, height: 40)
                    .background(Color(hex: selectedColor).opacity(0.15))
                    .clipShape(Circle())

                Text(name.isEmpty ? "Nome categoria" : name)
                    .font(.headline)
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
            }
        }
    }

    private func saveChanges() {
        category.name = name
        category.icon = selectedIcon
        category.color = selectedColor
        category.updatedAt = Date()

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
