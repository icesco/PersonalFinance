import Foundation
import SwiftData

/// Prepares the interactive chart using the same validated history as widgets.
public actor BalanceSeriesReader {
    public init() {}

    public func load(container: ModelContainer, contoIDs: Set<UUID>, interval: DateInterval,
                     now: Date = Date()) async throws -> [AccountBalanceSeries] {
        try Task.checkCancellation()
        guard !contoIDs.isEmpty else { return [] }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let ids = Array(contoIDs)
        let conti = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { ids.contains($0.id) }))
        let indexed = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { transaction in
            transaction.fromContoId.flatMap { ids.contains($0) } == true
                || transaction.toContoId.flatMap { ids.contains($0) } == true
        })
        let legacyFrom = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { transaction in
            transaction.fromContoId == nil && transaction.fromConto.flatMap { ids.contains($0.id) } == true
        })
        let legacyTo = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { transaction in
            transaction.toContoId == nil && transaction.toConto.flatMap { ids.contains($0.id) } == true
        })
        var visited: Set<PersistentIdentifier> = []
        var transactions = try [indexed, legacyFrom, legacyTo].flatMap { try context.fetch($0) }
            .filter { visited.insert($0.persistentModelID).inserted }
        // An edited occurrence may move to other conti and arrive before its resolution.
        // Keep it available to suppress the source's virtual copy without fetching every book.
        let sourceIDs = Array(Set(transactions.filter { $0.isRecurring == true }.map(\.id)))
        if !sourceIDs.isEmpty {
            let occurrences = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { transaction in
                transaction.recurrenceSourceID.flatMap { sourceIDs.contains($0) } == true
            })
            transactions += try context.fetch(occurrences).filter { visited.insert($0.persistentModelID).inserted }
        }
        let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>())
        FinanceDataChangeCenter.shared.rememberCategories(container: container, categories: transactions.compactMap(\.category))
        let ledger = try await LedgerCalculationCoordinator.shared.prepare(container: container,
            accounts: conti.map(LedgerCacheAccount.init), transactions: transactions.map(TransactionSnapshot.init(from:)), now: now)
        let series = AccountBalanceSeries.make(conti: conti, selectedIDs: contoIDs, transactions: transactions,
            resolutions: resolutions, interval: interval, now: now, ledgerSnapshots: ledger.snapshots)
        try Task.checkCancellation()
        LedgerCache.apply(ledger, to: conti)
        do { try FinanceDataChangeCenter.shared.saveCache(context: context) }
        catch { context.rollback() }
        return series
    }
}
