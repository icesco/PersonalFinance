import Foundation

/// Forward ledger estimate based only on explicitly scheduled movements and recurrences.
public enum ProjectedBalanceHistory {
    @MainActor
    public static func plannedTransactions(transactions: [Transaction], resolutions: [RecurrenceResolution],
                                           now: Date, through end: Date) -> [TransactionSnapshot] {
        var seen: Set<UUID> = []
        let unique = transactions.filter { seen.insert($0.id).inserted }
        // Materialized occurrences can sync before their resolution; suppress their virtual copy too.
        let resolved = Set(resolutions.map(\.key)).union(unique.compactMap { transaction -> String? in
            guard transaction.recurrenceSourceID != nil else { return nil }
            return transaction.externalID
        })
        var planned: [TransactionSnapshot] = []
        for transaction in unique {
            func snapshot(at date: Date) -> TransactionSnapshot {
                TransactionSnapshot(id: transaction.id, amount: transaction.amount ?? 0, type: transaction.type,
                                    date: date, fromContoId: transaction.fromContoId ?? transaction.fromConto?.id,
                                    toContoId: transaction.toContoId ?? transaction.toConto?.id,
                                    destinationAmount: transaction.destinationAmount)
            }
            if transaction.date > now, transaction.date < end {
                planned.append(snapshot(at: transaction.date))
            }
            guard transaction.isRecurring == true, let frequency = transaction.recurrenceFrequency else { continue }
            for date in RecurrenceSchedule.dates(anchor: transaction.date, frequency: frequency,
                after: max(now, transaction.date), through: end, ending: transaction.recurrenceEndDate)
                where date < end && !resolved.contains(RecurrenceResolution.key(sourceID: transaction.id, date: date)) {
                planned.append(snapshot(at: date))
            }
        }
        return planned.sorted { $0.date < $1.date }
    }

    public static func points(planned: [TransactionSnapshot], contoID: UUID, openingBalance: Decimal,
                              interval: DateInterval, now: Date) -> [BalanceDataPoint] {
        guard interval.start <= now, now < interval.end else { return [] }
        var changes: [Date: Decimal] = [:]
        for transaction in planned where transaction.date > now && transaction.date < interval.end {
            let delta = BalanceCalculator.netChange(for: transaction, contiIDs: [contoID])
            guard delta != 0 else { continue }
            changes[transaction.date, default: 0] += delta
        }
        var balance = openingBalance
        var result = [BalanceDataPoint(date: now, balance: balance)]
        for date in changes.keys.sorted() {
            balance += changes[date] ?? 0
            result.append(BalanceDataPoint(date: date, balance: balance))
        }
        result.append(BalanceDataPoint(date: interval.end, balance: balance))
        return result
    }
}
