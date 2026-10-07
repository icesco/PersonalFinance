import Foundation
import SwiftData

/// Synchronous settings edits restore only their own changes when persistence fails.
/// Other drafts in the shared UI context must not be rolled back.
@MainActor
public struct SettingsEdits {
    public enum Failure: Error { case invalidName, invalidSelection, invalidParent }
    private let context: ModelContext
    private let save: () throws -> Void

    public init(context: ModelContext) {
        self.init(context: context, save: { try context.save() })
    }

    init(context: ModelContext, save: @escaping () throws -> Void) {
        self.context = context
        self.save = save
    }

    /// Archiving a macro category also archives its subcategories, so none are left without a parent.
    public func archiveCategories(_ visible: [Category], at offsets: IndexSet) throws {
        guard offsets.allSatisfy({ visible.indices.contains($0) }) else { throw Failure.invalidSelection }
        let selected = offsets.map { visible[$0] }
        let selectedIDs = Set(selected.map(\.id))
        let candidates: [Category] = selected.flatMap { $0.account?.categories ?? [] }
        let children = candidates.filter { candidate in
            guard candidate.isActive == true, let parentID = candidate.parentCategoryId else { return false }
            return selectedIDs.contains(parentID) && !selectedIDs.contains(candidate.id)
        }
        var seen = Set<UUID>()
        try archive((selected + children).filter { seen.insert($0.id).inserted }, active: \.isActive)
    }

    public func archiveConti(_ visible: [Conto], at offsets: IndexSet) throws {
        guard offsets.allSatisfy({ visible.indices.contains($0) }) else { throw Failure.invalidSelection }
        // Resolve every index before mutating the collection's filter inputs.
        try archive(offsets.map { visible[$0] }, active: \.isActive)
    }

    private func archive<Model: AnyObject>(_ selected: [Model], active: ReferenceWritableKeyPath<Model, Bool?>) throws {
        guard !selected.isEmpty else { return }
        let previous = selected.map { ($0, $0[keyPath: active]) }
        for model in selected { model[keyPath: active] = false }
        do { try save() }
        catch {
            for (model, value) in previous { model[keyPath: active] = value }
            throw error
        }
    }

    /// A subcategory takes its macro category's kind; `kind` applies to macro categories only.
    @discardableResult
    public func createCategory(name: String, color: String, icon: String,
                               parentID: UUID?, kind: CategoryKind? = nil, account: Account) throws -> Category {
        let name = try validName(name)
        let parent = try validParent(parentID, for: nil, in: account)
        let category = Category(name: name, color: color, icon: icon, parentCategoryId: parentID,
                                kind: parent.map(\.kind) ?? kind)
        category.account = account
        context.insert(category)
        do { try save(); return category }
        catch {
            category.account = nil
            context.delete(category)
            throw error
        }
    }

    public func updateCategory(_ category: Category, name: String, color: String, icon: String) throws {
        try updateCategory(category, name: name, color: color, icon: icon,
                           parentID: category.parentCategoryId, kind: category.kind)
    }

    /// Moves the category under `parentID` (or makes it a macro category with `nil`).
    /// A macro category with subcategories cannot become a subcategory; its kind is passed on to them.
    public func updateCategory(_ category: Category, name: String, color: String, icon: String,
                               parentID: UUID?, kind: CategoryKind?) throws {
        let name = try validName(name)
        guard let account = category.account else { throw Failure.invalidParent }
        let parent = try validParent(parentID, for: category, in: account)
        let children = (account.categories ?? []).filter { $0.parentCategoryId == category.id }
        if parent != nil, children.contains(where: { $0.isActive == true }) { throw Failure.invalidParent }
        let kind = parent.map(\.kind) ?? kind
        let previous = (category.name, category.icon, category.color, category.parentCategoryId, category.kindRaw, category.updatedAt)
        let previousChildren = children.map { ($0, $0.kindRaw) }
        category.name = name
        category.icon = icon
        category.color = color
        category.parentCategoryId = parentID
        category.kind = kind
        category.updatedAt = Date()
        for child in children { child.kind = kind }
        do { try save() }
        catch {
            (category.name, category.icon, category.color, category.parentCategoryId, category.kindRaw, category.updatedAt) = previous
            for (child, kind) in previousChildren { child.kindRaw = kind }
            throw error
        }
    }

    private func validParent(_ parentID: UUID?, for category: Category?, in account: Account) throws -> Category? {
        guard let parentID else { return nil }
        guard parentID != category?.id, let parent = account.categories?.first(where: {
            $0.id == parentID && $0.isActive == true && $0.parentCategoryId == nil
        }) else { throw Failure.invalidParent }
        return parent
    }

    private func validName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.invalidName }
        return name
    }
}
