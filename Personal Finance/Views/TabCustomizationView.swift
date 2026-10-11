import SwiftUI
import SwiftData
import FinanceCore

struct TabCustomizationView: View {
    @Environment(AppStateManager.self) private var appState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Le sezioni che usi di più, a portata di mano.")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Oggi e Movimenti restano sempre nella barra. Puoi aggiungere fino a tre sezioni e scegliere il loro ordine.")
                        .foregroundStyle(ForgiaPalette.mutedText)
                    nativeTabPreview
                }.padding(.vertical, 8)
            }
            Section {
                fixedRow(.dashboard)
                fixedRow(.transactions)
            } header: {
                Text("Sempre visibili").foregroundStyle(ForgiaPalette.mutedText)
            }
            Section {
                if appState.optionalTabs.isEmpty {
                    Text("La barra contiene solo Oggi e Movimenti. Aggiungi una sezione dall’elenco qui sotto.")
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                ForEach(appState.optionalTabs, id: \.rawValue) { tab in
                    HStack(spacing: 12) {
                        Label(tab.navigationTitle, systemImage: tab.icon)
                        Spacer()
                        Button { move(tab, by: -1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                            .disabled(appState.optionalTabs.first == tab)
                            .accessibilityLabel("Sposta \(tab.navigationTitle) prima")
                        Button { move(tab, by: 1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                            .disabled(appState.optionalTabs.last == tab)
                            .accessibilityLabel("Sposta \(tab.navigationTitle) dopo")
                        Button { appState.setOptionalTabs(appState.optionalTabs.filter { $0 != tab }) } label: {
                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("Rimuovi \(tab.navigationTitle) dalla barra")
                    }.buttonStyle(.borderless)
                }
                #if os(macOS)
                orderingHelp
                #endif
            } header: {
                Text("Nella tua barra · \(appState.compactTabs.count)/5").foregroundStyle(ForgiaPalette.mutedText)
            } footer: {
                #if !os(macOS)
                orderingHelp
                #endif
            }
            Section {
                ForEach(AppTab.optionalChoices.filter { !appState.optionalTabs.contains($0) }, id: \.rawValue) { tab in
                    Button { appState.setOptionalTabs(appState.optionalTabs + [tab]) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(tab.navigationTitle, systemImage: tab.icon)
                                Text(tabDescription(tab)).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                        }.padding(.vertical, 4)
                    }
                    .disabled(appState.optionalTabs.count == 3)
                    .accessibilityLabel("Aggiungi \(tab.navigationTitle) alla barra")
                }
                #if os(macOS)
                availabilityHelp
                #endif
            } header: { Text("Sezioni disponibili").foregroundStyle(ForgiaPalette.mutedText) } footer: {
                #if !os(macOS)
                availabilityHelp
                #endif
            }
            Section {
                Label("Su iPad e Mac la sidebar mostra tutte le sezioni, indipendentemente da questa scelta.", systemImage: "sidebar.left")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ripristina Oggi, Movimenti e Pianifica") { appState.setOptionalTabs([.planning]) }
                    .disabled(appState.optionalTabs == [.planning])
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("Personalizza tab")
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    private var nativeTabPreview: some View {
        TabView(selection: .constant(AppTab.dashboard)) {
            ForEach(appState.compactTabs, id: \.rawValue) { tab in
                Color.clear
                    .tabItem { Label(tab.navigationTitle, systemImage: tab.icon) }
                    .tag(tab)
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

    private var orderingHelp: some View {
        Text("Le frecce cambiano l’ordine dei tab opzionali. Le modifiche vengono salvate subito su questo dispositivo.")
            .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var availabilityHelp: some View {
        Text(appState.optionalTabs.count == 3
             ? "Hai raggiunto cinque tab. Rimuovi una sezione dalla barra per aggiungerne un’altra."
             : "Una sezione fuori dalla barra resta disponibile nel menu Sezioni e impostazioni di Oggi.")
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

    private func tabDescription(_ tab: AppTab) -> String {
        switch tab {
        case .planning: "Scadenze, ricorrenze e progetti di risparmio"
        case .analysis: "Andamento delle spese, categorie e confronti"
        case .calendar: "Movimenti registrati e previsti, giorno per giorno"
        case .budgets: "Limiti di spesa del libro selezionato"
        case .accounts: "Saldi e gestione dei conti del libro selezionato"
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
            if !selectedBooks.isEmpty, Set(selectedBooks.map { $0.currency ?? "EUR" }).count == 1 {
                FinanceCalendarView(contoIDs: Set(selectedBooks.flatMap(\.activeConti).map(\.id)), currency: selectedBooks.first?.currency ?? "EUR")
                    .compactSettingsAccess()
            } else {
                BookSelectionRequiredView(message: "Scegli un libro per consultare il calendario nella sua valuta.")
                    .compactSettingsAccess()
            }
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
                    .compactSettingsAccess()
            }
        } else if section == .budgets {
            BudgetView(showsCloseButton: false)
        } else {
            NavigationStack { ContiSettingsView().compactSettingsAccess() }
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
            Button("Scegli libro") { appState.presentAccountSelection() }
                .buttonStyle(.borderedProminent)
        }
    }
}
