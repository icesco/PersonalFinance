import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct RecordedBudgetSpendingTests {
    @Test func allBudgetPeriodsAreAdjacentAndKeepTheFinalFractionOfASecond() {
        for period in [BudgetPeriod.weekly, .monthly, .quarterly, .yearly] {
            let budget = Budget(name: "Budget", amount: 100, period: period)
            let current = budget.currentPeriodRange
            let previous = budget.previousPeriodRange
            #expect(previous.end == current.start)
            #expect(previous.start < previous.end)
            #expect(current.start < current.end)
            let expected = period.interval(containing: current.start.addingTimeInterval(-0.5))
            #expect(expected?.start == previous.start)
            #expect(expected?.end == previous.end)
        }
    }

    @Test func detailQueryAndPreviewAgreeOnBookScopeLegacyEntriesAndBoundaries() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Budget book")
        let other = Account(name: "Other book")
        context.insert(book); context.insert(other)
        let conto = Conto(name: "Current", type: .checking)
        conto.account = book; context.insert(conto)
        let foreignConto = Conto(name: "Other", type: .checking)
        foreignConto.account = other; context.insert(foreignConto)
        let category = FinanceCore.Category(name: "Food")
        category.account = book; context.insert(category)
        let budget = Budget(name: "Food", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]; context.insert(budget)
        let range = budget.currentPeriodRange
        func entry(_ amount: Decimal, _ date: Date, foreign: Bool = false,
                   type: TransactionType = .expense) -> Transaction {
            let value = Transaction(amount: amount, type: type, date: date)
            value.setCategory(category)
            value.setFromConto(foreign ? foreignConto : conto)
            context.insert(value)
            return value
        }
        let first = entry(10, range.start)
        let last = entry(20, range.end.addingTimeInterval(-0.001))
        let next = entry(100, range.end)
        let before = entry(100, range.start.addingTimeInterval(-0.001))
        let foreign = entry(100, range.start, foreign: true)
        let income = entry(100, range.start, type: .income)
        let transfer = entry(100, range.start, type: .transfer)
        try context.save()
        // Older entries can have valid relationships but no denormalized IDs.
        first.categoryId = nil; first.fromContoId = nil
        try context.save()
        let transactions = [first, last, next, before, foreign, income, transfer]
        let expenses = budget.recordedExpenses(for: range, transactions: transactions + [first, last])
        #expect(expenses.map(\.id) == [last.id, first.id])
        let overlapping = Budget(name: "All food", amount: 200, period: .quarterly)
        overlapping.account = book; overlapping.categories = [category]; context.insert(overlapping)
        let combined = BudgetService.recordedExpenses(for: [budget, overlapping], period: range, transactions: transactions)
        #expect(combined.map(\.id) == [last.id, first.id])
        #expect(combined.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) } == 30)
        #expect(BudgetService.recordedExpenses(for: [], period: range, transactions: transactions).isEmpty)
        #expect(BudgetService.recordedExpenses(for: [budget], period: budget.previousPeriodRange,
                                             transactions: transactions).map(\.id) == [before.id])
        #expect(expenses.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
                == (try BudgetService.currentSpent(for: budget, in: context)))
        #expect(try BudgetService.currentSpent(for: budget, in: context) == 30)
        #expect(budget.currentSpent == 30)
        let preview = try #require(BudgetService.previewExpense(
            amount: 5, categoryID: category.id, accountID: book.id,
            date: range.start, budgets: [budget], transactions: transactions
        ).first)
        #expect(preview.spent == 30)
        #expect(preview.remaining == 65)
        #expect(RecordedBudgetSpending.total(for: budget, transactions: transactions + [first, last],
                                           start: range.start, end: range.end) == 30)
        #expect(try BudgetService.previousPeriodSpent(for: budget, in: context) == 100)
        #expect(budget.previousPeriodSpent == 100)
    }

    @Test func expenseListIncludesChildrenAndRecordedRecurrencesButRespectsExactMembership() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Book")
        context.insert(book)
        let conto = Conto(name: "Current", type: .checking)
        conto.account = book; context.insert(conto)
        let parent = FinanceCore.Category(name: "Food")
        parent.account = book; context.insert(parent)
        let child = FinanceCore.Category(name: "Groceries")
        child.account = book; child.parentCategoryId = parent.id; context.insert(child)
        let budget = Budget(name: "Food", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [parent]; context.insert(budget)
        let range = budget.currentPeriodRange
        let recurring = Transaction(amount: 120, type: .expense, date: range.end.addingTimeInterval(-1))
        recurring.setFromConto(conto); recurring.setCategory(child)
        recurring.isRecurring = true
        context.insert(recurring)
        try context.save()

        #expect(budget.recordedExpenses(for: range, transactions: [recurring]).map(\.id) == [recurring.id])
        #expect(try BudgetService.currentSpent(for: budget, in: context) == 120)
        budget.usesExactCategories = true
        #expect(budget.recordedExpenses(for: range, transactions: [recurring]).isEmpty)
        budget.categories = [child]
        #expect(budget.recordedExpenses(for: range, transactions: [recurring]).count == 1)
    }
}
