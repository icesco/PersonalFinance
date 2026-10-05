import Foundation
import SwiftData
import CloudKit

/// Serializes each book's reconciliation on this device. Network requests may
/// suspend, but exporting and applying the latest local graph has no await gap.
@MainActor
public final class SharedBookSyncCoordinator {
    public enum Failure: Error { case unavailable, alreadySyncing, missingLocalIdentity }
    public enum Outcome: Sendable {
        case synchronized(localBookID: UUID)
        case needsReview(conflicts: [SharedBookConflict], references: Set<SharedRecordID>)
    }
    public enum OwnerPreparation: Sendable {
        case ready(scope: SharedBookScope, share: CKShare)
        case needsReview(conflicts: [SharedBookConflict], references: Set<SharedRecordID>)
    }
    private let transport: SharedBookCloudTransport
    private let shadows: SharedBookShadowStore
    private let configuration: @MainActor () -> (container: ModelContainer?, generation: Int, enabled: Bool)
    private var running: Set<String> = []
    private var preparing: Set<UUID> = []
    private var scopeRevisions: [String: Int] = [:]
    private var ownerBookRevisions: [UUID: Int] = [:]
    private var revokedScopes: Set<String> = []
    private var pendingOwnerCleanup: Set<UUID> = []

    public init(transport: SharedBookCloudTransport, shadows: SharedBookShadowStore,
                configuration: @escaping @MainActor () -> (container: ModelContainer?, generation: Int, enabled: Bool)) {
        self.transport = transport; self.shadows = shadows; self.configuration = configuration
    }

