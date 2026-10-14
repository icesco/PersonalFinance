import Foundation
import SwiftData

/// Call only after withdrawal or owner revocation has been acknowledged by CloudKit.
/// The financial graph keeps every identity, relationship, attachment and edit.
@MainActor
enum SharedBookDepartureService {
    static func preservePrivateCopy(scope: SharedBookScope, container: ModelContainer, owner: Bool = false) throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let key = scope.key
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
            if owner && memberships.isEmpty {
                let departures = try context.fetch(FetchDescriptor<SharedBookDeparture>(predicate: #Predicate { $0.scopeKey == key }))
                if let departure = departures.last {
                    let bookID = departure.localBookID
                    if try context.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.id == bookID })) == 1 { return bookID }
                }
            }
            guard let first = memberships.first, memberships.allSatisfy({
                $0.isOwner == owner && $0.localBookID == first.localBookID && $0.ownerName == scope.ownerName && $0.remoteBookID == scope.bookID
            }) else { throw SharedBookSyncCoordinator.Failure.missingLocalIdentity }
            let localID = first.localBookID
            guard try context.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.id == localID })) == 1 else {
                throw SharedBookSyncCoordinator.Failure.missingLocalIdentity
            }
            if let contoID = first.localContoID {
                for conto in try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })) { conto.usesSharedCategories = false }
                for category in try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.sharedContoID == contoID })) { category.sharedContoID = nil }
            }
            let links = try context.fetch(FetchDescriptor<SharedBookRecordLink>(predicate: #Predicate { $0.scopeKey == key }))
            let departure = SharedBookDeparture(scopeKey: key, localBookID: localID)
            if first.localContoID != nil {
                let identityScope = first.importNamespace.map { SharedBookScope(ownerName: scope.ownerName, bookID: $0, isContoShare: scope.isContoShare) } ?? scope
                let root = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
                departure.retiredNamespaceID = identityScope.isolatedID(for: root)
            }
            context.insert(departure)
            for value in links { context.delete(value) }
            for value in memberships { context.delete(value) }
            try context.save()
            return localID
        } catch { context.rollback(); throw error }
    }
}
