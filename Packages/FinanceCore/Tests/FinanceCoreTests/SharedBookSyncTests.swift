import Foundation
import SwiftData
import CloudKit
import Testing
@testable import FinanceCore

@MainActor
private final class SyncDatabase: SharedCloudDatabase {
    var records: [CKRecord.ID: CKRecord] = [:]
    var leaves = 0
    var onLeave: () throws -> Void = {}
    func leaveShare(_ id: CKRecord.ID) async throws -> CKRecord.ID {
        leaves += 1; try onLeave(); return id
    }
    var saves = 0
    var events: [String] = []
    var afterSave: () throws -> Void = {}
    var onPage: () throws -> Void = {}
    var onOwnerStage: (String) throws -> Void = { _ in }
    func page(zone: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> SharedCloudPage {
        events.append("fetch")
        try onPage()
        return SharedCloudPage(records: Array(records.values), deleted: [], token: nil, moreComing: false)
    }
    func save(_ values: [CKRecord]) async throws -> [CKRecord] {
        saves += 1
        events.append("save")
        for value in values { records[value.recordID] = value }
        try afterSave()
        return values
    }
    func ownerRecordName() async throws -> String { events.append("identity"); try onOwnerStage("identity"); return "synthetic-owner" }
    func ensureZone(_ zone: CKRecordZone.ID) async throws { events.append("zone"); try onOwnerStage("zone") }
    func share(zone: CKRecordZone.ID, title: String) async throws -> CKShare {
        events.append("share")
        try onOwnerStage("share")
        let value = CKShare(recordZoneID: zone)
        value.publicPermission = .none
        return value
    }
}

@MainActor
struct SharedBookSyncTests {
    private func fixture() throws -> (SharedBookScope, SharedBookExport) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Demo", currency: "EUR")
        let conto = Conto(name: "Comune", type: .checking, initialBalance: 100)
        conto.account = book; book.conti = [conto]
        let expense = FinanceCore.Transaction(amount: 20, type: .expense)
        expense.setFromConto(conto)
        container.mainContext.insert(book); container.mainContext.insert(expense)
        try container.mainContext.save()
        return (SharedBookScope(ownerName: "synthetic-owner", bookID: book.id), try SharedBookExporter.export(bookID: book.id, container: container))
    }

