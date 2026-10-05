import Foundation
import SwiftData

@MainActor
public enum BalanceReconciliation {
    public enum Failure: Error { case invalidAmount, missingAccount, staleMovements }
    public struct Status {
        public let balance: Decimal
        public let latestMovement: Date?
        public let canReconcile: Bool
    }

    public static func status(for conto: Conto, now: Date = .now) -> Status {
        var seen: Set<UUID> = []
        let recorded = conto.allTransactions.filter { $0.date <= now && seen.insert($0.id).inserted }
        let net = recorded.reduce(Decimal.zero) { result, transaction in
            let snapshot = TransactionSnapshot(amount: transaction.amount ?? 0, type: transaction.type, date: transaction.date,
                                               fromContoId: transaction.fromConto?.id ?? transaction.fromContoId,
                                               toContoId: transaction.toConto?.id ?? transaction.toContoId,
                                               destinationAmount: transaction.destinationAmount)
            return result + BalanceCalculator.netChange(for: snapshot, contiIDs: [conto.id])
        }
        let latest = recorded.map(\.date).max()
        return Status(balance: (conto.initialBalance ?? 0) + net, latestMovement: latest,
                      canReconcile: latest.map { now.timeIntervalSince($0) <= 7 * 86_400 } ?? false)
    }

    /// Changes only the opening balance. No synthetic transaction is inserted.
    /// A private context prevents a failed save from becoming a later autosave.
    @discardableResult
    public static func apply(contoID: UUID, enteredBalance: String, container: ModelContainer, now: Date = .now) throws -> Decimal {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            guard let conto = try context.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == contoID })).first,
                  conto.isActive != false else { throw Failure.missingAccount }
            guard !enteredBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let target = BalanceInput.parse(enteredBalance, currency: conto.account?.currency ?? "EUR") else { throw Failure.invalidAmount }
            let current = status(for: conto, now: now)
            guard current.canReconcile else { throw Failure.staleMovements }
            let corrected = (conto.initialBalance ?? 0) + target - current.balance
            guard !corrected.isNaN else { throw Failure.invalidAmount }
            conto.initialBalance = corrected
            conto.updatedAt = now
            try context.save()
            return corrected
        } catch { context.rollback(); throw error }
    }
}
