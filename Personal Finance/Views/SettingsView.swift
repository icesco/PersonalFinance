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
    @Environment(DataStorageManager.self) private var dataStorageManager
    @Environment(AppLock.self) private var lock
    @Environment(RecurrenceReminders.self) private var reminders

    // MARK: - State
    @State private var showingCSVImport = false
    @State private var showingCSVExport = false
    @State private var showingDemoAlert = false
    @State private var isGeneratingDemo = false
    @State private var showingDemoSuccess = false

    // MARK: - Queries
    @Query(sort: \Account.name) private var allAccounts: [Account]

    // MARK: - Computed Properties
    private var account: Account? { appState.selectedAccount }

    private var categoryCount: Int {
        account?.categories?.filter { $0.isActive == true }.count ?? 0
    }

    private var contiCount: Int {
        account?.conti?.filter { $0.isActive == true }.count ?? 0
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    // MARK: - Body
    var body: some View {
        platformContent
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
                Text("Verrà creato un libro contabile \"Demo\" con un conto corrente e transazioni di esempio per il mese corrente e quello precedente.")
            }
            .alert("Demo Creata", isPresented: $showingDemoSuccess) {
                Button("OK") {
                    appState.triggerDataRefresh()
                }
            } message: {
                Text("Libro \"Demo\" creato con successo! Selezionalo dal menu in alto a destra nella dashboard.")
            }
    }

    @ViewBuilder private var platformContent: some View {
        #if os(macOS)
        MacSettingsWorkspace(onImportCSV: { showingCSVImport = true },
                             onExportCSV: { showingCSVExport = true },
                             onGenerateDemo: { showingDemoAlert = true },
                             isGeneratingDemo: isGeneratingDemo)
        #else
        NavigationStack {
            List {
                brandHeader
                bookSection
                preferencesSection
                integrationsSection
                dataSection
#if DEBUG
                developmentSection
#endif
                versionFooter
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Impostazioni")
        }
        #endif
    }

    // MARK: - Header

    private var brandHeader: some View {
        Section {
            HStack(spacing: 14) {
                FormiLogo(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Formi")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Piccoli passi. Un domani più sereno.")
                        .font(.subheadline)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Book

    private var bookSection: some View {
        Section {
            NavigationLink {
                BooksSettingsView()
            } label: {
                SettingsRow("Libri", systemImage: "books.vertical", value: account?.name ?? "Nessuno")
            }
            NavigationLink {
                ContiSettingsView()
            } label: {
                SettingsRow("Conti", systemImage: "creditcard", value: "\(contiCount)")
            }
            .disabled(account == nil)
            NavigationLink {
                CategoryManagementView()
            } label: {
                SettingsRow("Categorie", systemImage: "tag", value: "\(categoryCount)")
            }
            .disabled(account == nil)
        } header: {
            Text("Libro in uso")
        } footer: {
            Text("Conti e categorie appartengono al libro selezionato. Usa più libri per separare finanze personali, familiari o di lavoro.")
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section("Preferenze") {
            NavigationLink {
                ThemeSelectionView()
            } label: {
                SettingsRow("Aspetto", systemImage: "paintpalette", value: appState.themeManager.currentTheme.displayName)
            }
            NavigationLink {
                SettingsFormPage("Promemoria") { RecurrenceReminderSettings() }
            } label: {
                SettingsRow("Promemoria", systemImage: "bell.badge", value: reminders.enabled ? "Attivi" : "Disattivati")
            }
            NavigationLink {
                SettingsFormPage("Privacy") { AppLockSettingsSection() }
            } label: {
                SettingsRow("Privacy e blocco", systemImage: "lock", value: lock.isEnabled ? "Attivo" : "Disattivo")
            }
        }
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        Section("Integrazioni") {
            CaptureInboxEntry()
            NavigationLink("Automazione", destination: CaptureSetupView())
            NavigationLink {
                SettingsFormPage("Widget") { WidgetSettingsSection() }
            } label: {
                SettingsRow("Widget", systemImage: "square.grid.2x2")
            }
            #if os(iOS)
            NavigationLink {
                SettingsFormPage("Apple Watch") { WatchSettingsSection() }
            } label: {
                SettingsRow("Apple Watch", systemImage: "applewatch")
            }
            #endif
            NavigationLink {
                FinanceShortcutsView()
            } label: {
                SettingsRow("Comandi Rapidi e Siri", systemImage: "square.stack.3d.up")
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            NavigationLink {
                CloudSettingsView()
            } label: {
                SettingsRow("iCloud", systemImage: "icloud",
                            value: dataStorageManager.isCloudSyncEnabled ? "Attivo" : "Solo dispositivo")
            }
            Button {
                showingCSVImport = true
            } label: {
                SettingsRow("Importa da CSV", systemImage: "square.and.arrow.down")
            }
            Button {
                showingCSVExport = true
            } label: {
                SettingsRow("Esporta in CSV", systemImage: "square.and.arrow.up")
            }
            NavigationLink {
                EraseDataView()
            } label: {
                SettingsRow("Cancella dati", systemImage: "trash", role: .destructive)
            }
        } header: {
            Text("Dati")
        }
    }

    // MARK: - Development Section

    private var developmentSection: some View {
        Section {
            Button {
                showingDemoAlert = true
            } label: {
                HStack {
                    SettingsRow("Genera dati demo", systemImage: "wand.and.stars")
                    if isGeneratingDemo {
                        ProgressView()
                    }
                }
            }
            .disabled(isGeneratingDemo)
        } header: {
            Text("Sviluppo")
        } footer: {
            Text("Crea un libro di esempio con transazioni realistiche per provare l'app.")
        }
    }

    private var versionFooter: some View {
        Section {
        } footer: {
            Text("Formi \(appVersion)")
                .frame(maxWidth: .infinity)
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
}

// MARK: - Settings Building Blocks

/// A settings row with a tinted icon tile, the title and an optional current value.
struct SettingsRow: View {
    let title: String
    let systemImage: String
    var value: String?
    var role: ButtonRole?

    init(_ title: String, systemImage: String, value: String? = nil, role: ButtonRole? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.role = role
    }

    private var isDestructive: Bool { role == .destructive }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDestructive ? Color.red : ForgiaPalette.accent)
                .frame(width: 30, height: 30)
                .background(isDestructive ? Color.red.opacity(0.12) : ForgiaPalette.sageSurface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Hosts one of the settings `Section`s on its own page.
struct SettingsFormPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form { content }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - Books

struct BooksSettingsView: View {
    @Environment(AppStateManager.self) private var appState
    @Query(sort: \Account.name) private var allAccounts: [Account]
    @State private var showingAddAccount = false

    var body: some View {
        List {
            Section {
                ForEach(allAccounts, id: \.id) { book in
                    NavigationLink {
                        FinanceBookDetailsView(book: book)
                    } label: {
                        bookRow(book)
                    }
                    .modifier(FinanceDeletionActions(target: .book(book.id), name: book.name ?? "Libro"))
                }
            } footer: {
                Text("Separa le tue finanze personali, familiari o di lavoro. Il libro con la spunta è quello in uso.")
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .scrollContentBackground(.hidden)
        .themedBackground()
        #endif
        .navigationTitle("Libri")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAccount = true
                } label: {
                    Label("Nuovo libro", systemImage: "plus")
                }
            }
        }
        .financePresentation(isPresented: $showingAddAccount, title: "Nuovo libro") {
            CreateAccountView { newAccount in
                appState.selectAccount(newAccount)
            }
        }
    }

    private func bookRow(_ book: Account) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.body.weight(.semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 30, height: 30)
                .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.name ?? "Libro")
                    .font(.body.weight(.medium))
                Text("\(book.activeConti.count) conti · \(book.currency ?? "EUR")")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            Spacer()
            if book.id == appState.selectedAccount?.id {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.accent)
                    .accessibilityLabel("In uso")
            }
        }
    }
}

// MARK: - Conti

struct ContiSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @State private var showingAddConto = false
    @State private var showingSaveError = false

    private var visibleConti: [Conto] {
        appState.selectedAccount?.conti?.sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        List {
            let conti = visibleConti
            if conti.isEmpty {
                ContentUnavailableView {
                    Label("Nessun conto", systemImage: "creditcard")
                } description: {
                    Text("Aggiungi il primo conto del libro: corrente, carta o contanti.")
                } actions: {
                    Button("Aggiungi conto") { showingAddConto = true }
                        .buttonStyle(.borderedProminent)
                        .tint(ForgiaPalette.accent)
                }
            } else {
                Section {
                    ForEach(conti, id: \.id) { conto in
                        NavigationLink {
                            FinanceContoDetailsView(conto: conto)
                        } label: {
                            VStack(alignment: .leading) {
                                ContoSettingsRow(conto: conto)
                                if conto.isActive != true { Text("Archiviato").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .modifier(FinanceDeletionActions(target: .conto(conto.id), name: conto.name ?? "Conto", archive: conto.isActive == true ? { archiveConto(conto) } : nil))
                    }
                } header: {
                    Text(appState.selectedAccount?.name ?? "Libro")
                } footer: {
                    Text("Archivia conserva i movimenti. Elimina rimuove definitivamente anche i movimenti e i trasferimenti collegati.")
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .scrollContentBackground(.hidden)
        .themedBackground()
        #endif
        .navigationTitle("Conti")
        .financeEmptyOverlay(isPresented: visibleConti.isEmpty) {
            ContentUnavailableView {
                Label("Nessun conto", systemImage: "creditcard")
            } description: {
                Text("Aggiungi il primo conto del libro: corrente, carta o contanti.")
            } actions: {
                Button("Aggiungi conto") { showingAddConto = true }
                    .buttonStyle(.borderedProminent)
                    .tint(ForgiaPalette.accent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddConto = true
                } label: {
                    Label("Aggiungi conto", systemImage: "plus")
                }
            }
        }
        .financePresentation(isPresented: $showingAddConto, title: "Nuovo conto") {
            AddContoSheet()
        }
        .alert("Impossibile salvare", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Le modifiche non sono state salvate. Riprova.")
        }
    }

    private func archiveConto(_ conto: Conto) {
        do {
            try SettingsEdits(context: modelContext).archiveConti([conto], at: IndexSet(integer: 0))
            if appState.selectedConto?.id == conto.id { appState.selectAllConti() }
            appState.triggerDataRefresh()
        } catch {
            showingSaveError = true
        }
    }
}

// MARK: - iCloud

struct CloudSettingsView: View {
    @Environment(DataStorageManager.self) private var dataStorageManager
    @State private var cloudKitHelper = CloudKitHelper.shared
    @State private var showingSyncToggleAlert = false
    @State private var pendingSyncToggleValue = false

    var body: some View {
        Form {
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
                .tint(ForgiaPalette.accent)
                .disabled(dataStorageManager.isMigrating)

                if dataStorageManager.isMigrating {
                    HStack {
                        ProgressView()
                        Text("Aggiornamento in corso…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Sincronizza i tuoi dati su tutti i dispositivi con lo stesso account iCloud.")
            }

            if dataStorageManager.isCloudSyncEnabled {
                Section("Stato") {
                    NavigationLink {
                        CloudSyncDetailView()
                    } label: {
                        HStack {
                            if cloudKitHelper.isSyncing {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                    .symbolEffect(.rotate)
                                    .foregroundStyle(ForgiaPalette.accent)
                            } else if cloudKitHelper.syncError != nil {
                                Image(systemName: "exclamationmark.icloud")
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "checkmark.icloud")
                                    .foregroundStyle(ForgiaPalette.accent)
                            }
                            Text(cloudKitHelper.syncStatusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.columns)
        .toggleStyle(.checkbox)
        .padding(32)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
        .scrollContentBackground(.hidden)
        .themedBackground()
        #endif
        .navigationTitle("iCloud")
        .toolbarTitleDisplayMode(.inline)
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
                 : "I dati resteranno solo su questo dispositivo. I dati già sincronizzati su iCloud non verranno cancellati.")
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

// MARK: - Category Management View

struct CategoryManagementView: View {
    @State private var showingSaveError = false
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var showingAddCategory = false
    @State private var addingChildTo: FinanceCategory?
    @State private var editingCategory: FinanceCategory?
    @State private var searchText = ""

    private var account: Account? { appState.selectedAccount }

    private var hierarchy: CategoryHierarchy { CategoryHierarchy(categories: account?.categories ?? []) }

    private var activeCount: (roots: Int, children: Int) {
        let active = (account?.categories ?? []).filter { $0.isActive == true }
        let roots = hierarchy.roots.count
        return (roots, active.count - roots)
    }

    private var suggestions: CategoryDefaults.Plan? {
        guard let account else { return nil }
        let plan = CategoryDefaults.plan(for: account)
        return plan.isEmpty ? nil : plan
    }

    /// A macro category with the subcategories that match the search.
    private struct Family: Identifiable {
        let root: FinanceCategory
        let children: [FinanceCategory]
        let allChildren: Int
        let header: String?
        var id: UUID { root.id }
    }

    private var families: [Family] {
        let hierarchy = hierarchy
        var result: [Family] = []
        for (kind, title) in [(CategoryKind.expense, "Spese"), (.income, "Entrate"), (nil, "Entrate e spese")] as [(CategoryKind?, String)] {
            var first = true
            for root in hierarchy.roots where root.kind == kind {
                let all = hierarchy.children(of: root)
                var children = all
                if !searchText.isEmpty, !(root.name ?? "").localizedStandardContains(searchText) {
                    children = all.filter { ($0.name ?? "").localizedStandardContains(searchText) }
                    if children.isEmpty { continue }
                }
                result.append(Family(root: root, children: children, allChildren: all.count, header: first ? title : nil))
                first = false
            }
        }
        return result
    }

    var body: some View {
        List {
            if let suggestions, searchText.isEmpty {
                suggestionsCard(suggestions)
            }
            let families = families
            if families.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "Nessuna categoria" : "Nessun risultato", systemImage: "tag")
                } description: {
                    Text(searchText.isEmpty ? "Crea categorie per riconoscere le tue abitudini di spesa." : "Prova con un altro nome.")
                }
            } else {
                ForEach(families) { family in
                    Section {
                        familyRows(family)
                    } header: {
                        if let header = family.header { Text(header) }
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .scrollContentBackground(.hidden)
        .themedBackground()
        #endif
        .searchable(text: $searchText, prompt: "Cerca una categoria")
        .financeEmptyOverlay(isPresented: families.isEmpty && (suggestions == nil || !searchText.isEmpty)) {
            ContentUnavailableView {
                Label(searchText.isEmpty ? "Nessuna categoria" : "Nessun risultato", systemImage: "tag")
            } description: {
                Text(searchText.isEmpty ? "Crea categorie per riconoscere le tue abitudini di spesa." : "Prova con un altro nome.")
            }
        }
        .safeAreaInset(edge: .top) {
            #if os(macOS)
            Text("\(activeCount.roots) categorie principali · \(activeCount.children) sottocategorie")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 8)
            #else
            VStack(alignment: .leading, spacing: 6) {
                Text("Dai un nome alle tue abitudini")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text("\(activeCount.roots) principali · \(activeCount.children) sottocategorie · \(account?.name ?? "Scegli un libro")")
                    .font(.subheadline).foregroundStyle(.secondary)
                if account == nil {
                    Button("Scegli un libro") { appState.presentAccountSelection() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(.ultraThinMaterial)
            #endif
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
                    Label("Nuova categoria principale", systemImage: "plus")
                }
                .disabled(account == nil)
            }
        }
        .financePresentation(isPresented: $showingAddCategory, title: "Nuova categoria") {
            AddCategorySheet()
        }
        .financePresentation(item: $addingChildTo, title: "Nuova sottocategoria") { parent in
            AddCategorySheet(parent: parent)
        }
        .financePresentation(item: $editingCategory, title: "Modifica categoria") { category in
            EditCategorySheet(category: category)
        }
    }

    @ViewBuilder
    private func familyRows(_ family: Family) -> some View {
        let rows = [family.root] + family.children
        // Searching hides the add row, so the last match closes the tree.
        let showsAdd = searchText.isEmpty
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, category in
            NavigationLink {
                TransactionListView(initialCategoryID: category.id, isPushed: true,
                                    pushedTitle: category.displayPath)
            } label: {
                if index == 0 {
                    CategoryTreeRow(category: category, level: .macro(childCount: family.allChildren)) { chevron }
                } else {
                    CategoryTreeRow(category: category, level: .child(isLast: !showsAdd && index == rows.count - 1)) { chevron }
                }
            }
            .buttonStyle(.plain)
            .categoryTreeRowStyle(isMacro: index == 0)
            .contextMenu {
                Button("Modifica", systemImage: "pencil") { editingCategory = category }
            }
            .swipeActions(edge: .leading) {
                Button("Modifica", systemImage: "pencil") { editingCategory = category }
                    .tint(ForgiaPalette.accent)
            }
        }
        .onDelete { archive(rows, at: $0) }
        if showsAdd {
            Button { addingChildTo = family.root } label: {
                HStack(spacing: 12) {
                    TreeConnector(isLast: true)
                        .stroke(family.root.tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: CategoryTreeRow<EmptyView>.macroIconSize)
                        .frame(maxHeight: .infinity)
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(family.root.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Aggiungi a \(family.root.name ?? "Categoria")")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(family.root.tint)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .categoryTreeRowStyle(isMacro: false)
            .accessibilityLabel("Aggiungi una sottocategoria a \(family.root.name ?? "Categoria")")
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func suggestionsCard(_ plan: CategoryDefaults.Plan) -> some View {
        let onlyColors = plan.addedCount == 0 && plan.movedCount == 0
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(onlyColors ? "Nuovi colori per le categorie" : "Categorie suggerite",
                      systemImage: onlyColors ? "paintpalette" : "sparkles")
                    .font(.headline)
                Text(onlyColors ? "Porta le categorie suggerite sulla palette di Formi. I colori che hai scelto tu restano come sono."
                                : suggestionText(plan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(onlyColors ? "Aggiorna i colori" : "Aggiungi categorie suggerite", action: applySuggestions)
                    .buttonStyle(.borderedProminent)
                    .tint(ForgiaPalette.accent)
            }
            .padding(.vertical, 6)
        }
    }

    private func suggestionText(_ plan: CategoryDefaults.Plan) -> String {
        var parts: [String] = []
        if plan.addedCount > 0 { parts.append(plan.addedCount == 1 ? "1 nuova categoria" : "\(plan.addedCount) nuove categorie") }
        if plan.movedCount > 0 { parts.append(plan.movedCount == 1 ? "1 già tua raggruppata" : "\(plan.movedCount) già tue raggruppate") }
        if plan.recoloredCount > 0 { parts.append("nuovi colori") }
        let summary = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Organizza le categorie in principali e sottocategorie\(summary). Le transazioni restano dove sono e le categorie che hai archiviato non tornano."
    }

    private func applySuggestions() {
        guard let account else { return }
        do {
            try CategoryDefaults(context: modelContext).upgrade(account)
        } catch {
            showingSaveError = true
        }
    }

    private func archive(_ rows: [FinanceCategory], at offsets: IndexSet) {
        do {
            try SettingsEdits(context: modelContext).archiveCategories(rows, at: offsets)
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
            ContoLogo(conto: conto, size: 32)

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

// MARK: - Category Placement

/// Main category or subcategory, and for a main category whether it classifies income, expenses or both.
struct CategoryPlacementFields: View {
    let parents: [FinanceCategory]
    @Binding var parent: FinanceCategory?
    @Binding var kind: CategoryKind?
    var canMove = true

    var body: some View {
        Picker("Categoria principale", selection: $parent) {
            Text("Nessuna, è principale").tag(nil as FinanceCategory?)
            ForEach(parents, id: \.id) { category in
                Label(category.name ?? "Categoria", systemImage: category.icon ?? "tag")
                    .tag(category as FinanceCategory?)
            }
        }
        .disabled(!canMove)
        if parent == nil {
            Picker("Tipo", selection: $kind) {
                Text("Spese").tag(CategoryKind.expense as CategoryKind?)
                Text("Entrate").tag(CategoryKind.income as CategoryKind?)
                Text("Entrambe").tag(nil as CategoryKind?)
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
    @State private var selectedColor = CategoryPalette.fallback
    @State private var parentCategory: FinanceCategory?
    @State private var kind: CategoryKind? = .expense

    init(parent: FinanceCategory? = nil) {
        _parentCategory = State(initialValue: parent)
        _selectedColor = State(initialValue: parent?.color ?? CategoryPalette.fallback)
        _kind = State(initialValue: parent?.kind ?? .expense)
    }

    // MARK: - Constants
    private let icons = CategoryIconChoices.all


    // MARK: - Computed Properties
    private var parentCategories: [FinanceCategory] {
        CategoryHierarchy(categories: appState.selectedAccount?.categories ?? []).roots
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
            .navigationTitle(parentCategory == nil ? "Nuova categoria" : "Nuova sottocategoria")
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
        Section {
            TextField("Nome categoria", text: $name)
            CategoryPlacementFields(parents: parentCategories, parent: $parentCategory, kind: $kind)
        } header: {
            Text("Dettagli")
        } footer: {
            Text(parentCategory == nil
                 ? "Una categoria principale raggruppa le sottocategorie: usala quando non vuoi entrare nel dettaglio."
                 : "La sottocategoria eredita il tipo della categoria principale.")
        }
        .onChange(of: parentCategory) { _, parent in
            if let color = parent?.color { selectedColor = color }
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
                            .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : Color.primary)
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Colore") {
            CategoryColorGrid(selection: $selectedColor)
        }
    }

    private var previewSection: some View {
        Section("Anteprima") {
            HStack(spacing: 12) {
                let isMacro = parentCategory == nil
                Image(systemName: selectedIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMacro ? Color.white : Color(hex: selectedColor))
                    .frame(width: 40, height: 40)
                    .background(isMacro ? Color(hex: selectedColor) : Color(hex: selectedColor).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Nome categoria" : name)
                        .font(.headline)
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    Text(parentCategory.map { "Sottocategoria di \($0.name ?? "Categoria")" } ?? "Categoria principale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveCategory() {
        guard isValid, let account = appState.selectedAccount else { return }

        do {
            try SettingsEdits(context: modelContext).createCategory(
                name: name, color: selectedColor, icon: selectedIcon,
                parentID: parentCategory?.id, kind: kind, account: account
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
    @State private var selectedColor: String = CategoryPalette.fallback
    @State private var parentCategory: FinanceCategory?
    @State private var kind: CategoryKind?

    /// Only two levels: a macro category with subcategories stays a macro category.
    private var hasSubcategories: Bool {
        category.account?.categories?.contains { $0.parentCategoryId == category.id && $0.isActive == true } == true
    }

    private var parentCategories: [FinanceCategory] {
        CategoryHierarchy(categories: category.account?.categories ?? []).roots.filter { $0.id != category.id }
    }

    // MARK: - Constants
    private let icons = CategoryIconChoices.all


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
                selectedColor = category.color ?? CategoryPalette.fallback
                parentCategory = category.account?.categories?.first { $0.id == category.parentCategoryId }
                kind = category.kind
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Nome categoria", text: $name)
            CategoryPlacementFields(parents: parentCategories, parent: $parentCategory, kind: $kind,
                                    canMove: !hasSubcategories)
        } header: {
            Text("Dettagli")
        } footer: {
            if hasSubcategories {
                Text("Contiene sottocategorie, quindi resta una categoria principale. Il tipo vale anche per le sottocategorie.")
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
                            .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : Color.primary)
                }
            }
        }
    }

    private var colorSection: some View {
        Section("Colore") {
            CategoryColorGrid(selection: $selectedColor)
        }
    }

    private var previewSection: some View {
        Section("Anteprima") {
            HStack(spacing: 12) {
                let isMacro = parentCategory == nil
                Image(systemName: selectedIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMacro ? Color.white : Color(hex: selectedColor))
                    .frame(width: 40, height: 40)
                    .background(isMacro ? Color(hex: selectedColor) : Color(hex: selectedColor).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Nome categoria" : name)
                        .font(.headline)
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    Text(parentCategory.map { "Sottocategoria di \($0.name ?? "Categoria")" } ?? "Categoria principale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveChanges() {
        do {
            try SettingsEdits(context: modelContext).updateCategory(
                category, name: name, color: selectedColor, icon: selectedIcon,
                parentID: parentCategory?.id, kind: kind
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
                NavigationLink { TransactionListView(initialConto: conto, isPushed: true) } label: {
                    Label("Vedi movimenti", systemImage: "list.bullet.rectangle")
                }.buttonStyle(.bordered)
                NavigationLink { BalanceHistoryView(bookID: conto.account?.id, contoID: conto.id) } label: {
                    Label("Storico del saldo", systemImage: "chart.xyaxis.line")
                }.buttonStyle(.bordered)
            }.padding(22)
        }
        .themedBackground()
        .navigationTitle(conto.name ?? "Conto")
        .financePresentation(isPresented: $editing, title: "Modifica conto") { EditContoView(conto: conto) }
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


/// The same visible menu and swipe actions are available on iPhone, iPad and Mac.
private struct FinanceDeletionActions: ViewModifier {
    let target: FinanceContainerDeletion.Target
    let name: String
    var archive: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(AppStateManager.self) private var appState
    @State private var confirmation = false
    @State private var message = ""
    @State private var error: String?

    private var isBook: Bool { if case .book = target { return true }; return false }
    func body(content: Content) -> some View {
        HStack {
            content
            Menu {
                if let archive { Button("Archivia", systemImage: "archivebox", action: archive) }
                Button("Elimina", systemImage: "trash", role: .destructive, action: prepare)
            } label: { Image(systemName: "ellipsis.circle").padding(8) }
            .accessibilityLabel("Gestisci \(name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Elimina", systemImage: "trash", role: .destructive, action: prepare)
            if let archive { Button("Archivia", systemImage: "archivebox", action: archive).tint(.orange) }
        }
        .alert("Eliminare \(name)?", isPresented: $confirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina definitivamente", role: .destructive, action: delete)
        } message: { Text(message) }
        .alert("Impossibile eliminare", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func prepare() {
        do {
            let impact = try FinanceContainerDeletion(context: context).impact(of: target)
            let scope = isBook ? "Il libro e i suoi \(impact.conti) conti, anche archiviati, saranno eliminati insieme a categorie, budget e obiettivi. " : "Il conto sarà eliminato. "
            message = scope + "Verranno eliminati \(impact.transactions) movimenti, inclusi ricorrenze e allegati. I \(impact.transfers) trasferimenti collegati saranno eliminati per intero: cambierà anche il saldo degli altri conti coinvolti. L'operazione è definitiva e, se iCloud è attivo, si sincronizza sugli altri dispositivi."
            confirmation = true
        } catch { self.error = error.localizedDescription }
    }
    private func delete() {
        do {
            let selectedBookID = appState.selectedAccount?.id
            let selectedContoID = appState.selectedConto?.id
            try FinanceContainerDeletion(context: context).delete(target)
            switch target {
            case .book(let id) where selectedBookID == id:
                let remaining = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
                if let next = remaining.first { appState.selectAccount(next) }
                else { appState.selectedAccount = nil; appState.showAllAccounts = false; appState.selectAllConti() }
            case .conto(let id) where selectedContoID == id: appState.selectAllConti()
            default: break
            }
            appState.triggerDataRefresh()
        } catch { self.error = error.localizedDescription }
    }
}
