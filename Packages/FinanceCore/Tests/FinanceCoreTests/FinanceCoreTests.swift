import Testing
import Foundation
import SwiftData
@testable import FinanceCore

struct FinanceCoreTests {
    
    @Test func accountCreation() async throws {
        let account = Account(name: "Test Account", currency: "EUR")
        #expect(account.name == "Test Account")
        #expect(account.currency == "EUR")
        #expect(account.isActive == true)
        #expect(account.totalBalance == 0)
    }
    
    @Test func contoCreation() async throws {
        let conto = Conto(name: "Test Conto", type: .checking, initialBalance: 1000)
        #expect(conto.name == "Test Conto")
        #expect(conto.type == .checking)
        #expect(conto.initialBalance == 1000)
        #expect(conto.balance == 1000)
    }
    
    @Test func transactionCreation() async throws {
        let transaction = Transaction(
            amount: 100,
            type: .expense,
            transactionDescription: "Test expense"
        )
        #expect(transaction.amount == 100)
        #expect(transaction.type == .expense)
        #expect(transaction.displayAmount == -100)
        #expect(transaction.transactionDescription == "Test expense")
    }
    
    @Test func categoryCreation() async throws {
        let category = Category(name: "Food", color: "#FF0000", icon: "cart")
        #expect(category.name == "Food")
        #expect(category.color == "#FF0000")
        #expect(category.icon == "cart")
        #expect(category.isSubcategory == false)
    }
    
    @Test func budgetCreation() async throws {
        let budget = Budget(
            name: "Monthly Food Budget",
            amount: 500,
            period: .monthly,
            alertThreshold: 0.8
        )
        #expect(budget.name == "Monthly Food Budget")
        #expect(budget.amount == 500)
        #expect(budget.period == .monthly)
        #expect(budget.alertThreshold == 0.8)
        #expect(budget.currentSpent == 0)
        #expect(budget.remainingAmount == 500)
        #expect((budget.categories ?? []).isEmpty)
        #expect(budget.includeRecurringTransactions == true)
        
        // Test dynamic period calculation
        let (start, end) = budget.currentPeriodRange
        #expect(start <= Date())
        #expect(end >= Date())
    }
    
    @Test func recurringTransactionCreation() async throws {
        let transaction = Transaction(
            amount: 1200,
            type: .income,
            transactionDescription: "Monthly salary",
            isRecurring: true,
            recurrenceFrequency: .monthly
        )
        #expect(transaction.amount == 1200)
        #expect(transaction.isRecurring == true)
        #expect(transaction.recurrenceFrequency == .monthly)
        #expect(transaction.isRecurrenceActive() == true)
        #expect(transaction.nextRecurrenceDate() != nil)
    }
    
    @Test func recurrenceFrequencyDisplayNames() async throws {
        #expect(RecurrenceFrequency.daily.displayName == "Giornaliera")
        #expect(RecurrenceFrequency.weekly.displayName == "Settimanale")
        #expect(RecurrenceFrequency.monthly.displayName == "Mensile")
        #expect(RecurrenceFrequency.yearly.displayName == "Annuale")
    }
    
    @Test func transferCreation() async throws {
        let fromConto = Conto(name: "Checking", type: .checking, initialBalance: 1000)
        let toConto = Conto(name: "Savings", type: .savings, initialBalance: 500)

        let transfer = Transaction.createTransfer(
            amount: 200,
            fromConto: fromConto,
            toConto: toConto,
            transactionDescription: "Transfer to savings"
        )

        #expect(transfer.amount == 200)
        #expect(transfer.type == .transfer)
        #expect(transfer.fromConto === fromConto)
        #expect(transfer.toConto === toConto)
        #expect(transfer.fromContoId == fromConto.id)
        #expect(transfer.toContoId == toConto.id)

        // Test display amount from different perspectives
        #expect(transfer.displayAmount(for: fromConto.id) == -200)  // Money leaving
        #expect(transfer.displayAmount(for: toConto.id) == 200)     // Money entering
    }

    // MARK: - Balance Calculation Tests

    @Test func contoBalanceWithTransactions() async throws {
        let conto = Conto(name: "Checking", type: .checking, initialBalance: 1000)

        // Add income
        let income = Transaction(amount: 500, type: .income, transactionDescription: "Salary")
        income.setToConto(conto)

        // Add expense
        let expense = Transaction(amount: 100, type: .expense, transactionDescription: "Groceries")
        expense.setFromConto(conto)

        // Balance should be: 1000 (initial) + 500 (income) - 100 (expense) = 1400
        #expect(conto.balance == 1400)
    }

