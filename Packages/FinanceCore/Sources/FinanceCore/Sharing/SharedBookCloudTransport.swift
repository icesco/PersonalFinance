import Foundation
import CloudKit

struct SharedCloudPage: Sendable {
    var records: [CKRecord]
    var deleted: [CKRecord.ID]
    var token: CKServerChangeToken?
    var moreComing: Bool
}

@MainActor
protocol SharedCloudDatabase {
    func page(zone: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> SharedCloudPage
    func save(_ records: [CKRecord]) async throws -> [CKRecord]
    func ownerRecordName() async throws -> String
    func ensureZone(_ zone: CKRecordZone.ID) async throws
    func share(zone: CKRecordZone.ID, title: String) async throws -> CKShare
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare
    func leaveShare(_ id: CKRecord.ID) async throws -> CKRecord.ID
}

extension SharedCloudDatabase {
    func leaveShare(_ id: CKRecord.ID) async throws -> CKRecord.ID { throw SharedBookCloudTransport.Failure.unsupportedOperation }
    func ownerRecordName() async throws -> String { throw SharedBookCloudTransport.Failure.unsupportedOperation }
    func ensureZone(_ zone: CKRecordZone.ID) async throws { throw SharedBookCloudTransport.Failure.unsupportedOperation }
    func share(zone: CKRecordZone.ID, title: String) async throws -> CKShare { throw SharedBookCloudTransport.Failure.unsupportedOperation }
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare { throw SharedBookCloudTransport.Failure.unsupportedOperation }
}

@MainActor
private final class AppleSharedCloudDatabase: SharedCloudDatabase {
    let container: CKContainer
    let database: CKDatabase
    init(role: SharedBookCloudTransport.Role) {
        container = CKContainer(identifier: FinanceCoreModule.cloudKitContainerIdentifier)
        database = role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }
    func ownerRecordName() async throws -> String { try await container.userRecordID().recordName }
    func accept(_ metadata: CKShare.Metadata) async throws -> CKShare { try await container.accept(metadata) }
    func leaveShare(_ id: CKRecord.ID) async throws -> CKRecord.ID {
        // Deleting CKShare from the participant's shared database removes only
        // that participant. Never delete the owner's zone or application records.
        guard database.databaseScope == .shared, id.recordName == CKRecordNameZoneWideShare else {
            throw SharedBookCloudTransport.Failure.unsupportedOperation
        }
        do { return try await database.deleteRecord(withID: id) }
        catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // The first attempt may have succeeded before its response was lost,
            // or the owner may already have revoked access.
            return id
        }
    }
    func ensureZone(_ zone: CKRecordZone.ID) async throws {
        do { _ = try await database.recordZone(for: zone) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            try Task.checkCancellation()
            _ = try await database.save(CKRecordZone(zoneID: zone))
        }
    }
    func share(zone: CKRecordZone.ID, title: String) async throws -> CKShare {
        let fetched = try await database.recordZone(for: zone)
        try Task.checkCancellation()
        if let reference = fetched.share {
            guard let share = try await database.record(for: reference.recordID) as? CKShare else { throw SharedBookCloudTransport.Failure.incompleteResponse }
            return share
        }
        let share = CKShare(recordZoneID: zone)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        let result = try await save([share])
        guard let saved = result.first as? CKShare else { throw SharedBookCloudTransport.Failure.incompleteResponse }
        return saved
    }
    func page(zone: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> SharedCloudPage {
        let result = try await database.recordZoneChanges(inZoneWith: zone, since: token, resultsLimit: 200)
        let records = try result.modificationResultsByID.values.map { try $0.get().record }
        return SharedCloudPage(records: records, deleted: result.deletions.map(\.recordID), token: result.changeToken, moreComing: result.moreComing)
    }
    func save(_ records: [CKRecord]) async throws -> [CKRecord] {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        return try records.map { record in
            guard let saved = result.saveResults[record.recordID] else { throw SharedBookCloudTransport.Failure.incompleteResponse }
            return try saved.get()
        }
    }
}

/// Transport only: callers must reconcile local changes before uploading and
/// apply only complete fetched graphs. No CKContainer exists while disabled.
@MainActor
public final class SharedBookCloudTransport {
    public enum Role: Sendable { case owner, participant }
    public enum Failure: Error { case disabled, staleConfiguration, incompleteResponse, physicalDeletion, wrongZone, unsupportedOperation }
    public struct Snapshot: Sendable {
        public let records: [SharedBookRecord]
        public let assets: [SharedRecordID: Data]
        public let serverRecords: [SharedRecordID: CKRecord]
    }
    private let configuration: @MainActor () -> (enabled: Bool, generation: Int)
    private let makeDatabase: @MainActor (Role) -> any SharedCloudDatabase
    private var cancellations: [UUID: @MainActor () -> Void] = [:]

