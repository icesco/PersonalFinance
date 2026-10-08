import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct FinanceCalendarEventsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: .init(year: 2026, month: month, day: day, hour: hour))!
    }
    @Test func scopeKindsAndExclusiveBoundary() {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let other = Conto(name: "Altro", type: .checking, initialBalance: 1000)
        func expense(_ date: Date, _ conto: Conto, type: TransactionType = .expense) -> Transaction {
            let row = Transaction(amount: 20, type: type, date: date)
            row.setFromConto(conto)
            return row
        }
        let past = expense(date(10, 2), conto)
        let future = expense(date(10, 9), conto)
        let events = FinanceCalendarEvents.build(transactions: [past, past, future,
            expense(date(10, 3), other), expense(date(11, 1, 0), conto), expense(date(10, 4), conto, type: .transfer)],
            resolutions: [], contoIDs: [conto.id], interval: calendar.dateInterval(of: .month, for: date(10, 7))!, now: date(10, 7))
        #expect(events.count == 2)
        #expect(events[0].kind == .recorded)
        #expect(events[1].kind == .planned)
    }
    @Test func materializedAndSkippedOccurrencesAreNotCountedTwice() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let source = Transaction(amount: 50, type: .expense, date: date(9, 3), isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(conto)
        let due = try #require(source.nextRecurrenceDate(after: source.date))
        let recorded = Transaction(amount: 50, type: .expense, date: due)
        recorded.setFromConto(conto)
        recorded.recurrenceSourceID = source.id
        // Mirrors a materialized row arriving before its resolution through iCloud.
        recorded.externalID = RecurrenceResolution.key(sourceID: source.id, date: due)
        let interval = calendar.dateInterval(of: .month, for: due)!
        let events = FinanceCalendarEvents.build(transactions: [source, recorded], resolutions: [], contoIDs: [conto.id],
            interval: interval, now: date(10, 7))
        #expect(events.count == 1)
        #expect(events.first?.transactionID == recorded.id)
        let skipped = RecurrenceResolution(sourceID: source.id, scheduledDate: due, isSkipped: true)
        #expect(FinanceCalendarEvents.build(transactions: [source], resolutions: [skipped], contoIDs: [conto.id],
            interval: interval, now: date(10, 7)).isEmpty)
    }
    @Test func unresolvedPastDatesStayPendingAndInvalidAmountsStayUnknown() throws {
        let conto = Conto(name: "Corrente", type: .checking, initialBalance: 1000)
        let source = Transaction(amount: 50, type: .expense, date: date(9, 3), isRecurring: true, recurrenceFrequency: .monthly)
        source.setFromConto(conto)
        let invalid = Transaction(amount: 25, type: .expense, date: date(10, 25))
        invalid.amount = nil
        invalid.setFromConto(conto)
        let events = FinanceCalendarEvents.build(transactions: [source, invalid], resolutions: [], contoIDs: [conto.id],
            interval: calendar.dateInterval(of: .month, for: date(10, 27))!, now: date(10, 27))
        #expect(events.contains { $0.kind == .recurrence && $0.date < date(10, 27) })
        #expect(events.first { $0.transactionID == invalid.id }?.amount == nil)
    }

    @Test func timelineExcludesHistoryAndOverdueRecurrencesButIncludesLaterToday() {
        let now = date(10, 8)
        func event(_ id: String, _ date: Date, _ kind: FinanceCalendarEvent.Kind,
                   type: TransactionType = .expense) -> FinanceCalendarEvent {
            .init(id: id, transactionID: UUID(), date: date, amount: 20,
                  type: type, title: id, kind: kind)
        }
        let events = [
            event("recorded", date(10, 3), .recorded),
            event("overdue", date(10, 7), .recurrence),
            event("due-now", now, .recurrence),
            event("earlier-today", date(10, 8, 9), .recurrence),
            event("later-today", date(10, 8, 18), .planned),
            event("future-recurrence", date(10, 15), .recurrence),
            event("future-income", date(10, 20), .planned, type: .income)
        ]
        #expect(FinanceCalendarEvents.upcoming(events, now: now).map(\.id)
                == ["later-today", "future-recurrence", "future-income"])
        #expect(FinanceCalendarEvents.upcoming(Array(events.prefix(4)), now: now).isEmpty)
    }
}
