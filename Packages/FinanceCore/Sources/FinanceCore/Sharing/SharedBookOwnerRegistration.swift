import Foundation
import SwiftData
import CloudKit

/// Registers an existing book for the owner's custom CloudKit zone. This only
/// writes local identity metadata; it neither creates a share nor uploads data.
@MainActor
public enum SharedBookOwnerRegistration {
    public enum Failure: Error { case invalidOwner, alreadyRegistered, invalidMapping }
    public static func register(bookID: UUID, ownerRecordName: String, container: ModelContainer) throws -> SharedBookScope {
        guard !ownerRecordName.isEmpty, ownerRecordName != CKCurrentUserDefaultName,
              ownerRecordName.utf8.count <= 255, !ownerRecordName.contains("\u{0}") else { throw Failure.invalidOwner }
        let scope = SharedBookScope(ownerName: ownerRecordName, bookID: bookID)
        let snapshot = try SharedBookExporter.export(bookID: bookID, container: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.localBookID == bookID }))
            guard memberships.allSatisfy({ $0.scopeKey == scope.key && $0.ownerName == ownerRecordName && $0.remoteBookID == bookID && $0.isOwner }) else {
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
            for record in snapshot.records {
                if let identity = existing[record.id.recordName] {
                    guard identity == record.id.entityID else { throw Failure.invalidMapping }
                } else {
                    context.insert(SharedBookRecordLink(scopeKey: key, remoteRecordName: record.id.recordName, localIdentity: record.id.entityID))
                }
            }
            if memberships.isEmpty {
                context.insert(SharedBookMembership(scopeKey: key, ownerName: ownerRecordName, remoteBookID: bookID, localBookID: bookID, isOwner: true))
            }
            try context.save()
            return scope
        } catch { context.rollback(); throw error }
    }
}
