import Foundation

public struct TransactionPerson: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public var encoded: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
    public static func decode(_ value: String?) -> Self? {
        guard let value, value.utf8.count <= 2048, let data = value.data(using: .utf8),
              let person = try? JSONDecoder().decode(Self.self, from: data),
              !person.id.isEmpty, person.id.utf8.count <= 255, person.name.count <= 100 else { return nil }
        return person
    }
}

/// Attribution is descriptive metadata, never an authorization credential.
/// Unknown authors remain unknown; legacy movements are not attributed on import.
public enum TransactionPeople {
    public static var current: TransactionPerson? {
        guard let id = UserDefaults.standard.string(forKey: "formi.cloudPersonID"), !id.isEmpty else { return nil }
        let name = UserDefaults.standard.string(forKey: "formi.personDisplayName") ?? ""
        return TransactionPerson(id: id, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)))
    }
    public static func cacheCloudIdentity(_ id: String) {
        UserDefaults.standard.set(id, forKey: "formi.cloudPersonID")
    }
    public static func clearCloudIdentity() {
        UserDefaults.standard.removeObject(forKey: "formi.cloudPersonID")
    }
    public static func setDisplayName(_ name: String) {
        UserDefaults.standard.set(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), forKey: "formi.personDisplayName")
    }
}

extension Transaction {
    public var createdBy: TransactionPerson? { TransactionPerson.decode(createdByJSON) }
    public var lastEditedBy: TransactionPerson? { TransactionPerson.decode(lastEditedByJSON) }
    public var assignedTo: TransactionPerson? {
        get { TransactionPerson.decode(assignedToJSON) }
        set { assignedToJSON = newValue?.encoded }
    }
    public var contributor: TransactionPerson? {
        get { TransactionPerson.decode(contributorJSON) }
        set { contributorJSON = newValue?.encoded }
    }
    public func recordEdit(by person: TransactionPerson? = TransactionPeople.current) {
        lastEditedByJSON = person?.encoded
    }
}

public struct AccountContribution: Identifiable, Equatable, Sendable {
    public let id: String
    public let person: TransactionPerson?
    public var amount: Decimal
    public var count: Int
}

@MainActor
public enum AccountContributions {
    /// Uses actual credited amounts, never generated recurrences or future entries.
    /// The author is not a fallback: recording a partner's payment doesn't make it yours.
    public static func summarize(conto: Conto, interval: DateInterval, now: Date = Date()) -> [AccountContribution] {
        var seen: Set<UUID> = []
        var groups: [String: AccountContribution] = [:]
        for transaction in conto.allTransactions {
            guard seen.insert(transaction.id).inserted, transaction.type == .transfer,
                  (transaction.toContoId ?? transaction.toConto?.id) == conto.id,
                  (transaction.fromContoId ?? transaction.fromConto?.id) != conto.id,
                  transaction.date >= interval.start, transaction.date < interval.end, transaction.date <= now,
                  let amount = transaction.destinationAmount ?? transaction.amount, amount > 0 else { continue }
            let person = transaction.contributor
            let key = person?.id ?? "unassigned"
            var row = groups[key] ?? AccountContribution(id: key, person: person, amount: 0, count: 0)
            row.amount += amount; row.count += 1; groups[key] = row
        }
        return groups.values.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }
}
