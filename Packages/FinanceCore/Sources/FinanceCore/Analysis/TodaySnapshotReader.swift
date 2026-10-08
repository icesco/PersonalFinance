import Foundation
import SwiftData

public struct TodayBudgetSnapshot: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let limit: Decimal
    public let spent: Decimal
    public let threshold: Double
    public let currency: String
    public let icon: String
    public let colorHex: String
    public var remaining: Decimal { limit - spent }
    public var share: Double { limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0 }

    init(_ budget: Budget, now: Date, transactions: [Transaction]) {
        id = budget.id
        name = budget.name ?? "Budget"
        limit = budget.amount ?? 0
        if let interval = budget.period?.interval(containing: now) {
            spent = RecordedBudgetSpending.total(for: budget, transactions: transactions,
                                                start: interval.start, end: interval.end)
        } else { spent = 0 }
        threshold = budget.alertThreshold ?? 0.8
        currency = budget.account?.currency ?? "EUR"
        let category = Category.displayOrdered(budget.categories ?? []).first
        icon = category?.icon?.isEmpty == false ? category!.icon! : "target"
        colorHex = category?.color ?? CategoryPalette.fallback
    }
}

public struct TodaySnapshot: Sendable {
    public let entries: [DirectionTransaction]
    public let contoIDs: Set<UUID>
    public let refreshContoIDs: Set<UUID>
    public let accountName: String
    public let currency: String
    public let hasMixedCurrencies: Bool
    public let direction: SpendingDirection
    public let planned: [PlannedCashMovement]
    public let budgets: [TodayBudgetSnapshot]

    public init(entries: [DirectionTransaction], contoIDs: Set<UUID>, accountName: String,
                currency: String, hasMixedCurrencies: Bool, direction: SpendingDirection,
                planned: [PlannedCashMovement], budgets: [TodayBudgetSnapshot] = [], refreshContoIDs: Set<UUID>? = nil) {
        self.entries = entries
        self.contoIDs = contoIDs
        self.refreshContoIDs = refreshContoIDs ?? contoIDs
        self.accountName = accountName
        self.currency = currency
        self.hasMixedCurrencies = hasMixedCurrencies
        self.direction = direction
        self.planned = planned
        self.budgets = budgets
    }
}

/// Owns its read context off the UI executor. Only immutable values cross the boundary.
public actor TodaySnapshotReader {
    public init() {}

    public func load(container: ModelContainer, accountID: UUID?, showAllAccounts: Bool,
                     now: Date = Date()) async throws -> TodaySnapshot {
        try Task.checkCancellation()
        // A fresh context sees committed imports/edits without retaining old registered models.
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let accounts: [Account]
        if showAllAccounts {
            accounts = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.isActive == true }))
        } else if let accountID {
            accounts = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountID }))
        } else {
            accounts = []
        }
        let conti = accounts.flatMap(\.activeConti)
        let ids = Array(Set(conti.map(\.id)))
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { transaction in
            transaction.fromContoId.flatMap { ids.contains($0) } == true
                || transaction.toContoId.flatMap { ids.contains($0) } == true
        })
        descriptor.relationshipKeyPathsForPrefetching = [\.category]
        // Keep all history for balances and Analysis; limiting to 90 days would corrupt totals.
        let transactions = ids.isEmpty ? [] : try context.fetch(descriptor)
        let resolutions = ids.isEmpty ? [] : try context.fetch(FetchDescriptor<RecurrenceResolution>())
        try Task.checkCancellation()
        // Match the Home's existing deduplication policy before validating cached balances.
        var seen: Set<UUID> = []
        let ledgerEntries = transactions.filter { seen.insert($0.id).inserted }.map { TransactionSnapshot(from: $0) }
        FinanceDataChangeCenter.shared.rememberCategories(container: container, categories: transactions.compactMap(\.category))
        let ledger = try await LedgerCalculationCoordinator.shared.prepare(container: container,
            accounts: conti.map(LedgerCacheAccount.init), transactions: ledgerEntries, now: now)
        let horizon = Calendar.current.date(byAdding: .day, value: 45, to: now) ?? now
        let inputs = SpendingDirectionInputs.build(conti: conti, transactions: transactions,
                                                   resolutions: resolutions, now: now, horizon: horizon,
                                                   recordedBalances: ledger.snapshots.mapValues(\.balance))
        let direction = SpendingDirectionCalculator.calculate(
            transactions: inputs.transactions, planned: inputs.planned,
            liquidBalance: inputs.liquidBalance, creditDebt: inputs.creditDebt,
            balancesVerified: inputs.balancesVerified, now: now)
        try Task.checkCancellation()
        // The Home budget card follows the selected book even in the all-books overview.
        let budgetAccount: Account?
        if showAllAccounts, let accountID {
            budgetAccount = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountID })).first
        } else {
            budgetAccount = showAllAccounts ? nil : accounts.first
        }
        // Budgets with the same period share a single bounded fetch, including archived conti.
        var periodExpenses: [DateInterval: [Transaction]] = [:]
        let budgets = try (budgetAccount?.budgets ?? []).filter { $0.isActive == true }
            .map { budget in
                try Task.checkCancellation()
                guard let interval = budget.period?.interval(containing: now) else {
                    return TodayBudgetSnapshot(budget, now: now, transactions: [])
                }
                if periodExpenses[interval] == nil {
                    let start = interval.start
                    let end = interval.end
                    let expenseType = TransactionType.expense.rawValue
                    periodExpenses[interval] = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate {
                        $0.date >= start && $0.date < end && $0.typeRaw == expenseType
                    }))
                }
                return TodayBudgetSnapshot(budget, now: now, transactions: periodExpenses[interval] ?? [])
            }.sorted { lhs, rhs in
                let left = lhs.spent > lhs.limit
                let right = rhs.spent > rhs.limit
                return left != right ? left : lhs.share > rhs.share
            }
        try Task.checkCancellation()
        LedgerCache.apply(ledger, to: conti)
        do { try FinanceDataChangeCenter.shared.saveCache(context: context) }
        catch { context.rollback() } // Cache write failure must not fail the financial calculation.
        return TodaySnapshot(entries: inputs.transactions, contoIDs: Set(ids),
            accountName: showAllAccounts ? "Tutti i libri" : accounts.first?.name ?? "Il tuo libro",
            currency: accounts.first?.currency ?? "EUR",
            hasMixedCurrencies: Set(accounts.compactMap(\.currency)).count > 1,
            direction: direction, planned: inputs.planned.filter { $0.type == .expense && $0.date > now },
            budgets: budgets, refreshContoIDs: Set((accounts.flatMap { $0.conti ?? [] } + (budgetAccount?.conti ?? [])).map(\.id)))
    }
}
