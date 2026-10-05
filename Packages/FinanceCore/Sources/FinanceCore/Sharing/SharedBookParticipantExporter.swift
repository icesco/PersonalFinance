import Foundation
import SwiftData

/// Converts a participant's isolated local graph back into the owner's record
/// namespace. Persist mappings before any upload so retries retain identity.
@MainActor
public enum SharedBookParticipantExporter {
    public enum Failure: Error { case missingMembership, invalidMapping, missingReference }

    public static func export(scope: SharedBookScope, container: ModelContainer) throws -> SharedBookExport {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let key = scope.key
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
            guard let membership = memberships.first,
                  memberships.allSatisfy({ $0.localBookID == membership.localBookID && $0.ownerName == scope.ownerName && $0.remoteBookID == scope.bookID }) else {
                throw Failure.missingMembership
            }
            let snapshot = try SharedBookExporter.export(bookID: membership.localBookID, container: container)
            let links = try context.fetch(FetchDescriptor<SharedBookRecordLink>(predicate: #Predicate { $0.scopeKey == key }))
            var localToRemote: [SharedRecordID: SharedRecordID] = [:]
            var remoteToLocal: [SharedRecordID: SharedRecordID] = [:]
            func register(local: SharedRecordID, remote: SharedRecordID, persist: Bool) throws {
                guard local.kind == remote.kind,
                      localToRemote[local] == nil || localToRemote[local] == remote,
                      remoteToLocal[remote] == nil || remoteToLocal[remote] == local else { throw Failure.invalidMapping }
                if localToRemote[local] == nil, persist {
                    context.insert(SharedBookRecordLink(scopeKey: key, remoteRecordName: remote.recordName, localIdentity: local.entityID))
                }
                localToRemote[local] = remote
                remoteToLocal[remote] = local
            }
            for link in links {
                guard let separator = link.remoteRecordName.firstIndex(of: ":"),
                      let kind = SharedRecordID.Kind(rawValue: String(link.remoteRecordName[..<separator])) else { throw Failure.invalidMapping }
                let entity = String(link.remoteRecordName[link.remoteRecordName.index(after: separator)...])
                if kind != .recurrence {
                    guard let remoteUUID = UUID(uuidString: entity), remoteUUID.uuidString.lowercased() == entity,
                          let localUUID = UUID(uuidString: link.localIdentity), localUUID.uuidString.lowercased() == link.localIdentity else { throw Failure.invalidMapping }
                }
                let local = SharedRecordID(bookID: snapshot.bookID, kind: kind, entityID: link.localIdentity)
                let remote = SharedRecordID(bookID: scope.bookID, kind: kind, entityID: entity)
                try register(local: local, remote: remote, persist: false)
            }
            let localRoot = SharedRecordID(bookID: snapshot.bookID, kind: .book, entityID: snapshot.bookID.uuidString.lowercased())
            let remoteRoot = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
            try register(local: localRoot, remote: remoteRoot, persist: true)
            for record in snapshot.records where record.id.kind != .recurrence && localToRemote[record.id] == nil {
                // A locally created UUID is also a stable remote identity. Existing
                // aliases, including tombstones, reserve their remote names.
                let remote = SharedRecordID(bookID: scope.bookID, kind: record.id.kind, entityID: record.id.entityID)
                try register(local: record.id, remote: remote, persist: true)
            }
            func mapped(_ reference: SharedRecordID) throws -> SharedRecordID {
                guard let value = localToRemote[reference] else { throw Failure.missingReference }
                return value
            }
            for record in snapshot.records where record.id.kind == .recurrence {
                guard let source = try record.reference("source", kind: .transaction),
                      let scheduled = try record.date("scheduledDate"),
                      let sourceID = UUID(uuidString: try mapped(source).entityID) else { throw Failure.invalidMapping }
                let remote = SharedRecordID(bookID: scope.bookID, kind: .recurrence,
                                            entityID: RecurrenceResolution.key(sourceID: sourceID, date: scheduled))
                try register(local: record.id, remote: remote, persist: true)
            }
            var records: [SharedBookRecord] = []
            for record in snapshot.records {
                var fields: [String: SharedValue] = [:]
                for (name, value) in record.fields {
                    switch value {
                    case let .reference(reference): fields[name] = .reference(try mapped(reference))
                    case let .references(references):
                        fields[name] = .references(try references.map(mapped).sorted { $0.recordName < $1.recordName })
                    default: fields[name] = value
                    }
                }
                records.append(SharedBookRecord(id: try mapped(record.id), fields: fields))
            }
            var assets: [SharedRecordID: Data] = [:]
            for (id, bytes) in snapshot.assets { assets[try mapped(id)] = bytes }
            try context.save()
            return SharedBookExport(bookID: scope.bookID, records: records.sorted { $0.id.recordName < $1.id.recordName }, assets: assets)
        } catch {
            context.rollback()
            throw error
        }
    }
}