    @Test func contoBalanceWithMultipleTransactions() async throws {
        let conto = Conto(name: "Checking", type: .checking, initialBalance: 0)

        // Multiple incomes
        let income1 = Transaction(amount: 1000, type: .income)
        income1.setToConto(conto)

        let income2 = Transaction(amount: 500, type: .income)
        income2.setToConto(conto)

        // Multiple expenses
        let expense1 = Transaction(amount: 200, type: .expense)
        expense1.setFromConto(conto)

        let expense2 = Transaction(amount: 150, type: .expense)
        expense2.setFromConto(conto)

        // Balance: 0 + 1000 + 500 - 200 - 150 = 1150
        #expect(conto.balance == 1150)
    }

    @Test func accountTotalBalanceWithMultipleConti() async throws {
        let account = Account(name: "Main Account", currency: "EUR")

        let checking = Conto(name: "Checking", type: .checking, initialBalance: 1000)
        checking.account = account

        let savings = Conto(name: "Savings", type: .savings, initialBalance: 5000)
        savings.account = account

        let credit = Conto(name: "Credit Card", type: .credit, initialBalance: -500)
        credit.account = account

        account.conti = [checking, savings, credit]

        // Total: 1000 + 5000 + (-500) = 5500
        #expect(account.totalBalance == 5500)
    }

    @Test func transferAffectsContoBalances() async throws {
        let checking = Conto(name: "Checking", type: .checking, initialBalance: 1000)
        let savings = Conto(name: "Savings", type: .savings, initialBalance: 500)

        let transfer = Transaction.createTransfer(
            amount: 300,
            fromConto: checking,
            toConto: savings,
            transactionDescription: "Save money"
        )

        // Checking: 1000 - 300 = 700
        #expect(checking.balance == 700)

        // Savings: 500 + 300 = 800
        #expect(savings.balance == 800)
    }

    // MARK: - Transaction Type Tests

    @Test func incomeDisplayAmount() async throws {
        let income = Transaction(amount: 100, type: .income)
        #expect(income.displayAmount == 100)
    }

    @Test func expenseDisplayAmount() async throws {
        let expense = Transaction(amount: 100, type: .expense)
        #expect(expense.displayAmount == -100)
    }

    @Test func transactionTypeDisplayNames() async throws {
        #expect(TransactionType.income.displayName == "Entrata")
        #expect(TransactionType.expense.displayName == "Spesa")
        #expect(TransactionType.transfer.displayName == "Trasferimento")
    }

    // MARK: - Recurring Transaction Tests

    @Test func recurringTransactionNextDate() async throws {
        let calendar = Calendar.current
        let startDate = Date()

        let transaction = Transaction(
            amount: 100,
            type: .expense,
            date: startDate,
            isRecurring: true,
            recurrenceFrequency: .weekly
        )

        let nextDate = transaction.nextRecurrenceDate()
        #expect(nextDate != nil)

        if let next = nextDate {
            let daysDifference = calendar.dateComponents([.day], from: startDate, to: next).day
            #expect(daysDifference == 7)
        }
    }

    @Test func recurringTransactionGenerateDates() async throws {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .month, value: 3, to: startDate)!

        let transaction = Transaction(
            amount: 1200,
            type: .income,
            date: startDate,
            isRecurring: true,
            recurrenceFrequency: .monthly
        )

        let dates = transaction.generateRecurrenceDates(until: endDate)

