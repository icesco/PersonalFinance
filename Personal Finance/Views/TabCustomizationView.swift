import SwiftUI
import SwiftData
import FinanceCore
import UniformTypeIdentifiers

struct TabCustomizationView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targetedTab: AppTab?
    @State private var targetingBar = false
    @State private var targetingAvailable = false

    private var availableTabs: [AppTab] {
        AppTab.optionalChoices.filter { !appState.optionalTabs.contains($0) }
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Le sezioni che usi di più, a portata di mano.")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Oggi e Movimenti restano sempre nella barra. Puoi aggiungere fino a tre sezioni e scegliere il loro ordine.")
                        .foregroundStyle(ForgiaPalette.mutedText)
                    nativeTabPreview
                }.padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 12) {
                Text("Sempre visibili").font(.headline).foregroundStyle(ForgiaPalette.mutedText)
                fixedRow(.dashboard)
                fixedRow(.transactions)
            }.unifiedCard()
            selectedSection
            availableSection
            VStack(alignment: .leading, spacing: 16) {
                Label("Su iPad e Mac la sidebar mostra tutte le sezioni, indipendentemente da questa scelta.", systemImage: "sidebar.left")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ripristina Oggi, Movimenti e Pianifica") { appState.setOptionalTabs([.planning]) }
                    .disabled(appState.optionalTabs == [.planning])
            }.unifiedCard()
          }
          .padding(22)
        }
        .themedBackground()
        .navigationTitle("Personalizza tab")
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    private var selectedSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nella tua barra · \(appState.compactTabs.count)/5").font(.headline).foregroundStyle(ForgiaPalette.mutedText)
                if appState.optionalTabs.isEmpty {
                    Text("La barra contiene solo Oggi e Movimenti. Aggiungi una sezione dall’elenco qui sotto.")
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                ForEach(appState.optionalTabs, id: \.rawValue) { tab in
                    selectedRow(tab)
                }
                Label("Trascina qui per aggiungere alla barra", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tab-drop-bar")
                    .onDrop(of: [UTType.text], isTargeted: $targetingBar) { providers in
                        acceptDrop(providers)
                    }
                    .background(targetingBar ? ForgiaPalette.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                orderingHelp
            }.unifiedCard()
    }

    private var availableSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sezioni disponibili").font(.headline).foregroundStyle(ForgiaPalette.mutedText)
                Label("Trascina qui per togliere dalla barra", systemImage: "minus")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tab-drop-available")
                    .onDrop(of: [UTType.text], isTargeted: $targetingAvailable) { providers in
                        acceptDrop(providers, removing: true)
                    }
                    .background(targetingAvailable ? ForgiaPalette.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                ForEach(availableTabs, id: \.rawValue) { tab in
                    availableRow(tab)
                }
                availabilityHelp
            }.unifiedCard()
    }

    private var nativeTabPreview: some View {
        TabView(selection: .constant(AppTab.dashboard)) {
            ForEach(appState.compactTabs, id: \.rawValue) { tab in
                Tab(value: tab, role: tab == .search ? .search : nil) {
                    Color.clear
                } label: { Label(tab.navigationTitle, systemImage: tab.icon) }
            }
        }
        #if os(iOS)
        .environment(\.horizontalSizeClass, .compact)
        .frame(height: 110)
        #else
        .frame(height: 80)
        #endif
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Anteprima non interattiva della barra: \(appState.compactTabs.map(\.navigationTitle).joined(separator: ", "))")
    }

    private func selectedRow(_ tab: AppTab) -> some View {
        HStack(spacing: 12) {
            Label(tab.navigationTitle, systemImage: tab.icon)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: dragValue(tab) as NSString) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tab-drag-\(tab.rawValue)")
                .accessibilityHint(tab == .search ? "Trascina per togliere dalla barra. Ricerca resta separata dagli altri tab." : "Trascina per riordinare o togliere dalla barra")
            Spacer()
            Button { move(tab, by: -1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                .disabled(tab == .search || appState.optionalTabs.first == tab)
                .accessibilityLabel("Sposta \(tab.navigationTitle) prima")
                .accessibilityIdentifier("Sposta \(tab.navigationTitle) prima")
            Button { move(tab, by: 1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .disabled(tab == .search || appState.optionalTabs.filter { $0 != .search }.last == tab)
                .accessibilityLabel("Sposta \(tab.navigationTitle) dopo")
                .accessibilityIdentifier("Sposta \(tab.navigationTitle) dopo")
            Button { appState.setOptionalTabs(appState.optionalTabs.filter { $0 != tab }) } label: {
                Image(systemName: "minus.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Rimuovi \(tab.navigationTitle) dalla barra")
            .accessibilityIdentifier("Rimuovi \(tab.navigationTitle) dalla barra")
        }
        .buttonStyle(.borderless)
        .onDrop(of: [UTType.text], isTargeted: Binding(
            get: { targetedTab == tab }, set: { targetedTab = $0 ? tab : nil }
        )) { providers in acceptDrop(providers, before: tab) }
        .background(targetedTab == tab ? ForgiaPalette.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }

    private func availableRow(_ tab: AppTab) -> some View {
        HStack(spacing: 12) {
            availableLabel(tab)
            Spacer()
            Button { appState.setOptionalTabs(appState.optionalTabs + [tab]) } label: {
                Image(systemName: "plus.circle").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(appState.optionalTabs.count == 3)
            .accessibilityLabel("Aggiungi \(tab.navigationTitle) alla barra")
            .accessibilityIdentifier("Aggiungi \(tab.navigationTitle) alla barra")
        }
        .padding(.vertical, 4)
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in acceptDrop(providers, removing: true) }
    }

    private func availableLabel(_ tab: AppTab) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tab.navigationTitle, systemImage: tab.icon)
            Text(tabDescription(tab)).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: dragValue(tab) as NSString) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tab-drag-\(tab.rawValue)")
        .accessibilityHint("Trascina nella tua barra per aggiungere questo tab")
    }

    private var orderingHelp: some View {
        Text("Tieni premuta una sezione e trascinala per aggiungerla, riordinarla o toglierla dalla barra. Puoi usare anche i pulsanti. Le modifiche vengono salvate subito.")
            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var availabilityHelp: some View {
        Text(appState.optionalTabs.count == 3
             ? "Hai raggiunto cinque tab. Rimuovi una sezione dalla barra per aggiungerne un’altra."
             : "Una sezione fuori dalla barra resta disponibile nella schermata Oggi.")
            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fixedRow(_ tab: AppTab) -> some View {
        HStack {
            Label(tab.navigationTitle, systemImage: tab.icon)
            Spacer()
            Text("Fisso").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            Image(systemName: "lock").foregroundStyle(ForgiaPalette.mutedText)
        }.accessibilityElement(children: .combine)
    }

    private func move(_ tab: AppTab, by offset: Int) {
        var tabs = appState.optionalTabs
        guard let index = tabs.firstIndex(of: tab), tabs.indices.contains(index + offset) else { return }
        tabs.swapAt(index, index + offset)
        appState.setOptionalTabs(tabs)
    }

    private func dragValue(_ tab: AppTab) -> String { "formi-tab:\(tab.rawValue)" }

    private func acceptDrop(_ providers: [NSItemProvider], before destination: AppTab? = nil, removing: Bool = false) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String else { return }
            Task { @MainActor in
                if removing {
                    _ = removeDraggedTab([value])
                } else {
                    _ = placeDraggedTab([value], before: destination)
                }
            }
        }
        return true
    }

    private func draggedTab(_ values: [String]) -> AppTab? {
        guard values.count == 1, let value = values.first,
              value.hasPrefix("formi-tab:"),
              let rawValue = Int(value.dropFirst("formi-tab:".count)),
              let tab = AppTab(rawValue: rawValue), AppTab.optionalChoices.contains(tab) else { return nil }
        return tab
    }

    private func placeDraggedTab(_ values: [String], before destination: AppTab? = nil) -> Bool {
        guard let tab = draggedTab(values) else { return false }
        return withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            appState.placeOptionalTab(tab, before: destination)
        }
    }

    private func removeDraggedTab(_ values: [String]) -> Bool {
        guard let tab = draggedTab(values), appState.optionalTabs.contains(tab) else { return false }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            appState.setOptionalTabs(appState.optionalTabs.filter { $0 != tab })
        }
        return true
    }

    private func tabDescription(_ tab: AppTab) -> String {
        switch tab {
        case .planning: "Scadenze, ricorrenze e progetti di risparmio"
        case .analysis: "Andamento delle spese, categorie e confronti"
        case .calendar: "Movimenti registrati e previsti, giorno per giorno"
        case .budgets: "Limiti di spesa del libro selezionato"
        case .accounts: "Saldi e gestione dei conti del libro selezionato"
        case .search: "Cerca in tutte le date. Il tab resta separato dagli altri nella barra."
        default: ""
        }
    }
}

