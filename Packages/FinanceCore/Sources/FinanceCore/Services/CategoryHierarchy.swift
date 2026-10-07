import Foundation

/// Two-level category tree of one book: macro categories and their subcategories.
/// A subcategory whose macro is missing or archived is shown as a macro, so it never disappears.
/// Expenses precede income and generic categories; catch-all categories come last.
public struct CategoryHierarchy {
    /// Active macro categories in stable display order.
    public let roots: [Category]
    private let byID: [UUID: Category]
    private let activeChildren: [UUID: [Category]]
    private let allChildIDs: [UUID: [UUID]]

    public init(categories: [Category], kind: CategoryKind? = nil) {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func matches(_ category: Category) -> Bool {
            category.isActive == true && (kind == nil || category.kind == nil || category.kind == kind)
        }
        func activeParent(of category: Category) -> Category? {
            guard let id = category.parentCategoryId, let parent = byID[id], parent.isActive == true,
                  parent.parentCategoryId == nil else { return nil }
            return parent
        }
        var children: [UUID: [Category]] = [:]
        var allChildIDs: [UUID: [UUID]] = [:]
        var roots: [Category] = []
        for category in categories {
            if let parentID = category.parentCategoryId { allChildIDs[parentID, default: []].append(category.id) }
            guard matches(category) else { continue }
            if let parent = activeParent(of: category) { children[parent.id, default: []].append(category) }
            else { roots.append(category) }
        }
        self.byID = byID
        self.allChildIDs = allChildIDs
        self.activeChildren = children.mapValues(Category.displayOrdered)
        self.roots = Category.displayOrdered(roots)
    }

    public func children(of category: Category) -> [Category] {
        activeChildren[category.id] ?? []
    }

    /// The macro category a transaction rolls up to.
    public func root(of category: Category) -> Category {
        guard let parentID = category.parentCategoryId, let parent = byID[parentID] else { return category }
        return parent
    }

    /// Selected IDs plus every subcategory of a selected macro, archived ones included,
    /// so filters and budgets on a macro category also cover its subcategories' history.
    public func expanding(_ ids: Set<UUID>) -> Set<UUID> {
        ids.union(ids.flatMap { allChildIDs[$0] ?? [] })
    }

    /// Choosing a child of a selected macro narrows that family to the child.
    /// Choosing a macro replaces individual selections within its family.
    public func toggling(_ category: Category, in selection: Set<UUID>) -> Set<UUID> {
        var result = selection
        if result.contains(category.id) {
            result.remove(category.id)
        } else {
            if let parentID = category.parentCategoryId { result.remove(parentID) }
            result.subtract(allChildIDs[category.id] ?? [])
            result.insert(category.id)
        }
        return result
    }

    /// "Cibo › Ristoranti" for a subcategory, the plain name for a macro category.
    public func path(of category: Category) -> String {
        let name = category.name ?? "Categoria"
        let root = root(of: category)
        guard root.id != category.id else { return name }
        return "\(root.name ?? "Categoria") › \(name)"
    }
}

extension Category {
    /// Stable display order: expenses, income, shared categories; natural names within each group.
    /// Catch-all categories stay last, including in legacy books without category kinds.
    public static func displayOrdered(_ categories: [Category]) -> [Category] {
        func isOther(_ category: Category) -> Bool {
            ["altro", "altra", "altri", "altre", "other", "others"].contains(
                (category.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        func rank(_ category: Category) -> Int {
            switch category.kind {
            case .expense: 0
            case .income: 1
            case nil: 2
            }
        }
        return categories.sorted {
            if isOther($0) != isOther($1) { return !isOther($0) }
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            let order = ($0.name ?? "").localizedStandardCompare($1.name ?? "")
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// The macro category this one belongs to, or itself when it is a macro category.
    public var rootCategory: Category {
        guard let parentID = parentCategoryId,
              let parent = account?.categories?.first(where: { $0.id == parentID }) else { return self }
        return parent
    }

    /// "Cibo › Ristoranti" for a subcategory, the plain name for a macro category.
    public var displayPath: String {
        let root = rootCategory
        guard root.id != id else { return name ?? "Categoria" }
        return "\(root.name ?? "Categoria") › \(name ?? "Categoria")"
    }
}