    /// Invoked by an explicit sharing action, never by startup or background
    /// refresh. The sharing sheet is returned only after uploading the book.
    public func prepareOwnerShare(bookID: UUID) async throws -> OwnerPreparation {
        let initial = configuration()
        guard initial.enabled, let container = initial.container else { throw Failure.unavailable }
        guard !pendingOwnerCleanup.contains(bookID) else { throw Failure.unavailable }
        guard preparing.insert(bookID).inserted else { throw Failure.alreadySyncing }
        defer { preparing.remove(bookID) }
        let bookRevision = ownerBookRevisions[bookID, default: 0]
        func check() throws {
            try Task.checkCancellation()
            let current = configuration()
            guard current.enabled, current.generation == initial.generation, current.container === container,
                  ownerBookRevisions[bookID, default: 0] == bookRevision else { throw Failure.unavailable }
        }
        let owner = try await transport.ownerRecordName()
        try check()
        try container.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: bookID, ownerRecordName: owner, container: container)
        revokedScopes.remove(scope.key)
        try await transport.ensureOwnerZone(scope: scope)
        try check()
        switch try await synchronize(scope: scope, role: .owner) {
        case let .needsReview(conflicts, references): return .needsReview(conflicts: conflicts, references: references)
        case .synchronized: break
        }
        try check()
        let context = ModelContext(container)
        guard let book = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == bookID })).first else { throw Failure.missingLocalIdentity }
        let share = try await transport.ownerShare(scope: scope, title: book.name ?? "Libro condiviso")
        try check()
        return .ready(scope: scope, share: share)
    }
    /// The system sharing UI has already confirmed revocation. This performs
    /// no network request and invalidates any suspended synchronization first.
    public func ownerDidStopSharing(scope: SharedBookScope) throws -> UUID {
        ownerBookRevisions[scope.bookID, default: 0] += 1
        scopeRevisions[scope.key, default: 0] += 1
        revokedScopes.insert(scope.key)
        pendingOwnerCleanup.insert(scope.bookID)
        guard let container = configuration().container else { throw Failure.unavailable }
        try container.mainContext.save()
        let id = try SharedBookDepartureService.preservePrivateCopy(scope: scope, container: container, owner: true)
        pendingOwnerCleanup.remove(scope.bookID)
        return id
    }

    /// Stops participation while preserving the latest local graph as a private
    /// book. A failed or interrupted request leaves its identity metadata intact.
    public func leaveKeepingPrivateCopy(scope: SharedBookScope) async throws -> UUID {
        let initial = configuration()
        guard initial.enabled, let container = initial.container else { throw Failure.unavailable }
        guard running.insert(scope.key).inserted else { throw Failure.alreadySyncing }
        defer { running.remove(scope.key) }
        try container.mainContext.save()
        let context = ModelContext(container)
        let key = scope.key
        let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
        guard let membership = memberships.first, memberships.allSatisfy({
            !$0.isOwner && $0.ownerName == scope.ownerName && $0.remoteBookID == scope.bookID && $0.localBookID == membership.localBookID
        }) else { throw Failure.missingLocalIdentity }
        let localID = membership.localBookID
        guard try context.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.id == localID })) == 1 else { throw Failure.missingLocalIdentity }
        try await transport.leaveParticipantShare(scope: scope)
        try Task.checkCancellation()
        let current = configuration()
        guard current.enabled, current.generation == initial.generation, current.container === container else { throw Failure.unavailable }
        // Save edits made while the network request was pending. Detachment only
        // changes sharing metadata, never reimports an older financial snapshot.
        try container.mainContext.save()
        return try SharedBookDepartureService.preservePrivateCopy(scope: scope, container: container)
    }

    public func synchronize(scope: SharedBookScope, role: SharedBookCloudTransport.Role,
                            decisions: [SharedBookDecision] = []) async throws -> Outcome {
        let initial = configuration()
        guard initial.enabled, let container = initial.container else { throw Failure.unavailable }
        guard running.insert(scope.key).inserted else { throw Failure.alreadySyncing }
        defer { running.remove(scope.key) }
        let scopeRevision = scopeRevisions[scope.key, default: 0]
        func checkConfiguration() throws {
            try Task.checkCancellation()
            let current = configuration()
            guard current.enabled, current.generation == initial.generation, current.container === container,
                  scopeRevisions[scope.key, default: 0] == scopeRevision else { throw Failure.unavailable }
        }
        guard !revokedScopes.contains(scope.key) else { throw Failure.unavailable }
        var base = try shadows.read(scope: scope) ?? []
        let remote = try await transport.fetch(scope: scope, role: role)
        try checkConfiguration()
        try container.mainContext.save()
        let context = ModelContext(container)
        let key = scope.key
        let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
        let local: SharedBookExport
        if memberships.isEmpty {
            let departed = try context.fetchCount(FetchDescriptor<SharedBookDeparture>(predicate: #Predicate { $0.scopeKey == key })) > 0
            if departed { base = [] } // A new invitation must not merge the retained private copy.
            // Joining imports into an isolated namespace. Publishing an existing
            // owner's book requires registering its original identities first.
            guard role == .participant, base.isEmpty else { throw Failure.missingLocalIdentity }
            local = SharedBookExport(bookID: scope.bookID, records: [], assets: [:])
        } else {
            guard memberships.allSatisfy({ $0.isOwner == (role == .owner) }) else { throw Failure.missingLocalIdentity }
            let localID = memberships[0].localBookID
            let exists = try context.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.id == localID })) > 0
            let rootID = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
            if !exists, base.contains(where: { $0.id == rootID && $0.deleted }), base.allSatisfy(\.deleted) {
                // A previously acknowledged deletion has no exportable Account.
                // Preserve its tombstones on subsequent runs; never interpret an
                // unexplained missing local book as permission to delete remotely.
                local = SharedBookExport(bookID: scope.bookID, records: base, assets: [:])
            } else {
                local = try SharedBookParticipantExporter.export(scope: scope, container: container)
            }
        }
        let plan = try SharedBookReconciliation.reconcile(bookID: scope.bookID, base: base, local: local.records, remote: remote.records,
                                                          localAssets: local.assets, remoteAssets: remote.assets, decisions: decisions)
        guard plan.canApply else { return .needsReview(conflicts: plan.conflicts, references: plan.unresolvedReferences) }
        let localBookID = try SharedBookImporter.apply(scope: scope, records: plan.records, assets: plan.assets, container: container)
        // Applying preserves merged local edits. Checkpoint only what the server
        // has actually acknowledged, so an interrupted upload remains pending.
        try shadows.write(scope: scope, acknowledged: remote.records)
        if !plan.uploads.isEmpty {
            _ = try await transport.upload(scope: scope, role: role, changes: plan.uploads, assets: plan.assets, serverRecords: remote.serverRecords)
            try checkConfiguration()
            // Do not import again here: the person may have edited while awaiting
            // upload. Those newer edits will differ from this base on the next run.
            try shadows.write(scope: scope, acknowledged: plan.records)
        }
        return .synchronized(localBookID: localBookID)
    }
}
