import Foundation

/// Immutable input for the daily financial direction. Transfers are never spending.
public struct DirectionTransaction: Sendable {
    public let date: Date
    public let amount: Decimal
    public let type: TransactionType
    public let categoryID: UUID?
    public let categoryName: String
    public let isRecurring: Bool

    public init(
        date: Date, amount: Decimal, type: TransactionType,
        categoryID: UUID?, categoryName: String, isRecurring: Bool
    ) {
        self.date = date
        self.amount = amount
        self.type = type
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isRecurring = isRecurring
    }
}

public struct PlannedCashMovement: Sendable {
    public let date: Date
    public let amount: Decimal
    public let type: TransactionType
    public let title: String

    public init(date: Date, amount: Decimal, type: TransactionType, title: String) {
        self.date = date
        self.amount = amount
        self.type = type
        self.title = title
    }
}

public struct SpendingShift: Sendable {
    public let categoryID: UUID
    public let categoryName: String
    public let spent: Decimal
    public let expectedByToday: Decimal
    public let excess: Decimal
}

public struct CategoryOutflow: Sendable {
    public var categoryID: UUID? = nil
    public let name: String
    public let amount: Decimal
}

public struct CategoryIncrease: Sendable {
    public let name: String
    public let current: Decimal
    public let previous: Decimal
    public let increase: Decimal
}

public enum DirectionAvailability: Sendable, Equatable {
    case noMovements
    case staleData
    case shortHistory
    case sparseSpending
    case unverifiedBalances
    case noPlannedIncome
    case ready
}

public struct SpendingDirection: Sendable {
    public let availability: DirectionAvailability
    public let latestMovement: Date?
    public let nextIncome: PlannedCashMovement?
    public let liquidBalance: Decimal
    public let creditDebt: Decimal
    public let committedOutgoings: Decimal
    public let typicalVariableOutgoings: Decimal
    public let estimatedMargin: Decimal?
    public let recentIncome: Decimal
    public let recentExpenses: Decimal
    public let recentRecurringExpenses: Decimal
    public let recentVariableExpenses: Decimal
    public let upcoming30DaysRecurringExpenses: Decimal
    public let largestVariableOutflow: CategoryOutflow?
    public let previous30DaysExpenses: Decimal
    public let categoryOutflows: [CategoryOutflow]
    public let categoryIncreases: [CategoryIncrease]
    public let largestOutflows: [CategoryOutflow]
    public let shifts: [SpendingShift]

    /// Top five recorded expense categories plus the exact remainder for a compact chart.
    public var chartOutflows: [CategoryOutflow] {
        let ranked = categoryOutflows.filter { $0.amount > 0 }
        let leading = Array(ranked.prefix(5))
        let remainder = ranked.dropFirst(5).reduce(Decimal(0)) { $0 + $1.amount }
        guard remainder > 0 else { return leading }
        return leading + [CategoryOutflow(name: "Restanti categorie", amount: remainder)]
    }
}

