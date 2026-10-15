import Foundation
import SwiftData

@MainActor
public struct BudgetEdits {
    public enum Failure: Error { case invalidInput, invalidBook, invalidCategories, invalidConto }
    private let context: ModelContext
    private let save: () throws -> Void
    public init(context: ModelContext) { self.init(context: context, save: { try context.save() }) }
    init(context: ModelContext, save: @escaping () throws -> Void) { self.context = context; self.save = save }

    @discardableResult
    public func apply(to existing: Budget? = nil, account: Account, name: String, amountText: String,
                      period: BudgetPeriod, threshold: Double, categories: [Category], contoID: UUID? = nil) throws -> Budget {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let amount = BalanceInput.parse(amountText, currency: account.currency ?? "EUR"),
              amount > 0, threshold.isFinite, (0...1).contains(threshold) else { throw Failure.invalidInput }
        guard account.isActive == true, existing == nil || existing?.account?.id == account.id else { throw Failure.invalidBook }
        guard !categories.isEmpty, categories.allSatisfy({ $0.account?.id == account.id }),
              Set(categories.map(\.id)).count == categories.count else { throw Failure.invalidCategories }
        if let contoID {
            guard let conto = account.conti?.first(where: { $0.id == contoID }), conto.isActive != false,
                  categories.allSatisfy({ SharedContoCategories.permits($0, for: conto) }) else { throw Failure.invalidConto }
        }
        if let budget = existing {
            let previous = (budget.name, budget.amount, budget.period, budget.alertThreshold, budget.categories, budget.updatedAt, budget.planningGroupRaw, budget.usesExactCategories, budget.contoID)
            budget.name = name; budget.amount = amount; budget.period = period
            budget.alertThreshold = threshold; budget.categories = categories; budget.updatedAt = Date(); budget.contoID = contoID
            if Set((previous.4 ?? []).map(\.id)) != Set(categories.map(\.id)) || previous.8 != contoID {
                // Explicit category edits turn a generated limit into a manual budget.
                budget.planningGroupRaw = nil
                budget.usesExactCategories = previous.7 ?? true
            }
            do { try save(); return budget }
            catch {
                (budget.name, budget.amount, budget.period, budget.alertThreshold, budget.categories, budget.updatedAt, budget.planningGroupRaw, budget.usesExactCategories, budget.contoID) = previous
                throw error
            }
        }
        let budget = Budget(name: name, amount: amount, period: period,
                            alertThreshold: threshold, includeRecurringTransactions: false)
        budget.account = account; budget.categories = categories; budget.contoID = contoID
        context.insert(budget)
        do { try save(); return budget }
        catch {
            budget.categories = []; budget.account = nil
            context.delete(budget)
            throw error
        }
    }

    public func setActive(_ active: Bool, for budget: Budget) throws {
        let previous = (budget.isActive, budget.updatedAt)
        budget.isActive = active; budget.updatedAt = Date()
        do { try save() }
        catch { (budget.isActive, budget.updatedAt) = previous; throw error }
    }
}
