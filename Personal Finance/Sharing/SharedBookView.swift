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
    @State private var cloudIdentityRevision = 0
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
    private struct NameLookup: Hashable {
        let enabled: Bool
        let generation: Int
        let revision: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SharedBookOverview(name: conto?.name ?? book.name ?? "Libro", isContoShare: conto != nil)

                if let pendingStopScope {
                    SharedBookPanel(cardLayout: true) {
                        Button("Completa l’interruzione sul dispositivo") { completeOwnerStop(scope: pendingStopScope) }
                            .frame(minHeight: 44)
                    }
                }

                SharedBookInvitationCard(isContoShare: conto != nil, isOwner: membership?.isOwner != false,
                                         isShared: membership != nil, enabled: enabled, busy: action != nil,
                                         personName: Binding(get: { personName }, set: {
                                             personName = $0
                                             TransactionPeople.markDisplayNameAsManual()
                                         }),
                                         onInvite: { action = Action(kind: .share) },
                                         onSync: { action = Action(kind: .synchronize) }) {
                    SharedBookSyncFeedback(message: message, busy: action != nil,
                        status: enabled ? storage.sharedBookAutomaticRefresh.statuses[conto?.id ?? book.id] : nil)
                }

                SharedBookPrivacyCard(isContoShare: conto != nil)

                if let conto {
                    SharedContoCategoriesCard(conto: conto)
                }

                if let conto, membership?.isOwner == false {
                    SharedBookPanel("Libro sul tuo dispositivo", cardLayout: true) {
                        Picker("Inserisci il conto in", selection: $destinationBookID) {
                            Text("Scegli un libro").tag(nil as UUID?)
                            ForEach(books.filter { $0.isActive == true && $0.currency == book.currency && $0.id != book.id }) { candidate in
                                Text(candidate.name ?? "Libro").tag(Optional(candidate.id))
                            }
                        }
                        Button("Sposta nel libro scelto") { moveConto() }
                            .frame(minHeight: 44)
                            .disabled(destinationBookID == nil || action != nil)
                        Text("Il conto resta lo stesso. I conti personali del libro scelto restano privati.")
                            .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)
                        Text(conto.name ?? "Conto").font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    }
                }

                if membership?.isOwner == false {
                    SharedBookLeaveSection(enabled: enabled, busy: action != nil, cardLayout: true) {
                        action = Action(kind: .leave)
                    }
                }
                SharedBookConflictReview(conflicts: conflicts, referenceCount: referenceCount, currency: book.currency ?? "EUR",
                                         enabled: enabled, busy: action != nil, cardLayout: true, choices: $choices) {
                    action = Action(kind: .resolve)
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .themedBackground()
        .tint(ForgiaPalette.accent)
        .navigationTitle("Condivisione")
        .toolbarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            cloudIdentityRevision += 1
        }
        .task(id: NameLookup(enabled: enabled, generation: storage.containerGeneration, revision: cloudIdentityRevision)) {
            guard enabled, personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            _ = try? await storage.sharedBookTransport.currentPerson()
        }
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
