import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct LedgerCacheCompactionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func denseIntradayHistoryPersistsSmallAndRetainsExactShortCharts() throws {
        let conto = Conto(name: "Dense", type: .checking, initialBalance: 1_000)
        let entries = (0..<10_000).map { index in
            TransactionSnapshot(amount: Decimal(index % 3 + 1) / 100, type: .expense,
                date: now.addingTimeInterval(-Double(index)), fromContoId: conto.id)
        }
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        let snapshot = try #require(first.snapshots[conto.id])
        let json = try #require(first.updates[conto.id])
        #expect(snapshot.historyResolution == .day)
        #expect(snapshot.history.count <= 2)
        #expect(json.utf8.count < 2_000)
        print("Compact ledger (10000 intraday movements): \(json.utf8.count) bytes, \(snapshot.history.count) stored points")
        LedgerCache.apply(first, to: [conto])
        let reused = try LedgerCache.prepare(conti: [conto], transactions: entries.reversed(), now: now, calendar: calendar)
        #expect(reused.reusedCount == 1)
        #expect(reused.updates.isEmpty)
        let interval = DateInterval(start: now.addingTimeInterval(-8_500.5), end: now.addingTimeInterval(-300.5))
        let expected = RecordedBalanceHistory.points(transactions: entries, contiIDs: [conto.id], initialBalance: 1_000,
                                                     interval: interval, now: now)
        let actual = snapshot.points(interval: interval, now: now, transactions: entries, calendar: calendar)
        #expect(actual.map(\.date) == expected.map(\.date))
        #expect(actual.map(\.balance) == expected.map(\.balance))
        let fromDisk = try #require(reused.snapshots[conto.id])
        #expect(actual == fromDisk.points(interval: interval, now: now, transactions: entries, calendar: calendar))
    }

    @Test(arguments: [100, 400, 1_800])
    func longChartsBoundPointsAndKeepExactPartialBoundaries(days: Int) throws {
        let conto = Conto(name: "Long", type: .checking, initialBalance: 500)
        let entries = (0..<(days * 4)).map { index in
            TransactionSnapshot(amount: Decimal(index % 7 + 1) / 100, type: index % 2 == 0 ? .income : .expense,
                date: now.addingTimeInterval(-Double(index * 21_600)),
                fromContoId: index % 2 == 0 ? nil : conto.id, toContoId: index % 2 == 0 ? conto.id : nil)
        }
        let prepared = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        let snapshot = try #require(prepared.snapshots[conto.id])
        let interval = DateInterval(start: now.addingTimeInterval(-Double(days * 86_400) + 12_345),
                                    end: now.addingTimeInterval(-12_345))
        let expected = RecordedBalanceHistory.points(transactions: entries, contiIDs: [conto.id], initialBalance: 500,
                                                     interval: interval, now: now)
        let actual = snapshot.points(interval: interval, now: now, transactions: entries, calendar: calendar)
        #expect(actual.first?.date == interval.start)
        #expect(actual.last?.date == interval.end)
        #expect(actual.first?.balance == expected.first?.balance)
        #expect(actual.last?.balance == expected.last?.balance)
        #expect(actual.count <= (days > 732 ? days / 28 + 3 : days + 3))
        #expect(actual.count < expected.count)
        // Every retained point is a true cumulative balance, never a mean of balances.
        let balances = Dictionary(uniqueKeysWithValues: expected.map { ($0.date, $0.balance) })
        for point in actual { #expect(balances[point.date] == point.balance) }
    }

    @Test func decadesOfDailyHistoryFallBackToMonthlyPersistenceWithExactDayDetail() throws {
        let conto = Conto(name: "Decades", type: .checking, initialBalance: 20_000)
        let entries = (0..<8_000).map { index in
            TransactionSnapshot(amount: 1, type: .expense, date: now.addingTimeInterval(-Double(index * 86_400)),
                                fromContoId: conto.id)
        }
        let prepared = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        let snapshot = try #require(prepared.snapshots[conto.id])
        #expect(snapshot.historyResolution == .month)
        #expect(snapshot.history.count < 300)
        #expect(snapshot.balance == 12_000)
        #expect(try #require(prepared.updates[conto.id]).utf8.count <= LedgerCache.maximumPayloadBytes)
        LedgerCache.apply(prepared, to: [conto])
        let reused = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        #expect(reused.reusedCount == 1)
        let interval = DateInterval(start: now.addingTimeInterval(-100 * 86_400), end: now)
        let points = snapshot.points(interval: interval, now: now, transactions: entries, calendar: calendar)
        let expected = RecordedBalanceHistory.points(transactions: entries, contiIDs: [conto.id], initialBalance: 20_000,
                                                     interval: interval, now: now)
        #expect(points.map(\.balance) == expected.map(\.balance))
        #expect(points.map(\.date) == expected.map(\.date))
    }

    @Test func compactCacheEditsDeletesAndFutureMaturityInvalidateCorrectly() throws {
        let conto = Conto(name: "Dense", type: .checking, initialBalance: 20_000)
        var entries = (0..<2_000).map { index in
            TransactionSnapshot(amount: 1, type: .expense, date: now.addingTimeInterval(-Double(index)), fromContoId: conto.id)
        }
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        #expect(first.snapshots[conto.id]?.historyResolution == .day)
        LedgerCache.apply(first, to: [conto])
        entries.removeLast()
        entries.append(TransactionSnapshot(amount: 7, type: .income, date: now.addingTimeInterval(1), toContoId: conto.id))
        let deleted = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        #expect(deleted.rebuiltCount == 1)
        #expect(deleted.snapshots[conto.id]?.balance == 18_001)
        LedgerCache.apply(deleted, to: [conto])
        let matured = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now.addingTimeInterval(1), calendar: calendar)
        #expect(matured.rebuiltCount == 1)
        #expect(matured.snapshots[conto.id]?.balance == 18_008)
        conto.initialBalance = 30_000
        let edited = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now.addingTimeInterval(1), calendar: calendar)
        #expect(edited.snapshots[conto.id]?.balance == 28_008)
    }

    @Test func compactTimeZoneChangeDoesNotWriteAndPreservesCalculationDate() throws {
        let conto = Conto(name: "Dense", type: .checking, initialBalance: 10_000)
        let entries = (0..<2_000).map { index in
            TransactionSnapshot(amount: 1, type: .expense, date: now.addingTimeInterval(-Double(index * 60)), fromContoId: conto.id)
        }
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now, calendar: calendar)
        LedgerCache.apply(first, to: [conto])
        var alternate = calendar
        alternate.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let other = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now.addingTimeInterval(10), calendar: alternate)
        #expect(other.reusedCount == 1)
        #expect(other.updates.isEmpty)
        #expect(other.snapshots[conto.id]?.balance == first.snapshots[conto.id]?.balance)
        #expect(other.snapshots[conto.id]?.calculatedAt == first.snapshots[conto.id]?.calculatedAt)
    }
}
