import Foundation
import SwiftData

public struct WidgetBudgetSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let limit: Decimal
    public let spent: Decimal
    public var remaining: Decimal { limit - spent }
}

public struct WidgetBookSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let currency: String
    public let monthSpent: Decimal
    public let budget: WidgetBudgetSnapshot?
    public let occurrenceDates: [Date]
    /// Optional for compatibility with snapshots published by earlier app versions.
    public let balanceHistories: [WidgetBalanceSnapshot]?
    /// Missing in snapshots published before the upcoming-transactions widget.
    public let upcomingSchedule: WidgetUpcomingSnapshot?
}

public struct FinanceWidgetSnapshot: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case ready, hidden, unavailable }
    public let version: Int
    public let generatedAt: Date
    public let validUntil: Date
    public let state: State
    public let books: [WidgetBookSnapshot]

    public static func empty(_ state: State, now: Date = Date()) -> Self {
        Self(version: 1, generatedAt: now, validUntil: now, state: state, books: [])
    }

    public func usable(at now: Date) -> Bool { version == 1 && state == .ready && now < validUntil }
}

/// Only the app builds a snapshot. The extension never opens SwiftData or CloudKit.
public enum FinanceWidgetBuilder {
    private static func utilization(_ budget: WidgetBudgetSnapshot) -> Double {
        guard budget.limit > 0 else { return budget.spent > 0 ? .infinity : 0 }
        return NSDecimalNumber(decimal: budget.spent / budget.limit).doubleValue
    }

