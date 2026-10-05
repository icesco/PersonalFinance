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

    public func archiveCategories(_ visible: [Category], at offsets: IndexSet) throws {
        try archive(visible, at: offsets, active: \.isActive)
    }

    public func archiveConti(_ visible: [Conto], at offsets: IndexSet) throws {
        try archive(visible, at: offsets, active: \.isActive)
    }

    private func archive<Model: AnyObject>(_ visible: [Model], at offsets: IndexSet,
                                          active: ReferenceWritableKeyPath<Model, Bool?>) throws {
        guard offsets.allSatisfy({ visible.indices.contains($0) }) else { throw Failure.invalidSelection }
        guard !offsets.isEmpty else { return }
        // Resolve every index before mutating the collection's filter inputs.
        let selected = offsets.map { visible[$0] }
        let previous = selected.map { ($0, $0[keyPath: active]) }
        for model in selected { model[keyPath: active] = false }
        do { try save() }
        catch {
            for (model, value) in previous { model[keyPath: active] = value }
            throw error
        }
    }

    @discardableResult
    public func createCategory(name: String, color: String, icon: String,
                               parentID: UUID?, account: Account) throws -> Category {
        let name = try validName(name)
        if let parentID {
            guard account.categories?.contains(where: {
                $0.id == parentID && $0.isActive == true && $0.parentCategoryId == nil
            }) == true else { throw Failure.invalidParent }
        }
        let category = Category(name: name, color: color, icon: icon, parentCategoryId: parentID)
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
        let name = try validName(name)
        let previous = (category.name, category.icon, category.color, category.updatedAt)
        category.name = name
        category.icon = icon
        category.color = color
        category.updatedAt = Date()
        do { try save() }
        catch {
            (category.name, category.icon, category.color, category.updatedAt) = previous
            throw error
        }
    }

    private func validName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.invalidName }
        return name
    }
}
