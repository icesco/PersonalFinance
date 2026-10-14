import SwiftUI
import SwiftData
import CloudKit
import FinanceCore

struct SharedInvitationNotice: View {
    @State private var inbox = SharedInvitationInbox.shared
    @State private var showing = false
    var body: some View {
        if !inbox.pending.isEmpty || inbox.error != nil {
            Button {
                showing = true
            } label: {
                Label("Inviti alla condivisione", systemImage: "envelope.badge")
                    .frame(maxWidth: .infinity).padding(10)
            }
            .background(.regularMaterial)
            .sheet(isPresented: $showing) {
                NavigationStack {
                    SharedInvitationsView()
                        .toolbar { FinanceDismissToolbar { Button("Chiudi") { showing = false } } }
                }
            }
        }
    }
}

struct SharedInvitationsView: View {
    @Environment(DataStorageManager.self) private var storage
    @State private var inbox = SharedInvitationInbox.shared
    @State private var accepting: Acceptance?
    @State private var placement: Placement?
    private struct Placement: Identifiable {
        let id = UUID()
        let entry: SharedInvitationInbox.Entry
        let scope: SharedBookScope
        let bookID: UUID
    }
    private struct Acceptance: Identifiable { let id = UUID(); let entry: SharedInvitationInbox.Entry }
    @State private var message: String?
    private var enabled: Bool { storage.isCloudSyncEnabled && !storage.isMigrating }
    var body: some View {
        List {
            if let error = inbox.error {
                Section { Text(error); Button("Chiudi avviso") { inbox.error = nil } }
            }
            if !enabled {
                Section {
                    Label("Sincronizzazione iCloud disattivata", systemImage: "icloud.slash")
                    if inbox.pending.isEmpty {
                        Text("Per accettare un invito, attiva iCloud nelle impostazioni di Formi.")
                    } else {
                        Text("Gli inviti restano salvati. Attiva iCloud nelle impostazioni di Formi, poi torna qui per accettarli.")
                    }
                }
            }
            ForEach(inbox.pending) { entry in
                Section {
                    Text(entry.title).font(.headline)
                    Text("Accettando un conto condiviso, potrai scegliere un tuo libro o crearne uno nuovo. Gli inviti a un libro intero lo aggiungono come libro separato.")
                        .foregroundStyle(.secondary)
                    if entry.metadata.participantPermission != .readWrite {
                        Text("Questo invito non consente modifiche. L’apertura dei libri in sola lettura non è ancora disponibile.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Accetta invito") { accepting = Acceptance(entry: entry) }
                        .disabled(!enabled || accepting != nil || placement != nil || entry.metadata.participantPermission != .readWrite)
                    Button("Rimuovi da questo dispositivo", role: .destructive) { inbox.remove(entry.id) }
                        .disabled(accepting != nil || placement != nil)
                }
            }
            if inbox.pending.isEmpty { Text("Nessun invito in attesa.").foregroundStyle(.secondary) }
            if accepting != nil { ProgressView("Ricezione dei dati condivisi…") }
            if let message { Text(message) }
        }
        .navigationTitle("Inviti")
        .task(id: accepting?.id) {
            guard let request = accepting else { return }
            await accept(request)
        }
        .sheet(item: $placement) { value in
            SharedContoDestinationView(scope: value.scope, receivedBookID: value.bookID, title: value.entry.title) { _ in
                inbox.remove(value.entry.id)
                placement = nil
                message = "Conto aggiunto al libro scelto."
            }
        }
        .onChange(of: enabled) { if !enabled { accepting = nil; placement = nil } }
    }
    @MainActor private func accept(_ request: Acceptance) async {
        let entry = request.entry
        defer { if accepting?.id == request.id { accepting = nil } }
        message = nil
        do {
            let invitationScope = try SharedBookInvitation.scope(metadata: entry.metadata)
            let existing: Bool
            if let container = storage.currentContainer {
                let key = invitationScope.key
                existing = try ModelContext(container).fetchCount(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key })) > 0
            } else { existing = false }
            let scope: SharedBookScope
            if existing { scope = invitationScope }
            else { scope = try await storage.sharedBookTransport.acceptInvitation(entry.metadata) }
            try Task.checkCancellation()
            let result = try await storage.sharedBookCoordinator.synchronize(scope: scope, role: .participant)
            guard accepting?.id == request.id else { return }
            switch result {
            case let .synchronized(localBookID):
                if scope.isContoShare {
                    message = "Condivisione ricevuta. Scegli un libro per completare l’aggiunta; puoi riaprire questo invito se preferisci farlo più tardi."
                    placement = Placement(entry: entry, scope: scope, bookID: localBookID)
                } else {
                    inbox.remove(entry.id)
                    message = "Libro condiviso aggiunto. Lo trovi nell’elenco dei libri di Formi."
                }
            case .needsReview:
                message = "Il libro contiene modifiche da confrontare. Apri la sua schermata Condivisione per scegliere quali conservare."
            }
        } catch is CancellationError {
            guard accepting?.id == request.id else { return }
            message = "Operazione interrotta. L’invito resta disponibile per riprovare."
        } catch {
            guard accepting?.id == request.id else { return }
            message = enabled
                ? "Il libro non è stato aggiunto. Verifica la connessione e che l’invito sia ancora valido, poi riprova."
                : "Sincronizzazione disattivata. L’invito resta salvato."
        }
    }
}