    /// The caller must own all supplied models on its executor.
    public static func build(accounts: [Account], budgets: [Budget], transactions: [Transaction],
                             resolutions: [RecurrenceResolution], now: Date = Date(),
                             calendar: Calendar = .current,
                             ledgerSnapshots: [UUID: LedgerCacheSnapshot]? = nil) -> FinanceWidgetSnapshot {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let coverageEnd = calendar.date(byAdding: .day, value: 30, to: now) else {
            return .empty(.unavailable, now: now)
        }
        var validUntil = min(month.end, coverageEnd)
        let ledger = ledgerSnapshots ?? (try? LedgerCache.prepare(conti: accounts.flatMap { $0.conti ?? [] },
            transactions: transactions.map { transaction in
                TransactionSnapshot(id: transaction.id, amount: transaction.amount ?? 0, type: transaction.type,
                    date: transaction.date, fromContoId: transaction.fromContoId ?? transaction.fromConto?.id,
                    toContoId: transaction.toContoId ?? transaction.toConto?.id, destinationAmount: transaction.destinationAmount,
                    categoryID: transaction.categoryId ?? transaction.category?.id)
            }, now: now, calendar: calendar).snapshots)
        let resolved = Set(resolutions.map(\.key))
        var books: [WidgetBookSnapshot] = []
        for account in accounts where account.isActive == true {
            let contoIDs = Set((account.conti ?? []).map(\.id))
            let activeContoIDs = Set((account.conti ?? []).filter { $0.isActive == true }.map(\.id))
            var expenses: [Transaction] = []
            for transaction in transactions where transaction.type == .expense && transaction.date <= now {
                // Older records may predate the denormalized query IDs.
                if let id = transaction.fromContoId ?? transaction.fromConto?.id, contoIDs.contains(id) {
                    expenses.append(transaction)
                }
            }
            let monthSpent: Decimal
            if let ledger, contoIDs.allSatisfy({ ledger[$0] != nil }) {
                monthSpent = contoIDs.reduce(0) { total, id in
                    total + (ledger[id]?.months.first { $0.start == month.start }?.expenses ?? 0)
                }
            } else {
                monthSpent = expenses.filter { $0.date >= month.start }.reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
            }
            var bookBudgets: [WidgetBudgetSnapshot] = []
            for budget in budgets {
                guard budget.isActive == true, budget.account?.id == account.id,
                      let amount = budget.amount, amount >= 0,
                      let period = budget.period?.interval(containing: now, calendar: calendar) else { continue }
                validUntil = min(validUntil, period.end)
                let categories = Set((budget.categories ?? []).map(\.id))
                var spent: Decimal = 0
                for expense in expenses {
                    guard expense.date >= period.start, expense.date < period.end,
                          let categoryID = expense.categoryId ?? expense.category?.id, categories.contains(categoryID) else { continue }
                    spent += expense.amount ?? 0
                }
                bookBudgets.append(WidgetBudgetSnapshot(name: budget.name ?? "Budget", limit: amount, spent: spent))
            }
            bookBudgets.sort {
                let left = utilization($0)
                let right = utilization($1)
                return left == right ? $0.name < $1.name : left > right
            }
            var dates: [Date] = []
            for source in transactions where source.isRecurring == true {
                let sourceContoID: UUID?
                if source.type == .income { sourceContoID = source.toContoId ?? source.toConto?.id }
                else { sourceContoID = source.fromContoId ?? source.fromConto?.id }
                guard let sourceContoID, activeContoIDs.contains(sourceContoID) else { continue }
                let occurrences = source.recurrenceDates(after: max(now, source.date), through: coverageEnd)
                for date in occurrences {
                    let key = RecurrenceResolution.key(sourceID: source.id, date: date)
                    if !resolved.contains(key) { dates.append(date) }
                }
                if source.date > now && source.date <= coverageEnd { dates.append(source.date) }
            }
            dates.sort()
            let histories = WidgetBalancePeriod.allCases.map { period in
                WidgetBalanceSnapshot.make(period: period, conti: account.conti ?? [], transactions: transactions,
                                           resolutions: resolutions, now: now, calendar: calendar, ledgerSnapshots: ledger)
            }
            validUntil = min(validUntil, histories.map(\.interval.end).min() ?? validUntil)
            books.append(WidgetBookSnapshot(id: account.id, name: account.name ?? "Libro", currency: account.currency ?? "EUR",
                                      monthSpent: monthSpent, budget: bookBudgets.first, occurrenceDates: dates, balanceHistories: histories,
                                      upcomingSchedule: .build(transactions: transactions, resolutions: resolutions,
                                                               contoIDs: activeContoIDs, now: now, calendar: calendar)))
        }
        books.sort { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
        return FinanceWidgetSnapshot(version: 1, generatedAt: now, validUntil: validUntil, state: .ready, books: books)
    }
}

public enum FinanceWidgetStorage {
    public static let kind = "ForgiaOverview"
    public static let balanceKind = "FormiBalanceHistory"
    public static let upcomingKind = "FormiUpcomingTransactions"
    public static let filename = "forgia-widget-v1.json"
    public static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier)?
            .appendingPathComponent(filename)
    }
    public static func read(from url: URL?) -> FinanceWidgetSnapshot {
        guard let url,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(FinanceWidgetSnapshot.self, from: data), value.version == 1 else {
            return .empty(.unavailable)
        }
        return value
    }
    public static func write(_ snapshot: FinanceWidgetSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

public struct FinanceWidgetRoute: Equatable, Sendable {
    public enum Destination: String, Sendable { case today, planning, expense, analysis }
    public let destination: Destination
    public let bookID: UUID?
    public init(destination: Destination, bookID: UUID? = nil) { self.destination = destination; self.bookID = bookID }
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "forgia", components.host == "widget",
              let destination = Destination(rawValue: String(components.path.dropFirst())),
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }
        let query = components.queryItems ?? []
        guard query.count <= 1, query.allSatisfy({ $0.name == "book" }) else { return nil }
        if let item = query.first {
            guard let text = item.value, let id = UUID(uuidString: text) else { return nil }
            bookID = id
        } else { bookID = nil }
        self.destination = destination
    }
    public var url: URL {
        var components = URLComponents()
        components.scheme = "forgia"; components.host = "widget"; components.path = "/\(destination.rawValue)"
        if let bookID { components.queryItems = [URLQueryItem(name: "book", value: bookID.uuidString)] }
        return components.url!
    }
}
