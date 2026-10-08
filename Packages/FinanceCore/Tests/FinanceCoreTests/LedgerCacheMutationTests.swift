import Foundation
import Testing
@testable import FinanceCore

@MainActor
struct LedgerCacheMutationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func calculationDateSurvivesReuseAndAdvancesOnlyOnRebuild() throws {
        let conto = Conto(name: "A", type: .checking, initialBalance: 100)
        let id = UUID()
        let entry = TransactionSnapshot(id: id, amount: 10, type: .expense, date: now, fromContoId: conto.id)
        let first = try LedgerCache.prepare(conti: [conto], transactions: [entry], now: now)
        LedgerCache.apply(first, to: [conto])
        let reused = try LedgerCache.prepare(conti: [conto], transactions: [entry], now: now.addingTimeInterval(60))
        #expect(reused.snapshots[conto.id]?.calculatedAt == now)
        #expect(reused.updates.isEmpty)
        let edited = TransactionSnapshot(id: id, amount: 11, type: .expense, date: now, fromContoId: conto.id)
        let rebuilt = try LedgerCache.prepare(conti: [conto], transactions: [edited], now: now.addingTimeInterval(120))
        #expect(rebuilt.snapshots[conto.id]?.calculatedAt == now.addingTimeInterval(120))
        #expect(rebuilt.snapshots[conto.id]?.balance == 89)
    }

    @Test func newerRemoteTimestampCannotHideAnOlderLedger() throws {
        let conto = Conto(name: "A", type: .checking, initialBalance: 100)
        let id = UUID()
        let old = TransactionSnapshot(id: id, amount: 10, type: .expense, date: now.addingTimeInterval(-10), fromContoId: conto.id)
        // Simulate another device whose clock is ahead, followed by a same-count edit locally.
        let remote = try LedgerCache.prepare(conti: [conto], transactions: [old], now: now.addingTimeInterval(86_400))
        LedgerCache.apply(remote, to: [conto])
        let edited = TransactionSnapshot(id: id, amount: 25, type: .expense, date: old.date, fromContoId: conto.id)
        let local = try LedgerCache.prepare(conti: [conto], transactions: [edited], now: now)
        #expect(local.rebuiltCount == 1)
        #expect(local.snapshots[conto.id]?.balance == 75)
        #expect(local.snapshots[conto.id]?.calculatedAt == now)
        LedgerCache.apply(local, to: [conto])
        conto.ledgerCacheJSON = remote.updates[conto.id] // late delivery of the stale cache
        let late = try LedgerCache.prepare(conti: [conto], transactions: [edited], now: now)
        #expect(late.rebuiltCount == 1)
        #expect(late.snapshots[conto.id]?.balance == 75)
    }

    @Test(arguments: ["missingDate", "changedDate", "oldVersion", "wrongAccount", "checksum", "truncated", "oversized"])
    func invalidPayloadIsRebuilt(reason: String) throws {
        let conto = Conto(name: "A", type: .checking, initialBalance: 100)
        let entries = [TransactionSnapshot(amount: 10, type: .expense, date: now, fromContoId: conto.id)]
        LedgerCache.apply(try LedgerCache.prepare(conti: [conto], transactions: entries, now: now), to: [conto])
        let json = try #require(conto.ledgerCacheJSON)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var snapshot = try #require(envelope["snapshot"] as? [String: Any])
        switch reason {
        case "missingDate": snapshot.removeValue(forKey: "calculatedAt")
        case "changedDate": snapshot["calculatedAt"] = 0
        case "oldVersion": snapshot["version"] = 1
        case "wrongAccount": snapshot["contoID"] = UUID().uuidString
        case "checksum": envelope["checksum"] = "invalid"
        default: break
        }
        envelope["snapshot"] = snapshot
        conto.ledgerCacheJSON = String(decoding: try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys), as: UTF8.self)
        if reason == "truncated" { conto.ledgerCacheJSON = String(json.prefix(json.count / 2)) }
        if reason == "oversized" { conto.ledgerCacheJSON = String(repeating: "x", count: LedgerCache.maximumPayloadBytes + 1) }
        let repaired = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now)
        #expect(repaired.rebuiltCount == 1)
        #expect(repaired.snapshots[conto.id]?.balance == 90)
        #expect(repaired.snapshots[conto.id]?.calculatedAt == now)
        LedgerCache.apply(repaired, to: [conto])
        #expect(try LedgerCache.prepare(conti: [conto], transactions: entries, now: now).reusedCount == 1)
    }

    @Test func clockMovingBackwardsExcludesPreviouslyMaturedMovements() throws {
        let conto = Conto(name: "A", type: .checking, initialBalance: 100)
        let entries = [TransactionSnapshot(amount: 10, type: .expense, date: now, fromContoId: conto.id)]
        LedgerCache.apply(try LedgerCache.prepare(conti: [conto], transactions: entries, now: now), to: [conto])
        let earlier = try LedgerCache.prepare(conti: [conto], transactions: entries, now: now.addingTimeInterval(-1))
        #expect(earlier.rebuiltCount == 1)
        #expect(earlier.snapshots[conto.id]?.balance == 100)
        #expect(earlier.snapshots[conto.id]?.history.isEmpty == true)
    }

    @Test(arguments: [0, 1, 2, 3])
    func repeatedMixedEditsMatchUncachedHistory(seed: Int) throws {
        let conti = (0..<3).map { Conto(name: "Conto \($0)", type: .checking, initialBalance: Decimal(100 + $0 * 50)) }
        let categories = [UUID(), UUID()]
        var entries: [TransactionSnapshot] = []
        for i in 0..<12 {
            let date = now.addingTimeInterval(-Double(i * 86_400))
            entries.append(TransactionSnapshot(amount: Decimal(i + 1), type: .transfer,
                date: date, fromContoId: conti[i % 3].id,
                toContoId: conti[(i + 1) % 3].id, destinationAmount: Decimal(i + 2)))
        }
        for step in 0..<160 {
            let index = (step * 7 + seed) % entries.count
            let old = entries[index]
            let operation = (step + seed) % 10
            if operation == 8 && entries.count > 5 {
                entries.remove(at: index)
            } else if operation == 9 {
                entries.append(TransactionSnapshot(amount: Decimal(step + 1) / 100, type: .income,
                    date: now.addingTimeInterval(-Double(step * 100)), toContoId: conti[step % 3].id))
            } else if operation == 7 {
                conti[step % 3].initialBalance = Decimal(step - 80)
            } else {
                entries[index] = TransactionSnapshot(id: old.id,
                    amount: operation == 0 ? Decimal(step - 50) / 100 : old.amount,
                    type: operation == 1 ? .expense : operation == 2 ? .income : old.type,
                    date: operation == 3 ? now.addingTimeInterval(Double((step % 5) - 2) * 86_400) : old.date,
                    fromContoId: operation == 4 ? conti[(step + seed) % 3].id : old.fromContoId,
                    toContoId: operation == 5 ? conti[(step + seed + 1) % 3].id : old.toContoId,
                    destinationAmount: operation == 6 ? Decimal(step + 3) / 100 : old.destinationAmount,
                    categoryID: categories[step % 2])
            }
            let prepared = try LedgerCache.prepare(conti: conti, transactions: entries, now: now)
            for conto in conti {
                let snapshot = try #require(prepared.snapshots[conto.id])
                // An individual chart uses only this account's movements. Including unrelated
                // movements in the reference adds redundant flat points at their timestamps.
                let scoped = entries.filter { $0.fromContoId == conto.id || $0.toContoId == conto.id }
                for days in [1, 7, 30] {
                    let interval = DateInterval(start: now.addingTimeInterval(-Double(days * 86_400)), end: now.addingTimeInterval(1))
                    let expected = RecordedBalanceHistory.points(transactions: scoped, contiIDs: [conto.id],
                        initialBalance: conto.initialBalance ?? 0, interval: interval, now: now)
                    let actual = snapshot.points(interval: interval, now: now, transactions: entries, resolution: .transaction)
                    #expect(actual.map(\.date) == expected.map(\.date))
                    #expect(actual.map(\.balance) == expected.map(\.balance))
                }
                let recorded = entries.filter { $0.date <= now }
                let income = recorded.filter { $0.type == .income && $0.toContoId == conto.id }.reduce(Decimal.zero) { $0 + $1.amount }
                let expenses = recorded.filter { $0.type == .expense && $0.fromContoId == conto.id }.reduce(Decimal.zero) { $0 + $1.amount }
                #expect(snapshot.months.reduce(Decimal.zero) { $0 + $1.income } == income)
                #expect(snapshot.months.reduce(Decimal.zero) { $0 + $1.expenses } == expenses)
                #expect(snapshot.months.flatMap(\.categoryExpenses).reduce(Decimal.zero) { $0 + $1.amount } == expenses)
            }
            LedgerCache.apply(prepared, to: conti)
            let reused = try LedgerCache.prepare(conti: conti, transactions: Array(entries.reversed()), now: now.addingTimeInterval(0.5))
            #expect(reused.reusedCount == conti.count)
            #expect(reused.updates.isEmpty)
            for conto in conti {
                #expect(reused.snapshots[conto.id]?.history == prepared.snapshots[conto.id]?.history)
                #expect(reused.snapshots[conto.id]?.calculatedAt == prepared.snapshots[conto.id]?.calculatedAt)
            }
        }
    }
}
