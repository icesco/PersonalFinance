import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct TransactionListQueryTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func quarter(_ number: Int) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: 2026, month: (number - 1) * 3 + 1, day: 1))!
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 3, to: start)!)
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let bank: Conto
        let card: Conto
        let other: Conto
        let food: FinanceCore.Category
        let salary: FinanceCore.Category
        var context: ModelContext { container.mainContext }
    }

    private func fixture() throws -> Fixture {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Book")
        let bank = Conto(name: "Bank", type: .checking, initialBalance: 0)
        let card = Conto(name: "Card", type: .credit, initialBalance: 0)
        let other = Conto(name: "Other book", type: .checking, initialBalance: 0)
        bank.account = book; card.account = book
        let food = FinanceCore.Category(name: "Food")
        let salary = FinanceCore.Category(name: "Salary")
        context.insert(book); context.insert(bank); context.insert(card); context.insert(other)
        context.insert(food); context.insert(salary)
        try context.save()
        return Fixture(container: container, bank: bank, card: card, other: other, food: food, salary: salary)
    }

    @discardableResult
    private func add(_ f: Fixture, _ amount: Decimal, _ type: TransactionType, _ date: Date,
                     from: Conto? = nil, to: Conto? = nil, category: FinanceCore.Category? = nil) -> Transaction {
        let transaction = Transaction(amount: amount, type: type, date: date)
        transaction.setFromConto(from); transaction.setToConto(to); transaction.setCategory(category)
        f.context.insert(transaction)
        return transaction
    }

    @Test func quarterReturnsOnlyItsOwnTransactions() throws {
        let f = try fixture()
        add(f, 10, .expense, day(6, 30), from: f.bank)
        let july = add(f, 20, .expense, day(7, 1), from: f.bank)
        let september = add(f, 30, .expense, day(9, 30), from: f.bank)
        add(f, 40, .expense, day(10, 1), from: f.bank)
        try f.context.save()

        let query = TransactionListQuery(interval: quarter(3), contoIDs: [f.bank.id])
        let page = try query.fetchPage(in: f.context, offset: 0, limit: 50)
        #expect(page.map(\.id) == [september.id, july.id])
        #expect(try query.summary(in: f.context) == TransactionListSummary(count: 2, expenses: 50))
    }

    @Test func pagesAreDisjointAndCoverTheWholePeriod() throws {
        let f = try fixture()
        // Same timestamp for every row: only the tie-breaker keeps pages stable.
        for index in 0..<25 { add(f, Decimal(index + 1), .expense, day(8, 15), from: f.bank) }
        try f.context.save()

        let query = TransactionListQuery(interval: quarter(3), contoIDs: [f.bank.id])
        var loaded: [UUID] = []
        while true {
            let page = try query.fetchPage(in: f.context, offset: loaded.count, limit: 10)
            if page.isEmpty { break }
            loaded += page.map(\.id)
        }
        #expect(loaded.count == 25)
        #expect(Set(loaded).count == 25)
        #expect(try query.summary(in: f.context).count == 25)
    }

    @Test func filtersByContoTypeAndCategoryInTheStore() throws {
        let f = try fixture()
        let lunch = add(f, 12, .expense, day(8, 1), from: f.bank, category: f.food)
        let pay = add(f, 2000, .income, day(8, 2), to: f.bank, category: f.salary)
        let transfer = add(f, 100, .transfer, day(8, 3), from: f.card, to: f.bank)
        add(f, 99, .expense, day(8, 4), from: f.other, category: f.food)
        add(f, 5, .expense, day(8, 5))
        try f.context.save()

        let all = TransactionListQuery(interval: quarter(3), contoIDs: [f.bank.id, f.card.id])
        #expect(Set(try all.fetchPage(in: f.context, offset: 0, limit: 50).map(\.id)) == [lunch.id, pay.id, transfer.id])
        #expect(try all.summary(in: f.context) == TransactionListSummary(count: 3, income: 2000, expenses: 12))

        let cardOnly = TransactionListQuery(interval: quarter(3), contoIDs: [f.card.id])
        #expect(try cardOnly.fetchPage(in: f.context, offset: 0, limit: 50).map(\.id) == [transfer.id])

        let incomes = TransactionListQuery(interval: quarter(3), contoIDs: [f.bank.id], type: .income)
        #expect(try incomes.fetchPage(in: f.context, offset: 0, limit: 50).map(\.id) == [pay.id])

        let food = TransactionListQuery(interval: quarter(3), contoIDs: [f.bank.id, f.card.id], categoryIDs: [f.food.id])
        #expect(try food.fetchPage(in: f.context, offset: 0, limit: 50).map(\.id) == [lunch.id])
    }

    @Test func emptyScopeMatchesNothing() throws {
        let f = try fixture()
        add(f, 10, .expense, day(8, 1), from: f.bank)
        try f.context.save()
        let query = TransactionListQuery(interval: quarter(3), contoIDs: [])
        #expect(try query.fetchPage(in: f.context, offset: 0, limit: 10).isEmpty)
        #expect(try query.summary(in: f.context) == TransactionListSummary())
    }
}
