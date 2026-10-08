import Foundation
import CryptoKit

public struct LedgerCategoryExpense: Codable, Sendable, Equatable {
    public let categoryID: UUID?
    public let amount: Decimal
}

public struct LedgerMonthSummary: Codable, Sendable, Equatable {
    public let start: Date
    public var income: Decimal = 0
    public var expenses: Decimal = 0
    public var transferChange: Decimal = 0
    public var categoryExpenses: [LedgerCategoryExpense] = []
}

/// Model-free input for calculations shared by independent background readers.
public struct LedgerCacheAccount: Sendable {
    public let id: UUID
    public let initialBalance: Decimal
    public let ledgerCacheJSON: String?
    let changeState: FinanceContoState?

    public init(id: UUID, initialBalance: Decimal, ledgerCacheJSON: String? = nil) {
        self.id = id; self.initialBalance = initialBalance; self.ledgerCacheJSON = ledgerCacheJSON
        self.changeState = nil
    }
    public init(_ conto: Conto) {
        self.id = conto.id
        self.initialBalance = conto.initialBalance ?? 0
        self.ledgerCacheJSON = conto.ledgerCacheJSON
        self.changeState = FinanceContoState(conto)
    }
}

public enum LedgerHistoryResolution: String, Codable, Sendable {
    case transaction, day, month
}

/// A deterministic projection of recorded movements, never a forecast or source of truth.
public struct LedgerCacheSnapshot: Codable, Sendable {
    public let version: Int
    public let contoID: UUID
    public let sourceFingerprint: String
    /// When the recorded history was rebuilt. Reuse never advances this date.
    /// Freshness is established by sourceFingerprint, not device clocks.
    public let calculatedAt: Date
    public let initialBalance: Decimal
    public let calendarIdentifier: String
    public let timeZoneIdentifier: String
    public let historyResolution: LedgerHistoryResolution
    public let history: [BalanceDataPoint]
    public let months: [LedgerMonthSummary]
    public var balance: Decimal { history.last?.balance ?? initialBalance }

    /// Source movements supply exact boundaries and intraday detail if persisted history is compact.
    public func points(interval: DateInterval, now: Date, transactions: [TransactionSnapshot],
                       resolution: LedgerHistoryResolution? = nil, calendar: Calendar = .current) -> [BalanceDataPoint] {
        guard interval.start <= now, interval.duration > 0 else { return [] }
        let requested = resolution ?? (interval.duration <= 31 * 86_400 ? .transaction
            : interval.duration <= 2 * 366 * 86_400 ? .day : .month)
        let scoped = transactions.filter { $0.fromContoId == contoID || $0.toContoId == contoID }
        let canReuse = historyResolution == .transaction
            || (calendarIdentifier == String(describing: calendar.identifier)
                && timeZoneIdentifier == calendar.timeZone.identifier
                && (historyResolution == requested || requested == .month))
        let end = min(now, interval.end)
        var result: [BalanceDataPoint]
        if requested == .transaction && historyResolution != .transaction || !canReuse {
            result = RecordedBalanceHistory.points(transactions: scoped, contiIDs: [contoID],
                initialBalance: initialBalance, interval: interval, now: now)
                .map { BalanceDataPoint(id: LedgerCache.pointID(contoID, $0.date), date: $0.date, balance: $0.balance) }
        } else {
            let opening = historyResolution == .transaction
                ? history.last { $0.date <= interval.start && $0.date < interval.end }?.balance ?? initialBalance
                : initialBalance + scoped.filter { $0.date <= interval.start && $0.date < interval.end }
                    .reduce(Decimal.zero) { $0 + BalanceCalculator.netChange(for: $1, contiIDs: [contoID]) }
            result = [BalanceDataPoint(id: LedgerCache.pointID(contoID, interval.start), date: interval.start, balance: opening)]
            result += history.filter { $0.date > interval.start && $0.date <= end && $0.date < interval.end }
            // A compact bucket may end after the selected range; calculate the exact closing boundary.
            let closing = historyResolution == .transaction ? result.last!.balance
                : initialBalance + scoped.filter { $0.date <= end && $0.date < interval.end }
                    .reduce(Decimal.zero) { $0 + BalanceCalculator.netChange(for: $1, contiIDs: [contoID]) }
            if result.last?.date != end {
                result.append(BalanceDataPoint(id: LedgerCache.pointID(contoID, end), date: end, balance: closing))
            }
        }
        return requested == .transaction ? result : LedgerCache.compact(result, resolution: requested,
            calendar: calendar, preserveBoundaries: true)
    }

}