    public convenience init(configuration: @escaping @MainActor () -> (enabled: Bool, generation: Int)) {
        self.init(configuration: configuration, makeDatabase: { AppleSharedCloudDatabase(role: $0) })
    }
    init(configuration: @escaping @MainActor () -> (enabled: Bool, generation: Int),
         makeDatabase: @escaping @MainActor (Role) -> any SharedCloudDatabase) {
        self.configuration = configuration; self.makeDatabase = makeDatabase
    }
    public func cancelPendingRequests() {
        for cancel in cancellations.values { cancel() }
        cancellations.removeAll()
    }
    private func permit(_ generation: Int? = nil) throws -> Int {
        try Task.checkCancellation()
        let current = configuration()
        guard current.enabled else { throw Failure.disabled }
        guard generation == nil || generation == current.generation else { throw Failure.staleConfiguration }
        return current.generation
    }
    private func request<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        cancellations[id] = { task.cancel() }
        defer { cancellations.removeValue(forKey: id) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func zone(scope: SharedBookScope, role: Role) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SharedBookCloudCodec.zoneName(bookID: scope.bookID),
                        ownerName: role == .owner ? CKCurrentUserDefaultName : scope.ownerName)
    }

    public func ownerRecordName() async throws -> String {
        let generation = try permit()
        let database = makeDatabase(.owner)
        let name = try await request { try await database.ownerRecordName() }
        _ = try permit(generation)
        guard !name.isEmpty, name != CKCurrentUserDefaultName else { throw Failure.incompleteResponse }
        return name
    }

    public func acceptInvitation(_ metadata: CKShare.Metadata) async throws -> SharedBookScope {
        let generation = try permit()
        let scope = try SharedBookInvitation.scope(metadata: metadata)
        // Imported books currently expose editing throughout the app. Do not
        // import read-only data into that writable experience until its permission
        // policy is enforced across every editing entry point.
        guard metadata.participantPermission == .readWrite, metadata.participantRole != .owner else {
            throw SharedBookInvitation.Failure.unsupportedPermission
        }
        if metadata.participantStatus != .accepted {
            let database = makeDatabase(.participant)
            let accepted = try await request { try await database.accept(metadata) }
            _ = try permit(generation)
            guard accepted.recordID == metadata.share.recordID else { throw Failure.wrongZone }
        }
        return scope
    }

