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
        let categories = Category.defaultCategoryDefinitions.map { definition in
            let category = Category(name: definition.name, color: definition.color, icon: definition.icon)
            category.externalID = "\(account.id)-\(definition.stableKey)"
            category.account = account
            context.insert(category)
            return category
        }
        do { try save(); return account }
        catch {
            // Remove only this failed creation; preserve edits to existing books.
            for category in categories {
                category.account = nil
                context.delete(category)
            }
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
