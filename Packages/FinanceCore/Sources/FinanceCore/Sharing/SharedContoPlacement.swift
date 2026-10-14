import Foundation
import SwiftData

@MainActor
public enum SharedContoPlacement {
    public enum Failure: Error { case invalidMembership, incompatibleBook, categoriesInUse, invalidName }
    public enum Destination: Sendable { case existing(UUID), newBook(name: String) }

    /// Changes local organization only; the shared conto and movement IDs stay stable.
    public static func move(scope: SharedBookScope, to bookID: UUID, container: ModelContainer) throws {
        let context = container.mainContext
        try context.save()
        do {
            _ = try relocate(scope: scope, to: bookID, context: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }

    /// Completes the invitation locally in one save, including any new book.
    @discardableResult
    public static func completeAcceptance(scope: SharedBookScope, destination: Destination, container: ModelContainer) throws -> UUID {
        let context = container.mainContext
        try context.save()
        do {
            let key = scope.key
            guard let member = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key })).first,
                  !member.isOwner, let contoID = member.localContoID,
                  let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
                  let source = conto.account else { throw Failure.invalidMembership }
            let root = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased())
            let identityScope = member.importNamespace.map { SharedBookScope(ownerName: scope.ownerName, bookID: $0, isContoShare: true) } ?? scope
            let receptionBook = source.id == identityScope.isolatedID(for: root) && source.name == conto.name
            let targetID: UUID
            switch destination {
            case let .existing(id): targetID = id
            case let .newBook(name):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count <= 100 else { throw Failure.invalidName }
                let target = Account(name: trimmed, currency: source.currency ?? "EUR")
                context.insert(target); targetID = target.id
            }
            let previous = try relocate(scope: scope, to: targetID, context: context)
            context.processPendingChanges()
            if receptionBook, previous.id != targetID,
               (previous.conti ?? []).isEmpty, (previous.categories ?? []).isEmpty,
               (previous.budgets ?? []).isEmpty, (previous.savingsGoals ?? []).isEmpty {
                let previousID = previous.id
                let remaining = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.localBookID == previousID }))
                if remaining.isEmpty { context.delete(previous) }
            }
            try context.save()
            return targetID
        } catch { context.rollback(); throw error }
    }

    private static func relocate(scope: SharedBookScope, to bookID: UUID, context: ModelContext) throws -> Account {
        let key = scope.key
        let members = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
        guard members.count == 1, let member = members.first, !member.isOwner, let contoID = member.localContoID,
              let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
              let source = conto.account,
              let target = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == bookID })).first else { throw Failure.invalidMembership }
        if source.id == target.id { return source }
        let others = try context.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.localBookID == bookID }))
        guard target.isActive == true, target.currency == source.currency,
              others.allSatisfy({ $0.localContoID != nil }) else { throw Failure.incompatibleBook }
        let links = try context.fetch(FetchDescriptor<SharedBookRecordLink>(predicate: #Predicate { $0.scopeKey == key }))
        let categoryIDs = Set(links.filter { $0.remoteRecordName.hasPrefix("category:") }.compactMap { UUID(uuidString: $0.localIdentity) })
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        guard transactions.allSatisfy({ transaction in
            guard let id = transaction.categoryId ?? transaction.category?.id, categoryIDs.contains(id) else { return true }
            return transaction.fromConto?.id == contoID || transaction.toConto?.id == contoID
        }) else { throw Failure.categoriesInUse }
        conto.account = target
        for category in source.categories ?? [] where categoryIDs.contains(category.id) { category.account = target }
        let rootName = SharedRecordID(bookID: scope.bookID, kind: .book, entityID: scope.bookID.uuidString.lowercased()).recordName
        guard let rootLink = links.first(where: { $0.remoteRecordName == rootName }) else { throw Failure.invalidMembership }
        rootLink.localIdentity = target.id.uuidString.lowercased()
        member.localBookID = target.id
        return source
    }
}