    @Test(arguments: ["identity", "zone", "share"])
    func revokedOwnerPreparationCannotPresentOrReregisterTheShare(stage: String) async throws {
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Privato dopo revoca")
        target.mainContext.insert(book)
        try target.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: book.id, ownerRecordName: "synthetic-owner", container: target)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = SyncDatabase()
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: SharedBookShadowStore(directory: folder), configuration: { (target, 1, true) })
        database.onOwnerStage = { current in
            if current == stage { _ = try coordinator.ownerDidStopSharing(scope: scope) }
        }
        await #expect(throws: SharedBookSyncCoordinator.Failure.self) {
            try await coordinator.prepareOwnerShare(bookID: book.id)
        }
        let fresh = ModelContext(target)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookMembership>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookRecordLink>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(database.events.last == stage)
        database.onOwnerStage = { _ in }
        guard case .ready = try await coordinator.prepareOwnerShare(bookID: book.id) else {
            Issue.record("A later explicit request must work")
            return
        }
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
    }

    @Test func ownerRevocationPreservesGraphAndInvalidatesPendingFetch() async throws {
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Da mantenere")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        conto.account = book
        let expense = FinanceCore.Transaction(amount: 20, type: .expense)
        expense.setFromConto(conto)
        target.mainContext.insert(book); target.mainContext.insert(expense)
        try target.mainContext.save()
        let scope = try SharedBookOwnerRegistration.register(bookID: book.id, ownerRecordName: "synthetic-owner", container: target)
        let original = try SharedBookExporter.export(bookID: book.id, container: target)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = SyncDatabase()
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: SharedBookShadowStore(directory: folder), configuration: { (target, 1, true) })
        database.onPage = { _ = try coordinator.ownerDidStopSharing(scope: scope) }
        await #expect(throws: (any Error).self) { try await coordinator.synchronize(scope: scope, role: .owner) }
        #expect(database.events == ["fetch"])
        #expect(database.saves == 0)
        #expect(try coordinator.ownerDidStopSharing(scope: scope) == book.id)
        #expect(try SharedBookExporter.export(bookID: book.id, container: target).records == original.records)
        let fresh = ModelContext(target)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookMembership>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookRecordLink>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookDeparture>()) == 1)
        await #expect(throws: (any Error).self) { try await coordinator.synchronize(scope: scope, role: .owner) }
        #expect(database.events == ["fetch"])
        database.onPage = {}
        guard case .ready = try await coordinator.prepareOwnerShare(bookID: book.id) else { Issue.record("Explicit reshare failed"); return }
        #expect(try fresh.fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
    }

    @Test func firstJoinThenDisjointEditsPreserveNewEditDuringUpload() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shadows = SharedBookShadowStore(directory: folder)
        let database = SyncDatabase()
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName)
        for value in snapshot.records {
            let record = try SharedBookCloudCodec.encode(value, zoneID: zone)
            database.records[record.recordID] = record
        }
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: shadows, configuration: { (target, 1, true) })
        guard case .synchronized = try await coordinator.synchronize(scope: scope, role: .participant) else { Issue.record("Join failed"); return }
        #expect(database.saves == 0)
        #expect(try shadows.read(scope: scope) == snapshot.records)
        let context = ModelContext(target)
        let expense = try #require(context.fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
        expense.amount = 35; try context.save()
        let remoteID = try #require(snapshot.records.first { $0.id.kind == .transaction }?.id)
        var remote = try #require(snapshot.records.first { $0.id == remoteID })
        remote.fields["notes"] = .text("Nota remota")
        let cloud = try SharedBookCloudCodec.encode(remote, zoneID: zone)
        database.records[cloud.recordID] = cloud
        database.afterSave = {
            let editing = ModelContext(target)
            let latest = try #require(editing.fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
            latest.notes = "Modifica durante invio"
            try editing.save()
        }
        guard case .synchronized = try await coordinator.synchronize(scope: scope, role: .participant) else { Issue.record("Merge failed"); return }
        let saved = try #require(ModelContext(target).fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
        #expect(saved.amount == 35 && saved.notes == "Modifica durante invio")
        let acknowledged = try #require(shadows.read(scope: scope)?.first { $0.id == remoteID })
        #expect(acknowledged.fields["amount"] == .decimal(35))
        #expect(acknowledged.fields["notes"] == .text("Nota remota"))
        #expect(database.saves == 1)
    }

    @Test func repeatedRejoinsUseSameIdentitiesOnTwoDevicesAndKeepEveryPrivateCopy() throws {
        let (scope, snapshot) = try fixture()
        let first = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let second = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        var previous: Set<UUID> = []
        for cycle in 0..<3 {
            let firstID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: first)
            let secondID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: second)
            #expect(firstID == secondID && !previous.contains(firstID))
            previous.insert(firstID)
            let firstLinks = try ModelContext(first).fetch(FetchDescriptor<SharedBookRecordLink>())
            let secondLinks = try ModelContext(second).fetch(FetchDescriptor<SharedBookRecordLink>())
            #expect(Dictionary(uniqueKeysWithValues: firstLinks.map { ($0.remoteRecordName, $0.localIdentity) }) ==
                    Dictionary(uniqueKeysWithValues: secondLinks.map { ($0.remoteRecordName, $0.localIdentity) }))
            for container in [first, second] {
                #expect(try ModelContext(container).fetchCount(FetchDescriptor<Account>()) == cycle + 1)
                for id in previous {
                    let copy = try SharedBookExporter.export(bookID: id, container: container)
                    #expect(copy.records.first { $0.id.kind == .transaction }?.fields["amount"] == .decimal(20))
                }
                _ = try SharedBookDepartureService.preservePrivateCopy(scope: scope, container: container)
            }
            // Simulate duplicate/out-of-order metadata on the second device.
            let context = ModelContext(second)
            for id in previous.sorted(by: { $0.uuidString > $1.uuidString }) {
                context.insert(SharedBookDeparture(scopeKey: scope.key, localBookID: id))
            }
            try context.save()
        }
    }

    @Test func departureRejectsOwnersAndConfigurationChangesWithoutDetaching() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let membership = try #require(context.fetch(FetchDescriptor<SharedBookMembership>()).first)
        membership.isOwner = true
        try context.save()
        let database = SyncDatabase()
        var generation = 1
        let transport = SharedBookCloudTransport(configuration: { (true, generation) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: SharedBookShadowStore(directory: folder), configuration: { (target, generation, true) })
        await #expect(throws: (any Error).self) { try await coordinator.leaveKeepingPrivateCopy(scope: scope) }
        #expect(database.leaves == 0)
        membership.isOwner = false
        try context.save()
        database.onLeave = { generation += 1 }
        await #expect(throws: (any Error).self) { try await coordinator.leaveKeepingPrivateCopy(scope: scope) }
        #expect(database.leaves == 1)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookDeparture>()) == 0)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 1)
    }

    @Test func leavingKeepsLatestPrivateCopyAndRejoiningUsesIndependentIdentities() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shadows = SharedBookShadowStore(directory: folder)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let originalID = try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        try shadows.write(scope: scope, acknowledged: snapshot.records)
        let database = SyncDatabase()
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName)
        for value in snapshot.records {
            let record = try SharedBookCloudCodec.encode(value, zoneID: zone)
            database.records[record.recordID] = record
        }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: shadows, configuration: { (target, 1, true) })
        database.onLeave = { throw CKError(.networkUnavailable) }
        await #expect(throws: CKError.self) { try await coordinator.leaveKeepingPrivateCopy(scope: scope) }
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookDeparture>()) == 0)
        database.onLeave = {
            let editing = ModelContext(target)
            let expense = try #require(editing.fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
            expense.amount = 47
            try editing.save()
        }
        #expect(try await coordinator.leaveKeepingPrivateCopy(scope: scope) == originalID)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookMembership>()) == 0)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookRecordLink>()) == 0)
        let privateCopy = try SharedBookExporter.export(bookID: originalID, container: target)
        #expect(privateCopy.records.first { $0.id.kind == .transaction }?.fields["amount"] == .decimal(47))
        guard case let .synchronized(joinedID) = try await coordinator.synchronize(scope: scope, role: .participant) else {
            Issue.record("Rejoin failed"); return
        }
        #expect(joinedID != originalID)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 2)
        let rejoined = try SharedBookParticipantExporter.export(scope: scope, container: target)
        #expect(rejoined.records == snapshot.records)
        #expect(try SharedBookExporter.export(bookID: originalID, container: target).records == privateCopy.records)
        guard case let .synchronized(repeatedID) = try await coordinator.synchronize(scope: scope, role: .participant) else {
            Issue.record("Repeat synchronization failed"); return
        }
        #expect(repeatedID == joinedID && database.saves == 0)
    }

    @Test func missingLocalBookWithoutAcknowledgedDeletionCannotDeleteServerData() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shadows = SharedBookShadowStore(directory: folder)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        try shadows.write(scope: scope, acknowledged: snapshot.records)
        let editing = ModelContext(target)
        editing.delete(try #require(editing.fetch(FetchDescriptor<Account>()).first))
        try editing.save()
        let database = SyncDatabase()
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName)
        for value in snapshot.records {
            let record = try SharedBookCloudCodec.encode(value, zoneID: zone)
            database.records[record.recordID] = record
        }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: shadows, configuration: { (target, 1, true) })
        await #expect(throws: (any Error).self) {
            _ = try await coordinator.synchronize(scope: scope, role: .participant)
        }
        #expect(database.saves == 0)
        #expect(try shadows.read(scope: scope) == snapshot.records)
    }

    @Test func acknowledgedBookDeletionCanSynchronizeAgainWithoutRepublishing() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shadows = SharedBookShadowStore(directory: folder)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        try shadows.write(scope: scope, acknowledged: snapshot.records)
        let database = SyncDatabase()
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName)
        let deleted = snapshot.records.map { $0.tombstone() }
        for value in deleted {
            let record = try SharedBookCloudCodec.encode(value, zoneID: zone)
            database.records[record.recordID] = record
        }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: shadows, configuration: { (target, 1, true) })
        for _ in 0..<2 {
            guard case .synchronized = try await coordinator.synchronize(scope: scope, role: .participant) else {
                Issue.record("Deletion did not synchronize"); return
            }
            #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 0)
            #expect(try shadows.read(scope: scope) == deleted)
            #expect(database.saves == 0)
        }
    }

    @Test func conflictingAmountsDoNotMutateLocalDataOrAdvanceCheckpoint() async throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shadows = SharedBookShadowStore(directory: folder)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        try SharedBookImporter.apply(scope: scope, records: snapshot.records, assets: snapshot.assets, container: target)
        try shadows.write(scope: scope, acknowledged: snapshot.records)
        let context = ModelContext(target)
        let expense = try #require(context.fetch(FetchDescriptor<FinanceCore.Transaction>()).first)
        expense.amount = 30; try context.save()
        let database = SyncDatabase()
        let zone = CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName)
        for var value in snapshot.records {
            if value.id.kind == .transaction { value.fields["amount"] = .decimal(40) }
            let record = try SharedBookCloudCodec.encode(value, zoneID: zone); database.records[record.recordID] = record
        }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: shadows, configuration: { (target, 1, true) })
        guard case let .needsReview(conflicts, _) = try await coordinator.synchronize(scope: scope, role: .participant) else { Issue.record("Expected review"); return }
        #expect(conflicts.count == 1 && conflicts.first?.reason == .fields(["amount"]))
        #expect(try ModelContext(target).fetch(FetchDescriptor<FinanceCore.Transaction>()).first?.amount == 30)
        #expect(try shadows.read(scope: scope) == snapshot.records)
        #expect(database.saves == 0)
        let decision = SharedBookDecision(expected: try #require(conflicts.first), side: .remote)
        guard case .synchronized = try await coordinator.synchronize(scope: scope, role: .participant, decisions: [decision]) else {
            Issue.record("Expected resolved synchronization"); return
        }
        #expect(try ModelContext(target).fetch(FetchDescriptor<FinanceCore.Transaction>()).first?.amount == 40)
        #expect(try shadows.read(scope: scope)?.first { $0.id.kind == .transaction }?.fields["amount"] == .decimal(40))
        #expect(database.saves == 0) // Choosing the server version needs no upload.
    }

    @Test func conflictDecisionPreservesIndependentEditsAndRejectsStaleVersions() throws {
        let bookID = UUID()
        let root = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .book, entityID: bookID.uuidString.lowercased()))
        let base = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .transaction, entityID: UUID().uuidString.lowercased()),
                                    fields: ["amount": .decimal(20), "book": .reference(root.id)])
        var local = base, remote = base
        local.fields["amount"] = .decimal(30)
        remote.fields["amount"] = .decimal(40)
        remote.fields["notes"] = .text("Nota dell’altra persona")
        let first = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root, base], local: [root, local], remote: [root, remote], localAssets: [:], remoteAssets: [:])
        let decision = SharedBookDecision(expected: try #require(first.conflicts.first), side: .local)
        let resolved = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root, base], local: [root, local], remote: [root, remote], localAssets: [:], remoteAssets: [:], decisions: [decision])
        #expect(resolved.canApply)
        #expect(resolved.uploads.first?.fields["amount"] == .decimal(30))
        #expect(resolved.uploads.first?.fields["notes"] == remote.fields["notes"])
        remote.fields["amount"] = .decimal(50)
        let stale = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root, base], local: [root, local], remote: [root, remote], localAssets: [:], remoteAssets: [:], decisions: [decision])
        #expect(!stale.canApply && stale.conflicts.count == 1 && stale.uploads.isEmpty)
    }

    @Test func choosingDeletionCannotSilentlyDeleteANewDependentRecord() throws {
        let bookID = UUID()
        let root = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .book, entityID: bookID.uuidString.lowercased()), fields: ["name": .text("Prima")])
        var remote = root; remote.fields["name"] = .text("Dopo")
        let child = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .conto, entityID: UUID().uuidString.lowercased()), fields: ["book": .reference(root.id)])
        let first = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root], local: [], remote: [remote, child], localAssets: [:], remoteAssets: [:])
        let decision = SharedBookDecision(expected: try #require(first.conflicts.first), side: .local)
        let resolved = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root], local: [], remote: [remote, child], localAssets: [:], remoteAssets: [:], decisions: [decision])
        #expect(!resolved.canApply && resolved.unresolvedReferences == [root.id] && resolved.uploads.isEmpty)
    }

    @Test func parentDeletionAgainstNewChildBlocksEntireGraph() throws {
        let bookID = UUID()
        let root = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .book, entityID: bookID.uuidString.lowercased()))
        let child = SharedBookRecord(id: SharedRecordID(bookID: bookID, kind: .conto, entityID: UUID().uuidString.lowercased()), fields: ["book": .reference(root.id)])
        let plan = try SharedBookReconciliation.reconcile(bookID: bookID, base: [root], local: [], remote: [root, child], localAssets: [:], remoteAssets: [:])
        #expect(!plan.canApply && plan.uploads.isEmpty)
        #expect(plan.unresolvedReferences == [root.id])
        #expect(throws: (any Error).self) { try SharedBookReconciliation.reconcile(bookID: bookID, base: [root], local: [root], remote: [], localAssets: [:], remoteAssets: [:]) }
    }

    @Test func checkpointSurvivesReopenAndCorruptionIsNotTreatedAsFirstSync() throws {
        let (scope, snapshot) = try fixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try SharedBookShadowStore(directory: folder).write(scope: scope, acknowledged: snapshot.records)
        #expect(try SharedBookShadowStore(directory: folder).read(scope: scope) == snapshot.records)
        try Data([0, 1, 2]).write(to: folder.appendingPathComponent(scope.key + ".json"))
        #expect(throws: (any Error).self) { try SharedBookShadowStore(directory: folder).read(scope: scope) }
    }

    @Test func ownerPreparationUploadsBeforeShareAndRetryRecoversUnknownUploadOutcome() async throws {
        enum Simulated: Error { case lostAcknowledgement }
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Libro del proprietario", currency: "EUR")
        target.mainContext.insert(book); try target.mainContext.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = SyncDatabase()
        database.afterSave = { throw Simulated.lostAcknowledgement }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let coordinator = SharedBookSyncCoordinator(transport: transport, shadows: SharedBookShadowStore(directory: folder), configuration: { (target, 1, true) })
        await #expect(throws: Simulated.self) { try await coordinator.prepareOwnerShare(bookID: book.id) }
        #expect(database.events == ["identity", "zone", "fetch", "save"])
        database.afterSave = {}
        guard case let .ready(scope, share) = try await coordinator.prepareOwnerShare(bookID: book.id) else { Issue.record("Expected sharing sheet data"); return }
        #expect(scope.bookID == book.id && scope.ownerName == "synthetic-owner")
        #expect(share.publicPermission == .none)
        #expect(database.events.last == "share" && database.saves == 1)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<SharedBookMembership>()) == 1)
    }
}
