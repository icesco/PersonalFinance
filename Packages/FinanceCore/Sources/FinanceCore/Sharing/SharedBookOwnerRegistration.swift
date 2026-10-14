import Foundation
import SwiftData
import CloudKit

/// Registers the owner's local graph without creating a share or uploading data.
/// A single conto receives isolated category copies before its first export.
@MainActor
public enum SharedBookOwnerRegistration {
    public enum Failure: Error { case invalidOwner, alreadyRegistered, invalidMapping }
    public static func register(bookID: UUID, contoID: UUID? = nil, ownerRecordName: String, container: ModelContainer) throws -> SharedBookScope {
        guard !ownerRecordName.isEmpty, ownerRecordName != CKCurrentUserDefaultName,
              ownerRecordName.utf8.count <= 255, !ownerRecordName.contains("\u{0}") else { throw Failure.invalidOwner }
        let remoteID = contoID ?? bookID
        let scope = SharedBookScope(ownerName: ownerRecordName, bookID: remoteID, isContoShare: contoID != nil)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.localBookID == bookID }))
            guard memberships.allSatisfy({
                if $0.scopeKey == scope.key { return $0.ownerName == ownerRecordName && $0.remoteBookID == remoteID && $0.isOwner && $0.localContoID == contoID }
                return contoID != nil && $0.localContoID != nil && $0.localContoID != contoID
            }) else {
                throw Failure.alreadyRegistered
            }
            let key = scope.key
            let scopedMemberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
            guard scopedMemberships.allSatisfy({ $0.localBookID == bookID && $0.isOwner }) else { throw Failure.alreadyRegistered }
            let links = try context.fetch(FetchDescriptor<SharedBookRecordLink>(predicate: #Predicate { $0.scopeKey == key }))
            var existing: [String: String] = [:]
            for link in links {
                guard existing[link.remoteRecordName] == nil || existing[link.remoteRecordName] == link.localIdentity else { throw Failure.invalidMapping }
                existing[link.remoteRecordName] = link.localIdentity
            }
            if let contoID { try SharedContoCategories.prepare(contoID: contoID, container: container) }
            let snapshot = try SharedBookExporter.export(bookID: bookID, contoID: contoID, container: container)
            for original in snapshot.records {
                let record = original.id.kind == .book
                    ? SharedBookRecord(id: SharedRecordID(bookID: remoteID, kind: .book, entityID: remoteID.uuidString.lowercased())) : original
                let localIdentity = record.id.kind == .book ? bookID.uuidString.lowercased() : record.id.entityID
                if let identity = existing[record.id.recordName] {
                    guard identity == localIdentity else { throw Failure.invalidMapping }
                } else {
                    context.insert(SharedBookRecordLink(scopeKey: key, remoteRecordName: record.id.recordName, localIdentity: localIdentity))
                }
            }
            if scopedMemberships.isEmpty {
                let membership = SharedBookMembership(scopeKey: key, ownerName: ownerRecordName, remoteBookID: remoteID, localBookID: bookID, isOwner: true)
                membership.localContoID = contoID
                context.insert(membership)
            }
            try context.save()
            return scope
        } catch { context.rollback(); throw error }
    }
}
