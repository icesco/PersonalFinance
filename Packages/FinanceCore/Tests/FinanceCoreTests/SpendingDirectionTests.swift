import Foundation
import Testing
@testable import FinanceCore

struct SpendingDirectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func oldMovementsNeverProduceASpendableEstimate() {
        let now = date(2026, 9, 20)
        let entries = [DirectionTransaction(
            date: date(2026, 3, 1), amount: 20, type: .expense,
            categoryID: nil, categoryName: "Spesa", isRecurring: false
        )]
        let planned = [PlannedCashMovement(
            date: date(2026, 9, 30), amount: 1500, type: .income, title: "Entrata"
        )]
        let result = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: planned, liquidBalance: 1000,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.availability == .staleData)
        #expect(result.estimatedMargin == nil)
    }

    @Test func threeWeekOldExportIsMarkedIncomplete() {
        let now = date(2026, 9, 27)
        let entries = [DirectionTransaction(
            date: date(2026, 9, 3), amount: 30, type: .expense,
            categoryID: nil, categoryName: "Spesa", isRecurring: false
        )]
        let result = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: [], liquidBalance: 100,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.availability == .staleData)
    }

    @Test func marginDeductsCardDebtAndScheduledBillsButNeverTransfers() {
        let now = date(2026, 9, 20)
        let entries = [
            DirectionTransaction(date: date(2026, 7, 1), amount: 30, type: .expense,
                                 categoryID: nil, categoryName: "Spesa", isRecurring: false),
            DirectionTransaction(date: date(2026, 7, 10), amount: 20, type: .expense,
                                 categoryID: nil, categoryName: "Spesa", isRecurring: false),
            DirectionTransaction(date: date(2026, 8, 5), amount: 40, type: .expense,
                                 categoryID: nil, categoryName: "Spesa", isRecurring: false),
            DirectionTransaction(date: date(2026, 8, 15), amount: 25, type: .expense,
                                 categoryID: nil, categoryName: "Spesa", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 19), amount: 70, type: .expense,
                                 categoryID: nil, categoryName: "Spesa", isRecurring: false)
        ]
        let planned = [
            PlannedCashMovement(date: date(2026, 9, 25), amount: 50, type: .expense, title: "Bolletta"),
            PlannedCashMovement(date: date(2026, 9, 30), amount: 1500, type: .income, title: "Entrata")
        ]
        let base = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: planned, liquidBalance: 1000,
            creditDebt: 100, now: now, calendar: calendar
        )
        let withTransfer = SpendingDirectionCalculator.calculate(
            transactions: entries + [DirectionTransaction(
                date: date(2026, 9, 19), amount: 500, type: .transfer,
                categoryID: nil, categoryName: "Trasferimento", isRecurring: false
            )], planned: planned, liquidBalance: 1000, creditDebt: 100,
            now: now, calendar: calendar
        )
        #expect(base.availability == .ready)
        let unverified = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: planned, liquidBalance: 1000,
            creditDebt: 100, balancesVerified: false, now: now, calendar: calendar
        )
        #expect(unverified.availability == .unverifiedBalances)
        #expect(unverified.estimatedMargin == nil)
        #expect(base.committedOutgoings == 50)
        #expect(base.estimatedMargin == withTransfer.estimatedMargin)
        #expect(base.estimatedMargin! < 850)
    }

    @Test func recurrenceFindsTheNextOccurrenceFromAnOldTemplate() {
        let transaction = Transaction(
            amount: 100, type: .expense, date: date(2025, 1, 1),
            isRecurring: true, recurrenceFrequency: .weekly
        )
        let reference = date(2026, 9, 20)
        let next = transaction.nextRecurrenceDate(after: reference)
        #expect(next != nil)
        #expect(next! > reference)
        #expect(next! <= calendar.date(byAdding: .day, value: 7, to: reference)!)
        #expect(transaction.recurrenceDates(
            after: reference,
            through: calendar.date(byAdding: .day, value: 21, to: reference)!
        ).count == 3)
    }

    @Test func budgetSpentDoesNotIncludeUnrecordedRecurrences() {
        let book = Account(name: "Personale")
        let conto = Conto(name: "Banca", type: .checking)
        conto.account = book
        book.conti = [conto]
        let category = Category(name: "Alimentari")
        category.account = book
        let transaction = Transaction(
            amount: 40, type: .expense, date: Date(),
            isRecurring: true, recurrenceFrequency: .weekly
        )
        transaction.setCategory(category)
        transaction.setFromConto(conto)
        category.transactions = [transaction]
        let budget = Budget(name: "Spesa", amount: 200, period: .monthly)
        budget.account = book
        budget.addCategory(category)
        #expect(budget.currentSpent == 40)
    }

    @Test func categoryShiftNeedsThreePriorMonthsOfEvidence() {
        let now = date(2026, 9, 20)
        let category = UUID()
        let dates = [date(2026, 7, 1), date(2026, 7, 10), date(2026, 7, 20),
                     date(2026, 9, 5), date(2026, 9, 15)]
        let entries = dates.map { day in
            DirectionTransaction(date: day, amount: day < date(2026, 9, 1) ? 10 : 100,
                                 type: .expense, categoryID: category,
                                 categoryName: "Spesa", isRecurring: false)
        }
        let planned = [PlannedCashMovement(date: date(2026, 9, 30), amount: 1000,
                                           type: .income, title: "Entrata")]
        let result = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: planned, liquidBalance: 500,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.shifts.isEmpty)
    }

    @Test func recentActivityRemainsUsefulWithoutPlannedIncome() {
        let now = date(2026, 9, 20)
        let entries = [
            DirectionTransaction(date: date(2026, 9, 19), amount: 200, type: .income,
                                 categoryID: nil, categoryName: "Entrate", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 18), amount: 70, type: .expense,
                                 categoryID: nil, categoryName: "Alimentari", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 17), amount: 20, type: .expense,
                                 categoryID: nil, categoryName: "Trasporti", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 16), amount: 300, type: .transfer,
                                 categoryID: nil, categoryName: "Giroconto", isRecurring: false),
            DirectionTransaction(date: date(2026, 8, 1), amount: 55, type: .expense,
                                 categoryID: nil, categoryName: "Alimentari", isRecurring: false)
        ]
        let result = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: [], liquidBalance: 500,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.estimatedMargin == nil)
        #expect(result.recentIncome == 200)
        #expect(result.recentExpenses == 90)
        #expect(result.previous30DaysExpenses == 55)
        #expect(result.largestOutflows.first?.name == "Alimentari")
        #expect(result.categoryOutflows.reduce(Decimal(0)) { $0 + $1.amount } == 90)
    }

    @Test func categoryIncreaseComparesEqualWindowsWithoutTransfers() {
        let now = date(2026, 9, 20)
        let entries = [
            DirectionTransaction(date: date(2026, 8, 5), amount: 40, type: .expense,
                                 categoryID: nil, categoryName: "Casa", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 18), amount: 100, type: .expense,
                                 categoryID: nil, categoryName: "Casa", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 18), amount: 400, type: .transfer,
                                 categoryID: nil, categoryName: "Casa", isRecurring: false)
        ]
        let result = SpendingDirectionCalculator.calculate(
            transactions: entries, planned: [], liquidBalance: 500,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.categoryIncreases.first?.name == "Casa")
        #expect(result.categoryIncreases.first?.increase == 60)
    }

    @Test func compactCategoryChartKeepsExactTotalAndExcludesTransfers() {
        let now = date(2026, 9, 20)
        let amounts: [Decimal] = [100, 90, 80, 70, 60, 50, 40]
        let expenses = amounts.enumerated().map { index, amount in
            DirectionTransaction(date: date(2026, 9, 19), amount: amount,
                                 type: .expense, categoryID: nil,
                                 categoryName: "Categoria \(index)", isRecurring: false)
        }
        let transfer = DirectionTransaction(date: date(2026, 9, 19), amount: 1_000,
                                            type: .transfer, categoryID: nil,
                                            categoryName: "Giroconto", isRecurring: false)
        let result = SpendingDirectionCalculator.calculate(
            transactions: expenses + [transfer], planned: [], liquidBalance: 0,
            creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.chartOutflows.count == 6)
        #expect(result.chartOutflows.last?.name == "Restanti categorie")
        #expect(result.chartOutflows.last?.amount == 90)
        #expect(result.chartOutflows.reduce(Decimal(0)) { $0 + $1.amount } == result.recentExpenses)
    }

    @Test func transfersCannotEstablishSpendingHistory() {
        let now = date(2026, 9, 20)
        let transfers = (0..<6).map { index in
            DirectionTransaction(
                date: date(2026, index < 3 ? 7 : 9, index < 3 ? 1 + index : 14 + index),
                amount: 100, type: .transfer,
                categoryID: nil, categoryName: "Giroconto", isRecurring: false
            )
        }
        let result = SpendingDirectionCalculator.calculate(
            transactions: transfers,
            planned: [PlannedCashMovement(date: date(2026, 9, 30), amount: 1000,
                                          type: .income, title: "Entrata")],
            liquidBalance: 500, creditDebt: 0, now: now, calendar: calendar
        )
        #expect(result.availability == .sparseSpending)
        #expect(result.estimatedMargin == nil)
    }
}

