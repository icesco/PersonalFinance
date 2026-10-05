import Foundation

/// Remote identity is scoped to a book. A transfer can occur in two book zones;
/// importers must map these identities independently instead of joining the two
/// participants' local account graphs through a transaction UUID alone.
public struct SharedRecordID: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case book, conto, category, transaction, budget, goal, attachment, recurrence }
    public let bookID: UUID
    public let kind: Kind
    public let entityID: String
    public var recordName: String { "\(kind.rawValue):\(entityID)" }
    public init(bookID: UUID, kind: Kind, entityID: String) {
        self.bookID = bookID; self.kind = kind; self.entityID = entityID
    }
}

public enum SharedValue: Codable, Equatable, Sendable {
    case text(String), decimal(Decimal), date(Date), flag(Bool), integer(Int), number(Double)
    case reference(SharedRecordID), references([SharedRecordID])
}

public struct SharedBookRecord: Codable, Equatable, Sendable {
    public var version: Int = 1
    public let id: SharedRecordID
    public var deleted: Bool
    public var fields: [String: SharedValue]
    public init(id: SharedRecordID, deleted: Bool = false, fields: [String: SharedValue] = [:]) {
        self.id = id; self.deleted = deleted; self.fields = fields
    }
    public func tombstone() -> Self { Self(id: id, deleted: true) }
}

public struct SharedBookConflict: Codable, Equatable, Sendable {
    public enum Reason: Codable, Equatable, Sendable { case fields([String]), deletion, concurrentCreation }
    public let base: SharedBookRecord?
    public let local: SharedBookRecord
    public let remote: SharedBookRecord
    public let reason: Reason
    public var localReferenceNames: [SharedRecordID: String]? = nil
    public var remoteReferenceNames: [SharedRecordID: String]? = nil
}

/// A decision is valid only for the exact versions shown to the person.
public struct SharedBookDecision: Codable, Equatable, Sendable {
    public let expected: SharedBookConflict
    public let side: SharedBookMerge.Side
    public init(expected: SharedBookConflict, side: SharedBookMerge.Side) {
        self.expected = expected; self.side = side
    }
    public func resolved() throws -> SharedBookRecord {
        if case let .fields(keys) = expected.reason {
            return try SharedBookMerge.resolveFields(expected, choices: Dictionary(uniqueKeysWithValues: keys.map { ($0, side) }))
        }
        return side == .local ? expected.local : expected.remote
    }
}

public enum SharedBookMerge {
    public enum Failure: Error { case incompatibleVersion, differentIdentity, unresolvedConflict }
    public enum Result: Equatable, Sendable { case merged(SharedBookRecord), conflict(SharedBookConflict) }

    /// The base is the last acknowledged server record, not the last local edit.
    /// Absence is never interpreted as a deletion; deletions have explicit records.
    public static func merge(base: SharedBookRecord?, local: SharedBookRecord, remote: SharedBookRecord) throws -> Result {
        guard local.version == 1, remote.version == 1, base == nil || base?.version == 1 else { throw Failure.incompatibleVersion }
        guard local.id == remote.id, base == nil || base?.id == local.id else { throw Failure.differentIdentity }
        if local == remote { return .merged(local) }
        if local == base { return .merged(remote) }
        if remote == base { return .merged(local) }
        if local.deleted || remote.deleted {
            return .conflict(SharedBookConflict(base: base, local: local, remote: remote, reason: .deletion))
        }
        guard let base else {
            return .conflict(SharedBookConflict(base: nil, local: local, remote: remote, reason: .concurrentCreation))
        }
        var merged = local
        var conflicts: [String] = []
        for key in Set(base.fields.keys).union(local.fields.keys).union(remote.fields.keys).sorted() {
            let original = base.fields[key], lhs = local.fields[key], rhs = remote.fields[key]
            if lhs == rhs { merged.fields[key] = lhs }
            else if lhs == original { merged.fields[key] = rhs }
            else if rhs == original { merged.fields[key] = lhs }
            else if key == "updatedAt", case let .date(left)? = lhs, case let .date(right)? = rhs {
                // Audit time is metadata; it must not block disjoint content edits.
                merged.fields[key] = .date(max(left, right))
            } else { conflicts.append(key) }
        }
        if !conflicts.isEmpty {
            return .conflict(SharedBookConflict(base: base, local: local, remote: remote, reason: .fields(conflicts)))
        }
        return .merged(merged)
    }

    public enum Side: String, Codable, Sendable { case local, remote }

    /// Resolve only the disputed fields, keeping automatic merges for every
    /// other field. Deletion and independent creation require a whole-record choice.
    public static func resolveFields(_ conflict: SharedBookConflict, choices: [String: Side]) throws -> SharedBookRecord {
        guard case let .fields(keys) = conflict.reason, Set(choices.keys) == Set(keys) else { throw Failure.unresolvedConflict }
        var local = conflict.local, remote = conflict.remote
        for key in keys {
            switch choices[key] {
            case .local: remote.fields[key] = local.fields[key]
            case .remote: local.fields[key] = remote.fields[key]
            case nil: throw Failure.unresolvedConflict
            }
        }
        guard case let .merged(record) = try merge(base: conflict.base, local: local, remote: remote) else { throw Failure.unresolvedConflict }
        return record
    }

    /// Generate pending records from a complete local export and the server base.
    /// Missing records in an incremental network response must never be passed here.
    public static func localChanges(base: [SharedBookRecord], completeLocal: [SharedBookRecord]) throws -> [SharedBookRecord] {
        if let previousBook = base.first?.id.bookID, let currentBook = completeLocal.first?.id.bookID,
           previousBook != currentBook { throw Failure.differentIdentity }
        let old = try index(base), current = try index(completeLocal)
        var result: [SharedBookRecord] = []
        for (id, record) in current where old[id] != record { result.append(record) }
        for (id, record) in old where current[id] == nil && !record.deleted { result.append(record.tombstone()) }
        return result.sorted { $0.id.recordName < $1.id.recordName }
    }

    private static func index(_ records: [SharedBookRecord]) throws -> [SharedRecordID: SharedBookRecord] {
        var indexed: [SharedRecordID: SharedBookRecord] = [:]
        let bookID = records.first?.id.bookID
        for record in records {
            guard record.version == 1 else { throw Failure.incompatibleVersion }
            guard record.id.bookID == bookID, indexed[record.id] == nil else { throw Failure.differentIdentity }
            indexed[record.id] = record
        }
        return indexed
    }
}
