import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct BudgetingPlanTests {
    private enum SaveFailure: Error { case unavailable }
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var interval: DateInterval { DateInterval(start: start, duration: 30 * 86400) }

    private func fixture() throws -> (ModelContainer, Account, Conto, Conto, Conto, FinanceCore.Category, FinanceCore.Category) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext; context.autosaveEnabled = false
        let book = Account(name: "Libro")
        context.insert(book)
        let current = Conto(name: "Corrente", type: .checking)
        let savings = Conto(name: "Risparmio", type: .savings, initialBalance: 5000)
        let reserve = Conto(name: "Riserva", type: .savings)
        for conto in [current, savings, reserve] { conto.account = book; context.insert(conto) }
        let food = FinanceCore.Category(name: "Cibo", kind: .expense)
        let restaurant = FinanceCore.Category(name: "Ristorante", parentCategoryId: food.id, kind: .expense)
        for category in [food, restaurant] { category.account = book; context.insert(category) }
        try context.save()
        return (container, book, current, savings, reserve, food, restaurant)
    }
    private func plan(_ food: FinanceCore.Category, _ restaurant: FinanceCore.Category, _ savings: [Conto] = []) -> BudgetingPlan {
        BudgetingPlan(monthlyIncome: 2000, categoryGroups: [food.externalID: .needs, restaurant.externalID: .wants],
                      savingsContoIDs: Set(savings.map(\.externalID)))
    }
    private func entry(_ amount: Decimal, _ type: TransactionType, from: Conto? = nil, to: Conto? = nil,
                       at date: Date? = nil, category: FinanceCore.Category? = nil) -> Transaction {
        let value = Transaction(amount: amount, type: type, date: date ?? start.addingTimeInterval(10))
        value.setFromConto(from); value.setToConto(to); value.setCategory(category)
        return value
    }
    private func report(_ book: Account, _ entries: [Transaction]) -> MonthlySavingsReport {
        MonthlySavingsReport(account: book, transactions: entries, interval: interval, through: interval.end.addingTimeInterval(-1))
    }

    @Test func separatesMarginTargetAndNetSetAside() throws {
        let (container, book, current, savings, reserve, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        book.budgetingPlanJSON = try plan(food, restaurant, [savings, reserve]).encoded()
        let income = entry(2000, .income, to: current)
        let expense = entry(1600, .expense, from: current, category: food)
        let deposit = entry(300, .transfer, from: current, to: savings)
        let withdrawal = entry(80, .transfer, from: savings, to: current)
        let internalMove = entry(150, .transfer, from: savings, to: reserve)
        let result = report(book, [income, expense, deposit, withdrawal, internalMove, deposit])
        #expect(result.margin == 400)
        #expect(result.netSetAside == 220)
        #expect(book.budgetingPlan?.savingsTarget == 400)
        #expect(result.needsSpent == 1600)
        #expect(result.unclassifiedExpenses == 0)
    }

    @Test func countsDirectSavingsIncomeSpendingAndNegativeNetFlows() throws {
        let (container, book, current, savings, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        book.budgetingPlanJSON = try plan(food, restaurant, [savings]).encoded()
        let result = report(book, [entry(100, .income, to: savings), entry(150, .expense, from: savings),
                                   entry(50, .transfer, from: savings, to: current)])
        #expect(result.netSetAside == -100)
        #expect(result.margin == -50)
        #expect(result.unclassifiedExpenses == 150)
    }

    @Test func excludesOtherBooksOpeningBalancesFutureAndPeriodEnd() throws {
        let (container, book, current, savings, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        book.budgetingPlanJSON = try plan(food, restaurant, [savings]).encoded()
        let outside = Conto(name: "Altro libro", type: .checking)
        let result = MonthlySavingsReport(account: book, transactions: [
            entry(10, .income, to: outside), entry(20, .expense, from: outside),
            entry(30, .income, to: current, at: start.addingTimeInterval(-1)),
            entry(40, .income, to: current, at: interval.end),
            entry(50, .income, to: current, at: start.addingTimeInterval(500))
        ], interval: interval, through: start.addingTimeInterval(100))
        #expect(result.income == 0)
        #expect(result.expenses == 0)
        #expect(result.netSetAside == 0)
        #expect(result.marginRate == nil)
    }

    @Test func noSavingsPerimeterMeansUnknownRatherThanZero() throws {
        let (container, book, current, _, _, _, _) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let result = report(book, [entry(100, .income, to: current)])
        #expect(result.margin == 100)
        #expect(result.netSetAside == nil)
    }

    @Test func crossCurrencyTransferUsesCreditedAmountForSavings() throws {
        let (container, book, _, savings, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        book.budgetingPlanJSON = try plan(food, restaurant, [savings]).encoded()
        let foreign = Conto(name: "USD", type: .checking)
        let transfer = entry(100, .transfer, from: foreign, to: savings)
        transfer.destinationAmount = 90
        #expect(report(book, [transfer]).netSetAside == 90)
        #expect(report(book, [transfer]).income == 0)
    }

    @Test func childOverrideGeneratesDisjointBudgetsAndPreservesManualLimits() throws {
        let (container, book, current, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let manual = Budget(name: "Cibo settimanale", amount: 100, period: .weekly)
        manual.account = book; manual.categories = [food]; container.mainContext.insert(manual)
        try container.mainContext.save()
        try BudgetingPlanEdits(context: container.mainContext).apply(plan(food, restaurant), to: book)
        let generated = try container.mainContext.fetch(FetchDescriptor<Budget>()).filter { $0.planningGroupRaw != nil }
        let needs = try #require(generated.first { $0.planningGroupRaw == "needs" })
        let wants = try #require(generated.first { $0.planningGroupRaw == "wants" })
        #expect(needs.amount == 1000)
        #expect(wants.amount == 600)
        #expect(needs.coveredCategoryIDs == [food.id])
        #expect(wants.coveredCategoryIDs == [restaurant.id])
        #expect(manual.isActive == true)
        #expect(manual.coveredCategoryIDs == [food.id, restaurant.id])
        let spending = entry(30, .expense, from: current, category: restaurant)
        #expect(RecordedBudgetSpending.total(for: needs, transactions: [spending], start: interval.start, end: interval.end) == 0)
        #expect(RecordedBudgetSpending.total(for: wants, transactions: [spending], start: interval.start, end: interval.end) == 30)
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Account>()).first)
        #expect(stored.budgetingPlan == plan(food, restaurant))
    }

    @Test func reapplyingIsIdempotentAndManualModeArchivesOnlyGeneratedLimits() throws {
        let (container, book, _, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let manual = Budget(name: "Manuale", amount: 50, period: .monthly)
        manual.account = book; manual.categories = [food]; container.mainContext.insert(manual)
        let edits = BudgetingPlanEdits(context: container.mainContext)
        try edits.apply(plan(food, restaurant), to: book)
        try edits.apply(plan(food, restaurant), to: book)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Budget>()) == 3)
        try edits.apply(BudgetingPlan(method: .manual), to: book)
        #expect(manual.isActive == true)
        #expect(try container.mainContext.fetch(FetchDescriptor<Budget>()).filter { $0.planningGroupRaw != nil }.allSatisfy { $0.isActive == false })
    }

    @Test func explicitReconciliationArchivesOverlappingManualBudget() throws {
        let (container, book, _, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let manual = Budget(name: "Manuale", amount: 50, period: .monthly)
        manual.account = book; manual.categories = [food]; container.mainContext.insert(manual)
        try BudgetingPlanEdits(context: container.mainContext).apply(plan(food, restaurant), to: book, archiveOverlapping: true)
        #expect(manual.isActive == false)
    }

    @Test func failedSaveRestoresBudgetsPlanAndUnrelatedDraft() throws {
        let (container, book, _, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        try BudgetingPlanEdits(context: context).apply(plan(food, restaurant), to: book)
        let before = book.budgetingPlanJSON
        book.name = "Bozza non correlata"
        var changed = plan(food, restaurant); changed.monthlyIncome = 3000
        #expect(throws: SaveFailure.self) {
            try BudgetingPlanEdits(context: context, save: { throw SaveFailure.unavailable }).apply(changed, to: book)
        }
        #expect(book.name == "Bozza non correlata")
        #expect(book.budgetingPlanJSON == before)
        #expect(try context.fetch(FetchDescriptor<Budget>()).first { $0.planningGroupRaw == "needs" }?.amount == 1000)
        #expect(try context.fetch(FetchDescriptor<Budget>()).allSatisfy { $0.isActive == true })
    }

    @Test func rejectsIncompleteCategoryAssignmentAndInvalidPercentages() throws {
        let (container, book, _, _, _, food, _) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let incomplete = BudgetingPlan(monthlyIncome: 2000, categoryGroups: [:])
        #expect(throws: BudgetingPlanEdits.Failure.self) {
            try BudgetingPlanEdits(context: container.mainContext).apply(incomplete, to: book)
        }
        let inherited = BudgetingPlan(monthlyIncome: 2000, categoryGroups: [food.externalID: .needs])
        try BudgetingPlanEdits(context: container.mainContext).apply(inherited, to: book)
        #expect(book.budgetingPlan == inherited)
        #expect(!BudgetingPlan(method: .custom, monthlyIncome: 2000, needsPercent: 80, wantsPercent: 30).isValid)
        #expect(!BudgetingPlan(monthlyIncome: 2000, needsPercent: 60, wantsPercent: 20).isValid)
        #expect(BudgetingPlan.decode("invalid") == nil)
    }
    @Test func roundedAllocationsAlwaysSumToIncome() {
        let tiny = BudgetingPlan(method: .custom, monthlyIncome: Decimal(string: "0.01")!, needsPercent: 50, wantsPercent: 50)
        #expect(tiny.roundedLimit(for: .needs, currency: "EUR") == Decimal(string: "0.01"))
        #expect(tiny.roundedLimit(for: .wants, currency: "EUR") == 0)
        #expect(tiny.roundedSavingsTarget(currency: "EUR") == 0)
        let ordinary = BudgetingPlan(monthlyIncome: Decimal(string: "2000.03")!)
        #expect(ordinary.roundedLimit(for: .needs, currency: "EUR") + ordinary.roundedLimit(for: .wants, currency: "EUR") + ordinary.roundedSavingsTarget(currency: "EUR") == ordinary.monthlyIncome)
    }

    @Test func missingAmountsDoNotProduceAConfidentReport() throws {
        let (container, book, current, _, _, _, _) = try fixture()
        defer { withExtendedLifetime(container) {} }
        let broken = entry(100, .income, to: current); broken.amount = nil
        #expect(report(book, [broken]).hasInvalidAmounts)
    }

    @Test func failedFirstSaveLeavesNoGeneratedBudgets() throws {
        let (container, book, _, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        #expect(throws: SaveFailure.self) {
            try BudgetingPlanEdits(context: container.mainContext, save: { throw SaveFailure.unavailable }).apply(plan(food, restaurant), to: book)
        }
        #expect(book.budgetingPlanJSON == nil)
        try container.mainContext.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Budget>()) == 0)
    }

    @Test func newChildFollowsPlanWithoutOverlappingOtherGroup() throws {
        let (container, book, _, _, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        try BudgetingPlanEdits(context: container.mainContext).apply(plan(food, restaurant), to: book)
        let new = FinanceCore.Category(name: "Mercato", parentCategoryId: food.id, kind: .expense)
        new.account = book; container.mainContext.insert(new)
        let budgets = try container.mainContext.fetch(FetchDescriptor<Budget>())
        #expect(budgets.first { $0.planningGroupRaw == "needs" }?.coveredCategoryIDs.contains(new.id) == true)
        #expect(budgets.first { $0.planningGroupRaw == "wants" }?.coveredCategoryIDs.contains(new.id) == false)
    }

    @Test func sharedBookRoundTripKeepsPlanAndExactMembershipAcrossLocalIDs() throws {
        let (container, book, current, savings, _, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        try BudgetingPlanEdits(context: container.mainContext).apply(plan(food, restaurant, [savings]), to: book)
        let transfer = entry(300, .transfer, from: current, to: savings)
        container.mainContext.insert(transfer); try container.mainContext.save()
        let snapshot = try SharedBookExporter.export(bookID: book.id, container: container)
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let localID = try SharedBookImporter.apply(scope: SharedBookScope(ownerName: "owner", bookID: book.id), records: snapshot.records, assets: snapshot.assets, container: target)
        let context = ModelContext(target)
        let imported = try #require(context.fetch(FetchDescriptor<Account>()).first)
        #expect(localID != book.id)
        #expect(imported.budgetingPlan == book.budgetingPlan)
        let importedFood = try #require(imported.categories?.first { $0.externalID == food.externalID })
        let importedRestaurant = try #require(imported.categories?.first { $0.externalID == restaurant.externalID })
        let needs = try #require(imported.budgets?.first { $0.planningGroupRaw == "needs" })
        #expect(needs.usesExactCategories == true)
        #expect(needs.coveredCategoryIDs.contains(importedFood.id))
        #expect(!needs.coveredCategoryIDs.contains(importedRestaurant.id))
        let importedEntries = try context.fetch(FetchDescriptor<Transaction>())
        #expect(report(imported, importedEntries).netSetAside == 300)
    }

    @Test func changedSavingsPerimeterDoesNotSilentlyReportPartialSavings() throws {
        let (container, book, current, savings, reserve, food, restaurant) = try fixture()
        defer { withExtendedLifetime(container) {} }
        book.budgetingPlanJSON = try plan(food, restaurant, [savings, reserve]).encoded()
        reserve.type = .checking
        let result = report(book, [entry(100, .transfer, from: current, to: savings)])
        #expect(result.needsSavingsReview)
        #expect(result.netSetAside == nil)
    }

}