extension SpendingDirectionTests {
    @Test func recurringAndVariableTotalsExcludeTransfersAndFuturePayments() {
        let now = date(2026, 9, 20)
        let category = UUID()
        let entries = [
            DirectionTransaction(date: date(2026, 9, 5), amount: 100, type: .expense,
                                 categoryID: nil, categoryName: "Abbonamenti", isRecurring: true),
            DirectionTransaction(date: date(2026, 9, 19), amount: 60, type: .expense,
                                 categoryID: category, categoryName: "Ristoranti", isRecurring: false),
            DirectionTransaction(date: date(2026, 9, 19), amount: 500, type: .transfer,
                                 categoryID: nil, categoryName: "Trasferimento", isRecurring: true),
            DirectionTransaction(date: date(2026, 9, 25), amount: 100, type: .expense,
                                 categoryID: nil, categoryName: "Abbonamenti", isRecurring: true)
        ]
        let result = SpendingDirectionCalculator.calculate(transactions: entries, planned: [
            PlannedCashMovement(date: date(2026, 9, 25), amount: 100, type: .expense, title: "Abbonamento"),
            PlannedCashMovement(date: date(2026, 11, 1), amount: 90, type: .expense, title: "Fuori periodo"),
            PlannedCashMovement(date: date(2026, 9, 25), amount: 800, type: .income, title: "Entrata")
        ], liquidBalance: 1000, creditDebt: 0, now: now, calendar: calendar)
        #expect(result.recentRecurringExpenses == 100)
        #expect(result.recentVariableExpenses == 60)
        #expect(result.recentExpenses == 160)
        #expect(result.upcoming30DaysRecurringExpenses == 100)
        #expect(result.largestVariableOutflow?.categoryID == category)
        #expect(result.largestVariableOutflow?.amount == 60)
    }
}
