import Foundation
import SwiftData
import SwiftUI
import FinanceCore

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - Data State

    var monthlyIncome: Decimal = 0
    var monthlyExpenses: Decimal = 0
    var periodStartBalance: Decimal = 0
    var balanceHistory: [BalanceDataPoint] = []
    var multiAccountHistory: [AccountBalanceDataPoint] = []
    var multiContoHistory: [AccountBalanceDataPoint] = []
    var contiChanges: [UUID: Decimal] = [:]
    var recentTransactions: [FinanceCore.Transaction] = []
    var hasTransactionsInPeriod: Bool = true

    // MARK: - Selection State

    var selectedPeriod: ChartPeriod = .sixMonths
    var selectedMonth: Date = Date()

    // MARK: - Computed Properties (delegating to BalanceCalculator)

    func totalBalance(for accounts: [Account]) -> Decimal {
        let balances = accounts.map(\.totalBalance)
        return BalanceCalculator.totalBalance(contiBalances: balances)
    }

    func absoluteChange(for accounts: [Account]) -> Decimal {
        BalanceCalculator.absoluteChange(current: totalBalance(for: accounts), periodStart: periodStartBalance)
    }

    func percentageChange(for accounts: [Account]) -> Double {
        BalanceCalculator.percentageChange(current: totalBalance(for: accounts), periodStart: periodStartBalance)
    }

    func isPositiveChange(for accounts: [Account]) -> Bool {
        absoluteChange(for: accounts) >= 0
    }

    func chartYDomain(for accounts: [Account]) -> ClosedRange<Decimal> {
        let allPoints = pastBalanceHistory(for: accounts) + futureBalanceHistory(for: accounts)
        return BalanceCalculator.chartYDomain(dataPoints: allPoints)
    }

    func pastBalanceHistory(for accounts: [Account]) -> [BalanceDataPoint] {
        let (past, _) = BalanceCalculator.splitBalanceHistory(
            history: balanceHistory,
            today: Date(),
            period: selectedPeriod,
            selectedMonth: selectedMonth
        )
        return past
    }

    func futureBalanceHistory(for accounts: [Account]) -> [BalanceDataPoint] {
        let (_, future) = BalanceCalculator.splitBalanceHistory(
            history: balanceHistory,
            today: Date(),
            period: selectedPeriod,
            selectedMonth: selectedMonth
        )
        return future
    }

    // MARK: - Data Loading

    func loadDashboardData(
        displayedAccounts: [Account],
        allDisplayedConti: [Conto],
        showAllAccounts: Bool,
        showAllConti: Bool,
        modelContext: ModelContext
    ) {
        guard !displayedAccounts.isEmpty else {
            resetData()
            return
        }

        let allContiIDs = Set(allDisplayedConti.map(\.id))
        let calendar = Calendar.current
        let now = Date()

        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        // Fetch all transactions once for snapshot-based calculations
        let allSnapshots = fetchAllTransactionSnapshots(contiIDs: allContiIDs, modelContext: modelContext)
        let currentTotal = BalanceCalculator.totalBalance(contiBalances: displayedAccounts.map(\.totalBalance))

        // Period start balance (with transfer bug fix)
        let periodStart = computePeriodStartDate(now: now, calendar: calendar)
        periodStartBalance = BalanceCalculator.periodStartBalance(
            currentTotal: currentTotal,
            transactions: allSnapshots,
            contiIDs: allContiIDs,
            periodStart: periodStart,
            now: now
        )

        // Monthly totals
        let totals = BalanceCalculator.monthlyTotals(
            transactions: allSnapshots,
            contiIDs: allContiIDs,
            start: startOfMonth,
            end: endOfMonth
        )
        monthlyIncome = totals.income
        monthlyExpenses = totals.expenses

        // Balance history based on view mode
        if showAllAccounts && displayedAccounts.count > 1 {
            loadMultiAccountBalanceHistory(
                accounts: displayedAccounts,
                modelContext: modelContext
            )
        } else if !showAllAccounts && showAllConti && allDisplayedConti.count > 1 {
            loadMultiContoBalanceHistory(
                conti: allDisplayedConti,
                modelContext: modelContext
            )
        } else {
            loadBalanceHistory(
                allDisplayedConti: allDisplayedConti,
                contiIDs: allContiIDs,
                modelContext: modelContext
            )
        }

        // Conti changes
        contiChanges = BalanceCalculator.contiChanges(
            transactions: allSnapshots,
            contiIDs: allContiIDs,
            start: startOfMonth,
            end: endOfMonth
        )

        // Recent transactions (for single account view)
        if !showAllAccounts {
            loadRecentTransactions(contiIDs: allContiIDs, modelContext: modelContext)
        }
    }

    func resetData() {
        monthlyIncome = 0
        monthlyExpenses = 0
        periodStartBalance = 0
        balanceHistory = []
        multiAccountHistory = []
        multiContoHistory = []
        contiChanges = [:]
        recentTransactions = []
        hasTransactionsInPeriod = true
    }

    // MARK: - Private Helpers

    private func computePeriodStartDate(now: Date, calendar: Calendar) -> Date {
        if selectedPeriod == .oneMonth {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        } else {
            let monthsBack = selectedPeriod.monthsCount ?? 24
            let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return calendar.date(byAdding: .month, value: -(monthsBack - 1), to: startOfCurrentMonth)!
        }
    }

    private func fetchAllTransactionSnapshots(contiIDs: Set<UUID>, modelContext: ModelContext) -> [TransactionSnapshot] {
        let descriptor = FetchDescriptor<FinanceCore.Transaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)
            return allTransactions
                .filter { tx in
                    if let id = tx.fromContoId, contiIDs.contains(id) { return true }
                    if let id = tx.toContoId, contiIDs.contains(id) { return true }
                    return false
                }
                .map { TransactionSnapshot(from: $0) }
        } catch {
            return []
        }
    }

    private func loadBalanceHistory(
        allDisplayedConti: [Conto],
        contiIDs: Set<UUID>,
        modelContext: ModelContext
    ) {
        let calendar = Calendar.current
        let now = Date()

        let initialBalance = allDisplayedConti.reduce(Decimal(0)) { $0 + ($1.initialBalance ?? 0) }

        let periodStartDate: Date
        let periodEndDate: Date

        if selectedPeriod == .oneMonth {
            periodStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
            let endOfSelectedMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: periodStartDate)!
            periodEndDate = endOfSelectedMonth
        } else {
            let monthsBack = selectedPeriod.monthsCount ?? 24
            let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            guard let start = calendar.date(byAdding: .month, value: -(monthsBack - 1), to: startOfCurrentMonth) else {
                balanceHistory = []
                return
            }
            periodStartDate = start
            periodEndDate = now
        }

        // Fetch ALL transactions (not just filtered by period, so pre-period ones compute initial balance)
        let descriptor = FetchDescriptor<FinanceCore.Transaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)
            let snapshots = allTransactions
                .filter { tx in
                    if let id = tx.fromContoId, contiIDs.contains(id) { return true }
                    if let id = tx.toContoId, contiIDs.contains(id) { return true }
                    return false
                }
                .map { TransactionSnapshot(from: $0) }

            balanceHistory = BalanceCalculator.balanceHistory(
                transactions: snapshots,
                contiIDs: contiIDs,
                initialBalance: initialBalance,
                periodStart: periodStartDate,
                periodEnd: periodEndDate,
                calendar: calendar
            )
        } catch {
            balanceHistory = []
        }
    }

    private func loadMultiAccountBalanceHistory(
        accounts: [Account],
        modelContext: ModelContext
    ) {
        let now = Date()
        let monthsToLoad = selectedPeriod.monthsCount ?? 24

        // Fetch all transactions once
        let descriptor = FetchDescriptor<FinanceCore.Transaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)
            let allSnapshots = allTransactions.map { TransactionSnapshot(from: $0) }

            let accountInputs = accounts.enumerated().map { index, account in
                AccountInput(
                    id: account.id,
                    name: account.name ?? "Account",
                    contiIDs: Set(account.activeConti.map(\.id)),
                    initialBalance: account.activeConti.reduce(Decimal(0)) { $0 + ($1.initialBalance ?? 0) },
                    colorIndex: index
                )
            }

            multiAccountHistory = BalanceCalculator.multiAccountBalanceHistory(
                accounts: accountInputs,
                transactions: allSnapshots,
                monthsToLoad: monthsToLoad,
                now: now
            )
        } catch {
            multiAccountHistory = []
        }
    }

    private func loadMultiContoBalanceHistory(
        conti: [Conto],
        modelContext: ModelContext
    ) {
        let now = Date()
        let monthsToLoad = selectedPeriod.monthsCount ?? 24

        let descriptor = FetchDescriptor<FinanceCore.Transaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)
            let allSnapshots = allTransactions.map { TransactionSnapshot(from: $0) }

            let contoInputs = conti.enumerated().map { index, conto in
                ContoInput(
                    id: conto.id,
                    name: conto.name ?? "Conto",
                    initialBalance: conto.initialBalance ?? 0,
                    colorIndex: index
                )
            }

            multiContoHistory = BalanceCalculator.multiContoBalanceHistory(
                conti: contoInputs,
                transactions: allSnapshots,
                monthsToLoad: monthsToLoad,
                now: now
            )
        } catch {
            multiContoHistory = []
        }
    }

    private func loadRecentTransactions(contiIDs: Set<UUID>, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<FinanceCore.Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            let allTransactions = try modelContext.fetch(descriptor)
            recentTransactions = Array(
                allTransactions
                    .filter { tx in
                        if let id = tx.fromContoId, contiIDs.contains(id) { return true }
                        if let id = tx.toContoId, contiIDs.contains(id) { return true }
                        return false
                    }
                    .prefix(10)
            )
        } catch {
            recentTransactions = []
        }
    }
}
