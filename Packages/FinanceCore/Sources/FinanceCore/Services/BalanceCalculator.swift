import Foundation

/// Pure calculation functions for dashboard balance computations.
/// All functions are static, take value types, and return value types — no SwiftData dependency.
public struct BalanceCalculator: Sendable {

    // MARK: - 1. Net Change

    /// Calculate the net balance change of a single transaction relative to a set of conto IDs.
    ///
    /// - Income to a conto in the set: +amount
    /// - Expense from a conto in the set: -amount
    /// - Transfer out (from set, to external): -amount
    /// - Transfer in (from external, to set): +amount
    /// - Transfer internal (both in set): 0 (cancels out)
    /// - Transfer external (neither in set): 0
    public static func netChange(for transaction: TransactionSnapshot, contiIDs: Set<UUID>) -> Decimal {
        let amount = transaction.amount
        switch transaction.type {
        case .income:
            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                return amount
            }
            return 0
        case .expense:
            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                return -amount
            }
            return 0
        case .transfer:
            var change: Decimal = 0
            if let fromId = transaction.fromContoId, contiIDs.contains(fromId) {
                change -= amount
            }
            if let toId = transaction.toContoId, contiIDs.contains(toId) {
                change += amount
            }
            return change
        }
    }

    // MARK: - 2. Total Balance

    /// Sum an array of conto balances
    public static func totalBalance(contiBalances: [Decimal]) -> Decimal {
        contiBalances.reduce(Decimal(0), +)
    }

    // MARK: - 3. Absolute Change

    /// Absolute change between current and period start balance
    public static func absoluteChange(current: Decimal, periodStart: Decimal) -> Decimal {
        current - periodStart
    }

    // MARK: - 4. Percentage Change

    /// Percentage change from period start to current.
    /// Returns 0 if periodStart is zero.
    /// Uses absolute value of periodStart to handle negative-to-positive transitions correctly.
    public static func percentageChange(current: Decimal, periodStart: Decimal) -> Double {
        guard periodStart != 0 else { return 0 }
        let absPeriodStart = periodStart < 0 ? -periodStart : periodStart
        let change = (absoluteChange(current: current, periodStart: periodStart) / absPeriodStart) * 100
        return NSDecimalNumber(decimal: change).doubleValue
    }

    // MARK: - 5. Chart Y Domain

    /// Calculate the Y-axis domain for a chart with 10% padding.
    /// Positive-only data won't go below 0. Single-value data gets ±50 range.
    public static func chartYDomain(dataPoints: [BalanceDataPoint]) -> ClosedRange<Decimal> {
        guard !dataPoints.isEmpty else { return 0...100 }

        let values = dataPoints.map(\.balance)
        let minValue = values.min()!
        let maxValue = values.max()!

        if minValue == maxValue {
            return (minValue - 50)...(maxValue + 50)
        }

        let range = maxValue - minValue
        let padding = range * Decimal(string: "0.1")!

        let lowerBound = minValue >= 0 ? max(0, minValue - padding) : minValue - padding
        let upperBound = maxValue + padding

        return lowerBound...upperBound
    }

    // MARK: - 6. Period Start Balance (BUG FIX: now handles transfers)

    /// Calculate the balance at the start of a chart period by subtracting the net change
    /// of all transactions from periodStart to now from the current total balance.
    ///
    /// **Bug fix**: Previous implementation ignored transfers (`case .transfer: return result`).
    /// This version correctly accounts for transfers using `netChange(for:contiIDs:)`.
    public static func periodStartBalance(
        currentTotal: Decimal,
        transactions: [TransactionSnapshot],
        contiIDs: Set<UUID>,
        periodStart: Date,
        now: Date
    ) -> Decimal {
        let periodNet = transactions
            .filter { $0.date >= periodStart && $0.date <= now }
            .reduce(Decimal(0)) { result, tx in
                result + netChange(for: tx, contiIDs: contiIDs)
            }
        return currentTotal - periodNet
    }

    // MARK: - 7. Monthly Totals

    /// Calculate income and expense totals for transactions in a date range.
    /// Transfers are excluded (they move money, don't create/destroy it).
    public static func monthlyTotals(
        transactions: [TransactionSnapshot],
        contiIDs: Set<UUID>,
        start: Date,
        end: Date
    ) -> (income: Decimal, expenses: Decimal) {
        let filtered = transactions.filter { $0.date >= start && $0.date < end }

        let income = filtered
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { result, tx in
                if let toId = tx.toContoId, contiIDs.contains(toId) {
                    return result + tx.amount
                }
                return result
            }

        let expenses = filtered
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { result, tx in
                if let fromId = tx.fromContoId, contiIDs.contains(fromId) {
                    return result + tx.amount
                }
                return result
            }

        return (income, expenses)
    }

    // MARK: - 8. Balance History

    /// Build a chronological balance history from transactions, with daily granularity
    /// and month-end anchor points for smooth charting.
    public static func balanceHistory(
        transactions: [TransactionSnapshot],
        contiIDs: Set<UUID>,
        initialBalance: Decimal,
        periodStart: Date,
        periodEnd: Date,
        calendar: Calendar = .current
    ) -> [BalanceDataPoint] {
        guard periodStart <= periodEnd else { return [] }

        // Sort all transactions by date
        let sorted = transactions.sorted { $0.date < $1.date }

        // Calculate balance before the period start
        var balanceBeforePeriod = initialBalance
        for tx in sorted {
            guard tx.date < periodStart else { break }
            balanceBeforePeriod += netChange(for: tx, contiIDs: contiIDs)
        }

        // Filter transactions within the period
        let periodTransactions = sorted.filter { $0.date >= periodStart && $0.date <= periodEnd }

        // Build data points
        var data: [BalanceDataPoint] = []
        var runningBalance = balanceBeforePeriod

        // Start point
        data.append(BalanceDataPoint(date: periodStart, balance: runningBalance))

        // Group by day
        var transactionsByDay: [Date: [TransactionSnapshot]] = [:]
        for tx in periodTransactions {
            let dayStart = calendar.startOfDay(for: tx.date)
            transactionsByDay[dayStart, default: []].append(tx)
        }

        // Process each day
        for day in transactionsByDay.keys.sorted() {
            guard let dayTransactions = transactionsByDay[day] else { continue }
            for tx in dayTransactions {
                runningBalance += netChange(for: tx, contiIDs: contiIDs)
            }
            data.append(BalanceDataPoint(date: day, balance: runningBalance))
        }

        // Add month-end anchor points
        var monthEndDates: [Date] = []
        var currentMonth = periodStart
        while currentMonth <= periodEnd {
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            let effectiveEnd = min(endOfMonth, periodEnd)
            monthEndDates.append(effectiveEnd)
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { break }
            currentMonth = nextMonth
        }

        for monthEnd in monthEndDates {
            if let lastPoint = data.last, !calendar.isDate(lastPoint.date, inSameDayAs: monthEnd) {
                let hasPointInMonth = data.contains { calendar.isDate($0.date, equalTo: monthEnd, toGranularity: .month) }
                if !hasPointInMonth || data.last!.date < monthEnd {
                    data.append(BalanceDataPoint(date: monthEnd, balance: runningBalance))
                }
            }
        }

        return data.sorted { $0.date < $1.date }
    }

    // MARK: - 9. Split Balance History

    /// Split balance history into past and future segments for chart rendering.
    /// Future data is only returned for `.oneMonth` period.
    public static func splitBalanceHistory(
        history: [BalanceDataPoint],
        today: Date,
        period: ChartPeriod,
        selectedMonth: Date,
        calendar: Calendar = .current
    ) -> (past: [BalanceDataPoint], future: [BalanceDataPoint]) {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        let past = history.filter { $0.date < endOfToday }

        guard period == .oneMonth else {
            return (past, [])
        }

        let todayStart = calendar.startOfDay(for: today)
        var future = history.filter { $0.date >= endOfToday }

        guard let lastPast = past.last else {
            return (past, future)
        }

        let todayPoint = BalanceDataPoint(date: todayStart, balance: lastPast.balance)

        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!

        if future.isEmpty {
            if endOfMonth > todayStart {
                return (past, [todayPoint, BalanceDataPoint(date: endOfMonth, balance: lastPast.balance)])
            }
            return (past, [])
        } else {
            future.insert(todayPoint, at: 0)
            if let lastFuture = future.last, lastFuture.date < endOfMonth {
                future.append(BalanceDataPoint(date: endOfMonth, balance: lastFuture.balance))
            }
            return (past, future)
        }
    }

    // MARK: - 10. Multi-Account Balance History

    /// Build balance history for multiple accounts (Libri), one line per account.
    /// Works backwards from current balance using monthly net changes.
    public static func multiAccountBalanceHistory(
        accounts: [AccountInput],
        transactions: [TransactionSnapshot],
        monthsToLoad: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [AccountBalanceDataPoint] {
        var data: [AccountBalanceDataPoint] = []

        for account in accounts {
            let contiIDs = account.contiIDs

            // Calculate balance as of now
            let txUpToNow = transactions.filter { $0.date <= now }
            var balanceAsOfNow = account.initialBalance
            for tx in txUpToNow {
                balanceAsOfNow += netChange(for: tx, contiIDs: contiIDs)
            }

            // Collect monthly net changes
            var monthlyNetChanges: [(date: Date, net: Decimal)] = []
            for i in 0..<monthsToLoad {
                guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                let effectiveEndDate = i == 0 ? now : endOfMonth

                let monthTx = transactions.filter { $0.date >= startOfMonth && $0.date <= effectiveEndDate }
                var netChange: Decimal = 0
                for tx in monthTx {
                    netChange += Self.netChange(for: tx, contiIDs: contiIDs)
                }
                monthlyNetChanges.append((date: startOfMonth, net: netChange))
            }

            // Build history working backwards
            var accountData: [AccountBalanceDataPoint] = []
            var runningBalance = balanceAsOfNow

            for (index, monthData) in monthlyNetChanges.enumerated() {
                if index == 0 {
                    accountData.append(AccountBalanceDataPoint(
                        accountId: account.id,
                        accountName: account.name,
                        date: monthData.date,
                        balance: runningBalance,
                        colorIndex: account.colorIndex
                    ))
                } else {
                    let recentMonthNet = monthlyNetChanges[index - 1].net
                    runningBalance -= recentMonthNet
                    accountData.append(AccountBalanceDataPoint(
                        accountId: account.id,
                        accountName: account.name,
                        date: monthData.date,
                        balance: runningBalance,
                        colorIndex: account.colorIndex
                    ))
                }
            }

            data.append(contentsOf: accountData.reversed())
        }

        return data
    }

    // MARK: - 11. Multi-Conto Balance History

    /// Build balance history for multiple conti, one line per conto.
    /// Only includes conti that have transactions in the period.
    public static func multiContoBalanceHistory(
        conti: [ContoInput],
        transactions: [TransactionSnapshot],
        monthsToLoad: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [AccountBalanceDataPoint] {
        var data: [AccountBalanceDataPoint] = []

        for conto in conti {
            let contoID = conto.id
            let contiIDs: Set<UUID> = [contoID]

            // Calculate balance as of now
            let txUpToNow = transactions.filter { $0.date <= now }
            var balanceAsOfNow = conto.initialBalance
            for tx in txUpToNow {
                balanceAsOfNow += netChange(for: tx, contiIDs: contiIDs)
            }

            // Collect monthly net changes
            var monthlyNetChanges: [(date: Date, net: Decimal)] = []
            var hasAnyTransactions = false

            for i in 0..<monthsToLoad {
                guard let monthDate = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                let effectiveEndDate = i == 0 ? now : endOfMonth

                let monthTx = transactions.filter { $0.date >= startOfMonth && $0.date <= effectiveEndDate }
                let relevant = monthTx.filter {
                    $0.fromContoId == contoID || $0.toContoId == contoID
                }

                if !relevant.isEmpty {
                    hasAnyTransactions = true
                }

                var net: Decimal = 0
                for tx in relevant {
                    net += Self.netChange(for: tx, contiIDs: contiIDs)
                }
                monthlyNetChanges.append((date: startOfMonth, net: net))
            }

            guard hasAnyTransactions else { continue }

            // Build history working backwards
            var contoData: [AccountBalanceDataPoint] = []
            var runningBalance = balanceAsOfNow

            for (index, monthData) in monthlyNetChanges.enumerated() {
                if index == 0 {
                    contoData.append(AccountBalanceDataPoint(
                        accountId: contoID,
                        accountName: conto.name,
                        date: monthData.date,
                        balance: runningBalance,
                        colorIndex: conto.colorIndex
                    ))
                } else {
                    let recentMonthNet = monthlyNetChanges[index - 1].net
                    runningBalance -= recentMonthNet
                    contoData.append(AccountBalanceDataPoint(
                        accountId: contoID,
                        accountName: conto.name,
                        date: monthData.date,
                        balance: runningBalance,
                        colorIndex: conto.colorIndex
                    ))
                }
            }

            data.append(contentsOf: contoData.reversed())
        }

        return data
    }

    // MARK: - 12. Conti Changes

    /// Calculate net change for each conto in a date range.
    public static func contiChanges(
        transactions: [TransactionSnapshot],
        contiIDs: Set<UUID>,
        start: Date,
        end: Date
    ) -> [UUID: Decimal] {
        let filtered = transactions.filter { $0.date >= start && $0.date < end }
        var changes: [UUID: Decimal] = [:]

        for contoID in contiIDs {
            let singleSet: Set<UUID> = [contoID]
            let relevant = filtered.filter {
                $0.fromContoId == contoID || $0.toContoId == contoID
            }
            let change = relevant.reduce(Decimal(0)) { result, tx in
                result + netChange(for: tx, contiIDs: singleSet)
            }
            changes[contoID] = change
        }

        return changes
    }

    // MARK: - 13. Format Compact Currency

    /// Format a decimal value as a compact currency string (e.g. "1.5M €", "500K €", "42 €")
    public static func formatCompactCurrency(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        let absValue = abs(doubleValue)

        if absValue >= 1_000_000 {
            return String(format: "%.1fM €", doubleValue / 1_000_000)
        } else if absValue >= 1_000 {
            return String(format: "%.0fK €", doubleValue / 1_000)
        } else {
            return String(format: "%.0f €", doubleValue)
        }
    }
}