struct CalendarTabView: View {
    @Environment(AppStateManager.self) private var appState
    @Query private var books: [Account]

    private var selectedBooks: [Account] {
        appState.showAllAccounts ? books.filter { $0.isActive == true } : appState.selectedAccount.map { [$0] } ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if !selectedBooks.isEmpty, Set(selectedBooks.map { $0.currency ?? "EUR" }).count == 1 {
                    FinanceCalendarView(contoIDs: Set(selectedBooks.flatMap(\.activeConti).map(\.id)), currency: selectedBooks.first?.currency ?? "EUR")
                } else {
                    BookSelectionRequiredView(message: "Scegli un libro per consultare il calendario nella sua valuta.")
                }
            }
            .sectionSheetChrome("Calendario")
        }
    }
}

struct BookScopedTabView: View {
    @Environment(AppStateManager.self) private var appState
    let section: AppTab

    var body: some View {
        if appState.showAllAccounts || appState.selectedAccount == nil {
            NavigationStack {
                BookSelectionRequiredView(message: "Scegli un libro per gestire \(section == .budgets ? "i budget" : "i conti").")
                    .navigationTitle(section.navigationTitle)
                    .sectionSheetChrome(section.navigationTitle)
            }
        } else if section == .budgets {
            BudgetView(showsCloseButton: false)
        } else {
            NavigationStack { ContiSettingsView().sectionSheetChrome("Conti") }
        }
    }
}

private struct BookSelectionRequiredView: View {
    @Environment(AppStateManager.self) private var appState
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label("Scegli un libro", systemImage: "books.vertical")
        } description: {
            Text(message)
        } actions: {
            Button("Scegli libro nelle Impostazioni") { appState.openBookSettings() }
                .buttonStyle(.borderedProminent)
        }
    }
}
