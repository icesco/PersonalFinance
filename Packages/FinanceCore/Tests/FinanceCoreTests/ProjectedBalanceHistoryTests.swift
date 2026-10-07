import Foundation
import Testing
@testable import FinanceCore

struct ProjectedBalanceHistoryTests {
    @Test func projectionStartsAtRecordedBalanceAndStopsAtPeriodBoundary() {
        let a = UUID(), b = UUID(), start = Date(timeIntervalSince1970: 1000)
        let now = start.addingTimeInterval(20), end = start.addingTimeInterval(100)
        let planned = [
            TransactionSnapshot(amount: 999, type: .income, date: now, toContoId: a),
            TransactionSnapshot(amount: 20, type: .transfer, date: now.addingTimeInterval(10), fromContoId: a, toContoId: b),
            TransactionSnapshot(amount: 5, type: .expense, date: now.addingTimeInterval(10), fromContoId: a),
            TransactionSnapshot(amount: 999, type: .income, date: end, toContoId: a)
        ]
        let interval = DateInterval(start: start, end: end)
        let outgoing = ProjectedBalanceHistory.points(planned: planned, contoID: a, openingBalance: 100, interval: interval, now: now)
        let incoming = ProjectedBalanceHistory.points(planned: planned, contoID: b, openingBalance: 50, interval: interval, now: now)
        #expect(outgoing.map(\.balance) == [100, 75, 75])
        #expect(incoming.map(\.balance) == [50, 70, 70])
        #expect(outgoing.map(\.date) == [now, now.addingTimeInterval(10), end])
    }

    @Test func noScheduledMovementsStayFlatAndPastPeriodsHaveNoProjection() {
        let a = UUID(), start = Date(timeIntervalSince1970: 1000)
        let interval = DateInterval(start: start, duration: 100)
        let flat = ProjectedBalanceHistory.points(planned: [], contoID: a, openingBalance: -50, interval: interval, now: start)
        #expect(flat.map(\.balance) == [-50, -50])
        #expect(ProjectedBalanceHistory.points(planned: [], contoID: a, openingBalance: 100, interval: interval, now: interval.end).isEmpty)
    }

    @Test @MainActor func recurrencesExcludeSkippedAndMaterializedOccurrencesAndKeepScheduledTransfers() {
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .savings)
        let now = Date(timeIntervalSince1970: 1000)
        let source = Transaction(amount: 20, type: .transfer, date: now, isRecurring: true, recurrenceFrequency: .daily)
        source.setFromConto(a); source.setToConto(b)
        let dates = source.recurrenceDates(after: now, through: now.addingTimeInterval(4 * 86400))
        let skipped = RecurrenceResolution(sourceID: source.id, scheduledDate: dates[0], isSkipped: true)
        let materialized = Transaction(amount: 25, type: .transfer, date: dates[1])
        materialized.setFromConto(a); materialized.setToConto(b)
        materialized.recurrenceSourceID = source.id
        materialized.externalID = RecurrenceResolution.key(sourceID: source.id, date: dates[1])
        source.recurrenceEndDate = dates[2]
        let futureIncome = Transaction(amount: 100, type: .income, date: now.addingTimeInterval(100))
        futureIncome.setToConto(a)
        let planned = ProjectedBalanceHistory.plannedTransactions(transactions: [source, materialized, futureIncome, futureIncome],
            resolutions: [skipped], now: now, through: dates[3])
        #expect(planned.count == 3)
        #expect(planned.map(\.date) == [futureIncome.date, dates[1], dates[2]])
        #expect(planned.map(\.amount) == [100, 25, 20])
        #expect(planned.last?.fromContoId == a.id)
        #expect(planned.last?.toContoId == b.id)
    }

    @Test @MainActor func futureRecurringAnchorIsCountedOnlyOnce() {
        let now = Date(timeIntervalSince1970: 1000)
        let anchor = now.addingTimeInterval(86400)
        let source = Transaction(amount: 10, type: .expense, date: anchor, isRecurring: true, recurrenceFrequency: .daily)
        let planned = ProjectedBalanceHistory.plannedTransactions(transactions: [source], resolutions: [], now: now,
            through: anchor.addingTimeInterval(2 * 86400))
        #expect(planned.map(\.date) == [anchor, anchor.addingTimeInterval(86400)])
    }
}