public enum SpendingDirectionCalculator {
    /// A conservative estimate based on recent variable spending and explicitly scheduled bills.
    /// It is withheld when the register is stale or lacks enough history.
    public static func calculate(
        transactions: [DirectionTransaction],
        planned: [PlannedCashMovement],
        liquidBalance: Decimal,
        creditDebt: Decimal,
        balancesVerified: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendingDirection {
        let recorded = transactions.filter { $0.date <= now }
        let recentStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let historyStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let recent = recorded.filter { $0.date >= recentStart }
        let variableExpenses = recorded.filter {
            $0.type == .expense && !$0.isRecurring && $0.date >= historyStart
        }
        let spendingMonths = Set(variableExpenses.compactMap {
            calendar.dateInterval(of: .month, for: $0.date)?.start
        })
        let recentIncome = recent.filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let recentExpenses = recent.filter { $0.type == .expense }
        let recentSpent = recentExpenses.reduce(Decimal(0)) { $0 + $1.amount }
        let previousSpent = recorded
            .filter { $0.type == .expense && $0.date >= previousStart && $0.date < recentStart }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let groupedRecentExpenses = Dictionary(grouping: recentExpenses) { $0.categoryID?.uuidString ?? $0.categoryName }
        let unsortedOutflows: [CategoryOutflow] = groupedRecentExpenses.map { _, entries in
            let amount = entries.reduce(Decimal(0)) { $0 + $1.amount }
            return CategoryOutflow(categoryID: entries.first?.categoryID, name: entries.first?.categoryName ?? "Da classificare", amount: amount)
        }
        let categoryOutflows = unsortedOutflows.sorted { left, right in
            if left.amount == right.amount {
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            return left.amount > right.amount
        }
        let previousByCategory = Dictionary(grouping: recorded.filter {
            $0.type == .expense && $0.date >= previousStart && $0.date < recentStart
        }, by: \.categoryName).mapValues { entries in
            entries.reduce(Decimal(0)) { $0 + $1.amount }
        }
        let categoryIncreases = categoryOutflows.compactMap { category -> CategoryIncrease? in
            guard let previous = previousByCategory[category.name], previous >= 20 else { return nil }
            let increase = category.amount - previous
            guard increase >= 20, category.amount * 10 >= previous * 13 else { return nil }
            return CategoryIncrease(name: category.name, current: category.amount,
                                    previous: previous, increase: increase)
        }.sorted { $0.increase > $1.increase }
        let recurringSpent = recentExpenses.filter(\.isRecurring).reduce(Decimal(0)) { $0 + $1.amount }
        let variableByCategory = Dictionary(grouping: recentExpenses.filter { !$0.isRecurring }) { $0.categoryID?.uuidString ?? $0.categoryName }
        let variableOutflows: [CategoryOutflow] = variableByCategory.map { _, entries in
            let amount = entries.reduce(Decimal(0)) { $0 + $1.amount }
            return CategoryOutflow(categoryID: entries.first?.categoryID, name: entries.first?.categoryName ?? "Da classificare", amount: amount)
        }
        let largestVariable = variableOutflows.sorted { left, right in
            if left.amount == right.amount { return left.name < right.name }
            return left.amount > right.amount
        }.first
        let next30Days = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        let upcomingRecurring = planned.filter {
            $0.type == .expense && $0.date > now && $0.date <= next30Days
        }.reduce(Decimal(0)) { $0 + $1.amount }
        let latest = recorded.map(\.date).max()
        let earliest = recorded.map(\.date).min()
        let nextIncome = planned
            .filter { $0.type == .income && $0.date > now }
            .min { $0.date < $1.date }

        let availability: DirectionAvailability
        if latest == nil {
            availability = .noMovements
        } else if let latest, now.timeIntervalSince(latest) > 7 * 86_400 {
            availability = .staleData
        } else if let earliest, now.timeIntervalSince(earliest) < 45 * 86_400 {
            availability = .shortHistory
        } else if variableExpenses.count < 5 || spendingMonths.count < 2 ||
                    !variableExpenses.contains(where: { $0.date >= recentStart }) {
            availability = .sparseSpending
        } else if !balancesVerified {
            availability = .unverifiedBalances
        } else if nextIncome == nil {
            availability = .noPlannedIncome
        } else {
            availability = .ready
        }

        var committed: Decimal = 0
        var typicalVariable: Decimal = 0
        var margin: Decimal?
        if let nextIncome, availability == .ready {
            committed = planned
                .filter { $0.type == .expense && $0.date > now && $0.date <= nextIncome.date }
                .reduce(0) { $0 + $1.amount }

            let variable = variableExpenses.reduce(0) { $0 + $1.amount }
            let coveredDays = max(45, min(90, Int(now.timeIntervalSince(earliest ?? now) / 86_400)))
            let daysToIncome = max(1, calendar.dateComponents([.day], from: now, to: nextIncome.date).day ?? 1)
            typicalVariable = variable / Decimal(coveredDays) * Decimal(daysToIncome)
            margin = liquidBalance - creditDebt - committed - typicalVariable
        }

        return SpendingDirection(
            availability: availability,
            latestMovement: latest,
            nextIncome: nextIncome,
            liquidBalance: liquidBalance,
            creditDebt: creditDebt,
            committedOutgoings: committed,
            typicalVariableOutgoings: typicalVariable,
            estimatedMargin: margin,
            recentIncome: recentIncome,
            recentExpenses: recentSpent,
            recentRecurringExpenses: recurringSpent,
            recentVariableExpenses: recentSpent - recurringSpent,
            upcoming30DaysRecurringExpenses: upcomingRecurring,
            largestVariableOutflow: largestVariable,
            previous30DaysExpenses: previousSpent,
            categoryOutflows: categoryOutflows,
            categoryIncreases: Array(categoryIncreases.prefix(3)),
            largestOutflows: Array(categoryOutflows.prefix(3)),
            shifts: availability == .staleData || availability == .noMovements
                ? [] : categoryShifts(in: recorded, now: now, calendar: calendar)
        )
    }

    private static func categoryShifts(
        in transactions: [DirectionTransaction], now: Date, calendar: Calendar
    ) -> [SpendingShift] {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let historyStart = calendar.date(byAdding: .month, value: -3, to: month.start) else { return [] }
        let elapsedDays = max(1, calendar.dateComponents([.day], from: month.start, to: now).day ?? 0)
        guard elapsedDays >= 7 else { return [] }
        let monthDays = max(1, calendar.dateComponents([.day], from: month.start, to: month.end).day ?? 30)

        let expenses = transactions.filter { $0.type == .expense && $0.date >= historyStart }
        let grouped = Dictionary(grouping: expenses) { $0.categoryID }
        return grouped.compactMap { categoryID, entries -> SpendingShift? in
            guard let categoryID else { return nil }
            let current = entries.filter { $0.date >= month.start }
            let previous = entries.filter { $0.date < month.start }
            guard current.count >= 2, previous.count >= 3 else { return nil }
            let previousMonths = Set(previous.compactMap { entry in
                calendar.dateInterval(of: .month, for: entry.date)?.start
            })
            guard previousMonths.count == 3 else { return nil }
            let spent = current.reduce(Decimal(0)) { $0 + $1.amount }
            let historicalMonthly = previous.reduce(Decimal(0)) { $0 + $1.amount } / 3
            guard historicalMonthly > 0 else { return nil }
            let expected = historicalMonthly * Decimal(elapsedDays) / Decimal(monthDays)
            let excess = spent - expected
            guard excess >= 20, spent * 10 >= expected * 13 else { return nil }
            return SpendingShift(
                categoryID: categoryID,
                categoryName: current.first?.categoryName ?? "Da classificare",
                spent: spent,
                expectedByToday: expected,
                excess: excess
            )
        }
        .sorted { $0.excess > $1.excess }
        .prefix(3)
        .map { $0 }
    }
}
