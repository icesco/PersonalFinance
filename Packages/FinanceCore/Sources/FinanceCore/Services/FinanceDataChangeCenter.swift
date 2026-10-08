import Foundation
import SwiftData

/// Excludes inverse transaction collections and derived cache fields. Their changes are
/// covered by transaction endpoints or cache-only writes, not book-wide configuration.
struct FinanceContoState: Sendable, Equatable {
    let values: [String?]
    let logo: Data?
    init(_ conto: Conto) {
        values = [conto.name, conto.type?.rawValue, conto.initialBalance.map { NSDecimalNumber(decimal: $0).stringValue },
            conto.account?.id.uuidString, conto.isActive.map(String.init), conto.color, conto.contoDescription,
            conto.creditLimit.map { NSDecimalNumber(decimal: $0).stringValue },
            conto.statementClosingDay.map(String.init), conto.paymentDueDay.map(String.init),
            conto.annualInterestRate.map { NSDecimalNumber(decimal: $0).stringValue },
            conto.savingsGoal.map { NSDecimalNumber(decimal: $0).stringValue }, conto.savingsRatesJSON,
            conto.savingsGoalID?.uuidString, conto.externalID,
            conto.createdAt.map { String($0.timeIntervalSinceReferenceDate) }]
        logo = conto.logoData
    }
}

struct FinanceCategoryState: Sendable, Equatable {
    let values: [String?]
    init(_ category: Category) {
        values = [category.name, category.color, category.icon, category.isActive.map(String.init),
            category.account?.id.uuidString, category.parentCategoryId?.uuidString, category.kindRaw, category.externalID]
    }
}

public struct FinanceDataChange: Sendable {
    public let containerID: ObjectIdentifier
    /// nil means scope is unknown (or book/budget/category configuration changed).
    public let contoIDs: Set<UUID>?

    public func affects(container: ModelContainer, contoIDs scope: Set<UUID>?) -> Bool {
        guard containerID == ObjectIdentifier(container) else { return false }
        guard let contoIDs, let scope else { return true }
        return !contoIDs.isDisjoint(with: scope)
    }
    public static func from(_ notification: Notification) -> Self? { notification.userInfo?["change"] as? Self }
}

