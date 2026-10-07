import SwiftUI
import SwiftData
import CloudKit
import FinanceCore

struct SharedBookView: View {
    let book: Account
    @Environment(DataStorageManager.self) private var storage
    @Query private var memberships: [SharedBookMembership]
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
    private var membership: SharedBookMembership? { memberships.first { $0.localBookID == book.id } }
    private var enabled: Bool { storage.isCloudSyncEnabled && !storage.isMigrating }

    var body: some View {
        List {
            if let pendingStopScope {
                Button("Completa l’interruzione sul dispositivo") { completeOwnerStop(scope: pendingStopScope) }
            }
            Section {
                Text(book.name ?? "Libro").font(.headline)
                Text("Condividi conti, movimenti, budget, ricorrenze e allegati di questo libro con le persone che inviti.")
                    .foregroundStyle(.secondary)
                Text("I conti di altri libri restano privati. I trasferimenti mostrano soltanto la parte relativa a questo libro.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !enabled {
                Section {
                    Label("Sincronizzazione iCloud disattivata", systemImage: "icloud.slash")
                    Text("Attiva iCloud nelle impostazioni di Formi per condividere o aggiornare un libro.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if membership?.isOwner != false {
                    Button {
                        action = Action(kind: .share)
                    } label: {
                        Label(membership == nil ? "Condividi libro" : "Gestisci invitati", systemImage: "person.badge.plus")
                    }
                    .disabled(!enabled || action != nil)
                    .opacity(enabled && action == nil ? 1 : 0.45)
                    .accessibilityIdentifier("shared-book-invite")
                } else {
                    Label("Libro ricevuto", systemImage: "person.2")
                    Text("Gli inviti sono gestiti dal proprietario del libro.").foregroundStyle(.secondary)
                }
                if membership != nil {
                    Button("Sincronizza adesso", systemImage: "arrow.triangle.2.circlepath") { action = Action(kind: .synchronize) }
                        .disabled(!enabled || action != nil)
                        .opacity(enabled && action == nil ? 1 : 0.45)
                        .accessibilityIdentifier("shared-book-sync")
                }
                if action != nil { ProgressView("Aggiornamento del libro…") }
                if let message {
                    Text(message).font(.callout).accessibilityIdentifier("shared-book-status")
                } else if enabled, let status = storage.sharedBookAutomaticRefresh.statuses[book.id] {
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
                Text("I libri già condivisi si aggiornano automaticamente mentre Formi è aperta e sbloccata, con iCloud attivo. Puoi anche usare Sincronizza adesso. La prima condivisione carica i dati su iCloud prima di aprire gli inviti.")
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
            SharedBookSystemSheet(share: value.share, title: book.name ?? "Libro condiviso", onStatus: { message = $0 }, onStopSharing: {
                completeOwnerStop(scope: value.scope)
            })
        }
    }

    @MainActor private func completeOwnerStop(scope: SharedBookScope) {
        action = nil
        pendingStopScope = scope
        do {
            _ = try storage.sharedBookCoordinator.ownerDidStopSharing(scope: scope)
            storage.sharedBookAutomaticRefresh.clearStatus(for: book.id)
            pendingStopScope = nil
            prepared = nil
            message = "Condivisione interrotta. Il libro resta privato sul dispositivo."
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
                let result = try await storage.sharedBookCoordinator.prepareOwnerShare(bookID: book.id)
                guard self.action == action else { return }
                switch result {
                case let .ready(scope, share):
                    try Task.checkCancellation()
                    guard enabled else { return }
                    storage.sharedBookAutomaticRefresh.clearStatus(for: book.id)
                    prepared = PreparedShare(share: share, scope: scope)
                case let .needsReview(values, references): conflicts = values; referenceCount = references.count
                }
            case .leave:
                guard let membership, !membership.isOwner else { return }
                let scope = SharedBookScope(ownerName: membership.ownerName, bookID: membership.remoteBookID)
                _ = try await storage.sharedBookCoordinator.leaveKeepingPrivateCopy(scope: scope)
                guard self.action == action else { return }
                storage.sharedBookAutomaticRefresh.clearStatus(for: book.id)
                message = "Hai lasciato la condivisione. Questo libro è ora una copia privata con i dati presenti sul dispositivo."
            case .synchronize, .resolve:
                guard let membership else { return }
                let scope = SharedBookScope(ownerName: membership.ownerName, bookID: membership.remoteBookID)
                let result = try await storage.sharedBookCoordinator.synchronize(scope: scope, role: membership.isOwner ? .owner : .participant,
                                                                                     decisions: action.kind == .resolve ? decisions : [])
                guard self.action == action else { return }
                switch result {
                case .synchronized:
                    storage.sharedBookAutomaticRefresh.clearStatus(for: book.id)
                    message = "Libro aggiornato."
                case let .needsReview(values, references): conflicts = values; referenceCount = references.count
                }
            }
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
