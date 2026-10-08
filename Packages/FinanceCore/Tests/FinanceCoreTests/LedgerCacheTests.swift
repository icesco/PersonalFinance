import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct LedgerCacheTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func measuresValidatedReuseAcrossFourHistoryPeriods() throws {
        let conti = (0..<8).map { Conto(name: "Conto \($0)", type: .checking, initialBalance: 1_000) }
        let entries = (0..<8_000).map { index in
            TransactionSnapshot(amount: Decimal(index % 100), type: .expense,
                date: now.addingTimeInterval(-Double(index * 3_600)), fromContoId: conti[index % conti.count].id)
        }
        LedgerCache.apply(try LedgerCache.prepare(conti: conti, transactions: entries, now: now), to: conti)
        let periods = [7, 30, 90, 365].map { DateInterval(start: now.addingTimeInterval(-Double($0 * 86_400)), end: now) }
        let openings = Dictionary(uniqueKeysWithValues: conti.map { ($0.id, $0.initialBalance ?? 0) })
        let clock = ContinuousClock()
        var fresh: [UUID: [BalanceDataPoint]] = [:]
        let freshTime = clock.measure {
            for period in periods { fresh = RecordedBalanceHistory.series(transactions: entries, initialBalances: openings, interval: period, now: now) }
        }
        var cached: [UUID: [BalanceDataPoint]] = [:]
        let cachedTime = try clock.measure {
            let reused = try LedgerCache.prepare(conti: conti, transactions: entries, now: now)
            #expect(reused.reusedCount == conti.count)
            for period in periods { cached = reused.snapshots.mapValues { $0.points(interval: period, now: now, transactions: entries, resolution: .transaction) } }
        }
        for conto in conti { #expect(cached[conto.id]?.last?.balance == fresh[conto.id]?.last?.balance) }
        print("Ledger cache benchmark (8 conti, 8000 movements, 4 periods): fresh=\(freshTime), validated cache=\(cachedTime)")
    }

    @Test func persistedCacheReusesAcrossContextsAndDoesNotRequestAnotherWrite() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 500)
        context.insert(conto)
        let entries = [TransactionSnapshot(amount: 20, type: .expense, date: now, fromContoId: conto.id)]
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now)
        #expect(first.rebuiltCount == 1)
        #expect(first.snapshots[conto.id]?.balance == 480)
        LedgerCache.apply(first, to: [conto])
        try context.save()
        let secondContext = ModelContext(container)
        let id = conto.id
        let other = try #require(secondContext.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == id })).first)
        let second = try LedgerCache.prepare(conti: [other], transactions: Array(entries.reversed()), now: now.addingTimeInterval(60))
        #expect(second.reusedCount == 1)
        #expect(second.updates.isEmpty)
        #expect(second.snapshots[id]?.balance == 480)
    }

    @Test func sameCountEditsDeletionsAndMovedTransfersInvalidateOnlyAffectedConti() throws {
        let a = Conto(name: "A", type: .checking, initialBalance: 500)
        let b = Conto(name: "B", type: .checking, initialBalance: 10)
        let untouched = Conto(name: "C", type: .cash, initialBalance: 5)
        let id = UUID()
        let original = TransactionSnapshot(id: id, amount: 100, type: .transfer, date: now,
                                          fromContoId: a.id, toContoId: b.id, destinationAmount: 90)
        let first = try LedgerCache.prepare(conti: [a, b, untouched], transactions: [original], now: now)
        LedgerCache.apply(first, to: [a, b, untouched])
        let edited = TransactionSnapshot(id: id, amount: 120, type: .transfer, date: now,
                                        fromContoId: a.id, toContoId: b.id, destinationAmount: 110)
        let second = try LedgerCache.prepare(conti: [a, b, untouched], transactions: [edited], now: now)
        #expect(second.reusedCount == 1)
        #expect(second.rebuiltCount == 2)
        #expect(second.snapshots[a.id]?.balance == 380)
        #expect(second.snapshots[b.id]?.balance == 120)
        LedgerCache.apply(second, to: [a, b, untouched])
        let deleted = try LedgerCache.prepare(conti: [a, b, untouched], transactions: [TransactionSnapshot](), now: now)
        #expect(deleted.rebuiltCount == 2)
        #expect(deleted.snapshots[a.id]?.balance == 500)
        #expect(deleted.snapshots[b.id]?.balance == 10)
        let moved = TransactionSnapshot(id: id, amount: 120, type: .transfer, date: now,
                                       fromContoId: a.id, toContoId: untouched.id, destinationAmount: 110)
        let third = try LedgerCache.prepare(conti: [a, b, untouched], transactions: [moved], now: now)
        #expect(third.rebuiltCount == 3)
        #expect(third.snapshots[b.id]?.balance == 10)
        #expect(third.snapshots[untouched.id]?.balance == 115)
    }

    @Test func remoteCacheAheadOfLedgerAndChangedOpeningBalanceAreRejected() throws {
        let source = Conto(name: "Remote", type: .checking, initialBalance: 100)
        let entries = [TransactionSnapshot(amount: 30, type: .expense, date: now, fromContoId: source.id)]
        LedgerCache.apply(try LedgerCache.prepare(conti: [source], transactions: entries, now: now), to: [source])
        let local = Conto(name: "Locale", type: .checking, initialBalance: 100)
        local.id = source.id
        local.ledgerCacheJSON = source.ledgerCacheJSON
        let missing = try LedgerCache.prepare(conti: [local], transactions: [TransactionSnapshot](), now: now)
        #expect(missing.reusedCount == 0)
        #expect(missing.snapshots[local.id]?.balance == 100)
        let complete = try LedgerCache.prepare(conti: [local], transactions: entries, now: now)
        #expect(complete.reusedCount == 1)
        local.initialBalance = 200
        let changed = try LedgerCache.prepare(conti: [local], transactions: entries, now: now)
        #expect(changed.rebuiltCount == 1)
        #expect(changed.snapshots[local.id]?.balance == 170)
    }

    @Test func categoryChangesRefreshMonthlyBreakdownAndIndependentRebuildsAreDeterministic() throws {
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let id = UUID(), category = UUID(), replacement = UUID()
        let original = TransactionSnapshot(id: id, amount: 20, type: .expense, date: now,
                                          fromContoId: conto.id, categoryID: category)
        let first = try LedgerCache.prepare(conti: [conto], transactions: [original], now: now)
        let independent = try LedgerCache.prepare(conti: [conto], transactions: [original], now: now.addingTimeInterval(1))
        #expect(first.snapshots[conto.id]?.sourceFingerprint == independent.snapshots[conto.id]?.sourceFingerprint)
        #expect(first.snapshots[conto.id]?.history == independent.snapshots[conto.id]?.history)
        #expect(first.snapshots[conto.id]?.calculatedAt == now)
        #expect(independent.snapshots[conto.id]?.calculatedAt == now.addingTimeInterval(1))
        LedgerCache.apply(first, to: [conto])
        let changed = TransactionSnapshot(id: id, amount: 20, type: .expense, date: now,
                                         fromContoId: conto.id, categoryID: replacement)
        let second = try LedgerCache.prepare(conti: [conto], transactions: [changed], now: now)
        #expect(second.rebuiltCount == 1)
        #expect(second.snapshots[conto.id]?.balance == 80)
        #expect(second.snapshots[conto.id]?.months.first?.categoryExpenses.first?.categoryID == replacement)
        #expect(second.snapshots[conto.id]?.months.first?.categoryExpenses.first?.amount == 20)
    }

    @Test func differentDeviceTimeZonesReuseHistoryWithoutCloudWritePingPong() throws {
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        var losAngeles = rome
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = Date(timeIntervalSince1970: 1_790_812_800) // 2026-10-01 00:00 UTC
        let entries = [TransactionSnapshot(amount: 20, type: .expense, date: date, fromContoId: conto.id)]
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: date, calendar: rome)
        LedgerCache.apply(first, to: [conto])
        let remote = try LedgerCache.prepare(conti: [conto], transactions: entries, now: date, calendar: losAngeles)
        #expect(remote.reusedCount == 1)
        #expect(remote.updates.isEmpty)
        #expect(remote.snapshots[conto.id]?.history == first.snapshots[conto.id]?.history)
        #expect(remote.snapshots[conto.id]?.months.first?.start != first.snapshots[conto.id]?.months.first?.start)
        #expect(remote.snapshots[conto.id]?.months.first?.expenses == 20)
    }

    @Test func clockAdvancesWithoutCountingFutureMovementsEarlyAndMonthTotalsExcludeTransfers() throws {
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let entries = [
            TransactionSnapshot(amount: 20, type: .expense, date: now, fromContoId: conto.id),
            TransactionSnapshot(amount: 10, type: .income, date: now, toContoId: conto.id),
            TransactionSnapshot(amount: 5, type: .transfer, date: now, fromContoId: conto.id, toContoId: UUID()),
            TransactionSnapshot(amount: 90, type: .income, date: now.addingTimeInterval(1), toContoId: conto.id)
        ]
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now)
        LedgerCache.apply(first, to: [conto])
        #expect(first.snapshots[conto.id]?.balance == 85)
        #expect(first.snapshots[conto.id]?.months.first?.expenses == 20)
        #expect(first.snapshots[conto.id]?.months.first?.income == 10)
        #expect(first.snapshots[conto.id]?.months.first?.transferChange == -5)
        let next = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now.addingTimeInterval(1))
        #expect(next.rebuiltCount == 1)
        #expect(next.snapshots[conto.id]?.balance == 175)
    }

    @Test func cachedHistoryMatchesLedgerAtBoundariesAndCorruptPayloadIsRebuilt() throws {
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let start = now.addingTimeInterval(-100)
        let entries = [
            TransactionSnapshot(amount: 10, type: .expense, date: start.addingTimeInterval(-1), fromContoId: conto.id),
            TransactionSnapshot(amount: 20, type: .expense, date: start, fromContoId: conto.id),
            TransactionSnapshot(amount: 5, type: .income, date: now, toContoId: conto.id)
        ]
        let first = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now)
        let snapshot = try #require(first.snapshots[conto.id])
        for interval in [DateInterval(start: start, end: now), DateInterval(start: start, end: now.addingTimeInterval(1))] {
            let expected = RecordedBalanceHistory.points(transactions: entries, contiIDs: [conto.id],
                                                         initialBalance: 100, interval: interval, now: now)
            let cached = snapshot.points(interval: interval, now: now, transactions: entries, resolution: .transaction)
            #expect(cached.map(\.date) == expected.map(\.date))
            #expect(cached.map(\.balance) == expected.map(\.balance))
        }
        LedgerCache.apply(first, to: [conto])
        let json = try #require(conto.ledgerCacheJSON)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var payload = try #require(envelope["snapshot"] as? [String: Any])
        payload["initialBalance"] = 999
        envelope["snapshot"] = payload
        conto.ledgerCacheJSON = String(decoding: try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys), as: UTF8.self)
        let repaired = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now)
        #expect(repaired.rebuiltCount == 1)
        #expect(repaired.snapshots[conto.id]?.balance == 75)
    }
}
