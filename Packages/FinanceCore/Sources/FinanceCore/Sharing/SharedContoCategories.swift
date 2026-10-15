import Foundation
import SwiftData

@MainActor
public enum SharedContoCategories {
    public enum Failure: Error { case invalidScope }

    public static func available(for conto: Conto?, in categories: [Category]) -> [Category] {
        guard let conto, let bookID = conto.account?.id else { return [] }
        let scopeID = conto.usesSharedCategories == true ? conto.id : nil
        return categories.filter { $0.account?.id == bookID && $0.sharedContoID == scopeID && $0.isActive == true }
    }

    nonisolated public static func permits(_ category: Category, for conto: Conto) -> Bool {
        category.account?.id == conto.account?.id && category.sharedContoID == (conto.usesSharedCategories == true ? conto.id : nil)
    }

    /// Reuses stable copy identities without overwriting independently edited copies.
    @discardableResult
    public static func copyPersonalCategories(contoID: UUID, categoryIDs: Set<UUID>, container: ModelContainer) throws -> Int {
        guard !categoryIDs.isEmpty else { throw Failure.invalidScope }
        try container.mainContext.save()
        return try copyCategories(contoID: contoID, selectedIDs: categoryIDs, container: container)
    }

    public static func personalCategories(in categories: [Category], memberships: [SharedBookMembership]) -> [Category] {
        let sharedBooks = Set(memberships.filter { $0.localContoID == nil }.map(\.localBookID))
        return categories.filter { $0.sharedContoID == nil && $0.isActive == true && $0.account?.isActive == true && $0.account.map { !sharedBooks.contains($0.id) } == true }
    }

    /// Copies only categories already used on this conto, leaving personal categories and budgets intact.
    public static func prepare(contoID: UUID, container: ModelContainer) throws {
        _ = try copyCategories(contoID: contoID, selectedIDs: nil, container: container)
    }

    private static func copyCategories(contoID: UUID, selectedIDs: Set<UUID>?, container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            guard let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
                  let book = conto.account else { throw Failure.invalidScope }
            let transactions = try context.fetch(FetchDescriptor<Transaction>()).filter {
                $0.type != .transfer && ($0.fromContoId == contoID || $0.toContoId == contoID || $0.fromConto?.id == contoID || $0.toConto?.id == contoID)
            }
            let categories = try context.fetch(FetchDescriptor<Category>())
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>())
            let eligibleIDs = Set(personalCategories(in: categories, memberships: memberships).map(\.id))
            if let selectedIDs {
                guard conto.usesSharedCategories == true, selectedIDs.isSubset(of: eligibleIDs) else { throw Failure.invalidScope }
            }
            var added = 0
            var copies = Dictionary(uniqueKeysWithValues: categories.filter { $0.sharedContoID == contoID }.map { ($0.id, $0) })
            let scope = SharedBookScope(ownerName: "local-category", bookID: contoID, isContoShare: true)
            var visiting: Set<UUID> = []
            func copy(_ original: Category) throws -> Category {
                if original.sharedContoID == contoID { return original }
                guard (selectedIDs == nil ? original.account?.id == book.id : eligibleIDs.contains(original.id)), original.sharedContoID == nil,
                      visiting.insert(original.id).inserted else { throw Failure.invalidScope }
                defer { visiting.remove(original.id) }
                let id = scope.isolatedID(for: SharedRecordID(bookID: contoID, kind: .category, entityID: original.id.uuidString.lowercased()))
                if let existing = copies[id] { return existing }
                guard !categories.contains(where: { $0.id == id }) else { throw Failure.invalidScope }
                let parent: Category?
                if let parentID = original.parentCategoryId {
                    guard let originalParent = categories.first(where: { $0.id == parentID }), originalParent.account?.id == original.account?.id else { throw Failure.invalidScope }
                    parent = try copy(originalParent)
                } else { parent = nil }
                let value = Category(name: original.name ?? "Categoria", color: original.color ?? CategoryPalette.fallback,
                    icon: original.icon ?? "tag", parentCategoryId: parent?.id, kind: original.kind)
                value.id = id; value.externalID = id.uuidString.lowercased()
                value.sharedContoID = contoID; value.account = book; value.isActive = original.isActive
                context.insert(value); copies[id] = value; added += 1
                return value
            }
            if let selectedIDs {
                for category in categories where selectedIDs.contains(category.id) { _ = try copy(category) }
            }
            for transaction in selectedIDs == nil ? transactions : [] {
                if let category = transaction.category ?? categories.first(where: { $0.id == transaction.categoryId }) {
                    let scoped = try copy(category)
                    if scoped.id != category.id { transaction.setCategory(scoped) }
                }
            }
            for budget in try context.fetch(FetchDescriptor<Budget>()) where budget.contoID == contoID && budget.account?.id == book.id {
                budget.categories = try (budget.categories ?? []).map(copy)
            }
            if conto.usesSharedCategories != true { conto.usesSharedCategories = true }
            try context.save()
            return added
        } catch { context.rollback(); throw error }
    }
}
