import Foundation

public struct MonthlyFundingSplit: Equatable, Sendable {
    public let total: Decimal
    public let firstPercentage: Decimal
    public let firstAmount: Decimal
    public let secondAmount: Decimal
    public var secondPercentage: Decimal { 100 - firstPercentage }

    public init?(shortfall: Decimal, firstPercentage: Decimal = 50, currency: String) {
        guard !shortfall.isNaN, shortfall >= 0, !firstPercentage.isNaN,
              firstPercentage >= 0, firstPercentage <= 100 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        func rounded(_ value: Decimal) -> Decimal {
            var value = value
            var result = Decimal.zero
            NSDecimalRound(&result, &value, formatter.maximumFractionDigits, .bankers)
            return result
        }
        let total = rounded(shortfall)
        let first = rounded(total * firstPercentage / 100)
        guard !total.isNaN, !first.isNaN, first >= 0, first <= total else { return nil }
        self.total = total
        self.firstPercentage = firstPercentage
        firstAmount = first
        secondAmount = total - first
    }
}

@MainActor
public enum MonthlyForecastParticipants {
    public static func people(conto: Conto, memberships: [SharedBookMembership]) -> [TransactionPerson] {
        let matching = memberships.filter { $0.localBookID == conto.account?.id }
        let specific = matching.filter { $0.localContoID == conto.id }
        let relevant = specific.isEmpty ? matching.filter { $0.localContoID == nil } : specific
        var people: [String: TransactionPerson] = [:]
        for membership in relevant {
            guard let json = membership.peopleJSON, json.utf8.count <= 65_536,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([TransactionPerson].self, from: data) else { continue }
            for person in decoded where !person.id.isEmpty && person.id.utf8.count <= 255 && person.name.count <= 100 {
                people[person.id] = person
            }
        }
        return people.values.sorted { $0.id < $1.id }
    }
}
