import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct WidgetUpcomingSnapshotTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func bank(_ book: Account) -> Conto {
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 0)
        bank.account = book; book.conti = [bank]
        return bank
    }
    private func row(_ bank: Conto, day: Int, type: TransactionType = .expense, recurring: Bool = false) -> Transaction {
        let row = Transaction(amount: 25, type: type, date: date(day), transactionDescription: "Movimento",
                              isRecurring: recurring, recurrenceFrequency: recurring ? .weekly : nil)
        if type == .income { row.setToConto(bank) } else { row.setFromConto(bank) }
        return row
    }

    @Test func includesOneOffIncomeAndExpenseScopesBooksAndExcludesTransfersAndArchivedAccounts() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let other = bank(Account(name: "Altro"))
        let archived = Conto(name: "Archiviato", type: .checking, initialBalance: 0)
        archived.isActive = false; archived.account = book; book.conti?.append(archived)
        let income = row(account, day: 9, type: .income)
        // Legacy records with only relationships must also work.
        income.toContoId = nil
        let expense = row(account, day: 10)
        let transactions = [expense, income, row(account, day: 7), row(account, day: 8),
                            row(account, day: 11, type: .transfer), row(other, day: 9), row(archived, day: 9)]
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: transactions,
                                                 resolutions: [], now: date(8), calendar: calendar)
        let schedule = try #require(snapshot.books.first?.upcomingSchedule)
        #expect(schedule.transactions.map(\.id) == [income.id.uuidString, expense.id.uuidString])
        #expect(schedule.transactions.first?.type == .income)
        #expect(schedule.upcoming(at: date(9)).first?.id == expense.id.uuidString)
        #expect(schedule.upcoming(at: schedule.coverageEnd).isEmpty)
    }

    @Test func suppressesSkippedAndMaterializedOccurrencesButKeepsFutureSeedOnce() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let source = row(account, day: 9, recurring: true)
        let skipDate = try #require(source.nextRecurrenceDate(after: source.date))
        let recordedDate = try #require(source.nextRecurrenceDate(after: skipDate))
        let resolution = RecurrenceResolution(sourceID: source.id, scheduledDate: skipDate, isSkipped: true)
        let materialized = row(account, day: 23)
        materialized.date = recordedDate
        materialized.recurrenceSourceID = source.id
        let schedule = WidgetUpcomingSnapshot.build(transactions: [source, source, materialized], resolutions: [resolution],
                                                    contoIDs: [account.id], now: date(8), calendar: calendar)
        #expect(schedule.transactions.filter { $0.date == source.date }.count == 1)
        #expect(!schedule.transactions.contains { $0.date == skipDate })
        #expect(schedule.transactions.filter { $0.date == recordedDate }.count == 1)
        #expect(schedule.transactions.first?.id == source.id.uuidString)
    }

    @Test func horizonUsesCalendarDaysAcrossDSTAndKeepsDistantPlannedEntries() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let invalid = row(account, day: 9); invalid.amount = .nan
        let distant = row(account, day: 10)
        distant.date = calendar.date(byAdding: .day, value: 91, to: date(8))!
        let schedule = WidgetUpcomingSnapshot.build(transactions: [invalid, distant], resolutions: [],
                                                    contoIDs: [account.id], now: date(8), calendar: calendar)
        #expect(schedule.coverageEnd == calendar.date(byAdding: .day, value: 90, to: date(8)))
        #expect(schedule.transactions.count == 2)
        #expect(schedule.transactions.first?.amount == nil)
        #expect(schedule.upcoming(at: schedule.coverageEnd).first?.id == distant.id.uuidString)
    }

    @Test func annualExpenseRemainsVisibleOutsideNinetyDayWindow() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let annual = row(account, day: 7, recurring: true)
        annual.recurrenceFrequency = .yearly
        let schedule = WidgetUpcomingSnapshot.build(transactions: [annual], resolutions: [],
                                                    contoIDs: [account.id], now: date(8), calendar: calendar)
        #expect(schedule.transactions.count == 1)
        #expect(schedule.transactions.first?.date == annual.nextRecurrenceDate(after: date(8)))
        #expect(try #require(schedule.transactions.first).date > schedule.coverageEnd)
        let skippedDate = try #require(schedule.transactions.first?.date)
        let skipped = RecurrenceResolution(sourceID: annual.id, scheduledDate: skippedDate, isSkipped: true)
        let afterSkip = WidgetUpcomingSnapshot.build(transactions: [annual], resolutions: [skipped],
                                                     contoIDs: [account.id], now: date(8), calendar: calendar)
        #expect(afterSkip.transactions.first?.date == annual.nextRecurrenceDate(after: skippedDate))
    }

    @Test func preservesAssignedSubcategoryAppearanceForPlannedAndRecurringRows() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let parent = Category(name: "Casa", color: CategoryPalette.prugna, icon: "house")
        let child = Category(name: "Utenze", color: CategoryPalette.ocra, icon: "bolt", parentCategoryId: parent.id)
        let planned = row(account, day: 9)
        planned.setCategory(parent)
        let recurring = row(account, day: 7, recurring: true)
        recurring.setCategory(child)
        let schedule = WidgetUpcomingSnapshot.build(transactions: [planned, recurring], resolutions: [],
                                                    contoIDs: [account.id], now: date(8), calendar: calendar)
        let parentRow = try #require(schedule.transactions.first { $0.id == planned.id.uuidString })
        #expect(parentRow.categoryIcon == "house")
        #expect(parentRow.categoryColor == CategoryPalette.prugna)
        let recurringRows = schedule.transactions.filter { $0.id != planned.id.uuidString }
        #expect(!recurringRows.isEmpty)
        #expect(recurringRows.allSatisfy { $0.categoryIcon == "bolt" && $0.categoryColor == CategoryPalette.ocra })
        #expect(try JSONDecoder().decode(WidgetUpcomingSnapshot.self, from: JSONEncoder().encode(schedule)) == schedule)
    }

    @Test func schedulesPublishedWithoutCategoryAppearanceStillDecode() throws {
        let transaction = WidgetUpcomingTransaction(id: "old", date: date(9), title: "Abbonamento", amount: 10, type: .expense,
                                                    categoryIcon: "play.tv", categoryColor: CategoryPalette.albicocca)
        let data = try JSONEncoder().encode(transaction)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "categoryIcon"); json.removeValue(forKey: "categoryColor")
        let old = try JSONDecoder().decode(WidgetUpcomingTransaction.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.categoryIcon == nil)
        #expect(old.categoryColor == nil)
        #expect(old.title == transaction.title)
    }

    @Test func compactSummaryGroupsExpensesByDayAndNeverNetsIncome() throws {
        let first = WidgetUpcomingTransaction(id: "music", date: date(9, hour: 8), title: "Musica", amount: 10, type: .expense,
                                              categoryIcon: "play.tv", categoryColor: CategoryPalette.albicocca)
        let second = WidgetUpcomingTransaction(id: "gym", date: date(9, hour: 20), title: "Palestra", amount: 30, type: .expense,
                                               categoryIcon: "play.tv", categoryColor: CategoryPalette.albicocca)
        let rows = [second, first,
                    WidgetUpcomingTransaction(id: "income", date: date(8, hour: 18), title: "Stipendio", amount: 1000, type: .income),
                    WidgetUpcomingTransaction(id: "later", date: date(10), title: "Affitto", amount: 650, type: .expense)]
        let summary = try #require(WidgetUpcomingDaySummary.next(in: rows, at: date(8), calendar: calendar))
        #expect(summary.daysUntilDue == 1)
        #expect(summary.date == first.date)
        #expect(summary.total == 40)
        #expect(summary.transactions.map(\.id) == ["music", "gym"])
        #expect(summary.categoryRepresentatives.count == 1)
        let advanced = try #require(WidgetUpcomingDaySummary.next(in: rows, at: date(9), calendar: calendar))
        #expect(advanced.daysUntilDue == 0)
        #expect(advanced.total == 30)
    }

    @Test func compactSummaryDoesNotUnderstateUnknownAmountsAndFallsBackToIncome() throws {
        let known = WidgetUpcomingTransaction(id: "known", date: date(9), title: "Spesa", amount: 10, type: .expense)
        let unknown = WidgetUpcomingTransaction(id: "unknown", date: date(9), title: "Spesa", amount: nil, type: .expense)
        #expect(WidgetUpcomingDaySummary.next(in: [known, unknown], at: date(8), calendar: calendar)?.total == nil)
        let income = WidgetUpcomingTransaction(id: "income", date: date(9), title: "Stipendio", amount: 1000, type: .income)
        let summary = try #require(WidgetUpcomingDaySummary.next(in: [income], at: date(8), calendar: calendar))
        #expect(summary.type == .income)
        #expect(summary.total == 1000)
        #expect(WidgetUpcomingDaySummary.next(in: [known], at: date(10), calendar: calendar) == nil)
    }

    @Test func compactDueDateCountsCalendarDaysAcrossAutumnDST() throws {
        let now = date(24, hour: 23)
        let expense = WidgetUpcomingTransaction(id: "dst", date: date(26, hour: 1), title: "Spesa", amount: 20, type: .expense)
        let summary = try #require(WidgetUpcomingDaySummary.next(in: [expense], at: now, calendar: calendar))
        #expect(summary.daysUntilDue == 2)
    }

    @Test func olderSnapshotsDecodeWithoutScheduleAndNewSchedulesRoundTrip() throws {
        let book = Account(name: "Personale")
        let account = bank(book)
        let snapshot = FinanceWidgetBuilder.build(accounts: [book], budgets: [], transactions: [row(account, day: 9)],
                                                 resolutions: [], now: date(8), calendar: calendar)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: data) == snapshot)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var books = try #require(json["books"] as? [[String: Any]])
        books[0].removeValue(forKey: "upcomingSchedule"); json["books"] = books
        let old = try JSONDecoder().decode(FinanceWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.books.first?.upcomingSchedule == nil)
        #expect(old.books.first?.id == book.id)
    }
}