    /// Explicit participant withdrawal. Local data is deliberately untouched;
    /// the coordinator must preserve it until the server acknowledges departure.
    public func leaveParticipantShare(scope: SharedBookScope) async throws {
        let generation = try permit()
        let zoneID = zone(scope: scope, role: .participant)
        _ = try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier,
                                           zoneName: zoneID.zoneName, ownerName: zoneID.ownerName,
                                           shareRecordName: CKRecordNameZoneWideShare, hierarchical: false)
        let database = makeDatabase(.participant)
        let expected = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let removed = try await request { try await database.leaveShare(expected) }
        _ = try permit(generation)
        guard removed == expected else { throw Failure.wrongZone }
    }

    public func ensureOwnerZone(scope: SharedBookScope) async throws {
        let generation = try permit()
        let database = makeDatabase(.owner)
        let zoneID = zone(scope: scope, role: .owner)
        try await request { try await database.ensureZone(zoneID) }
        _ = try permit(generation)
    }

    /// Call only after the owner's book upload succeeds. Public link access is
    /// disabled; the system sharing UI controls the explicitly invited people.
    public func ownerShare(scope: SharedBookScope, title: String) async throws -> CKShare {
        let generation = try permit()
        let database = makeDatabase(.owner)
        let zoneID = zone(scope: scope, role: .owner)
        let share = try await request { try await database.share(zone: zoneID, title: title) }
        _ = try permit(generation)
        guard share.recordID.zoneID == zoneID else { throw Failure.wrongZone }
        return share
    }

    /// Fetch from the beginning; pagination is accumulated before exposing any
    /// graph. A later incremental implementation must retain a durable shadow.
    public func fetch(scope: SharedBookScope, role: Role) async throws -> Snapshot {
        let generation = try permit()
        let database = makeDatabase(role)
        let zoneID = zone(scope: scope, role: role)
        var token: CKServerChangeToken?
        var records: [SharedRecordID: SharedBookRecord] = [:]
        var assets: [SharedRecordID: Data] = [:]
        var serverRecords: [SharedRecordID: CKRecord] = [:]
        repeat {
            _ = try permit(generation)
            let pageToken = token
            let page = try await request { try await database.page(zone: zoneID, token: pageToken) }
            _ = try permit(generation)
            // Application deletions are explicit tombstones. Physical deletion
            // requires recovery, never inference that local edits can be erased.
            guard page.deleted.allSatisfy({ $0.recordName == CKRecordNameZoneWideShare }) else { throw Failure.physicalDeletion }
            for record in page.records {
                guard record.recordID.zoneID == zoneID else { throw Failure.wrongZone }
                if record is CKShare { continue }
                let value = try SharedBookCloudCodec.decode(record, expectedBookID: scope.bookID)
                records[value.id] = value; serverRecords[value.id] = record
                if value.id.kind == .attachment, !value.deleted {
                    guard let url = (record["file"] as? CKAsset)?.fileURL else { throw SharedBookCloudCodec.Failure.missingAsset }
                    assets[value.id] = try Data(contentsOf: url)
                } else { assets.removeValue(forKey: value.id) }
            }
            token = page.token
            if !page.moreComing { break }
            guard token != nil else { throw Failure.incompleteResponse }
        } while true
        return Snapshot(records: records.values.sorted { $0.id.recordName < $1.id.recordName }, assets: assets, serverRecords: serverRecords)
    }

    /// Changes are already reconciled against these exact server versions.
    /// Errors (including serverRecordChanged) are propagated for refetch/merge;
    /// never retry with an overwrite policy. Earlier batches may have succeeded.
    public func upload(scope: SharedBookScope, role: Role, changes: [SharedBookRecord], assets: [SharedRecordID: Data],
                       serverRecords: [SharedRecordID: CKRecord]) async throws -> [CKRecord] {
        let generation = try permit()
        guard !changes.isEmpty else { return [] }
        let zoneID = zone(scope: scope, role: role)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var encoded: [CKRecord] = []
        guard Set(changes.map(\.id)).count == changes.count else { throw SharedBookCloudCodec.Failure.invalidIdentity }
        for value in changes {
            guard value.id.bookID == scope.bookID else { throw SharedBookCloudCodec.Failure.wrongBook }
            var assetURL: URL?
            if value.id.kind == .attachment, !value.deleted {
                guard let bytes = assets[value.id] else { throw SharedBookCloudCodec.Failure.missingAsset }
                let url = directory.appendingPathComponent(UUID().uuidString)
                try bytes.write(to: url, options: [.atomic]); assetURL = url
            }
            // Copy system fields only: preserve the change tag without mutating
            // the downloaded baseline used by conflict reconciliation.
            let existing: CKRecord?
            if let original = serverRecords[value.id] {
                let archiver = NSKeyedArchiver(requiringSecureCoding: true)
                original.encodeSystemFields(with: archiver); archiver.finishEncoding()
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
                unarchiver.requiresSecureCoding = true
                existing = CKRecord(coder: unarchiver); unarchiver.finishDecoding()
                guard existing != nil else { throw Failure.incompleteResponse }
            } else { existing = nil }
            encoded.append(try SharedBookCloudCodec.encode(value, zoneID: zoneID, existing: existing, assetURL: assetURL))
        }
        _ = try permit(generation)
        let database = makeDatabase(role)
        var saved: [CKRecord] = []
        for start in stride(from: 0, to: encoded.count, by: 200) {
            _ = try permit(generation)
            let batch = Array(encoded[start..<min(start + 200, encoded.count)])
            let result = try await request { try await database.save(batch) }
            _ = try permit(generation)
            guard Set(result.map(\.recordID)) == Set(batch.map(\.recordID)), result.count == batch.count else { throw Failure.incompleteResponse }
            let expected = Dictionary(uniqueKeysWithValues: batch.map { ($0.recordID, $0) })
            guard result.allSatisfy({ record in
                record.recordType == SharedBookCloudCodec.recordType &&
                (record["payload"] as? Data) == (expected[record.recordID]?["payload"] as? Data)
            }) else { throw Failure.incompleteResponse }
            saved.append(contentsOf: result)
        }
        return saved
    }
}
