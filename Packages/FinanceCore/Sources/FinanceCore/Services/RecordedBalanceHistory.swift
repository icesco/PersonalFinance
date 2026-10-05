import Foundation

/// Recorded ledger history only. Recurrence projections must be rendered separately.
public enum RecordedBalanceHistory {
    public static func points(transactions: [TransactionSnapshot], contiIDs: Set<UUID>, initialBalance: Decimal,
                              interval: DateInterval, now: Date) -> [BalanceDataPoint] {
        guard !contiIDs.isEmpty, interval.start <= now, interval.duration > 0 else { return [] }
        let end = min(now, interval.end)
        var opening = initialBalance
        var changes: [Date: Decimal] = [:]
        for transaction in transactions where transaction.date <= now && transaction.date < interval.end {
            let delta = BalanceCalculator.netChange(for: transaction, contiIDs: contiIDs)
            if transaction.date < interval.start { opening += delta }
            else if transaction.date <= end { changes[transaction.date, default: 0] += delta }
        }
        // At a timestamp the displayed balance includes all entries at that time.
        opening += changes.removeValue(forKey: interval.start) ?? 0
        var result = [BalanceDataPoint(date: interval.start, balance: opening)]
        var balance = opening
        for date in changes.keys.sorted() {
            balance += changes[date] ?? 0
            result.append(BalanceDataPoint(date: date, balance: balance))
        }
        if result.last?.date != end { result.append(BalanceDataPoint(date: end, balance: balance)) }
        return result
    }
}
