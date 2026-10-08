import Foundation
import SwiftData

/// Serializes shared ledger work and reuses exactly matching values per account.
/// Models remain on the reader's executor; timestamps never substitute for content equality.
public actor LedgerCalculationCoordinator {
    public static let shared = LedgerCalculationCoordinator()
    private struct Key: Hashable {
        let container: ObjectIdentifier
        let contoID: UUID
        let calendar: String
        let timeZone: String
    }
    private struct Entry {
        let opening: Decimal
        let sources: [TransactionSnapshot]
        let inputPayload: String?
        let preparation: LedgerCachePreparation
    }
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    // Retain identities while cached, preventing address reuse across replaced containers.
    private var containers: [ObjectIdentifier: ModelContainer] = [:]
    private let maximumEntries: Int
    public private(set) var calculationCount = 0
    public private(set) var memoryReuseCount = 0
    public var retainedEntryCount: Int { entries.count }

    public init(maximumEntries: Int = 32) { self.maximumEntries = max(1, maximumEntries) }

    public func prepare(container: ModelContainer, accounts: [LedgerCacheAccount],
                        transactions: [TransactionSnapshot], now: Date,
                        calendar: Calendar = .current) throws -> LedgerCachePreparation {
        try Task.checkCancellation()
        FinanceDataChangeCenter.shared.remember(container: container, transactions: transactions, accounts: accounts)
        let identity = ObjectIdentifier(container)
        containers[identity] = container
        let ids = Set(accounts.map(\.id))
        var grouped: [UUID: [TransactionSnapshot]] = [:]
        for entry in transactions where entry.date <= now {
            for id in Set([entry.fromContoId, entry.toContoId].compactMap { $0 }).intersection(ids) {
                grouped[id, default: []].append(entry)
            }
        }
        var snapshots: [UUID: LedgerCacheSnapshot] = [:]
        var updates: [UUID: String] = [:]
        var reused = 0
        for account in accounts {
            try Task.checkCancellation()
            let key = Key(container: identity, contoID: account.id,
                          calendar: String(describing: calendar.identifier), timeZone: calendar.timeZone.identifier)
            // Equality below checks every source value, not just an ID, count or hash.
            let sources = (grouped[account.id] ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
            let preparation: LedgerCachePreparation
            if let cached = entries[key], cached.opening == account.initialBalance, cached.sources == sources,
               account.ledgerCacheJSON == cached.inputPayload || account.ledgerCacheJSON == cached.preparation.updates[account.id] {
                preparation = cached.preparation
                memoryReuseCount += 1
                reused += 1
            } else {
                preparation = try LedgerCache.prepare(accounts: [account], transactions: sources, now: now, calendar: calendar)
                calculationCount += 1
                reused += preparation.reusedCount
                entries[key] = Entry(opening: account.initialBalance, sources: sources,
                                     inputPayload: account.ledgerCacheJSON, preparation: preparation)
            }
            order.removeAll { $0 == key }
            order.append(key)
            snapshots.merge(preparation.snapshots) { _, new in new }
            if let payload = preparation.updates[account.id], payload != account.ledgerCacheJSON {
                updates[account.id] = payload
            }
        }
        while order.count > maximumEntries || entries.values.reduce(0, { $0 + $1.sources.count }) > 50_000 {
            entries.removeValue(forKey: order.removeFirst())
        }
        containers = containers.filter { id, _ in order.contains { $0.container == id } }
        return LedgerCachePreparation(snapshots: snapshots, reusedCount: reused,
                                      rebuiltCount: accounts.count - reused, updates: updates)
    }
}
