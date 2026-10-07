import Foundation
import SwiftData

/// Seeds the suggested macro categories and subcategories, and brings older books up to date
/// without touching what the user archived or reorganised.
@MainActor
public struct CategoryDefaults {
    /// What an upgrade would change in a book.
    public struct Plan {
        fileprivate var creations: [Category.DefaultCategoryDefinition] = []
        fileprivate var attachments: [(category: Category, parentKey: String)] = []
        fileprivate var kinds: [(category: Category, kind: CategoryKind)] = []
        fileprivate var colors: [(category: Category, color: String)] = []
        fileprivate var matched: [String: Category] = [:]

        public var addedCount: Int { creations.count }
        public var movedCount: Int { attachments.count }
        public var recoloredCount: Int { colors.count }
        public var isEmpty: Bool { creations.isEmpty && attachments.isEmpty && kinds.isEmpty && colors.isEmpty }
    }

    private let context: ModelContext
    private let save: () throws -> Void

    public init(context: ModelContext) { self.init(context: context, save: { try context.save() }) }
    init(context: ModelContext, save: @escaping () throws -> Void) { self.context = context; self.save = save }

    public static func externalID(for key: String, in account: Account) -> String { "\(account.id)-\(key)" }

    public static func plan(for account: Account) -> Plan {
        let existing = account.categories ?? []
        var plan = Plan()
        var claimed = Set<UUID>()
        let defaultIDs = Set(Category.defaultCategoryDefinitions.map { externalID(for: $0.stableKey, in: account) })
        for definition in Category.defaultCategoryDefinitions {
            let externalID = externalID(for: definition.stableKey, in: account)
            // An archived default counts as a match: the user removed it on purpose.
            let match = existing.first { $0.externalID == externalID } ?? existing.first {
                !claimed.contains($0.id) && !defaultIDs.contains($0.externalID) && $0.isActive == true &&
                ($0.name ?? "").trimmingCharacters(in: .whitespaces)
                    .compare(definition.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                (definition.parentKey != nil || $0.parentCategoryId == nil)
            }
            guard let match else {
                // Don't recreate subcategories under a macro the user archived.
                if let parentKey = definition.parentKey, let parent = plan.matched[parentKey],
                   parent.isActive != true { continue }
                plan.creations.append(definition)
                continue
            }
            claimed.insert(match.id)
            plan.matched[definition.stableKey] = match
            guard match.isActive == true else { continue }
            if match.kind == nil, let kind = definition.kind { plan.kinds.append((match, kind)) }
            if let color = match.color?.uppercased(), CategoryPalette.legacyDefaultColors.contains(color),
               color != definition.color.uppercased() {
                plan.colors.append((match, definition.color))
            }
            guard let parentKey = definition.parentKey, match.parentCategoryId == nil,
                  !existing.contains(where: { $0.parentCategoryId == match.id }) else { continue }
            if let parent = plan.matched[parentKey], parent.isActive != true { continue }
            plan.attachments.append((match, parentKey))
        }
        return plan
    }

    /// Inserts the planned categories without saving. Returns an undo for a failed save.
    @discardableResult
    static func apply(_ plan: Plan, to account: Account, in context: ModelContext) -> () -> Void {
        var byKey = plan.matched
        var created: [Category] = []
        for definition in plan.creations {
            let parentID = definition.parentKey.flatMap { byKey[$0]?.id }
            let category = Category(name: definition.name, color: definition.color, icon: definition.icon,
                                    parentCategoryId: parentID, kind: definition.kind)
            category.externalID = externalID(for: definition.stableKey, in: account)
            category.account = account
            context.insert(category)
            created.append(category)
            byKey[definition.stableKey] = category
        }
        let previous = (plan.attachments.map(\.category) + plan.kinds.map(\.category) + plan.colors.map(\.category))
            .map { ($0, $0.parentCategoryId, $0.kindRaw, $0.color, $0.updatedAt) }
        for (category, kind) in plan.kinds { category.kind = kind; category.updatedAt = Date() }
        for (category, color) in plan.colors { category.color = color; category.updatedAt = Date() }
        for (category, parentKey) in plan.attachments {
            guard let parent = byKey[parentKey] else { continue }
            category.parentCategoryId = parent.id
            category.updatedAt = Date()
        }
        return {
            for (category, parent, kind, color, updatedAt) in previous.reversed() {
                category.parentCategoryId = parent; category.kindRaw = kind
                category.color = color; category.updatedAt = updatedAt
            }
            for category in created {
                category.account = nil
                context.delete(category)
            }
        }
    }

    /// Adds missing suggested categories and files earlier flat defaults under their macro category.
    @discardableResult
    public func upgrade(_ account: Account) throws -> Plan {
        let plan = Self.plan(for: account)
        guard !plan.isEmpty else { return plan }
        let undo = Self.apply(plan, to: account, in: context)
        do { try save(); return plan }
        catch { undo(); throw error }
    }
}
