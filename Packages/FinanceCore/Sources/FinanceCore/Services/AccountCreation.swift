import Foundation
import SwiftData

@MainActor
public struct AccountCreation {
    public enum Failure: Error { case invalidName, invalidCurrency, invalidConti }
    private let context: ModelContext
    private let save: () throws -> Void
    public init(context: ModelContext) { self.init(context: context, save: { try context.save() }) }
    init(context: ModelContext, save: @escaping () throws -> Void) { self.context = context; self.save = save }

    public func create(name: String, currency: String, conti: [Conto] = []) throws -> Account {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.invalidName }
        guard Locale.commonISOCurrencyCodes.contains(currency) else { throw Failure.invalidCurrency }
        guard Set(conti.map(\.id)).count == conti.count,
              conti.allSatisfy({
                  $0.modelContext == nil && $0.account == nil &&
                  !($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  BalanceInput.parse(NSDecimalNumber(decimal: $0.initialBalance ?? 0).stringValue, currency: currency) != nil
              }) else { throw Failure.invalidConti }
        let account = Account(name: name, currency: currency)
        context.insert(account)
        for conto in conti {
            conto.account = account
            context.insert(conto)
        }
        let removeCategories = CategoryDefaults.apply(CategoryDefaults.plan(for: account), to: account, in: context)
        do {
            for conto in conti where conto.type == .savings && conto.savingsGoal != nil {
                try SavingsAccountEdits.linkGoal(conto: conto, existingID: nil, target: conto.savingsGoal, context: context)
            }
            try save()
            return account
        }
        catch {
            // Remove only this failed creation; preserve edits to existing books.
            removeCategories()
            for goal in account.savingsGoals ?? [] { context.delete(goal) }
            for conto in conti {
                conto.account = nil
                context.delete(conto)
            }
            account.conti = []
            account.categories = []
            context.delete(account)
            throw error
        }
    }
}
