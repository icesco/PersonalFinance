import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct CategoryHierarchyTests {
    private enum SaveFailure: Error { case unavailable }

    private func container() throws -> ModelContainer {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        container.mainContext.autosaveEnabled = false
        return container
    }

    private func category(_ name: String, in book: Account, parent: FinanceCore.Category? = nil,
                          kind: CategoryKind? = nil, context: ModelContext) -> FinanceCore.Category {
        let value = FinanceCore.Category(name: name, parentCategoryId: parent?.id, kind: kind)
        value.account = book
        context.insert(value)
        return value
    }

    // MARK: - Default tree

    @Test func defaultTreeHasUniqueKeysTwoLevelsAndSharedKinds() {
        let definitions = FinanceCore.Category.defaultCategoryDefinitions
        let byKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.stableKey, $0) })
        #expect(byKey.count == definitions.count)
        for definition in definitions {
            guard let parentKey = definition.parentKey else { continue }
            let parent = try? #require(byKey[parentKey])
            #expect(parent?.parentKey == nil)
            #expect(parent?.kind == definition.kind)
            #expect(parent?.color == definition.color)
            #expect(CategoryPalette.swatches.contains { $0.hex == definition.color })
            // Parents come first so they exist when their subcategories are created.
            #expect(definitions.firstIndex { $0.stableKey == parentKey }! < definitions.firstIndex { $0.stableKey == definition.stableKey }!)
        }
        #expect(definitions.contains { $0.kind == .income && $0.parentKey == nil })
        #expect(definitions.contains { $0.kind == .expense && $0.parentKey == nil })
    }

    @Test func newBookGetsTheTreeWithoutAnyChoice() throws {
        let container = try container()
        let book = try AccountCreation(context: container.mainContext).create(name: "Casa", currency: "EUR")
        let categories = book.categories ?? []
        let byExternalID = Dictionary(uniqueKeysWithValues: categories.map { ($0.externalID, $0) })
        let ristoranti = try #require(byExternalID["\(book.id)-ristoranti"])
        let cibo = try #require(byExternalID["\(book.id)-cibo"])
        #expect(ristoranti.parentCategoryId == cibo.id)
        #expect(ristoranti.kind == .expense && cibo.kind == .expense)
        #expect(byExternalID["\(book.id)-stipendio"]?.kind == .income)
        #expect(CategoryDefaults.plan(for: book).isEmpty)
    }

    // MARK: - Hierarchy

    @Test func displayOrderIsIndependentOfRelationshipOrderAndKeepsOtherLast() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let other = category("Altro", in: book, context: context)
        let income = category("Lavoro", in: book, kind: .income, context: context)
        let travel = category("Viaggi", in: book, kind: .expense, context: context)
        let food = category("Cibo", in: book, kind: .expense, context: context)
        let legacy = category("Abbonamenti", in: book, context: context)
        let childOther = category("Altro", in: book, parent: food, kind: .expense, context: context)
        let restaurant = category("Ristoranti", in: book, parent: food, kind: .expense, context: context)
        let bar = category("Bar", in: book, parent: food, kind: .expense, context: context)
        let input = [other, income, travel, childOther, food, restaurant, legacy, bar]
        let expected = [food.id, travel.id, income.id, legacy.id, other.id]
        #expect(CategoryHierarchy(categories: input).roots.map(\.id) == expected)
        #expect(CategoryHierarchy(categories: input.reversed()).roots.map(\.id) == expected)
        #expect(CategoryHierarchy(categories: input).children(of: food).map(\.id) == [bar.id, restaurant.id, childOther.id])
        #expect(Category.displayOrdered([other, legacy]).map(\.id) == [legacy.id, other.id])
    }

    @Test func hierarchyFiltersByKindKeepsOrphansAndExpandsArchivedChildren() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let food = category("Cibo", in: book, kind: .expense, context: context)
        let restaurants = category("Ristoranti", in: book, parent: food, kind: .expense, context: context)
        let bars = category("Bar", in: book, parent: food, kind: .expense, context: context)
        bars.isActive = false
        let work = category("Lavoro", in: book, kind: .income, context: context)
        let other = category("Altro", in: book, context: context)
        let archivedParent = category("Vecchia", in: book, kind: .expense, context: context)
        archivedParent.isActive = false
        let orphan = category("Orfana", in: book, parent: archivedParent, kind: .expense, context: context)

        let expenses = CategoryHierarchy(categories: book.categories ?? [], kind: .expense)
        #expect(expenses.roots.map(\.id) == [food.id, orphan.id, other.id])
        #expect(expenses.children(of: food).map(\.id) == [restaurants.id])
        #expect(!expenses.roots.contains { $0.id == work.id })
        #expect(expenses.path(of: restaurants) == "Cibo › Ristoranti")
        #expect(expenses.root(of: restaurants).id == food.id)
        #expect(expenses.expanding([food.id]) == [food.id, restaurants.id, bars.id])
        #expect(restaurants.displayPath == "Cibo › Ristoranti")
        #expect(food.displayPath == "Cibo")
        #expect(restaurants.fits(.expense) && !restaurants.fits(.income) && other.fits(.income) && !other.fits(.transfer))
    }

    @Test func categoryFilterNarrowsMacroAndPreservesOtherFamilies() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let food = category("Cibo", in: book, context: context)
        let restaurant = category("Ristoranti", in: book, parent: food, context: context)
        let bar = category("Bar", in: book, parent: food, context: context)
        let travel = category("Viaggi", in: book, context: context)
        let hierarchy = CategoryHierarchy(categories: [food, restaurant, bar, travel])
        let narrowed = hierarchy.toggling(restaurant, in: [food.id, travel.id])
        #expect(narrowed == [restaurant.id, travel.id])
        #expect(hierarchy.expanding(narrowed) == [restaurant.id, travel.id])
        let widened = hierarchy.toggling(food, in: [restaurant.id, bar.id, travel.id])
        #expect(widened == [food.id, travel.id])
        #expect(hierarchy.expanding(widened) == [food.id, restaurant.id, bar.id, travel.id])
        #expect(hierarchy.toggling(food, in: widened) == [travel.id])
    }

    // MARK: - Upgrade of existing books

    @Test func upgradeFilesLegacyFlatDefaultsAndRespectsArchivedAndRenamed() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        func legacy(_ key: String, _ name: String) -> FinanceCore.Category {
            let value = category(name, in: book, context: context)
            value.externalID = "\(book.id)-\(key)"
            return value
        }
        let groceries = legacy("alimentari", "Spesa")       // renamed by the user
        groceries.color = "#F44336"                          // old seeded colour
        let recoloredByUser = legacy("trasporti", "Trasporti")
        recoloredByUser.color = "#123456"
        let casa = legacy("casa", "Casa")
        let utenze = legacy("utenze", "Utenze")
        let sport = legacy("sport", "Sport"); sport.isActive = false
        let custom = category("Ristoranti", in: book, context: context) // user-made, same name as a default
        let transaction = Transaction(amount: 12, type: .expense)
        transaction.setCategory(groceries); context.insert(transaction)
        try context.save()

        let plan = try CategoryDefaults(context: context).upgrade(book)
        #expect(plan.movedCount == 3)
        let categories = book.categories ?? []
        let cibo = try #require(categories.first { $0.externalID == "\(book.id)-cibo" })
        #expect(groceries.parentCategoryId == cibo.id && groceries.name == "Spesa" && groceries.kind == .expense)
        #expect(groceries.color == CategoryPalette.terracotta && cibo.color == CategoryPalette.terracotta)
        #expect(recoloredByUser.color == "#123456")
        #expect(plan.recoloredCount == 1)
        #expect(utenze.parentCategoryId == casa.id && casa.parentCategoryId == nil)
        #expect(custom.parentCategoryId == cibo.id)
        #expect(categories.filter { $0.name == "Ristoranti" }.count == 1)
        #expect(sport.isActive == false && sport.parentCategoryId == nil)
        #expect(categories.filter { $0.externalID == "\(book.id)-sport" }.count == 1)
        #expect(transaction.category?.id == groceries.id)
        #expect(CategoryDefaults.plan(for: book).isEmpty)
    }

    @Test func failedUpgradeRestoresTheBook() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let utenze = category("Utenze", in: book, context: context)
        try context.save()
        let failing = CategoryDefaults(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try failing.upgrade(book) }
        #expect(utenze.parentCategoryId == nil && utenze.kind == nil)
        #expect(book.categories?.map(\.id) == [utenze.id])
    }

    // MARK: - Edits

    @Test func archivingAMacroArchivesItsSubcategories() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let food = category("Cibo", in: book, context: context)
        let bar = category("Bar", in: book, parent: food, context: context)
        let home = category("Casa", in: book, context: context)
        try context.save()
        try SettingsEdits(context: context).archiveCategories([food, home], at: [0])
        #expect(food.isActive == false && bar.isActive == false && home.isActive == true)
    }

    @Test func movingKeepsTwoLevelsAndInheritsKind() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let food = category("Cibo", in: book, kind: .expense, context: context)
        let bar = category("Bar", in: book, parent: food, kind: .expense, context: context)
        let loose = category("Pizza", in: book, context: context)
        try context.save()
        let edits = SettingsEdits(context: context)

        try edits.updateCategory(loose, name: "Pizza", color: "#000000", icon: "tag", parentID: food.id, kind: .income)
        #expect(loose.parentCategoryId == food.id && loose.kind == .expense)
        #expect(throws: SettingsEdits.Failure.invalidParent) {
            try edits.updateCategory(food, name: "Cibo", color: "#000000", icon: "tag", parentID: loose.id, kind: nil)
        }
        #expect(throws: SettingsEdits.Failure.invalidParent) {
            try edits.updateCategory(food, name: "Cibo", color: "#000000", icon: "tag", parentID: food.id, kind: nil)
        }
        try edits.updateCategory(food, name: "Cibo", color: "#000000", icon: "tag", parentID: nil, kind: .income)
        #expect(bar.kind == .income && loose.kind == .income)
        let created = try edits.createCategory(name: "Sushi", color: "#000000", icon: "tag", parentID: food.id,
                                               kind: .expense, account: book)
        #expect(created.kind == .income)
    }

    // MARK: - Roll-up

    @Test func budgetOnMacroCountsSubcategorySpending() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let conto = Conto(name: "Conto", type: .checking); conto.account = book; context.insert(conto)
        let food = category("Cibo", in: book, kind: .expense, context: context)
        let bar = category("Bar", in: book, parent: food, kind: .expense, context: context)
        let home = category("Casa", in: book, kind: .expense, context: context)
        let budget = Budget(name: "Cibo", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [food]; context.insert(budget)
        let date = budget.currentPeriodRange.start.addingTimeInterval(60)
        for (amount, category) in [(Decimal(10), food), (Decimal(5), bar), (Decimal(40), home)] {
            let value = Transaction(amount: amount, type: .expense, date: date)
            value.setFromConto(conto); value.setCategory(category); context.insert(value)
        }
        try context.save()
        #expect(try BudgetService.currentSpent(for: budget, in: context) == 15)
        let preview = BudgetService.previewExpense(amount: 3, categoryID: bar.id, accountID: book.id, date: date,
                                                   budgets: [budget], transactions: try context.fetch(FetchDescriptor<Transaction>()))
        #expect(preview.first?.spent == 15)
        #expect(BudgetService.previewExpense(amount: 3, categoryID: home.id, accountID: book.id, date: date,
                                             budgets: [budget], transactions: []).isEmpty)
    }

    @Test func spendingRollsUpToMacroCategories() throws {
        let container = try container()
        let context = container.mainContext
        let book = Account(name: "Libro"); context.insert(book)
        let conto = Conto(name: "Conto", type: .checking, initialBalance: 100); conto.account = book; context.insert(conto)
        let food = category("Cibo", in: book, kind: .expense, context: context)
        let bar = category("Bar", in: book, parent: food, kind: .expense, context: context)
        let now = Date()
        var transactions: [Transaction] = []
        for (amount, category) in [(Decimal(10), food), (Decimal(5), bar)] {
            let value = Transaction(amount: amount, type: .expense, date: now.addingTimeInterval(-60))
            value.setFromConto(conto); value.setCategory(category); context.insert(value)
            transactions.append(value)
        }
        try context.save()
        let inputs = SpendingDirectionInputs.build(conti: [conto], transactions: transactions, resolutions: [],
                                                   now: now, horizon: now)
        #expect(Set(inputs.transactions.map(\.categoryID)) == [food.id])
        #expect(Set(inputs.transactions.map(\.categoryName)) == ["Cibo"])
    }
}
