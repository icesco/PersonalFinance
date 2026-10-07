import SwiftUI
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
                Label("Inviti ai libri condivisi", systemImage: "envelope.badge")
                    .frame(maxWidth: .infinity).padding(10)
            }
            .background(.regularMaterial)
            .sheet(isPresented: $showing) {
                NavigationStack {
                    SharedInvitationsView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { showing = false } } }
                }
            }
        }
    }
}

struct SharedInvitationsView: View {
    @Environment(DataStorageManager.self) private var storage
    @State private var inbox = SharedInvitationInbox.shared
    @State private var accepting: Acceptance?
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
                    Text("Accettando, Formi aggiungerà il libro condiviso senza collegarlo ai tuoi libri privati.")
                        .foregroundStyle(.secondary)
                    if entry.metadata.participantPermission != .readWrite {
                        Text("Questo invito non consente modifiche. L’apertura dei libri in sola lettura non è ancora disponibile.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Accetta e aggiungi libro") { accepting = Acceptance(entry: entry) }
                        .disabled(!enabled || accepting != nil || entry.metadata.participantPermission != .readWrite)
                    Button("Rimuovi da questo dispositivo", role: .destructive) { inbox.remove(entry.id) }
                        .disabled(accepting != nil)
                }
            }
            if inbox.pending.isEmpty { Text("Nessun invito in attesa.").foregroundStyle(.secondary) }
            if accepting != nil { ProgressView("Aggiunta del libro…") }
            if let message { Text(message) }
        }
        .navigationTitle("Inviti")
        .task(id: accepting?.id) {
            guard let request = accepting else { return }
            await accept(request)
        }
        .onChange(of: enabled) { if !enabled { accepting = nil } }
    }
    @MainActor private func accept(_ request: Acceptance) async {
        let entry = request.entry
        defer { if accepting?.id == request.id { accepting = nil } }
        message = nil
        do {
            let scope = try await storage.sharedBookTransport.acceptInvitation(entry.metadata)
            try Task.checkCancellation()
            let result = try await storage.sharedBookCoordinator.synchronize(scope: scope, role: .participant)
            guard accepting?.id == request.id else { return }
            switch result {
            case .synchronized:
                inbox.remove(entry.id)
                message = "Libro aggiunto. Lo trovi nell’elenco dei libri di Formi."
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
