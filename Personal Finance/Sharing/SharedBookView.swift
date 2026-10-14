import SwiftUI
import SwiftData
import CloudKit
import FinanceCore

struct SharedBookView: View {
    let book: Account
    var conto: Conto? = nil
    @AppStorage("formi.personDisplayName") private var personName = ""
    @Environment(DataStorageManager.self) private var storage
    @Query private var memberships: [SharedBookMembership]
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Account]
    @State private var destinationBookID: UUID?
    @State private var action: Action?
    @State private var prepared: PreparedShare?
    @State private var message: String?
    @State private var pendingStopScope: SharedBookScope?
    @State private var conflicts: [SharedBookConflict] = []
    @State private var referenceCount = 0
    @State private var choices: [SharedRecordID: SharedBookMerge.Side] = [:]
    private struct Action: Hashable {
        enum Kind: Hashable { case share, synchronize, resolve, leave }
        let id = UUID()
        let kind: Kind
    }
    private struct PreparedShare: Identifiable { let id = UUID(); let share: CKShare; let scope: SharedBookScope }
    private var membership: SharedBookMembership? { memberships.first { $0.localBookID == book.id && $0.localContoID == conto?.id } }
    private var enabled: Bool { storage.isCloudSyncEnabled && !storage.isMigrating }

    var body: some View {
        List {
            if let pendingStopScope {
                Button("Completa l’interruzione sul dispositivo") { completeOwnerStop(scope: pendingStopScope) }
            }
            Section {
                Text(conto?.name ?? book.name ?? "Libro").font(.headline)
                Text(conto == nil ? "Condividi conti, movimenti, budget, ricorrenze e allegati di questo libro con le persone che inviti." : "Condividi soltanto questo conto e i suoi movimenti. I tuoi altri conti restano privati, anche se appartengono allo stesso libro.")
                    .foregroundStyle(.secondary)
                Text(conto == nil ? "I conti di altri libri restano privati. I trasferimenti mostrano soltanto la parte relativa a questo libro." : "I trasferimenti mantengono il collegamento al tuo conto privato sul tuo dispositivo. Gli invitati vedono solo il movimento sul conto condiviso, senza note o allegati del trasferimento privato.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let conto {
                Section("Categorie del conto") {
                    Text("Questo conto ha un elenco di categorie condiviso con le persone invitate. Alla condivisione, Formi copia nell’elenco le categorie già usate dai suoi movimenti. Puoi anche creare nuove categorie dedicate al conto.")
                    Text("Le copie sono indipendenti: le categorie personali originali restano invariate.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if conto.usesSharedCategories == true {
                        NavigationLink("Gestisci categorie condivise") { SharedContoCategoriesView(conto: conto) }
                    }
                }
            }
            Section("Come compari nei movimenti") {
                TextField("Il tuo nome", text: $personName)
                Text("Serve a riconoscere chi registra i movimenti e chi effettua i versamenti.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !enabled {
                Section {
                    Label("Sincronizzazione iCloud disattivata", systemImage: "icloud.slash")
                    Text("Attiva iCloud nelle impostazioni di Formi per condividere o aggiornare i dati.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if membership?.isOwner != false {
                    Button {
                        action = Action(kind: .share)
                    } label: {
                        Label(membership == nil ? (conto == nil ? "Condividi libro" : "Condividi conto") : "Gestisci invitati", systemImage: "person.badge.plus")
                    }
                    .disabled(!enabled || action != nil)
                    .opacity(enabled && action == nil ? 1 : 0.45)
                    .accessibilityIdentifier("shared-book-invite")
                } else {
                    Label(conto == nil ? "Libro ricevuto" : "Conto ricevuto", systemImage: "person.2")
                    Text("Gli inviti sono gestiti dal proprietario della condivisione.").foregroundStyle(.secondary)
                }
                if membership != nil {
                    Button("Sincronizza adesso", systemImage: "arrow.triangle.2.circlepath") { action = Action(kind: .synchronize) }
                        .disabled(!enabled || action != nil)
                        .opacity(enabled && action == nil ? 1 : 0.45)
                        .accessibilityIdentifier("shared-book-sync")
                }
                if action != nil { ProgressView("Aggiornamento della condivisione…") }
                if let message {
                    Text(message).font(.callout).accessibilityIdentifier("shared-book-status")
                } else if enabled, let status = storage.sharedBookAutomaticRefresh.statuses[conto?.id ?? book.id] {
                    switch status {
                    case let .updated(date):
                        Text("Aggiornamento automatico: \(date, format: .dateTime.hour().minute())")
                            .font(.callout)
                    case .needsReview:
                        Text("Ci sono differenze da verificare. Tocca Sincronizza adesso per confrontarle.")
                            .font(.callout)
                    case .failed:
                        Text("Aggiornamento automatico non riuscito. I dati locali restano disponibili; puoi riprovare con Sincronizza adesso.")
                            .font(.callout)
                    }
                }
            }
            if let conto, membership?.isOwner == false {
                Section("Libro sul tuo dispositivo") {
                    Picker("Inserisci il conto in", selection: $destinationBookID) {
                        Text("Scegli un libro").tag(nil as UUID?)
                        ForEach(books.filter { $0.isActive == true && $0.currency == book.currency && $0.id != book.id }) { candidate in
                            Text(candidate.name ?? "Libro").tag(Optional(candidate.id))
                        }
                    }
                    Button("Sposta nel libro scelto") { moveConto() }
                        .disabled(destinationBookID == nil || action != nil)
                    Text("Il conto resta lo stesso. I conti personali del libro scelto restano privati.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(conto.name ?? "Conto").font(.caption).foregroundStyle(.secondary)
                }
            }
            if membership?.isOwner == false {
                SharedBookLeaveSection(enabled: enabled, busy: action != nil) {
                    action = Action(kind: .leave)
                }
            }
            SharedBookConflictReview(conflicts: conflicts, referenceCount: referenceCount, currency: book.currency ?? "EUR",
                                     enabled: enabled, busy: action != nil, choices: $choices) {
                action = Action(kind: .resolve)
            }
            Section {
                Text("I conti e i libri già condivisi si aggiornano automaticamente mentre Formi è aperta e sbloccata, con iCloud attivo. Puoi anche usare Sincronizza adesso. La prima condivisione carica i dati su iCloud prima di aprire gli inviti.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Condivisione")
        .task(id: action) {
            guard let action else { return }
            await perform(action)
        }
        .onChange(of: enabled) {
            if !enabled { action = nil; prepared = nil }
        }
        .sheet(item: $prepared) { value in
            SharedBookSystemSheet(share: value.share, title: conto?.name ?? book.name ?? "Condivisione", onStatus: { message = $0 }, onStopSharing: {
                completeOwnerStop(scope: value.scope)
            })
        }
    }

    @MainActor private func moveConto() {
        guard let membership, let destinationBookID, let container = storage.currentContainer else { return }
        do {
            let scope = SharedBookScope(ownerName: membership.ownerName, bookID: membership.remoteBookID, isContoShare: membership.localContoID != nil)
            try SharedContoPlacement.move(scope: scope, to: destinationBookID, container: container)
            dismiss()
        } catch { message = "Spostamento non riuscito. Scegli un libro privato nella stessa valuta, senza categorie usate da altri conti." }
    }

    @MainActor private func completeOwnerStop(scope: SharedBookScope) {
        action = nil
        pendingStopScope = scope
        do {
            _ = try storage.sharedBookCoordinator.ownerDidStopSharing(scope: scope)
            storage.sharedBookAutomaticRefresh.clearStatus(for: conto?.id ?? book.id)
            pendingStopScope = nil
            prepared = nil
            message = "Condivisione interrotta. I dati restano privati sul dispositivo."
        } catch {
            prepared = nil
            message = "La condivisione è stata interrotta su iCloud. Completa l’interruzione sul dispositivo per aggiornare lo stato locale."
        }
    }

    @MainActor private func perform(_ action: Action) async {
        defer { if self.action == action { self.action = nil } }
        let decisions = conflicts.compactMap { conflict in
            choices[conflict.local.id].map { SharedBookDecision(expected: conflict, side: $0) }
        }
        message = nil; conflicts = []; referenceCount = 0; choices = [:]
        do {
            switch action.kind {
            case .share:
                let result = try await storage.sharedBookCoordinator.prepareOwnerShare(bookID: book.id, contoID: conto?.id)
                guard self.action == action else { return }
                switch result {
                case let .ready(scope, share):
                    try Task.checkCancellation()
                    guard enabled else { return }
                    storage.sharedBookAutomaticRefresh.clearStatus(for: conto?.id ?? book.id)
                    prepared = PreparedShare(share: share, scope: scope)
                case let .needsReview(values, references): conflicts = values; referenceCount = references.count
                }
            case .leave:
                guard let membership, !membership.isOwner else { return }
                let scope = SharedBookScope(ownerName: membership.ownerName, bookID: membership.remoteBookID, isContoShare: membership.localContoID != nil)
                _ = try await storage.sharedBookCoordinator.leaveKeepingPrivateCopy(scope: scope)
                guard self.action == action else { return }
                storage.sharedBookAutomaticRefresh.clearStatus(for: conto?.id ?? book.id)
                message = "Hai lasciato la condivisione. I dati ricevuti restano come copia privata sul dispositivo."
            case .synchronize, .resolve:
                guard let membership else { return }
                let scope = SharedBookScope(ownerName: membership.ownerName, bookID: membership.remoteBookID, isContoShare: membership.localContoID != nil)
                let result = try await storage.sharedBookCoordinator.synchronize(scope: scope, role: membership.isOwner ? .owner : .participant,
                                                                                     decisions: action.kind == .resolve ? decisions : [])
                guard self.action == action else { return }
                switch result {
                case .synchronized:
                    storage.sharedBookAutomaticRefresh.clearStatus(for: conto?.id ?? book.id)
                    message = "Dati condivisi aggiornati."
                case let .needsReview(values, references): conflicts = values; referenceCount = references.count
                }
            }
        } catch SharedBookOwnerRegistration.Failure.alreadyRegistered {
            message = "Questo conto appartiene già a una condivisione. Gestisci quella esistente oppure interrompila prima di cambiare il perimetro degli invitati."
        } catch is CancellationError {
            guard self.action == action else { return }
            message = "Operazione interrotta. Puoi riprovare per verificare lo stato del libro."
        } catch SharedBookImporter.Failure.protectedTransfer {
            guard self.action == action else { return }
            message = "Una modifica riguarda un trasferimento collegato a un libro privato. Non è stata applicata: occorre confrontare le due versioni."
        } catch {
            guard self.action == action else { return }
            if !enabled { message = "Sincronizzazione iCloud disattivata." }
            else if let cloud = error as? CKError, cloud.code == .notAuthenticated {
                message = "Accedi a iCloud nelle impostazioni del dispositivo, poi riprova."
            } else if let cloud = error as? CKError, cloud.code == .permissionFailure {
                message = "Non hai il permesso di aggiornare questo libro. Verifica l’invito con il proprietario."
            } else {
                message = "Aggiornamento non confermato. Le modifiche locali restano sul dispositivo: controlla la connessione e riprova."
            }
        }
    }
}
