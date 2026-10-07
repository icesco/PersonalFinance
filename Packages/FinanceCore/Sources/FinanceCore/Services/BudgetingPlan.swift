import Foundation

public enum BudgetingMethod: String, Codable, CaseIterable, Sendable {
    case fiftyThirtyTwenty, custom, manual
}

public enum BudgetAllocationGroup: String, Codable, CaseIterable, Sendable {
    case needs, wants
}

/// External IDs survive shared-book import and do not depend on local model identity.
public struct BudgetingPlan: Codable, Equatable, Sendable {
    public var version = 1
    public var method: BudgetingMethod
    public var monthlyIncome: Decimal
    public var needsPercent: Int
    public var wantsPercent: Int
    public var categoryGroups: [String: BudgetAllocationGroup]
    public var savingsContoIDs: Set<String>

    public init(method: BudgetingMethod = .fiftyThirtyTwenty, monthlyIncome: Decimal = 0,
                needsPercent: Int = 50, wantsPercent: Int = 30,
                categoryGroups: [String: BudgetAllocationGroup] = [:], savingsContoIDs: Set<String> = []) {
        self.method = method; self.monthlyIncome = monthlyIncome
        self.needsPercent = needsPercent; self.wantsPercent = wantsPercent
        self.categoryGroups = categoryGroups; self.savingsContoIDs = savingsContoIDs
    }

    public var savingsPercent: Int { 100 - needsPercent - wantsPercent }
    public var isValid: Bool {
        version == 1 && !monthlyIncome.isNaN && monthlyIncome >= 0 &&
        (0...100).contains(needsPercent) && (0...100).contains(wantsPercent) && savingsPercent >= 0 &&
        (method == .manual || (monthlyIncome > 0 &&
          (method != .fiftyThirtyTwenty || (needsPercent == 50 && wantsPercent == 30))))
    }
    public func limit(for group: BudgetAllocationGroup) -> Decimal {
        monthlyIncome * Decimal(group == .needs ? needsPercent : wantsPercent) / 100
    }
    public var savingsTarget: Decimal { monthlyIncome * Decimal(savingsPercent) / 100 }
    public func roundedSavingsTarget(currency: String) -> Decimal {
        monthlyIncome - roundedLimit(for: .needs, currency: currency) - roundedLimit(for: .wants, currency: currency)
    }
    public func roundedLimit(for group: BudgetAllocationGroup, currency: String) -> Decimal {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = currency
        var value = limit(for: group), result = Decimal.zero
        NSDecimalRound(&result, &value, formatter.maximumFractionDigits, .plain)
        if group == .wants {
            return min(result, monthlyIncome - roundedLimit(for: .needs, currency: currency))
        }
        return result
    }

    public func group(for category: Category) -> BudgetAllocationGroup? {
        categoryGroups[category.externalID] ?? categoryGroups[category.rootCategory.externalID]
    }
    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
    public static func decode(_ text: String?) -> Self? {
        guard let text, let plan = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)), plan.isValid else { return nil }
        return plan
    }
}

extension Account {
    public var budgetingPlan: BudgetingPlan? { BudgetingPlan.decode(budgetingPlanJSON) }
}

/// Recorded month-to-date flows, never forecasts or opening balances.
public struct MonthlySavingsReport {
    public let income: Decimal
    public let expenses: Decimal
    public let hasInvalidAmounts: Bool
    public let netSetAside: Decimal?
    public let needsSavingsReview: Bool
    public let unclassifiedExpenses: Decimal
    public let needsSpent: Decimal
    public let wantsSpent: Decimal
    public var margin: Decimal { income - expenses }
    public var marginRate: Decimal? { income > 0 ? margin / income : nil }

    public init(account: Account, transactions: [Transaction], interval: DateInterval, through: Date) {
        let plan = account.budgetingPlan
        let conti = account.conti ?? []
        let bookIDs = Set(conti.map(\.id))
        let eligible = Set(conti.filter { $0.type == .savings }.map(\.externalID))
        let needsSavingsReview = plan.map { !$0.savingsContoIDs.isSubset(of: eligible) } ?? false
        let savingsIDs = Set(conti.filter { $0.type == .savings && plan?.savingsContoIDs.contains($0.externalID) == true }.map(\.id))
        var scopeSeen = Set<UUID>()
        let scoped = transactions.filter { entry in
            guard scopeSeen.insert(entry.id).inserted else { return false }
            switch entry.type {
            case .income: return (entry.toContoId ?? entry.toConto?.id).map(bookIDs.contains) == true
            case .expense: return (entry.fromContoId ?? entry.fromConto?.id).map(bookIDs.contains) == true
            case .transfer:
                return (entry.fromContoId ?? entry.fromConto?.id).map(bookIDs.contains) == true ||
                       (entry.toContoId ?? entry.toConto?.id).map(bookIDs.contains) == true
            }
        }
        let recorded = RecordedSavingsReport.calculate(transactions: scoped.map {
            DirectionTransaction(date: $0.date, amount: $0.amount ?? 0, type: $0.type,
                                 categoryID: $0.categoryId, categoryName: "", isRecurring: $0.isRecurring == true,
                                 hasValidAmount: $0.amount != nil && $0.amount?.isNaN == false)
        }, interval: interval, now: through)
        var setAside: Decimal = 0
        var invalidSavings = false
        var needs: Decimal = 0, wants: Decimal = 0, unclassified: Decimal = 0
        var visited = Set<UUID>()
        for entry in scoped {
            guard entry.date >= interval.start, entry.date < interval.end, entry.date <= through,
                  visited.insert(entry.id).inserted else { continue }
            guard let amount = entry.amount, !amount.isNaN else {
                invalidSavings = true
                continue
            }
            let from = entry.fromContoId ?? entry.fromConto?.id
            let to = entry.toContoId ?? entry.toConto?.id
            let fromHere = from.map(bookIDs.contains) == true
            let fromSavings = from.map(savingsIDs.contains) == true
            let toSavings = to.map(savingsIDs.contains) == true
            switch entry.type {
            case .income:
                if toSavings { setAside += amount }
            case .expense:
                if fromHere {
                    let category = entry.category ?? account.categories?.first { $0.id == entry.categoryId }
                    switch category.flatMap({ plan?.group(for: $0) }) {
                    case .needs: needs += amount
                    case .wants: wants += amount
                    case nil: unclassified += amount
                    }
                }
                if fromSavings { setAside -= amount }
            case .transfer:
                // A transfer inside the savings perimeter changes no allocation.
                if fromSavings != toSavings {
                    if fromSavings { setAside -= amount }
                    if toSavings {
                        let credited = entry.destinationAmount ?? amount
                        if credited.isNaN { invalidSavings = true } else { setAside += credited }
                    }
                }
            }
        }
        self.income = recorded.income; self.expenses = recorded.expenses
        self.hasInvalidAmounts = recorded.hasInvalidAmounts || invalidSavings || setAside.isNaN
        self.needsSavingsReview = needsSavingsReview
        self.netSetAside = savingsIDs.isEmpty || needsSavingsReview ? nil : setAside
        self.needsSpent = needs; self.wantsSpent = wants; self.unclassifiedExpenses = unclassified
    }
}
