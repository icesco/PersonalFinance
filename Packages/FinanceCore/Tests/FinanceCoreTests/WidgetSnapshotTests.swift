import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct WidgetSnapshotTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    @Test func separatesBooksAndCountsRecordedExpensesInArchivedAccounts() throws {
        let euro = Account(name: "Euro", currency: "EUR")
        let dollar = Account(name: "Dollari", currency: "USD")
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 0)
        bank.account = euro; bank.isActive = false; euro.conti = [bank]
        let other = Conto(name: "Altro", type: .checking, initialBalance: 0)
        other.account = dollar; dollar.conti = [other]
        let category = Category(name: "Spese", color: "green", icon: "cart")
        let budget = Budget(name: "Mensile", amount: 100, period: .monthly)
        budget.account = euro; budget.categories = [category]
        func transaction(_ amount: Decimal, _ conto: Conto, _ day: Int, type: TransactionType = .expense) -> Transaction {
            let t = Transaction(amount: amount, type: type, date: date(day))
            t.setFromConto(conto); t.setCategory(category)
            return t
        }
        let values = [transaction(125, bank, 2), transaction(20, other, 2), transaction(90, bank, 20), transaction(500, bank, 3, type: .transfer)]
        values[0].fromContoId = nil
        values[0].categoryId = nil
        let snapshot = FinanceWidgetBuilder.build(accounts: [euro, dollar], budgets: [budget], transactions: values, resolutions: [], now: date(5), calendar: calendar)
        let euroResult = try #require(snapshot.books.first { $0.id == euro.id })
        #expect(euroResult.monthSpent == 125)
        #expect(euroResult.budget?.remaining == -25)
        #expect(snapshot.books.first { $0.id == dollar.id }?.monthSpent == 20)
        #expect(!snapshot.usable(at: snapshot.validUntil))
    }

    @Test func resolvedOccurrencesDisappearAndFutureSeedIsCountedOnce() throws {
        let book = Account(name: "Libro")
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 0)
        bank.account = book; book.conti = [bank]
        let source = Transaction(amount: 20, type: .expense, date: date(6), isRecurring: true, recurrenceFrequency: .weekly)
        source.setFromConto(bank)
        let resolvedDate = try #require(source.nextRecurrenceDate(after: date(6)))
        let resolution = RecurrenceResolution(sourceID: source.id, scheduledDate: resolvedDate, transactionID: nil, isSkipped: true)
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [source], resolutions: [resolution], now: date(5), calendar: calendar)
        let result = try #require(snapshot.books.first)
        #expect(result.monthSpent == 0)
        #expect(result.occurrenceDates.filter { $0 == date(6) }.count == 1)
        #expect(!result.occurrenceDates.contains(resolvedDate))
    }

    @Test func redactionReplacesPersistedFinancialDataAndCorruptionFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let book = Account(name: "Nome privato")
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [], resolutions: [], now: date(5), calendar: calendar)
        try FinanceWidgetStorage.write(snapshot, to: url)
        #expect(FinanceWidgetStorage.read(from: url).books.count == 1)
        try FinanceWidgetStorage.write(.empty(.hidden), to: url)
        #expect(FinanceWidgetStorage.read(from: url).books.isEmpty)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("Nome privato"))
        try Data("invalid".utf8).write(to: url)
        #expect(FinanceWidgetStorage.read(from: url).state == .unavailable)
    }

    @Test func linksRoundTripAndRejectUnrecognizedActions() {
        let route = FinanceWidgetRoute(destination: .expense, bookID: UUID())
        #expect(FinanceWidgetRoute(url: route.url) == route)
        for text in ["https://widget/expense", "forgia://widget/delete", "forgia://widget/expense?book=invalid", "forgia://widget/expense?book=a&book=b"] {
            #expect(FinanceWidgetRoute(url: URL(string: text)!) == nil)
        }
    }
}
