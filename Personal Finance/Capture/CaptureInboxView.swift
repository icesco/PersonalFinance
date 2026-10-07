import SwiftUI
import SwiftData
import FinanceCore

struct CaptureInboxView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [PendingCapture] = []
    @State private var store: ModelContainer?
    @State private var error: String?
    @State private var discard: PendingCapture?
    @State private var selected: PendingCapture?
    @Environment(\.modelContext) private var context
    @Query(sort: \Conto.name) private var conti: [Conto]
    @State private var history: [FinanceTransaction] = []
    @Environment(AppStateManager.self) private var appState
    @State private var totalCount = 0
    @State private var hasMore = false
    private let pageSize = 30
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink("Configura notifiche e condivisione", destination: CaptureSetupView())
                Text("Le proposte restano su questo dispositivo e non cambiano saldi o budget finché non le approvi.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
            }.unifiedCard()
            if items.isEmpty {
                ContentUnavailableView("Nessuna proposta da approvare", systemImage: "tray", description: Text("Acquisisci una notifica bancaria oppure condividi un PDF, una foto o del testo con Formi."))
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Da approvare · \(totalCount)").font(.subheadline.weight(.semibold)).foregroundStyle(ForgiaPalette.mutedText)
                    ForEach(items) { item in
                        Button { selected = item } label: {
                            CaptureProposalRow(capture: item, conti: conti, history: history)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .unifiedCard()
                        .accessibilityIdentifier(item.document == nil ? "capture-proposal-text" : "capture-proposal-document")
                        .contextMenu { Button("Scarta", role: .destructive) { discard = item } }
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .id(items.last?.id)
                            .onAppear { loadMore() }
                    }
                }
            }
            }.padding(.horizontal, 22).padding(.vertical, 20)
        }
        .themedBackground()
        .navigationTitle("Da approvare")
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { CaptureReviewView(capture: selected, onFinish: refreshAfterRemoval) }
        }
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .refreshable { reload() }
        .confirmationDialog("Scartare questa proposta?", isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } }), titleVisibility: .visible) {
            Button("Scarta proposta", role: .destructive) {
                do {
                    if let discard, let store { try CaptureStore.discard(id: discard.id, in: store) }
                    discard = nil; refreshAfterRemoval()
                } catch { self.error = error.localizedDescription }
            }
        }
        .alert("Impossibile completare", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func reload() {
        do {
            let store = try CaptureStore.container()
            self.store = store
            let loadedLimit = max(pageSize, items.count)
            items = try CaptureStore.pendingPage(in: store, limit: loadedLimit)
            totalCount = try CaptureStore.pendingCount(in: store)
            hasMore = items.count < totalCount
            var descriptor = FetchDescriptor<FinanceTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 500
            history = try context.fetch(descriptor)
        } catch { self.error = error.localizedDescription }
    }
    private func loadMore() {
        guard hasMore, let store, let last = items.last else { return }
        do {
            let boundaryIDs = items.filter { $0.createdAt == last.createdAt }.map(\.id)
            let page = try CaptureStore.pendingPage(in: store, before: last.createdAt,
                                                   excludingBoundaryIDs: boundaryIDs, limit: pageSize)
            items.append(contentsOf: page)
            totalCount = try CaptureStore.pendingCount(in: store)
            hasMore = !page.isEmpty && items.count < totalCount
        } catch { hasMore = false; self.error = error.localizedDescription }
    }
    private func refreshAfterRemoval() {
        reload()
        appState.triggerDataRefresh()
    }
}

struct CaptureInboxEntry: View {
    var compactHomeStyle = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStateManager.self) private var appState
    @State private var count: Int?
    var body: some View {
        NavigationLink(destination: CaptureInboxView()) {
            if compactHomeStyle {
                HStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ForgiaPalette.accent)
                        .frame(width: 30, height: 30)
                        .background(ForgiaPalette.sageSurface, in: RoundedRectangle(cornerRadius: 9))
                    Text("Da approvare")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(ForgiaPalette.onAccent)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(ForgiaPalette.accent, in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Da approvare")
                .accessibilityValue(count.map { "\($0) proposte" } ?? "")
            } else {
                Label {
                    HStack { Text("Da approvare"); Spacer(); if let count, count > 0 { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) } }
                        .contentShape(Rectangle())
                } icon: { Image(systemName: "tray.and.arrow.down") }
            }
        }
        .onAppear { refresh() }
        .onChange(of: appState.dataRefreshTrigger) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }
    private func refresh() { count = try? CaptureStore.pendingCount(in: CaptureStore.container()) }
}

struct CaptureSetupView: View {
    var body: some View {
        List {
            Section("Destinazione delle notifiche") {
                NavigationLink("Conti predefiniti per banca", destination: CaptureBankDefaultsView())
            }
            Section("Notifiche bancarie · iOS 27") {
                Text("1. In Comandi Rapidi crea un comando e aggiungi l’automazione Notifica, scegliendo l’app della tua banca o Wallet.")
                Text("2. Filtra le notifiche di pagamento. Aggiungi l’azione di Formi “Acquisisci notifica bancaria” e passa il testo della notifica nel campo Testo.")
                Text("3. Indica la banca o app di origine. Il nome del conto di destinazione è facoltativo: se lo lasci vuoto, Formi usa il default configurato per quella banca oppure propone l’unico libro e conto disponibili. Scegli l’esecuzione immediata dove disponibile e prova con una notifica reale.")
                Text("Un conto indicato nel comando ha la precedenza sul default e viene proposto solo se corrisponde a un unico conto attivo. Controlla sempre la destinazione durante l’approvazione.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("PDF, foto e testo") {
                Text("Apri l’allegato in Mail, File o un’altra app, tocca Condividi e scegli Formi. Il documento verrà conservato in Da approvare.")
                Text("Per un’email senza allegati, condividi il testo selezionato se il client lo consente. La lettura del documento avviene quando apri la proposta in Formi.")
            }
            Section("Prima dell’approvazione") {
                Text("Controlla importo, valuta, data, conto e categoria. Una fattura ricevuta non dimostra il pagamento: approvala solo quando è stata pagata.")
                Text("Notifiche ripetute o importazioni CSV possono descrivere lo stesso movimento. Formi segnala possibili duplicati e richiede un controllo.")
                Text("Le proposte sono locali; il movimento approvato segue le impostazioni iCloud del tuo libro. Se l’acquisizione fallisce, Comandi Rapidi mostra un errore: la notifica non è stata conservata.")
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(ForgiaPalette.surface)
        .themedBackground()
        .navigationTitle("Automazione")
        .toolbarTitleDisplayMode(.inline)
    }
}
