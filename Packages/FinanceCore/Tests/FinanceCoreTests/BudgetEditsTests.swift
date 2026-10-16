import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct BudgetEditsTests {
    enum SaveFailure: Error { case unavailable }
    private func fixture() throws -> (ModelContainer, Account, FinanceCore.Category, FinanceCore.Category) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Book", currency: "EUR")
        context.insert(book)
        let first = FinanceCore.Category(name: "Food")
        let second = FinanceCore.Category(name: "Travel")
        first.account = book; second.account = book
        context.insert(first); context.insert(second)
        try context.save()
        return (container, book, first, second)
    }
    @Test func editPreservesIdentityAndArchiveIsReversibleWithoutDeletingLedger() throws {
        let (container, book, first, second) = try fixture()
        let context = container.mainContext
        let edits = BudgetEdits(context: context)
        let budget = try edits.apply(account: book, name: "Original", amountText: "100", period: .monthly,
                                     threshold: 0.8, categories: [first])
        let id = budget.id
        let created = budget.createdAt
        let movement = Transaction(amount: 20, type: .expense, date: Date())
        movement.setCategory(first)
        context.insert(movement); try context.save()
        try edits.apply(to: budget, account: book, name: "  Updated  ", amountText: "200,50", period: .weekly,
                        threshold: 0.9, categories: [second])
        #expect(budget.id == id && budget.createdAt == created)
        #expect(budget.name == "Updated" && budget.amount == Decimal(string: "200.50"))
        #expect(budget.period == .weekly && budget.categories?.map(\.id) == [second.id])
        try edits.setActive(false, for: budget)
        #expect(budget.isActive == false)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 1)
        try edits.setActive(true, for: budget)
        let persisted = try #require(ModelContext(container).fetch(FetchDescriptor<Budget>()).first)
        #expect(persisted.id == id && persisted.isActive == true)
        #expect(persisted.name == "Updated")
    }
    @Test func failedEditAndArchiveRestoreFieldsAndPreserveOtherDrafts() throws {
        let (container, book, first, second) = try fixture()
        let context = container.mainContext
        let budget = try BudgetEdits(context: context).apply(account: book, name: "Original", amountText: "100",
            period: .monthly, threshold: 0.8, categories: [first])
        let previousDate = budget.updatedAt
        book.name = "Draft"
        let failing = BudgetEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.apply(to: budget, account: book, name: "Changed", amountText: "200", period: .weekly,
                              threshold: 0.9, categories: [second])
        }
        #expect(budget.name == "Original" && budget.amount == 100 && budget.period == .monthly)
        #expect(budget.categories?.map(\.id) == [first.id] && budget.alertThreshold == 0.8)
        #expect(throws: SaveFailure.self) { try failing.setActive(false, for: budget) }
        #expect(budget.updatedAt == previousDate && budget.isActive == true)
        #expect(book.name == "Draft")
        try context.save()
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Budget>()).first)
        #expect(stored.categories?.map(\.id) == [first.id] && stored.amount == 100 && stored.isActive == true)
    }
    @Test func editingGeneratedBudgetUsesExplicitCategoriesInExpensePreview() throws {
        let (container, book, first, second) = try fixture()
        book.budgetingPlanJSON = try BudgetingPlan(monthlyIncome: 1000,
            categoryGroups: [first.externalID: .needs, second.externalID: .wants]).encoded()
        let budget = Budget(name: "Needs", amount: 100, period: .monthly)
        budget.account = book
        budget.categories = [first]
        budget.planningGroupRaw = BudgetAllocationGroup.needs.rawValue
        budget.usesExactCategories = true
        container.mainContext.insert(budget)
        try container.mainContext.save()
        try BudgetEdits(context: container.mainContext).apply(to: budget, account: book,
            name: "Needs renamed", amountText: "120", period: .monthly, threshold: 0.8, categories: [first])
        #expect(budget.planningGroupRaw == BudgetAllocationGroup.needs.rawValue)
        let failing = BudgetEdits(context: container.mainContext, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.apply(to: budget, account: book, name: "Travel", amountText: "100",
                              period: .monthly, threshold: 0.8, categories: [second])
        }
        #expect(budget.planningGroupRaw == BudgetAllocationGroup.needs.rawValue)
        #expect(budget.usesExactCategories == true)
        #expect(budget.coveredCategoryIDs == [first.id])

        try BudgetEdits(context: container.mainContext).apply(to: budget, account: book,
            name: "Travel", amountText: "100", period: .monthly, threshold: 0.8, categories: [second])
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Budget>()).first)
        #expect(stored.planningGroupRaw == nil)
        #expect(stored.usesExactCategories == true)
        #expect(stored.coveredCategoryIDs == [second.id])
        func preview(categoryID: UUID) -> [ExpenseBudgetPreview] {
            BudgetService.previewExpense(amount: 150, categoryID: categoryID, accountID: book.id,
                date: Date(), budgets: [stored], transactions: [])
        }
        #expect(preview(categoryID: first.id).isEmpty)
        #expect(preview(categoryID: second.id).first?.status == .overLimit)
    }

    @Test(arguments: [nil, false, true] as [Bool?])
    func categoryEditsPreserveCoverageAndRestoreItOnFailure(exact: Bool?) throws {
        let (container, book, first, second) = try fixture()
        let context = container.mainContext
        let child = FinanceCore.Category(name: "Child", parentCategoryId: second.id)
        child.account = book; context.insert(child)
        let budget = Budget(name: "Original", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [first]; budget.usesExactCategories = exact
        context.insert(budget); try context.save()
        let failing = BudgetEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.apply(to: budget, account: book, name: "Changed", amountText: "100",
                              period: .monthly, threshold: 0.8, categories: [second])
        }
        #expect(budget.usesExactCategories == exact)
        #expect(budget.categories?.map(\.id) == [first.id])
        try BudgetEdits(context: context).apply(to: budget, account: book, name: "Changed", amountText: "100",
                                              period: .monthly, threshold: 0.8, categories: [second])
        let readContext = ModelContext(container)
        let stored = try #require(readContext.fetch(FetchDescriptor<Budget>()).first)
        #expect(stored.usesExactCategories == (exact ?? false))
        #expect(stored.coveredCategoryIDs == (exact == true ? [second.id] : [second.id, child.id]))
    }

    @Test func failedCreationDoesNotLeaveBudgetOrInverseRelationship() throws {
        let (container, book, first, _) = try fixture()
        let context = container.mainContext
        let failing = BudgetEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.apply(account: book, name: "Budget", amountText: "100", period: .monthly,
                              threshold: 0.8, categories: [first])
        }
        try context.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Budget>()) == 0)
        #expect((book.budgets ?? []).isEmpty)
        #expect((first.budgets ?? []).isEmpty)
    }
    @Test func rejectsPartialAmountsForeignCategoriesAndWrongBookBeforeSaving() throws {
        let (container, book, first, _) = try fixture()
        var saves = 0
        let edits = BudgetEdits(context: container.mainContext, save: { saves += 1 })
        for invalid in ["12abc", "1.234,56", "0", "-10", "1.001", ""] {
            #expect(throws: BudgetEdits.Failure.invalidInput) {
                try edits.apply(account: book, name: "Budget", amountText: invalid, period: .monthly,
                                threshold: 0.8, categories: [first])
            }
        }
        let foreign = FinanceCore.Category(name: "Foreign")
        #expect(throws: BudgetEdits.Failure.invalidCategories) {
            try edits.apply(account: book, name: "Budget", amountText: "100", period: .monthly,
                            threshold: 0.8, categories: [foreign])
        }
        let other = Account(name: "Other")
        let wrongBudget = Budget(name: "Other", amount: 100, period: .monthly)
        wrongBudget.account = other
        #expect(throws: BudgetEdits.Failure.invalidBook) {
            try edits.apply(to: wrongBudget, account: book, name: "Budget", amountText: "100", period: .monthly,
                            threshold: 0.8, categories: [first])
        }
        #expect(saves == 0)
    }
}
