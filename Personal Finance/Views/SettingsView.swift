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
    @State private var showingSaveError = false
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Environment(DataStorageManager.self) private var dataStorageManager

    // MARK: - State
    @State private var cloudKitHelper = CloudKitHelper.shared
    @State private var showingAddConto = false
    @State private var showingAddAccount = false
    @State private var showingCSVImport = false
    @State private var showingCSVExport = false
    @State private var showingDemoAlert = false
    @State private var isGeneratingDemo = false
    @State private var showingDemoSuccess = false
    @State private var showingSyncToggleAlert = false
    @State private var pendingSyncToggleValue = false

    // MARK: - Queries
    @Query(sort: \Account.name) private var allAccounts: [Account]

    // MARK: - Computed Properties
    private var account: Account? { appState.selectedAccount }

    private var categoryCount: Int {
        account?.categories?.filter { $0.isActive == true }.count ?? 0
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                // Libri contabili section
                libriContabiliSection

                // Conti section
                contiSection

                // Categorie section (NavigationLink)
                categoriesSection

                // Data management section
                dataManagementSection

                // iCloud section
                iCloudSection

                AppLockSettingsSection()
                WidgetSettingsSection()
                #if os(iOS)
                WatchSettingsSection()
                #endif

                Section {
                    NavigationLink {
                        FinanceShortcutsView()
                    } label: {
                        Label("Comandi Rapidi e Siri", systemImage: "square.stack.3d.up")
                    }
                }
                RecurrenceReminderSettings()

                appearanceSection

#if DEBUG
                developmentSection
#endif

                // Info section
                infoSection
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Impostazioni")
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Le modifiche non sono state salvate. Riprova.")
            }
            .financePresentation(isPresented: $showingAddConto, title: "Nuovo conto") {
                AddContoSheet()
            }
            .financePresentation(isPresented: $showingAddAccount, title: "Nuovo libro") {
                CreateAccountView { newAccount in
                    appState.selectAccount(newAccount)
                }
            }
            .financePresentation(isPresented: $showingCSVImport, title: "Importa CSV", width: 800) {
                CSVImportView()
            }
            .financePresentation(isPresented: $showingCSVExport, title: "Esporta CSV", width: 800) {
                CSVExportView()
            }
            .alert("Dati Demo", isPresented: $showingDemoAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Genera Dati") {
                    generateDemoData()
                }
            } message: {
                Text("Verra' creato un libro contabile \"Demo\" con un conto corrente e transazioni di esempio per il mese corrente e quello precedente.")
            }
            .alert("Demo Creata", isPresented: $showingDemoSuccess) {
                Button("OK") {
                    appState.triggerDataRefresh()
                }
            } message: {
                Text("Libro \"Demo\" creato con successo! Selezionalo dal menu in alto a destra nella dashboard.")
            }
            .alert(
                pendingSyncToggleValue ? "Attivare iCloud?" : "Disattivare iCloud?",
                isPresented: $showingSyncToggleAlert
            ) {
                Button("Annulla", role: .cancel) { }
                Button(pendingSyncToggleValue ? "Attiva" : "Disattiva") {
                    Task {
                        await dataStorageManager.performSyncToggle(enableCloud: pendingSyncToggleValue)
                    }
                }
            } message: {
                Text(pendingSyncToggleValue
                     ? "I tuoi dati verranno sincronizzati su iCloud e disponibili su tutti i dispositivi."
                     : "I dati resteranno solo su questo dispositivo. I dati gia' sincronizzati su iCloud non verranno cancellati.")
            }
            .alert("Impossibile cambiare sincronizzazione", isPresented: Binding(
                get: { dataStorageManager.syncToggleError != nil },
                set: { _ in }
            )) {
                Button("OK") { dataStorageManager.clearSyncToggleError() }
            } message: {
                Text(dataStorageManager.syncToggleError ?? "")
            }
            .task {
                await cloudKitHelper.refreshSyncStatus()
            }
        }
    }

    // MARK: - iCloud Section

    private var iCloudSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { dataStorageManager.isCloudSyncEnabled },
                set: { newValue in
                    pendingSyncToggleValue = newValue
                    showingSyncToggleAlert = true
                }
            )) {
                Label("Sincronizzazione iCloud", systemImage: "icloud")
            }
            .disabled(dataStorageManager.isMigrating)

            if dataStorageManager.isCloudSyncEnabled {
                NavigationLink {
                    CloudSyncDetailView()
                } label: {
                    HStack {
                        if cloudKitHelper.isSyncing {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                .symbolEffect(.rotate)
                                .foregroundStyle(.blue)
                        } else if cloudKitHelper.syncError != nil {
                            Image(systemName: "exclamationmark.icloud")
                                .foregroundStyle(.red)
                        } else {
                            Image(systemName: "checkmark.icloud")
                                .foregroundStyle(.green)
                        }

                        Text(cloudKitHelper.syncStatusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if dataStorageManager.isMigrating {
                HStack {
                    ProgressView()
                    Text("Aggiornamento in corso...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Sincronizza i tuoi dati su tutti i dispositivi con iCloud")
        }
    }

    // MARK: - Development Section

    private var developmentSection: some View {
        Section {
            Button {
                showingDemoAlert = true
            } label: {
                HStack {
                    Label("Genera Dati Demo", systemImage: "wand.and.stars")

                    Spacer()

                    if isGeneratingDemo {
                        ProgressView()
                    }
                }
            }
            .disabled(isGeneratingDemo)
        } header: {
            Text("Sviluppo")
        } footer: {
            Text("Crea account di esempio con transazioni realistiche per testare l'app")
        }
    }

    // MARK: - Demo Data Generation

    private func generateDemoData() {
        isGeneratingDemo = true

        Task {
            do {
                let demoService = DemoDataService(modelContext: modelContext)
                try await demoService.generateDemoData()

                await MainActor.run {
                    isGeneratingDemo = false
                    showingDemoSuccess = true
                }
            } catch {
                await MainActor.run {
                    isGeneratingDemo = false
                }
                print("Error generating demo data: \(error)")
            }
        }
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        Section {
            Button {
                showingCSVImport = true
            } label: {
                Label("Importa da CSV", systemImage: "square.and.arrow.down")
            }

            Button {
                showingCSVExport = true
            } label: {
                Label("Esporta in CSV", systemImage: "square.and.arrow.up")
            }

            NavigationLink {
                EraseDataView()
            } label: {
                Label("Cancella Dati", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Gestione Dati")
        } footer: {
            Text("Importa, esporta o cancella i tuoi dati")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
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

            // Tinted backgrounds toggle
            Toggle(isOn: Binding(
                get: { appState.tintedBackgrounds },
                set: { appState.tintedBackgrounds = $0 }
            )) {
                Label("Superfici colorate", systemImage: "paintpalette")
            }
        } header: {
            Text("Aspetto")
        } footer: {
            Text("Scegli l'aspetto dell'app")
        }
    }

    // MARK: - Libri Contabili Section

    private var libriContabiliSection: some View {
        Section {
            ForEach(allAccounts, id: \.id) { acc in
                libroRow(acc)
            }

            Button {
                showingAddAccount = true
            } label: {
                Label("Nuovo libro", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Libri")
        } footer: {
            Text("Separa le tue finanze personali, familiari o di lavoro")
        }
    }

    private func libroRow(_ acc: Account) -> some View {
        let isCurrent = acc.id == account?.id
        return NavigationLink {
            FinanceBookDetailsView(book: acc)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(acc.name ?? "Libro")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(acc.currency ?? "EUR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Conti Section

    private var contiSection: some View {
        Section {
            if let conti = account?.conti, !conti.isEmpty {
                ForEach(conti.filter { $0.isActive == true }, id: \.id) { conto in
                    NavigationLink {
                        FinanceContoDetailsView(conto: conto)
                    } label: {
                        ContoSettingsRow(conto: conto)
                    }
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
                Label("Aggiungi conto", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Conti")
        } footer: {
            Text("Conti correnti, carte e contanti del libro selezionato")
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
        do {
            try SettingsEdits(context: modelContext).archiveConti(conti, at: offsets)
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Category Management View

struct CategoryManagementView: View {
    @State private var showingSaveError = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var showingAddCategory = false
    @State private var editingCategory: FinanceCategory?
    @State private var searchText = ""

    private var account: Account? { appState.selectedAccount }

    private var activeCategories: [FinanceCategory] {
        (account?.categories ?? []).filter { $0.isActive == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    private var categories: [FinanceCategory] {
        activeCategories.filter { category in
            category.parentCategoryId == nil && (searchText.isEmpty ||
                (category.name ?? "").localizedStandardContains(searchText) ||
                activeCategories.contains { $0.parentCategoryId == category.id && ($0.name ?? "").localizedStandardContains(searchText) })
        }
    }

    var body: some View {
        List {
            if categories.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "Nessuna categoria" : "Nessun risultato", systemImage: "tag")
                } description: {
                    Text(searchText.isEmpty ? "Crea categorie per riconoscere le tue abitudini di spesa." : "Prova con un altro nome.")
                }
            } else {
                ForEach(categories, id: \.id) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        CategorySettingsRow(category: category) { editingCategory = category }
                        let children = activeCategories.filter { $0.parentCategoryId == category.id }
                        if !children.isEmpty {
                            ForEach(children) { child in
                                CategorySettingsRow(category: child) { editingCategory = child }
                                    .padding(.leading, 32)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onDelete(perform: deleteCategories)
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .searchable(text: $searchText, prompt: "Cerca una categoria")
        .financeEmptyOverlay(isPresented: categories.isEmpty) {
            ContentUnavailableView(searchText.isEmpty ? "Nessuna categoria" : "Nessun risultato", systemImage: "tag",
                description: Text(searchText.isEmpty ? "Crea categorie per riconoscere le tue abitudini di spesa." : "Prova con un altro nome."))
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dai un nome alle tue abitudini")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("\(activeCategories.count) categorie · \(account?.name ?? "Scegli un libro")")
                    .font(.subheadline).foregroundStyle(.secondary)
                if account == nil {
                    Button("Scegli un libro") { appState.presentAccountSelection() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(.ultraThinMaterial)
        }
        .navigationTitle("Categorie")
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Le modifiche non sono state salvate. Riprova.")
            }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCategory = true
                } label: {
                    Label("Nuova categoria", systemImage: "plus")
                }
                .disabled(account == nil)
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
        do {
            try SettingsEdits(context: modelContext).archiveCategories(categories, at: offsets)
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Conto Settings Row

struct ContoSettingsRow: View {
    let conto: Conto

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conto.type?.icon ?? "creditcard")
                .foregroundStyle(Color(hex: conto.displayColorHex))
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

            Text(conto.balance.formatted(.currency(code: conto.account?.currency ?? "EUR")))
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
                    .frame(width: 44, height: 44)
                    .background(Color(hex: category.color ?? "#007AFF").opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

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
    @Environment(AppStateManager.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let account = appState.selectedAccount {
            CreateContoView(account: account)
        } else {
            NavigationStack {
                ContentUnavailableView("Seleziona un libro", systemImage: "books.vertical", description: Text("Per aggiungere un conto, scegli prima il libro a cui appartiene."))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            }
        }
    }
}

// MARK: - Add Category Sheet

struct AddCategorySheet: View {
    @State private var showingSaveError = false
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
    private let icons = CategoryIconChoices.all

    private let colors = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500", "#FFCC00",
        "#AF52DE", "#5856D6", "#FF2D55", "#00C7BE", "#8E8E93"
    ]

    // MARK: - Computed Properties
    private var parentCategories: [FinanceCategory] {
        appState.selectedAccount?.categories?.filter { $0.isActive == true && $0.parentCategoryId == nil } ?? []
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Le modifiche non sono state salvate. Riprova.")
            }
            .toolbarTitleDisplayMode(.inline)
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
                    .buttonStyle(.plain)
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
        guard isValid, let account = appState.selectedAccount else { return }

        do {
            try SettingsEdits(context: modelContext).createCategory(
                name: name, color: selectedColor, icon: selectedIcon,
                parentID: parentCategory?.id, account: account
            )
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Edit Category Sheet

struct EditCategorySheet: View {
    @State private var showingSaveError = false
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
    private let icons = CategoryIconChoices.all

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
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Le modifiche non sono state salvate. Riprova.")
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { saveChanges() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .buttonStyle(.plain)
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
        do {
            try SettingsEdits(context: modelContext).updateCategory(
                category, name: name, color: selectedColor, icon: selectedIcon
            )
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppStateManager())
        .environment(RecurrenceReminders())
        .environment(AppLock())
        .environment(DataStorageManager.shared)
        .environment(NavigationRouter())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}


struct FinanceContoDetailsView: View {
    let conto: Conto
    @State private var editing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(conto.type?.displayName ?? "Conto", systemImage: conto.type?.icon ?? "creditcard")
                        .foregroundStyle(Color(hex: conto.displayColorHex))
                    Text(conto.displayBalance, format: .currency(code: conto.account?.currency ?? "EUR"))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(conto.account?.name ?? "Libro").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).unifiedCard()
                Button("Modifica conto", systemImage: "pencil") { editing = true }
                    .buttonStyle(.borderedProminent).tint(ForgiaPalette.accent)
                NavigationLink { TransactionListView(initialConto: conto) } label: {
                    Label("Vedi movimenti", systemImage: "list.bullet.rectangle")
                }.buttonStyle(.bordered)
                NavigationLink { BalanceHistoryView(bookID: conto.account?.id, contoID: conto.id) } label: {
                    Label("Storico del saldo", systemImage: "chart.xyaxis.line")
                }.buttonStyle(.bordered)
            }.padding(22)
        }
        .themedBackground()
        .navigationTitle(conto.name ?? "Conto")
        .sheet(isPresented: $editing) { EditContoView(conto: conto) }
    }
}

struct FinanceBookDetailsView: View {
    let book: Account
    @Environment(\.modelContext) private var context
    @Environment(AppStateManager.self) private var appState
    @State private var editing = false
    @State private var name = ""
    @State private var saveError = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Libro contabile", systemImage: "books.vertical").foregroundStyle(ForgiaPalette.accent)
                    Text(book.name ?? "Libro").font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("\(book.activeConti.count) conti · \(book.currency ?? "EUR")").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).unifiedCard()
                HStack {
                    Button("Usa questo libro", systemImage: "checkmark.circle") { appState.selectAccount(book) }
                        .buttonStyle(.borderedProminent).tint(ForgiaPalette.accent)
                    Button("Modifica nome", systemImage: "pencil") { name = book.name ?? ""; editing = true }
                        .buttonStyle(.bordered)
                }
                ForEach(book.activeConti) { conto in
                    NavigationLink { FinanceContoDetailsView(conto: conto) } label: {
                        ContoSettingsRow(conto: conto).unifiedCard()
                    }.buttonStyle(.plain)
                }
                NavigationLink { SharedBookView(book: book) } label: {
                    Label("Condivisione del libro", systemImage: "person.2")
                }.buttonStyle(.bordered)
            }.padding(22)
        }
        .themedBackground()
        .navigationTitle("Dettagli libro")
        .alert("Modifica libro", isPresented: $editing) {
            TextField("Nome del libro", text: $name)
            Button("Annulla", role: .cancel) { }
            Button("Salva") {
                let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { saveError = true; return }
                let previous = (book.name, book.updatedAt)
                book.name = value; book.updatedAt = Date()
                do { try context.save(); appState.triggerDataRefresh() }
                catch { (book.name, book.updatedAt) = previous; saveError = true }
            }
        } message: { Text("La valuta resta quella dei movimenti già registrati.") }
        .alert("Modifica non salvata", isPresented: $saveError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Inserisci un nome valido e riprova.") }
    }
}
