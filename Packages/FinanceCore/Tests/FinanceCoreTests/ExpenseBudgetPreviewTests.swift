import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct ExpenseBudgetPreviewTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ month: Int, _ day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test func assessesAllMatchingBudgetsWithoutMutatingThem() {
        let account = Account(name: "Personale")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 1000)
        conto.account = account
        account.conti = [conto]
        let food = Category(name: "Cibo", color: "green", icon: "cart")
        let home = Category(name: "Casa", color: "blue", icon: "house")
        let monthly = Budget(name: "Spese", amount: 100, period: .monthly)
        monthly.account = account
        monthly.categories = [food, home]
        let annual = Budget(name: "Annuale", amount: 1000, period: .yearly)
        annual.account = account
        annual.categories = [food]
        let expense = Transaction(amount: 70, type: .expense, date: date(10))
        expense.setCategory(home)
        expense.setFromConto(conto)
        let transfer = Transaction(amount: 500, type: .transfer, date: date(10))
        transfer.setCategory(food)
        transfer.setFromConto(conto)
        let previews = BudgetService.previewExpense(
            amount: 40, categoryID: food.id, accountID: account.id, date: date(10),
            budgets: [monthly, annual], transactions: [expense, transfer], calendar: calendar)
        #expect(previews.count == 2)
        #expect(previews[0].remaining == -10)
        #expect(previews[0].status == .overLimit)
        #expect(previews[1].remaining == 960)
        #expect(previews[1].status == .withinLimit)
        #expect(expense.amount == 70)
        #expect(monthly.amount == 100)
    }

    @Test func editingReplacesOriginalAmountAndUsesNewCategoryAndPeriod() {
        let account = Account(name: "Personale")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = account; account.conti = [conto]
        let food = Category(name: "Cibo", color: "green", icon: "cart")
        let home = Category(name: "Casa", color: "blue", icon: "house")
        let budget = Budget(name: "Mensile", amount: 100, period: .monthly)
        budget.account = account; budget.categories = [food, home]
        let original = Transaction(amount: 60, type: .expense, date: date(10))
        original.setFromConto(conto); original.setCategory(food)
        let other = Transaction(amount: 30, type: .expense, date: date(10))
        other.setFromConto(conto); other.setCategory(home)
        let transactions = [original, other]
        func preview(_ amount: Decimal, month: Int = 10, categoryID: UUID) -> ExpenseBudgetPreview? {
            BudgetService.previewExpense(amount: amount, categoryID: categoryID, accountID: account.id,
                date: date(month), budgets: [budget], transactions: transactions, calendar: calendar,
                excludingTransactionID: original.id).first
        }
        #expect(preview(20, categoryID: food.id)?.spent == 30)
        #expect(preview(20, categoryID: food.id)?.remaining == 50)
        #expect(preview(80, categoryID: food.id)?.remaining == -10)
        #expect(preview(80, categoryID: food.id)?.status == .overLimit)
        #expect(preview(20, categoryID: home.id)?.remaining == 50)
        #expect(preview(20, month: 11, categoryID: home.id)?.remaining == 80)
        #expect(original.amount == 60 && original.categoryId == food.id && original.date == date(10))
    }

    @Test func handlesThresholdExactLimitAndAlreadyExceededBudget() {
        let account = Account(name: "Personale")
        let category = Category(name: "Cibo", color: "green", icon: "cart")
        let budget = Budget(name: "Cibo", amount: 100, period: .monthly, alertThreshold: 0.8)
        budget.account = account
        budget.categories = [category]
        func result(_ amount: Decimal) -> ExpenseBudgetPreview? {
            BudgetService.previewExpense(amount: amount, categoryID: category.id, accountID: account.id,
                date: date(10), budgets: [budget], transactions: [], calendar: calendar).first
        }
        #expect(result(79)?.status == .withinLimit)
        #expect(result(80)?.status == .approachingLimit)
        #expect(result(100)?.status == .atLimit)
        #expect(result(110)?.remaining == -10)
        #expect(result(0) == nil)
        budget.amount = 0
        #expect(result(1)?.status == .overLimit)
        budget.isActive = false
        #expect(result(40) == nil)
    }

    @Test func usesDraftDateAndOnlyTheSelectedBook() {
        let account = Account(name: "Personale")
        let other = Account(name: "Altro")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = account
        account.conti = [conto]
        let category = Category(name: "Cibo", color: "green", icon: "cart")
        let budget = Budget(name: "Mensile", amount: 100, period: .monthly)
        budget.account = account
        budget.categories = [category]
        let expense = Transaction(amount: 90, type: .expense, date: date(10), isRecurring: true, recurrenceFrequency: .monthly)
        expense.setCategory(category)
        expense.setFromConto(conto)
        let nextMonth = BudgetService.previewExpense(amount: 30, categoryID: category.id, accountID: account.id,
            date: date(11), budgets: [budget], transactions: [expense], calendar: calendar)
        #expect(nextMonth.first?.remaining == 70) // No invented recurrence in November.
        #expect(BudgetService.previewExpense(amount: 30, categoryID: category.id, accountID: other.id,
            date: date(10), budgets: [budget], transactions: [expense], calendar: calendar).isEmpty)
        #expect(BudgetService.previewExpense(amount: 30, categoryID: UUID(), accountID: account.id,
            date: date(10), budgets: [budget], transactions: [expense], calendar: calendar).isEmpty)
    }
}
