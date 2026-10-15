import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct PlanningSnapshotReaderTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Rome")!
        return value
    }
    private func date(_ month: Int, _ day: Int = 1, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func calendarMatchesFullArchiveForAllPresentationsAndUpdates() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .checking)
        context.insert(a); context.insert(b)
        let category = Category(name: "Spesa")
        context.insert(category)
        let source = Transaction(amount: 10, type: .expense, date: date(1, 3), isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(a); source.setCategory(category); context.insert(source)
        let paid = Transaction(amount: 11, type: .expense, date: date(9, 4))
        paid.setFromConto(a); paid.recurrenceSourceID = source.id
        paid.externalID = RecurrenceResolution.key(sourceID: source.id, date: date(10, 3)); context.insert(paid)
        let planned = Transaction(amount: 50, type: .expense, date: date(10, 20))
        planned.setFromConto(a); context.insert(planned)
        let income = Transaction(amount: 100, type: .income, date: date(10, 25))
        income.setToConto(a); context.insert(income)
        for index in 0..<100 {
            let other = Transaction(amount: 999, type: .expense, date: date(10, 2).addingTimeInterval(Double(index)))
            other.setFromConto(b); context.insert(other)
        }
        context.insert(RecurrenceResolution(sourceID: source.id, scheduledDate: date(11, 3), isSkipped: true))
        try context.save()
        let reader = FinanceCalendarSnapshotReader()
        for month in [9, 10, 11] {
            let interval = calendar.dateInterval(of: .month, for: date(month))!
            let all = try context.fetch(FetchDescriptor<Transaction>())
            let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>())
            let expected = FinanceCalendarEvents.build(transactions: all, resolutions: resolutions,
                contoIDs: [a.id], interval: interval, now: date(10, 15))
            let actual = try await reader.load(container: container, contoIDs: [a.id], interval: interval,
                now: date(10, 15), calendar: calendar)
            for expensesOnly in [false, true] {
                for timeline in [false, true] {
                    var events = expected.filter { !expensesOnly || $0.type == .expense }
                    if timeline { events = FinanceCalendarEvents.upcoming(events, now: date(10, 15)) }
                    let presentation = actual.presentation(expensesOnly: expensesOnly, timeline: timeline)
                    #expect(presentation.events == events)
                    #expect(presentation.byDay == Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) })
                }
            }
        }
        planned.amount = 75; planned.setFromConto(b); category.name = "Modificata"
        context.delete(paid); try context.save()
        let interval = calendar.dateInterval(of: .month, for: date(10))!
        let expected = FinanceCalendarEvents.build(transactions: try context.fetch(FetchDescriptor<Transaction>()),
            resolutions: try context.fetch(FetchDescriptor<RecurrenceResolution>()), contoIDs: [a.id], interval: interval, now: date(10, 15))
        let updated = try await reader.load(container: container, contoIDs: [a.id], interval: interval, now: date(10, 15), calendar: calendar)
        #expect(updated.presentation(expensesOnly: false, timeline: false).events == expected)
    }

    @Test func forecastMatchesFullArchiveIncludingBudgetsAndUnsavedChanges() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Libro"), foreign = Account(name: "Altro")
        let a = Conto(name: "A", type: .checking, initialBalance: 1_000), b = Conto(name: "B", type: .checking)
        a.account = book; b.account = foreign
        context.insert(book); context.insert(foreign); context.insert(a); context.insert(b)
        let category = Category(name: "Variabili"); category.account = book; context.insert(category)
        var rows: [Transaction] = []
        for month in 6...10 {
            for day in [1, 5, 10] {
                let row = Transaction(amount: Decimal(month * day) / 3, type: .expense, date: date(month, day))
                row.createdAt = row.date; row.setFromConto(a); row.setCategory(category)
                context.insert(row); rows.append(row)
            }
        }
        let source = Transaction(amount: 12, type: .expense, date: date(1, 20), isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(a); context.insert(source)
        let transfer = Transaction(amount: 20, type: .transfer, date: date(10, 25))
        transfer.destinationAmount = 18; transfer.setFromConto(b); transfer.setToConto(a); context.insert(transfer)
        let other = Transaction(amount: 99_999, type: .income, date: date(10, 1)); other.setToConto(b); context.insert(other)
        let budget = Budget(name: "Mensile", amount: 200, period: .monthly)
        budget.account = book; budget.contoID = a.id; budget.categories = [category]; context.insert(budget)
        try context.save()
        let reader = MonthlyForecastSnapshotReader()
        for month in [9, 10, 11] {
            let expected = MonthlyForecastCalculator.build(conto: a, transactions: try context.fetch(FetchDescriptor<Transaction>()),
                resolutions: [], month: date(month), now: date(10, 15), calendar: calendar, budgets: [budget])
            let actual = try await reader.load(container: container, contoID: a.id, month: date(month), now: date(10, 15), calendar: calendar)
            #expect(actual == expected)
            #expect(actual.excludingVariableCategories(Set(actual.estimates.map(\.id))) == expected.excludingVariableCategories(Set(expected.estimates.map(\.id))))
        }
        rows[0].amount = 123; budget.amount = 250
        let expectedPending = MonthlyForecastCalculator.build(conto: a, transactions: try context.fetch(FetchDescriptor<Transaction>()),
            resolutions: [], month: date(10), now: date(10, 15), calendar: calendar, budgets: [budget])
        #expect(try MonthlyForecastSnapshotReader.read(in: context, contoID: a.id, month: date(10), now: date(10, 15), calendar: calendar) == expectedPending)
        #expect(context.hasChanges)
        try context.save()
        #expect(try await reader.load(container: container, contoID: a.id, month: date(10), now: date(10, 15), calendar: calendar) == expectedPending)
    }

    @Test func cancelledRequestCannotChangeSubsequentResults() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let reader = FinanceCalendarSnapshotReader()
        let interval = calendar.dateInterval(of: .month, for: date(10))!
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.load(container: container, contoIDs: [], interval: interval)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled request returned a snapshot") }
        catch is CancellationError {}
        let valid = try await reader.load(container: container, contoIDs: [], interval: interval)
        #expect(valid.presentation(expensesOnly: false, timeline: false).events.isEmpty)
    }
}
