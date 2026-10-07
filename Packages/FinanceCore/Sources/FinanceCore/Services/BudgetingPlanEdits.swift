import Foundation
import SwiftData

@MainActor
public struct BudgetingPlanEdits {
    public enum Failure: Error { case invalidPlan, invalidBook, incompleteCategories, invalidSavingsConti }
    private let context: ModelContext
    private let save: () throws -> Void
    public init(context: ModelContext) { self.init(context: context, save: { try context.save() }) }
    init(context: ModelContext, save: @escaping () throws -> Void) { self.context = context; self.save = save }

    public func apply(_ plan: BudgetingPlan, to account: Account, archiveOverlapping: Bool = false) throws {
        guard account.isActive == true else { throw Failure.invalidBook }
        guard plan.isValid else { throw Failure.invalidPlan }
        let categories = (account.categories ?? []).filter { $0.fits(.expense) }
        let eligible = Set((account.conti ?? []).filter { $0.type == .savings }.map(\.externalID))
        guard plan.savingsContoIDs.isSubset(of: eligible) else { throw Failure.invalidSavingsConti }
        if plan.method != .manual {
            guard categories.filter({ $0.isActive == true }).allSatisfy({ plan.group(for: $0) != nil }) else {
                throw Failure.incompleteCategories
            }
        }
        let json = try plan.encoded()
        let previousPlan = account.budgetingPlanJSON, previousUpdated = account.updatedAt
        let existing = account.budgets ?? []
        let snapshots = existing.map(BudgetBackup.init)
        var inserted: [Budget] = []
        let covered = Set(categories.filter { plan.group(for: $0) != nil }.map(\.id))
        do {
            // Only budgets owned by this feature are changed without explicit reconciliation.
            for budget in existing where budget.planningGroupRaw != nil {
                budget.isActive = false; budget.updatedAt = Date()
            }
            if plan.method != .manual {
                for group in BudgetAllocationGroup.allCases {
                    let members = categories.filter { plan.group(for: $0) == group }
                    let amount = plan.roundedLimit(for: group, currency: account.currency ?? "EUR")
                    guard amount > 0, !members.isEmpty else { continue }
                    let budget: Budget
                    if let owned = existing.first(where: { $0.planningGroupRaw == group.rawValue }) { budget = owned }
                    else {
                        budget = Budget(name: "", amount: amount, period: .monthly, includeRecurringTransactions: false)
                        budget.account = account; context.insert(budget); inserted.append(budget)
                    }
                    budget.name = group == .needs ? "Necessità · piano" : "Desideri · piano"
                    budget.amount = amount; budget.period = .monthly; budget.isActive = true
                    budget.categories = members; budget.usesExactCategories = true
                    budget.planningGroupRaw = group.rawValue; budget.includeRecurringTransactions = false; budget.updatedAt = Date()
                }
                if archiveOverlapping {
                    for budget in existing where budget.planningGroupRaw == nil && !budget.coveredCategoryIDs.isDisjoint(with: covered) {
                        budget.isActive = false; budget.updatedAt = Date()
                    }
                }
            }
            account.budgetingPlanJSON = json; account.updatedAt = Date()
            try save()
        } catch {
            account.budgetingPlanJSON = previousPlan; account.updatedAt = previousUpdated
            snapshots.forEach { $0.restore() }
            for budget in inserted { budget.categories = []; budget.account = nil; context.delete(budget) }
            throw error
        }
    }
}

@MainActor
private struct BudgetBackup {
    let budget: Budget
    let name: String?, amount: Decimal?, period: BudgetPeriod?, active: Bool?, categories: [Category]?
    let exact: Bool?, group: String?, recurring: Bool?, updated: Date?
    init(_ budget: Budget) {
        self.budget = budget; name = budget.name; amount = budget.amount; period = budget.period
        active = budget.isActive; categories = budget.categories; exact = budget.usesExactCategories
        group = budget.planningGroupRaw; recurring = budget.includeRecurringTransactions; updated = budget.updatedAt
    }
    func restore() {
        budget.name = name; budget.amount = amount; budget.period = period; budget.isActive = active
        budget.categories = categories; budget.usesExactCategories = exact; budget.planningGroupRaw = group
        budget.includeRecurringTransactions = recurring; budget.updatedAt = updated
    }
}
