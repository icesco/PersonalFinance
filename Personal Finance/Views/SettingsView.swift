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
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var showingAddConto = false
    @State private var showingAddCategory = false
    @State private var editingCategory: FinanceCategory?

    private var account: Account? { appState.selectedAccount }

    var body: some View {
        NavigationStack {
            List {
                // Conti section
                contiSection

                // Categorie section
                categoriesSection

                // Info section
                infoSection
            }
            .navigationTitle("Impostazioni")
            .sheet(isPresented: $showingAddConto) {
                AddContoSheet()
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategorySheet()
            }
            .sheet(item: $editingCategory) { category in
                EditCategorySheet(category: category)
            }
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
            if let categories = account?.categories?.filter({ $0.isActive == true && $0.parentCategoryId == nil }), !categories.isEmpty {
                ForEach(categories.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.id) { category in
                    CategorySettingsRow(category: category) {
                        editingCategory = category
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Nessuna categoria", systemImage: "tag")
                } description: {
                    Text("Le categorie verranno create automaticamente")
                }
            }

            Button {
                showingAddCategory = true
            } label: {
                Label("Aggiungi Categoria", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Categorie")
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

// MARK: - Conto Settings Row

struct ContoSettingsRow: View {
    let conto: Conto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conto.type?.icon ?? "creditcard")
                .font(.title3)
                .foregroundStyle(.accent)
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
                .foregroundStyle(conto.balance >= 0 ? .primary : .red)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var name = ""
    @State private var type: ContoType = .checking
    @State private var initialBalance = ""

    private var isValid: Bool {
        !name.isEmpty
    }

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var name = ""
    @State private var selectedIcon = "tag"
    @State private var selectedColor = "#007AFF"
    @State private var parentCategory: FinanceCategory?

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

    private var parentCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true && $0.parentCategoryId == nil } ?? []
    }

    private var isValid: Bool {
        !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Nome categoria", text: $name)

                    Picker("Categoria padre (opzionale)", selection: $parentCategory) {
                        Text("Nessuna (categoria principale)").tag(nil as FinanceCategory?)
                        ForEach(parentCategories, id: \.id) { cat in
                            Text(cat.name ?? "").tag(cat as FinanceCategory?)
                        }
                    }
                }

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
                            .foregroundStyle(selectedIcon == icon ? .accent : .primary)
                        }
                    }
                }

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

                // Preview
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
    let category: FinanceCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag"
    @State private var selectedColor: String = "#007AFF"

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Nome categoria", text: $name)
                }

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
                            .foregroundStyle(selectedIcon == icon ? .accent : .primary)
                        }
                    }
                }

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

                // Preview
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