/// Captures changes synchronously on the context's own executor, publishes immutable scopes after save.
/// The lock protects only tiny dictionaries; no fetch, calculation or notification occurs under it.
public final class FinanceDataChangeCenter: @unchecked Sendable {
    public static let shared = FinanceDataChangeCenter()
    public static var notificationName: Notification.Name {
        _ = shared
        return Notification.Name("financeDataDidChange")
    }
    private struct Endpoint: Sendable {
        let ids: Set<UUID>
    }
    private struct Pending {
        let change: FinanceDataChange?
        let rows: [UUID: Endpoint]
        let deleted: Set<UUID>
        let conti: [UUID: FinanceContoState]
        let categories: [UUID: FinanceCategoryState]
    }
    private let lock = NSLock()
    private var known: [ObjectIdentifier: [UUID: Endpoint]] = [:]
    private var knownCategories: [ObjectIdentifier: [UUID: FinanceCategoryState]] = [:]
    private var knownConti: [ObjectIdentifier: [UUID: FinanceContoState]] = [:]
    private var containers: [ObjectIdentifier: ModelContainer] = [:]
    private var pending: [ObjectIdentifier: Pending] = [:]
    private var cacheWriters: Set<ObjectIdentifier> = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { [weak self] in self?.willSave($0) })
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] in self?.didSave($0) })
    }

    public func remember(container: ModelContainer, transactions: [TransactionSnapshot], accounts: [LedgerCacheAccount] = []) {
        let id = ObjectIdentifier(container)
        let rows = Dictionary(transactions.map { ($0.id, Endpoint(ids: Set([$0.fromContoId, $0.toContoId].compactMap { $0 }))) }, uniquingKeysWith: { old, new in
            Endpoint(ids: old.ids.union(new.ids))
        })
        lock.lock(); defer { lock.unlock() }
        retain(container)
        known[id, default: [:]].merge(rows) { old, new in Endpoint(ids: old.ids.union(new.ids)) }
        for account in accounts { if let state = account.changeState { knownConti[id, default: [:]][account.id] = state } }
        if known[id, default: [:]].count > 50_000 { known[id] = rows.count <= 50_000 ? rows : [:] }
    }

    /// Called synchronously by the executor owning the supplied models.
    public func rememberCategories(container: ModelContainer, categories: [Category]) {
        var states: [UUID: FinanceCategoryState] = [:]
        for category in categories where states[category.id] == nil { states[category.id] = FinanceCategoryState(category) }
        lock.lock(); defer { lock.unlock() }
        retain(container)
        knownCategories[ObjectIdentifier(container), default: [:]].merge(states) { _, new in new }
    }

    /// Only fresh cache-only contexts use this method. Their saves cannot trigger financial refresh loops.
    public func saveCache(context: ModelContext) throws {
        guard context.hasChanges else { return }
        let id = ObjectIdentifier(context)
        lock.lock(); cacheWriters.insert(id); lock.unlock()
        defer { lock.lock(); cacheWriters.remove(id); lock.unlock() }
        try context.save()
    }

    private func retain(_ container: ModelContainer) {
        let id = ObjectIdentifier(container)
        containers[id] = container
        if containers.count > 4, let oldest = containers.keys.first(where: { $0 != id }) {
            containers.removeValue(forKey: oldest)
            known.removeValue(forKey: oldest)
            knownConti.removeValue(forKey: oldest)
            knownCategories.removeValue(forKey: oldest)
        }
    }

    private func willSave(_ notification: Notification) {
        guard let context = notification.object as? ModelContext else { return }
        let contextID = ObjectIdentifier(context), containerID = ObjectIdentifier(context.container)
        lock.lock()
        let isCache = cacheWriters.contains(contextID)
        let oldRows = known[containerID] ?? [:]
        let oldConti = knownConti[containerID] ?? [:]
        let oldCategories = knownCategories[containerID] ?? [:]
        lock.unlock()
        if isCache {
            lock.lock(); pending[contextID] = Pending(change: nil, rows: [:], deleted: [], conti: [:], categories: [:]); lock.unlock()
            return
        }
        var ids: Set<UUID> = [], rows: [UUID: Endpoint] = [:], deleted: Set<UUID> = []
        var contoStates: [UUID: FinanceContoState] = [:]
        var categoryStates: [UUID: FinanceCategoryState] = [:]
        var unknown = false
        let inserted = context.insertedModelsArray
        let changed = context.changedModelsArray
        let removed = context.deletedModelsArray
        let insertedIDs = Set(inserted.map(\.persistentModelID))
        let deletedIDs = Set(removed.map(\.persistentModelID))
        for model in inserted + changed + removed {
            if let conto = model as? Conto {
                let state = FinanceContoState(conto)
                contoStates[conto.id] = state
                if oldConti[conto.id] != state || insertedIDs.contains(conto.persistentModelID)
                    || deletedIDs.contains(conto.persistentModelID) { unknown = true }
                continue
            }
            if let category = model as? Category {
                let state = FinanceCategoryState(category)
                categoryStates[category.id] = state
                if oldCategories[category.id] != state || insertedIDs.contains(category.persistentModelID)
                    || deletedIDs.contains(category.persistentModelID) { unknown = true }
                continue
            }
            guard let transaction = model as? Transaction else { unknown = true; continue }
            let endpoints = Set([transaction.fromContoId ?? transaction.fromConto?.id,
                                 transaction.toContoId ?? transaction.toConto?.id].compactMap { $0 })
            ids.formUnion(endpoints)
            if let old = oldRows[transaction.id] { ids.formUnion(old.ids) }
            else if !insertedIDs.contains(transaction.persistentModelID) {
                // A moved endpoint may no longer be present on the edited model. Never guess.
                unknown = true
            }
            rows[transaction.id] = Endpoint(ids: endpoints)
            if deletedIDs.contains(transaction.persistentModelID) { deleted.insert(transaction.id) }
        }
        let change = FinanceDataChange(containerID: containerID, contoIDs: unknown ? nil : ids)
        lock.lock()
        retain(context.container)
        pending[contextID] = Pending(change: change, rows: rows, deleted: deleted, conti: contoStates, categories: categoryStates)
        if pending.count > 256 { pending = [contextID: pending[contextID]!] }
        lock.unlock()
    }

    private func didSave(_ notification: Notification) {
        guard let context = notification.object as? ModelContext else { return }
        let id = ObjectIdentifier(context.container)
        lock.lock()
        let value = pending.removeValue(forKey: ObjectIdentifier(context))
        if let value {
            known[id, default: [:]].merge(value.rows) { _, new in new }
            for row in value.deleted { known[id]?.removeValue(forKey: row) }
            knownConti[id, default: [:]].merge(value.conti) { _, new in new }
            knownCategories[id, default: [:]].merge(value.categories) { _, new in new }
            if known[id, default: [:]].count > 50_000 { known[id] = [:] }
        }
        lock.unlock()
        let change = value?.change ?? (value == nil ? FinanceDataChange(containerID: id, contoIDs: nil) : nil)
        if let change {
            NotificationCenter.default.post(name: Notification.Name("financeDataDidChange"), object: nil, userInfo: ["change": change])
        }
    }
}
