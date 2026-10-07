import Foundation

public struct SavingsRate: Codable, Equatable, Identifiable, Sendable {
    public var effectiveDate: Date
    public var annualPercent: Decimal
    public var id: Date { effectiveDate }
    public init(effectiveDate: Date, annualPercent: Decimal) {
        self.effectiveDate = effectiveDate; self.annualPercent = annualPercent
    }
}

public struct SavingsValue: Equatable, Sendable {
    public var capital: Decimal
    public var creditedInterest: Decimal
    public var pendingInterest: Decimal
    public var estimatedValue: Decimal { capital + creditedInterest + pendingInterest }
}

public struct SavingsMovement: Sendable {
    public let date: Date
    public let amount: Decimal
    public let isInterest: Bool
    public init(date: Date, amount: Decimal, isInterest: Bool = false) {
        self.date = date; self.amount = amount; self.isInterest = isInterest
    }
}

/// Simple accrual on the recorded balance. Only credited interest is capitalized.
/// No taxes/fees are inferred: the user supplies the applicable annual rate.
public enum SavingsValuation {
    public static func value(initialBalance: Decimal, start: Date, rates: [SavingsRate],
                             movements: [SavingsMovement], at date: Date,
                             calendar: Calendar = .current) -> SavingsValue {
        let entries = movements.filter { $0.date <= date }.sorted { $0.date < $1.date }
        let changes = Dictionary(grouping: entries, by: \.date)
        let schedule = rates.sorted { $0.effectiveDate < $1.effectiveDate }
        var result = SavingsValue(capital: initialBalance, creditedInterest: 0, pendingInterest: 0)
        // Older imported entries affect the opening balance; accrual starts only at `start`.
        func apply(_ entry: SavingsMovement) {
            if entry.isInterest {
                result.creditedInterest += entry.amount
                // Settle only the accrued component with the same sign. A credit
                // must not erase an outstanding loss, nor a debit an accrued gain.
                if entry.amount >= 0 && result.pendingInterest >= 0 {
                    result.pendingInterest = max(0, result.pendingInterest - entry.amount)
                } else if entry.amount < 0 && result.pendingInterest < 0 {
                    result.pendingInterest = min(0, result.pendingInterest - entry.amount)
                }
            } else { result.capital += entry.amount }
        }
        for entry in entries where entry.date <= start { apply(entry) }
        guard date > start else { return result }
        var boundaries = Set(entries.filter { $0.date > start }.map(\.date))
        boundaries.formUnion(schedule.filter { $0.effectiveDate > start && $0.effectiveDate < date }.map(\.effectiveDate))
        var year = calendar.dateInterval(of: .year, for: start)!.end
        while year < date {
            boundaries.insert(year)
            year = calendar.dateInterval(of: .year, for: year)!.end
        }
        boundaries.insert(date)
        var previous = start
        for end in boundaries.sorted() {
            let rate = schedule.last { $0.effectiveDate <= previous }?.annualPercent ?? 0
            let yearLength = calendar.dateInterval(of: .year, for: previous)!.duration
            let fraction = Decimal(end.timeIntervalSince(previous) / yearLength)
            result.pendingInterest += max(0, result.capital + result.creditedInterest) * rate / 100 * fraction
            for entry in changes[end] ?? [] { apply(entry) }
            previous = end
        }
        return result
    }
}

extension Conto {
    public var savingsRates: [SavingsRate] {
        guard let json = savingsRatesJSON, let data = json.data(using: .utf8),
              let rates = try? JSONDecoder().decode([SavingsRate].self, from: data) else { return [] }
        return rates.sorted { $0.effectiveDate < $1.effectiveDate }
    }

    public func setSavingsRate(_ rate: Decimal, effectiveDate: Date) throws {
        guard !rate.isNaN else { throw SavingsAccountEdits.Failure.invalidRate }
        var rates = savingsRates.filter { $0.effectiveDate != effectiveDate }
        rates.append(SavingsRate(effectiveDate: effectiveDate, annualPercent: rate))
        savingsRatesJSON = String(decoding: try JSONEncoder().encode(rates.sorted { $0.effectiveDate < $1.effectiveDate }), as: UTF8.self)
        annualInterestRate = rates.filter { $0.effectiveDate <= Date() }.max { $0.effectiveDate < $1.effectiveDate }?.annualPercent
    }

    public var linkedSavingsGoal: SavingsGoal? {
        (account?.savingsGoals ?? []).first { $0.id == savingsGoalID }
    }

    public func savingsMovements(transactions: [Transaction]? = nil) -> [SavingsMovement] {
        var seen = Set<UUID>()
        return (transactions ?? allTransactions).compactMap { transaction in
            guard seen.insert(transaction.id).inserted else { return nil }
            let incoming = (transaction.toContoId ?? transaction.toConto?.id) == id
            let outgoing = (transaction.fromContoId ?? transaction.fromConto?.id) == id
            var delta: Decimal = 0
            if incoming && (transaction.type == .income || transaction.type == .transfer) {
                delta += transaction.type == .transfer ? (transaction.destinationAmount ?? transaction.amount ?? 0) : (transaction.amount ?? 0)
            }
            if outgoing && (transaction.type == .expense || transaction.type == .transfer) { delta -= transaction.amount ?? 0 }
            guard delta != 0 else { return nil }
            return SavingsMovement(date: transaction.date, amount: delta,
                isInterest: incoming && transaction.type == .income && transaction.isSavingsInterest == true)
        }
    }

    public func savingsCapital(at date: Date, transactions: [Transaction]? = nil) -> Decimal {
        savingsMovements(transactions: transactions).filter { !$0.isInterest && $0.date <= date }
            .reduce(initialBalance ?? 0) { $0 + $1.amount }
    }

    public func savingsSnapshot(at date: Date, transactions: [Transaction]? = nil) -> SavingsValue {
        let rates = savingsRates
        let start = rates.first?.effectiveDate ?? createdAt ?? date
        return SavingsValuation.value(initialBalance: initialBalance ?? 0, start: start,
            rates: rates, movements: savingsMovements(transactions: transactions), at: date)
    }
}
