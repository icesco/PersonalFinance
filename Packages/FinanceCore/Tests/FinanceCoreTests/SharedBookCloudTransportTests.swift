import Foundation
import CloudKit
import Testing
@testable import FinanceCore

@MainActor
private final class FakeSharedCloudDatabase: SharedCloudDatabase {
    var leaveIDs: [CKRecord.ID] = []
    var onLeave: (CKRecord.ID) async throws -> CKRecord.ID = { $0 }
    func leaveShare(_ id: CKRecord.ID) async throws -> CKRecord.ID {
        leaveIDs.append(id); return try await onLeave(id)
    }
    var pageCalls = 0
    var saveCalls = 0
    var onPage: () async throws -> SharedCloudPage = { SharedCloudPage(records: [], deleted: [], token: nil, moreComing: false) }
    var onSave: ([CKRecord]) async throws -> [CKRecord] = { $0 }
    func page(zone: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> SharedCloudPage {
        pageCalls += 1; return try await onPage()
    }
    func save(_ records: [CKRecord]) async throws -> [CKRecord] {
        saveCalls += 1; return try await onSave(records)
    }
}

@MainActor
struct SharedBookCloudTransportTests {
    private let scope = SharedBookScope(ownerName: "synthetic-owner", bookID: UUID())
    private func record() -> SharedBookRecord {
        SharedBookRecord(id: SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased()), fields: ["name": .text("Demo")])
    }
    private var zone: CKRecordZone.ID { CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID), ownerName: scope.ownerName) }

    @Test func leavingUsesOnlyParticipantShareAndRejectsWrongAcknowledgement() async throws {
        let database = FakeSharedCloudDatabase()
        var roles: [SharedBookCloudTransport.Role] = []
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { roles.append($0); return database })
        try await transport.leaveParticipantShare(scope: scope)
        let expected = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        #expect(database.leaveIDs == [expected])
        #expect(roles.count == 1 && roles[0] == .participant)
        #expect(database.saveCalls == 0 && database.pageCalls == 0)
        database.onLeave = { _ in CKRecord.ID(recordName: "wrong", zoneID: self.zone) }
        await #expect(throws: SharedBookCloudTransport.Failure.wrongZone) {
            try await transport.leaveParticipantShare(scope: scope)
        }
    }

    @Test func leavingDisabledOrInvalidOwnerNeverConstructsDatabase() async throws {
        var factories = 0
        var enabled = false
        let transport = SharedBookCloudTransport(configuration: { (enabled, 1) }, makeDatabase: { _ in factories += 1; return FakeSharedCloudDatabase() })
        await #expect(throws: (any Error).self) { try await transport.leaveParticipantShare(scope: scope) }
        enabled = true
        let invalid = SharedBookScope(ownerName: CKCurrentUserDefaultName, bookID: scope.bookID)
        await #expect(throws: (any Error).self) { try await transport.leaveParticipantShare(scope: invalid) }
        #expect(factories == 0)
    }

    @Test func leavingRejectsLateAcknowledgementAndPropagatesNetworkFailure() async throws {
        var generation = 1
        let database = FakeSharedCloudDatabase()
        var pending: CheckedContinuation<CKRecord.ID, Never>?
        database.onLeave = { _ in await withCheckedContinuation { pending = $0 } }
        let transport = SharedBookCloudTransport(configuration: { (true, generation) }, makeDatabase: { _ in database })
        let operation = Task { try await transport.leaveParticipantShare(scope: scope) }
        while pending == nil { await Task.yield() }
        generation += 1
        pending?.resume(returning: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone))
        await #expect(throws: (any Error).self) { try await operation.value }
        database.onLeave = { _ in throw CKError(.networkUnavailable) }
        await #expect(throws: CKError.self) { try await transport.leaveParticipantShare(scope: scope) }
        #expect(database.leaveIDs.count == 2)
    }

    @Test func disabledNeverConstructsCloudDatabaseForFetchOrUpload() async throws {
        var factories = 0
        let transport = SharedBookCloudTransport(configuration: { (false, 1) }, makeDatabase: { _ in factories += 1; return FakeSharedCloudDatabase() })
        await #expect(throws: (any Error).self) { try await transport.fetch(scope: scope, role: .participant) }
        await #expect(throws: (any Error).self) { try await transport.upload(scope: scope, role: .participant, changes: [record()], assets: [:], serverRecords: [:]) }
        #expect(factories == 0)
    }

    @Test func configurationChangeRejectsLatePageEvenAfterReenable() async throws {
        var generation = 1
        var pending: CheckedContinuation<SharedCloudPage, Never>?
        let database = FakeSharedCloudDatabase()
        database.onPage = { await withCheckedContinuation { pending = $0 } }
        let transport = SharedBookCloudTransport(configuration: { (true, generation) }, makeDatabase: { _ in database })
        let operation = Task { try await transport.fetch(scope: scope, role: .participant) }
        while pending == nil { await Task.yield() }
        generation = 3
        pending?.resume(returning: SharedCloudPage(records: [], deleted: [], token: nil, moreComing: false))
        await #expect(throws: (any Error).self) { try await operation.value }
        #expect(database.pageCalls == 1)
    }

    @Test func cancellationReachesInFlightTask() async throws {
        let database = FakeSharedCloudDatabase()
        var cancellationObserved = false
        database.onPage = {
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancellationObserved = Task.isCancelled; throw error }
            return SharedCloudPage(records: [], deleted: [], token: nil, moreComing: false)
        }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let operation = Task { try await transport.fetch(scope: scope, role: .participant) }
        while database.pageCalls == 0 { await Task.yield() }
        transport.cancelPendingRequests()
        await #expect(throws: (any Error).self) { try await operation.value }
        #expect(cancellationObserved)
    }

    @Test func downloadsDecodedRecordsAndRejectsPhysicalDeletion() async throws {
        let database = FakeSharedCloudDatabase()
        let cloud = try SharedBookCloudCodec.encode(record(), zoneID: zone)
        database.onPage = { SharedCloudPage(records: [cloud], deleted: [], token: nil, moreComing: false) }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let result = try await transport.fetch(scope: scope, role: .participant)
        #expect(result.records == [record()])
        database.onPage = { SharedCloudPage(records: [], deleted: [cloud.recordID], token: nil, moreComing: false) }
        await #expect(throws: (any Error).self) { try await transport.fetch(scope: scope, role: .participant) }
    }

    @Test func uploadDoesNotMutateBaselineAndStopsAfterConfigurationChange() async throws {
        let database = FakeSharedCloudDatabase()
        var enabled = true
        let transport = SharedBookCloudTransport(configuration: { (enabled, 1) }, makeDatabase: { _ in database })
        let baseline = record()
        let cloud = try SharedBookCloudCodec.encode(baseline, zoneID: zone)
        var edited = baseline; edited.fields["name"] = .text("Modificato")
        let saved = try await transport.upload(scope: scope, role: .participant, changes: [edited], assets: [:], serverRecords: [baseline.id: cloud])
        #expect(try SharedBookCloudCodec.decode(saved[0], expectedBookID: scope.bookID) == edited)
        #expect(try SharedBookCloudCodec.decode(cloud, expectedBookID: scope.bookID) == baseline)
        var changes: [SharedBookRecord] = []
        for _ in 0..<201 {
            changes.append(SharedBookRecord(id: SharedRecordID(bookID: scope.bookID, kind: .category, entityID: UUID().uuidString.lowercased())))
        }
        database.onSave = { records in enabled = false; return records }
        await #expect(throws: (any Error).self) { try await transport.upload(scope: scope, role: .participant, changes: changes, assets: [:], serverRecords: [:]) }
        #expect(database.saveCalls == 2) // First edit + first batch only.
    }

    @Test func conflictIsPropagatedWithoutOverwriteRetry() async throws {
        let database = FakeSharedCloudDatabase()
        database.onSave = { _ in throw CKError(.serverRecordChanged) }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        await #expect(throws: CKError.self) { try await transport.upload(scope: scope, role: .participant, changes: [record()], assets: [:], serverRecords: [:]) }
        #expect(database.saveCalls == 1)
    }

    @Test func cancellationDiscardsResponseFromNonCooperativeBackend() async throws {
        let database = FakeSharedCloudDatabase()
        var pending: CheckedContinuation<SharedCloudPage, Never>?
        database.onPage = { await withCheckedContinuation { pending = $0 } }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        let operation = Task { try await transport.fetch(scope: scope, role: .participant) }
        while pending == nil { await Task.yield() }
        transport.cancelPendingRequests()
        pending?.resume(returning: SharedCloudPage(records: [], deleted: [], token: nil, moreComing: false))
        await #expect(throws: CancellationError.self) { try await operation.value }
    }

    @Test func incompletePagesAndUploadAcknowledgementsFailClosed() async throws {
        let database = FakeSharedCloudDatabase()
        database.onPage = { SharedCloudPage(records: [], deleted: [], token: nil, moreComing: true) }
        let transport = SharedBookCloudTransport(configuration: { (true, 1) }, makeDatabase: { _ in database })
        await #expect(throws: (any Error).self) { try await transport.fetch(scope: scope, role: .participant) }
        #expect(database.pageCalls == 1)
        database.onSave = { _ in [] }
        await #expect(throws: (any Error).self) { try await transport.upload(scope: scope, role: .participant, changes: [record()], assets: [:], serverRecords: [:]) }
        #expect(database.saveCalls == 1)
    }
}