public struct LedgerCachePreparation: Sendable {
    public let snapshots: [UUID: LedgerCacheSnapshot]
    public let reusedCount: Int
    public let rebuiltCount: Int
    /// Only changed payloads are saved: cache saves must not create refresh/sync loops.
    let updates: [UUID: String]
}

public enum LedgerCache {
    public static let version = 3
    // Large histories remain calculable without writing oversized CloudKit records.
    static let maximumPayloadBytes = 512 * 1024

    static let detailedPayloadBytes = 128 * 1024

    private struct Source: Codable {
        let version: Int
        let contoID: UUID
        let initialBalance: Decimal
        let entries: [String]
    }
    private struct Envelope: Codable {
        let snapshot: LedgerCacheSnapshot
        let checksum: String
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    fileprivate static func pointID(_ contoID: UUID, _ date: Date) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("\(contoID.uuidString)|\(date.timeIntervalSinceReferenceDate.bitPattern)".utf8)))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Relationship fallbacks retain support for legacy entries without denormalized IDs.
    public static func prepare(conti: [Conto], transactions: [Transaction], now: Date,
                               calendar: Calendar = .current) throws -> LedgerCachePreparation {
        try prepare(conti: conti, transactions: transactions.map { transaction in
            TransactionSnapshot(id: transaction.id, amount: transaction.amount ?? 0, type: transaction.type,
                date: transaction.date, fromContoId: transaction.fromContoId ?? transaction.fromConto?.id,
                toContoId: transaction.toContoId ?? transaction.toConto?.id, destinationAmount: transaction.destinationAmount,
                categoryID: transaction.categoryId ?? transaction.category?.id)
        }, now: now, calendar: calendar)
    }

    /// Must run on the executor owning `conti`. No models leave this method.
    /// Fingerprints check actual local values, including deletions and same-count edits.
    /// Remote cache records arriving ahead of their movements cannot pass this validation.
    public static func prepare(conti: [Conto], transactions: [TransactionSnapshot], now: Date,
                               calendar: Calendar = .current) throws -> LedgerCachePreparation {
        try prepare(accounts: conti.map(LedgerCacheAccount.init), transactions: transactions, now: now, calendar: calendar)
    }

    public static func prepare(accounts: [LedgerCacheAccount], transactions: [TransactionSnapshot], now: Date,
                               calendar: Calendar = .current) throws -> LedgerCachePreparation {
        let ids = Set(accounts.map(\.id))
        var grouped: [UUID: [TransactionSnapshot]] = [:]
        var encoded: [UUID: [String]] = [:]
        let encoder = encoder()
        for transaction in transactions where transaction.date <= now {
            try Task.checkCancellation()
            let endpoints = Set([transaction.fromContoId, transaction.toContoId].compactMap { $0 }).intersection(ids)
            guard !endpoints.isEmpty else { continue }
            let source = String(decoding: try encoder.encode(transaction), as: UTF8.self)
            for id in endpoints {
                grouped[id, default: []].append(transaction)
                encoded[id, default: []].append(source)
            }
        }
        var snapshots: [UUID: LedgerCacheSnapshot] = [:]
        var updates: [UUID: String] = [:]
        var reused = 0
        for conto in accounts {
            try Task.checkCancellation()
            let opening = conto.initialBalance
            let calendarIdentifier = String(describing: calendar.identifier)
            let fingerprint = digest(try encoder.encode(Source(version: version, contoID: conto.id,
                initialBalance: opening, entries: (encoded[conto.id] ?? []).sorted())))
            var cachedCore: LedgerCacheSnapshot?
            if let json = conto.ledgerCacheJSON, json.utf8.count <= maximumPayloadBytes,
               let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(json.utf8)),
               envelope.snapshot.version == version, envelope.snapshot.contoID == conto.id,
               envelope.snapshot.sourceFingerprint == fingerprint,
               envelope.checksum == digest(try encoder.encode(envelope.snapshot)) {
                reused += 1
                if envelope.snapshot.calendarIdentifier == calendarIdentifier,
                   envelope.snapshot.timeZoneIdentifier == calendar.timeZone.identifier {
                    snapshots[conto.id] = envelope.snapshot
                    continue
                }
                // Different device calendars reuse the absolute history and derive local month totals.
                // Do not rewrite a valid remote cache just for a time-zone difference (sync ping-pong).
                cachedCore = envelope.snapshot
            }
            var changes: [Date: Decimal] = [:]
            var months: [Date: LedgerMonthSummary] = [:]
            var categoryExpenses: [Date: [String: Decimal]] = [:]
            for transaction in grouped[conto.id] ?? [] {
                let delta = BalanceCalculator.netChange(for: transaction, contiIDs: [conto.id])
                if cachedCore == nil || cachedCore?.historyResolution != .transaction { changes[transaction.date, default: 0] += delta }
                if let month = calendar.dateInterval(of: .month, for: transaction.date)?.start {
                    var summary = months[month] ?? LedgerMonthSummary(start: month)
                    switch transaction.type {
                    case .income:
                        if transaction.toContoId == conto.id { summary.income += transaction.amount }
                    case .expense:
                        if transaction.fromContoId == conto.id {
                            summary.expenses += transaction.amount
                            categoryExpenses[month, default: [:]][transaction.categoryID?.uuidString ?? "", default: 0] += transaction.amount
                        }
                    case .transfer: summary.transferChange += delta
                    }
                    months[month] = summary
                }
            }
            var balance = opening
            let history = (cachedCore?.historyResolution == .transaction ? cachedCore?.history : nil) ?? changes.keys.sorted().map { date in
                balance += changes[date] ?? 0
                return BalanceDataPoint(id: pointID(conto.id, date), date: date, balance: balance)
            }
            let summaries = months.values.sorted { $0.start < $1.start }.map { month in
                var month = month
                let categories = categoryExpenses[month.start] ?? [:]
                month.categoryExpenses = categories.keys.sorted().map {
                    LedgerCategoryExpense(categoryID: UUID(uuidString: $0), amount: categories[$0] ?? 0)
                }
                return month
            }
            let snapshot = LedgerCacheSnapshot(version: version, contoID: conto.id, sourceFingerprint: fingerprint,
                calculatedAt: cachedCore?.calculatedAt ?? now,
                initialBalance: opening, calendarIdentifier: calendarIdentifier, timeZoneIdentifier: calendar.timeZone.identifier,
                historyResolution: .transaction, history: history, months: summaries)
            snapshots[conto.id] = snapshot
            guard cachedCore == nil else { continue }
            var stored = snapshot
            var payload = try encode(stored)
            if payload.count > detailedPayloadBytes {
                stored = replacingHistory(snapshot, resolution: .day, calendar: calendar)
                payload = try encode(stored)
            }
            if payload.count > maximumPayloadBytes {
                stored = replacingHistory(snapshot, resolution: .month, calendar: calendar)
                payload = try encode(stored)
            }
            // Use the same representation immediately and after a restart.
            snapshots[conto.id] = stored
            if payload.count <= maximumPayloadBytes {
                updates[conto.id] = String(decoding: payload, as: UTF8.self)
            }
        }
        return LedgerCachePreparation(snapshots: snapshots, reusedCount: reused,
                                      rebuiltCount: accounts.count - reused, updates: updates)
    }

    private static func encode(_ snapshot: LedgerCacheSnapshot) throws -> Data {
        let encoder = encoder()
        return try encoder.encode(Envelope(snapshot: snapshot, checksum: digest(try encoder.encode(snapshot))))
    }

    private static func replacingHistory(_ snapshot: LedgerCacheSnapshot, resolution: LedgerHistoryResolution,
                                         calendar: Calendar) -> LedgerCacheSnapshot {
        LedgerCacheSnapshot(version: snapshot.version, contoID: snapshot.contoID,
            sourceFingerprint: snapshot.sourceFingerprint, calculatedAt: snapshot.calculatedAt,
            initialBalance: snapshot.initialBalance, calendarIdentifier: snapshot.calendarIdentifier,
            timeZoneIdentifier: snapshot.timeZoneIdentifier, historyResolution: resolution,
            history: compact(snapshot.history, resolution: resolution, calendar: calendar, preserveBoundaries: false),
            months: snapshot.months)
    }

    /// Select closing values, never sum or average balances. Quiet buckets need no stored point.
    static func compact(_ points: [BalanceDataPoint], resolution: LedgerHistoryResolution,
                        calendar: Calendar, preserveBoundaries: Bool) -> [BalanceDataPoint] {
        guard resolution != .transaction, let first = points.first, let last = points.last else { return points }
        var buckets: [Date: BalanceDataPoint] = [:]
        for point in points {
            let start = resolution == .day ? calendar.startOfDay(for: point.date)
                : calendar.dateInterval(of: .month, for: point.date)?.start ?? calendar.startOfDay(for: point.date)
            buckets[start] = point
        }
        var values = Dictionary(uniqueKeysWithValues: buckets.values.map { ($0.date, $0) })
        if preserveBoundaries { values[first.date] = first; values[last.date] = last }
        return values.values.sorted { $0.date < $1.date }
    }

    /// Cache-only writers own a fresh context, never the context containing user drafts.
    public static func apply(_ preparation: LedgerCachePreparation, to conti: [Conto]) {
        for conto in conti {
            if let json = preparation.updates[conto.id], conto.ledgerCacheJSON != json {
                conto.ledgerCacheJSON = json
            }
        }
    }
}