        // Should generate approximately 3 monthly occurrences
        #expect(dates.count >= 2)
        #expect(dates.count <= 3)
    }

    @Test func recurringTransactionWithEndDate() async throws {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .month, value: 2, to: startDate)!

        let transaction = Transaction(
            amount: 100,
            type: .expense,
            date: startDate,
            isRecurring: true,
            recurrenceFrequency: .monthly,
            recurrenceEndDate: endDate
        )

        #expect(transaction.isRecurrenceActive() == true)

        // Transaction with end date in the past should not be active
        let pastDate = calendar.date(byAdding: .year, value: -1, to: Date())!
        let expiredTransaction = Transaction(
            amount: 100,
            type: .expense,
            date: startDate,
            isRecurring: true,
            recurrenceFrequency: .monthly,
            recurrenceEndDate: pastDate
        )

        #expect(expiredTransaction.isRecurrenceActive() == false)
    }

    @Test func allRecurrenceFrequencies() async throws {
        #expect(RecurrenceFrequency.daily.displayName == "Giornaliera")
        #expect(RecurrenceFrequency.weekly.displayName == "Settimanale")
        #expect(RecurrenceFrequency.biweekly.displayName == "Ogni 2 settimane")
        #expect(RecurrenceFrequency.monthly.displayName == "Mensile")
        #expect(RecurrenceFrequency.quarterly.displayName == "Trimestrale")
        #expect(RecurrenceFrequency.semiannually.displayName == "Semestrale")
        #expect(RecurrenceFrequency.yearly.displayName == "Annuale")
    }

    // MARK: - Budget Tests

    @Test func budgetPeriodRanges() async throws {
        let budget = Budget(
            name: "Monthly Budget",
            amount: 1000,
            period: .monthly
        )

        let (start, end) = budget.currentPeriodRange
        #expect(start <= Date())
        #expect(end >= Date())

        // Test that range is approximately one month
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: start, to: end)
        #expect(components.day ?? 0 >= 27) // At least 27 days
        #expect(components.day ?? 0 <= 32) // At most 32 days
    }

    @Test func budgetPeriodDisplayNames() async throws {
        #expect(BudgetPeriod.weekly.displayName == "Settimanale")
        #expect(BudgetPeriod.monthly.displayName == "Mensile")
        #expect(BudgetPeriod.quarterly.displayName == "Trimestrale")
        #expect(BudgetPeriod.yearly.displayName == "Annuale")
    }

    @Test func budgetCategoryManagement() async throws {
        let budget = Budget(name: "Food Budget", amount: 500, period: .monthly)
        let category1 = Category(name: "Groceries", color: "#FF0000", icon: "cart")
        let category2 = Category(name: "Restaurants", color: "#00FF00", icon: "fork.knife")

        budget.addCategory(category1)
        budget.addCategory(category2)

        #expect(budget.categories?.count == 2)
        #expect(budget.categories?.contains(where: { $0.id == category1.id }) == true)
        #expect(budget.categories?.contains(where: { $0.id == category2.id }) == true)

        // Adding same category again should not duplicate
        budget.addCategory(category1)
        #expect(budget.categories?.count == 2)

        // Remove category
        budget.removeCategory(category1)
        #expect(budget.categories?.count == 1)
        #expect(budget.categories?.contains(where: { $0.id == category1.id }) == false)
    }

    @Test func budgetDaysRemaining() async throws {
        let budget = Budget(name: "Weekly Budget", amount: 200, period: .weekly)
        let daysRemaining = budget.daysRemaining

        // Should be between 0 and 7 for a weekly budget
        #expect(daysRemaining >= 0)
        #expect(daysRemaining <= 7)
    }

    @Test func budgetPeriodProgress() async throws {
        let budget = Budget(name: "Monthly Budget", amount: 1000, period: .monthly)
        let progress = budget.periodProgressPercentage

        // Should be between 0 and 1
        #expect(progress >= 0.0)
        #expect(progress <= 1.0)
    }

    // MARK: - ContoType Tests

    @Test func contoTypeDisplayNames() async throws {
        #expect(ContoType.checking.displayName == "Conto Corrente")
        #expect(ContoType.savings.displayName == "Conto Risparmio")
        #expect(ContoType.credit.displayName == "Carta di Credito")
        #expect(ContoType.investment.displayName == "Investimenti")
        #expect(ContoType.cash.displayName == "Contanti")
        #expect(ContoType.other.displayName == "Altro")
    }

    @Test func contoTypeIcons() async throws {
        #expect(ContoType.checking.icon == "creditcard")
        #expect(ContoType.savings.icon == "banknote")
        #expect(ContoType.credit.icon == "creditcard.fill")
        #expect(ContoType.investment.icon == "chart.line.uptrend.xyaxis")
        #expect(ContoType.cash.icon == "dollarsign.circle")
        #expect(ContoType.other.icon == "questionmark.circle")
    }

    // MARK: - Relationship Tests

    @Test func accountContoRelationship() async throws {
        let account = Account(name: "Test Account", currency: "EUR")
        let conto = Conto(name: "Checking", type: .checking, initialBalance: 1000)

        conto.account = account
        account.conti = [conto]

        #expect(conto.account === account)
        #expect(account.conti?.count == 1)
        #expect(account.conti?.first === conto)
    }

    @Test func contoTransactionRelationship() async throws {
        let conto = Conto(name: "Checking", type: .checking, initialBalance: 1000)

        let income = Transaction(amount: 500, type: .income)
        income.setToConto(conto)

        let expense = Transaction(amount: 100, type: .expense)
        expense.setFromConto(conto)

        #expect(income.toConto === conto)
        #expect(income.toContoId == conto.id)
        #expect(expense.fromConto === conto)
        #expect(expense.fromContoId == conto.id)
    }

    @Test func categoryTransactionRelationship() async throws {
        let category = Category(name: "Food", color: "#FF0000", icon: "cart")
        let transaction = Transaction(amount: 50, type: .expense)

        transaction.setCategory(category)

        #expect(transaction.category === category)
        #expect(transaction.categoryId == category.id)
    }

    // MARK: - Edge Cases

    @Test func contoWithZeroInitialBalance() async throws {
        let conto = Conto(name: "New Account", type: .checking, initialBalance: 0)
        #expect(conto.balance == 0)

        let income = Transaction(amount: 100, type: .income)
        income.setToConto(conto)

        #expect(conto.balance == 100)
    }

    @Test func contoWithNegativeInitialBalance() async throws {
        // Credit card starting with debt
        let creditCard = Conto(name: "Credit Card", type: .credit, initialBalance: -500)
        #expect(creditCard.balance == -500)

        // Payment reduces debt
        let payment = Transaction(amount: 200, type: .income)
        payment.setToConto(creditCard)

        #expect(creditCard.balance == -300)
    }

    @Test func transactionWithZeroAmount() async throws {
        let transaction = Transaction(amount: 0, type: .expense)
        #expect(transaction.amount == 0)
        #expect(transaction.displayAmount == 0)
    }

    @Test func accountWithNoConti() async throws {
        let account = Account(name: "Empty Account", currency: "EUR")
        #expect(account.totalBalance == 0)
        #expect(account.activeConti.isEmpty)
    }

    @Test func accountActiveContiFilter() async throws {
        let account = Account(name: "Test Account", currency: "EUR")

        let active = Conto(name: "Active", type: .checking, initialBalance: 100)
        active.isActive = true
        active.account = account

        let inactive = Conto(name: "Inactive", type: .savings, initialBalance: 200)
        inactive.isActive = false
        inactive.account = account

        account.conti = [active, inactive]

        #expect(account.activeConti.count == 1)
        #expect(account.activeConti.first?.name == "Active")
    }

    @Test func budgetAlertThresholdClamping() async throws {
        // Test that alert threshold is clamped between 0 and 1
        let budget1 = Budget(name: "Test", amount: 100, period: .monthly, alertThreshold: 1.5)
        #expect(budget1.alertThreshold == 1.0)

        let budget2 = Budget(name: "Test", amount: 100, period: .monthly, alertThreshold: -0.5)
        #expect(budget2.alertThreshold == 0.0)

        let budget3 = Budget(name: "Test", amount: 100, period: .monthly, alertThreshold: 0.8)
        #expect(budget3.alertThreshold == 0.8)
    }

    @Test func contoAllTransactionsSorted() async throws {
        let conto = Conto(name: "Checking", type: .checking, initialBalance: 1000)

        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!

        let transaction1 = Transaction(amount: 100, type: .expense, date: lastWeek)
        transaction1.setFromConto(conto)

        let transaction2 = Transaction(amount: 200, type: .income, date: today)
        transaction2.setToConto(conto)

        let transaction3 = Transaction(amount: 50, type: .expense, date: yesterday)
        transaction3.setFromConto(conto)

        let allTransactions = conto.allTransactions

        // Should be sorted by date descending (newest first)
        #expect(allTransactions.count == 3)
        #expect(allTransactions[0].date >= allTransactions[1].date)
        #expect(allTransactions[1].date >= allTransactions[2].date)
    }

    // MARK: - Category Tests

    @Test func subcategoryCreation() async throws {
        let parent = Category(name: "Food", color: "#FF0000", icon: "cart")
        let child = Category(name: "Groceries", color: "#FF0000", icon: "cart", parentCategoryId: parent.id)

        #expect(child.isSubcategory == true)
        #expect(child.parentCategoryId == parent.id)
    }

    @Test func categoryWithMultipleTransactions() async throws {
        let category = Category(name: "Food", color: "#FF0000", icon: "cart")

        let transaction1 = Transaction(amount: 50, type: .expense)
        transaction1.setCategory(category)

        let transaction2 = Transaction(amount: 75, type: .expense)
        transaction2.setCategory(category)

        category.transactions = [transaction1, transaction2]

        #expect(category.transactions?.count == 2)
    }

    // MARK: - SavingsGoal Tests

    @Test func savingsGoalCreation() async throws {
        let goal = SavingsGoal(
            name: "Emergency Fund",
            targetAmount: 5000,
            category: .emergency,
            goalDescription: "Save for emergencies"
        )

        #expect(goal.name == "Emergency Fund")
        #expect(goal.targetAmount == 5000)
        #expect(goal.currentAmount == 0)
        #expect(goal.category == .emergency)
        #expect(goal.status == .active)
        #expect(goal.isActive == true)
        #expect(goal.isCompleted == false)
        #expect(goal.progressPercentage == 0.0)
        #expect(goal.remainingAmount == 5000)
    }

    @Test func savingsGoalProgress() async throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 2000,
            category: .vacation
        )

        goal.addProgress(amount: 500)
        #expect(goal.currentAmount == 500)
        #expect(goal.remainingAmount == 1500)
        #expect(goal.progressPercentage == 25.0)
        #expect(goal.isCompleted == false)
        #expect(goal.status == .active)

        goal.addProgress(amount: 1500)
        #expect(goal.currentAmount == 2000)
        #expect(goal.remainingAmount == 0)
        #expect(goal.progressPercentage == 100.0)
        #expect(goal.isCompleted == true)
        #expect(goal.status == .completed) // Should auto-complete
    }

    @Test func savingsGoalOverfunded() async throws {
        let goal = SavingsGoal(
            name: "Car",
            targetAmount: 10000,
            category: .car
        )

        goal.addProgress(amount: 12000)

        #expect(goal.currentAmount == 12000)
        #expect(goal.remainingAmount == 0) // Should not go negative
        #expect(goal.progressPercentage == 100.0) // Capped at 100%
        #expect(goal.isCompleted == true)
    }

    @Test func savingsGoalWithTargetDate() async throws {
        let calendar = Calendar.current
        let futureDate = calendar.date(byAdding: .month, value: 6, to: Date())!

        let goal = SavingsGoal(
            name: "Home Down Payment",
            targetAmount: 50000,
            targetDate: futureDate,
            category: .home
        )

        let daysUntilTarget = goal.daysUntilTarget
        #expect(daysUntilTarget != nil)
        #expect(daysUntilTarget! > 0)
        #expect(daysUntilTarget! <= 200) // Approximately 6 months
    }

    @Test func savingsGoalCategoryDisplayNames() async throws {
        #expect(SavingsGoalCategory.emergency.displayName == "Fondo di Emergenza")
        #expect(SavingsGoalCategory.vacation.displayName == "Vacanze")
        #expect(SavingsGoalCategory.home.displayName == "Casa")
        #expect(SavingsGoalCategory.car.displayName == "Auto")
        #expect(SavingsGoalCategory.education.displayName == "Educazione")
        #expect(SavingsGoalCategory.retirement.displayName == "Pensione")
        #expect(SavingsGoalCategory.other.displayName == "Altro")
    }

    @Test func savingsGoalStatusDisplayNames() async throws {
        #expect(SavingsGoalStatus.active.displayName == "Attivo")
        #expect(SavingsGoalStatus.completed.displayName == "Completato")
        #expect(SavingsGoalStatus.paused.displayName == "In Pausa")
    }

    @Test func savingsGoalCategoryIcons() async throws {
        #expect(SavingsGoalCategory.emergency.icon == "shield.fill")
        #expect(SavingsGoalCategory.vacation.icon == "airplane")
        #expect(SavingsGoalCategory.home.icon == "house.fill")
        #expect(SavingsGoalCategory.car.icon == "car.fill")
        #expect(SavingsGoalCategory.education.icon == "graduationcap.fill")
        #expect(SavingsGoalCategory.retirement.icon == "clock.fill")
        #expect(SavingsGoalCategory.other.icon == "target")
    }

    @Test func savingsGoalMultipleProgressUpdates() async throws {
        let goal = SavingsGoal(
            name: "Tech Gadget",
            targetAmount: 1000,
            category: .other
        )

        goal.addProgress(amount: 100)
        goal.addProgress(amount: 200)
        goal.addProgress(amount: 300)

        #expect(goal.currentAmount == 600)
        #expect(goal.progressPercentage == 60.0)
        #expect(goal.remainingAmount == 400)
    }
}