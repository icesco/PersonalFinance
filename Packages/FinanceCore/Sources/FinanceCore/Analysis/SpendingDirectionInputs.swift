import Foundation

/// Separates money already recorded as of now from future commitments.
/// Values are detached from SwiftData before the estimate is calculated.
public struct SpendingDirectionInputs: Sendable {
    public let transactions: [DirectionTransaction]
    public let planned: [PlannedCashMovement]
    public let liquidBalance: Decimal
    public let creditDebt: Decimal
    public let balancesVerified: Bool

    @MainActor
    public static func build(conti: [Conto], transactions: [Transaction], resolutions: [RecurrenceResolution],
                             now: Date, horizon: Date) -> SpendingDirectionInputs {
        let ids = Set(conti.map(\.id))
        var seen: Set<UUID> = []
        let relevant = transactions.filter {
            seen.insert($0.id).inserted &&
            (($0.fromContoId.map { ids.contains($0) } ?? false) ||
             ($0.toContoId.map { ids.contains($0) } ?? false))
        }
        let entries = relevant.map {
            DirectionTransaction(date: $0.date, amount: $0.amount ?? 0, type: $0.type,
                                 categoryID: $0.categoryId, categoryName: $0.category?.name ?? "Da classificare",
                                 isRecurring: $0.isRecurring == true || $0.recurrenceSourceID != nil,
                                 hasValidAmount: $0.amount != nil && $0.amount?.isNaN == false)
        }
        // A materialized occurrence may arrive before its resolution through iCloud.
        let resolved = Set(resolutions.map(\.key)).union(relevant.compactMap { transaction -> String? in
            guard transaction.recurrenceSourceID != nil else { return nil }
            return transaction.externalID
        })
        var planned: [PlannedCashMovement] = []
        for transaction in relevant where transaction.type != .transfer {
            let contoID = transaction.type == .income ? transaction.toContoId : transaction.fromContoId
            guard let contoID, ids.contains(contoID) else { continue }
            let recurring = transaction.isRecurring == true || transaction.recurrenceSourceID != nil
            let title = transaction.transactionDescription ?? transaction.category?.name ?? "Movimento previsto"
            if transaction.date > now, transaction.date <= horizon {
                planned.append(PlannedCashMovement(date: transaction.date, amount: transaction.amount ?? 0,
                                                   type: transaction.type, title: title, isRecurring: recurring))
            }
            guard transaction.isRecurring == true else { continue }
            for date in transaction.recurrenceDates(after: max(now, transaction.date), through: horizon)
                where !resolved.contains(RecurrenceResolution.key(sourceID: transaction.id, date: date)) {
                planned.append(PlannedCashMovement(date: date, amount: transaction.amount ?? 0,
                                                   type: transaction.type, title: title, isRecurring: true))
            }
        }
        let recorded = relevant.filter { $0.date <= now }.map { TransactionSnapshot(from: $0) }
        var liquid: Decimal = 0
        var debt: Decimal = 0
        let balanceConti = conti.filter { [.checking, .savings, .cash, .credit].contains($0.type) }
        for conto in balanceConti {
            let balance = recorded.reduce(conto.initialBalance ?? 0) {
                $0 + BalanceCalculator.netChange(for: $1, contiIDs: [conto.id])
            }
            if conto.type == .credit { debt += max(0, -balance) }
            else { liquid += balance }
        }
        return SpendingDirectionInputs(transactions: entries, planned: planned.sorted { $0.date < $1.date },
                                       liquidBalance: liquid, creditDebt: debt,
                                       balancesVerified: !balanceConti.isEmpty && balanceConti.allSatisfy { $0.initialBalance != nil })
    }
}
