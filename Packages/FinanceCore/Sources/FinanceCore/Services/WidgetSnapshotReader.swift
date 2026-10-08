import Foundation
import SwiftData

/// Fetches and computes widget data on its own executor, returning only values.
public actor WidgetSnapshotReader {
    public init() {}

    public func load(container: ModelContainer) async throws -> FinanceWidgetSnapshot {
        try Task.checkCancellation()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let now = Date()
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let conti = accounts.flatMap { $0.conti ?? [] }
        FinanceDataChangeCenter.shared.rememberCategories(container: container, categories: transactions.compactMap(\.category))
        let ledger = try await LedgerCalculationCoordinator.shared.prepare(container: container,
            accounts: conti.map(LedgerCacheAccount.init), transactions: transactions.map(TransactionSnapshot.init(from:)), now: now)
        let value = FinanceWidgetBuilder.build(
            accounts: accounts,
            budgets: try context.fetch(FetchDescriptor<Budget>()),
            transactions: transactions,
            resolutions: try context.fetch(FetchDescriptor<RecurrenceResolution>()), now: now,
            ledgerSnapshots: ledger.snapshots)
        try Task.checkCancellation()
        LedgerCache.apply(ledger, to: conti)
        do { try FinanceDataChangeCenter.shared.saveCache(context: context) }
        catch { context.rollback() }
        return value
    }
}
