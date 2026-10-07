#if os(macOS)
import SwiftUI
import SwiftData
import FinanceCore
import AppKit

enum MacSettingsPane: String, CaseIterable, Identifiable {
    case appearance, reminders, privacy, books, accounts, categories, widgets, shortcuts, cloud, files, erase, about
    var id: Self { self }
    var title: String {
        switch self {
        case .appearance: "Aspetto"
        case .reminders: "Promemoria"
        case .privacy: "Privacy e blocco"
        case .books: "Libri"
        case .accounts: "Conti"
        case .categories: "Categorie"
        case .widgets: "Widget"
        case .shortcuts: "Comandi Rapidi e Siri"
        case .cloud: "iCloud"
        case .files: "Importa ed esporta"
        case .erase: "Cancella dati"
        case .about: "Informazioni"
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .reminders: "bell.badge"
        case .privacy: "lock"
        case .books: "books.vertical"
        case .accounts: "creditcard"
        case .categories: "tag"
        case .widgets: "square.grid.2x2"
        case .shortcuts: "square.stack.3d.up"
        case .cloud: "icloud"
        case .files: "arrow.up.arrow.down"
        case .erase: "trash"
        case .about: "info.circle"
        }
    }
}

private enum MacSettingsGroup: String, CaseIterable, Identifiable {
    case general, books, integrations, data, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "Generali"
        case .books: "Libri e conti"
        case .integrations: "Integrazioni"
        case .data: "Dati"
        case .about: "Informazioni"
        }
    }
    var panes: [MacSettingsPane] {
        switch self {
        case .general: [.appearance, .reminders, .privacy]
        case .books: [.books, .accounts, .categories]
        case .integrations: [.widgets, .shortcuts]
        case .data: [.cloud, .files, .erase]
        case .about: [.about]
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .books: "books.vertical"
        case .integrations: "square.grid.2x2"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
}

struct MacSettingsWorkspace: View {
    @Environment(AppStateManager.self) private var state
    @Query(sort: \Account.name) private var books: [Account]
    @State private var selection: MacSettingsPane
    @State private var group: MacSettingsGroup
    var onImportCSV: () -> Void
    var onExportCSV: () -> Void
    var onGenerateDemo: () -> Void
    var isGeneratingDemo: Bool

    init(initialPane: MacSettingsPane = .appearance, onImportCSV: @escaping () -> Void = {},
         onExportCSV: @escaping () -> Void = {}, onGenerateDemo: @escaping () -> Void = {},
         isGeneratingDemo: Bool = false) {
        _selection = State(initialValue: initialPane)
        _group = State(initialValue: MacSettingsGroup.allCases.first { $0.panes.contains(initialPane) } ?? .general)
        self.onImportCSV = onImportCSV
        self.onExportCSV = onExportCSV
        self.onGenerateDemo = onGenerateDemo
        self.isGeneratingDemo = isGeneratingDemo
    }

    var body: some View {
        Group {
            if group.panes.count > 1 {
                NavigationSplitView {
                    List(selection: Binding<MacSettingsPane?>(
                        get: { selection },
                        set: { if let pane = $0 { selection = pane } }
                    )) {
                        Section(group.title) {
                            ForEach(group.panes) { pane in
                                Label(pane.title, systemImage: pane.symbol)
                                    .tag(pane)
                                    .accessibilityIdentifier("mac-settings-pane-\(pane.rawValue)")
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
                } detail: {
                    settingsDetail
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar(removing: .sidebarToggle)
            } else {
                settingsDetail
            }
        }
        .toolbar {
            preferenceItem(.general)
            preferenceItem(.books)
            preferenceItem(.integrations)
            preferenceItem(.data)
            preferenceItem(.about)
        }
        .frame(minWidth: 960, minHeight: 560)
        .background(MacPreferenceWindowStyle())
        .accessibilityIdentifier("mac-settings-workspace")
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            if group == .books || group == .data {
                HStack {
                    Text("Libro:").foregroundStyle(.secondary)
                    Picker("Libro", selection: Binding(
                        get: { state.selectedAccount?.id },
                        set: { id in
                            if let book = books.first(where: { $0.id == id }) { state.selectAccount(book) }
                        }
                    )) {
                        Text("Scegli libro").tag(nil as UUID?)
                        ForEach(books.filter { $0.isActive == true }) { book in
                            Text(book.name ?? "Libro").tag(Optional(book.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
            NavigationStack {
                pane(selection)
                    .navigationTitle(selection.title)
            }
            .id(selection)
        }
    }

    @ToolbarContentBuilder
    private func preferenceItem(_ tab: MacSettingsGroup) -> some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(id: "settings-\(tab.rawValue)") { sectionButton(tab) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "settings-\(tab.rawValue)") { sectionButton(tab) }
        }
    }

    private func sectionButton(_ tab: MacSettingsGroup) -> some View {
        Button {
            group = tab
            selection = tab.panes[0]
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 24, weight: .regular))
                Text(tab.title).font(.system(size: 12, weight: group == tab ? .medium : .regular))
            }
            .foregroundStyle(group == tab ? ForgiaPalette.accent : Color.primary)
            .frame(width: 104, height: 64)
            .background {
                if group == tab {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .accessibilityAddTraits(group == tab ? .isSelected : [])
        .accessibilityIdentifier("mac-settings-tab-\(tab.rawValue)")
    }

    @ViewBuilder private func pane(_ pane: MacSettingsPane) -> some View {
        switch pane {
        case .appearance: appearance
        case .reminders: settingsForm { RecurrenceReminderSettings() }
        case .privacy: settingsForm { AppLockSettingsSection() }
        case .books: BooksSettingsView()
        case .accounts:
            if state.selectedAccount != nil { ContiSettingsView() }
            else { chooseBook }
        case .categories:
            if state.selectedAccount != nil { CategoryManagementView() }
            else { chooseBook }
        case .widgets: settingsForm { WidgetSettingsSection() }
        case .shortcuts: FinanceShortcutsView()
        case .cloud: CloudSettingsView()
        case .files: files
        case .erase: EraseDataView()
        case .about: about
        }
    }

    private var appearance: some View {
        @Bindable var state = state
        return settingsForm {
            Section("Colori") {
                Picker("Tema", selection: Binding(
                    get: { state.themeManager.currentTheme },
                    set: { state.themeManager.setTheme($0) }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Sfondi sfumati", isOn: $state.tintedBackgrounds)
            }
            Section {
                Text("Il tema si applica a tutte le finestre. Gli sfondi sfumati aggiungono una leggera sfumatura in cima alle schermate.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var files: some View {
        settingsForm {
            Section("CSV") {
                LabeledContent("Importa movimenti") {
                    Button("Importa CSV…", action: onImportCSV)
                }
                LabeledContent("Salva una copia dei movimenti") {
                    Button("Esporta CSV…", action: onExportCSV)
                }
            }
            Section {
                Text("L'importazione e l'esportazione si aprono in finestre separate, così puoi continuare a consultare il libro.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var about: some View {
        settingsForm {
            Section {
                LabeledContent {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                } label: {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Formi")
                        .font(.headline)
                    Text("Piccoli passi. Un domani più sereno.").foregroundStyle(.secondary)
                }
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
            #if DEBUG
            Section("Sviluppo") {
                HStack {
                    Text("Libro con movimenti di esempio")
                    Spacer()
                    if isGeneratingDemo { ProgressView().controlSize(.small) }
                    Button("Genera dati demo…", action: onGenerateDemo).disabled(isGeneratingDemo)
                }
            }
            #endif
        }
    }

    private var chooseBook: some View {
        ContentUnavailableView("Seleziona un libro", systemImage: "books.vertical",
            description: Text("Scegli il libro dal menu Libro per gestire i suoi conti e le sue categorie."))
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            Form { content() }
                .formStyle(.columns)
                .toggleStyle(.checkbox)
                .controlSize(.regular)
                .padding(32)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Keep the preference toolbar below the title, with icons and labels like Mail.
private struct MacPreferenceWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.configureWindow() }

    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }
        func configureWindow() {
            guard let window else { return }
            window.toolbarStyle = .preference
            window.toolbar?.displayMode = .iconOnly
            window.toolbar?.sizeMode = .regular
        }
    }
}

#endif
