import Foundation
import CryptoKit

public struct SharedBookScope: Codable, Hashable, Sendable {
    public let ownerName: String
    public let bookID: UUID
    public init(ownerName: String, bookID: UUID) { self.ownerName = ownerName; self.bookID = bookID }
    public var key: String { digest("scope").map { String(format: "%02x", $0) }.joined() }

    /// Each confirmed departure advances the deterministic identity chain once.
    /// Devices with the same departure history therefore rejoin into the same
    /// namespace, regardless of CloudKit delivery order or duplicate markers.
    func importNamespace(afterLeaving retiredBookIDs: Set<UUID>) -> UUID? {
        let root = SharedRecordID(bookID: bookID, kind: .book, entityID: bookID.uuidString.lowercased())
        var namespace: UUID?
        var candidate = isolatedID(for: root)
        for _ in retiredBookIDs {
            guard retiredBookIDs.contains(candidate) else { break }
            namespace = candidate
            candidate = SharedBookScope(ownerName: ownerName, bookID: candidate).isolatedID(for: root)
        }
        return namespace
    }

    /// Separate namespaces prevent a foreign book or a cross-book transfer from
    /// attaching itself to existing private objects that have the same remote UUID.
    public func isolatedID(for record: SharedRecordID) -> UUID {
        var bytes = Array(digest(record.recordName).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private func digest(_ suffix: String) -> SHA256.Digest {
        SHA256.hash(data: Data("forgia.shared.v1\u{0}\(ownerName)\u{0}\(bookID.uuidString)\u{0}\(suffix)".utf8))
    }
}

extension SharedBookRecord {
    func text(_ key: String) throws -> String? {
        guard let value = fields[key] else { return nil }
        guard case let .text(text) = value else { throw SharedBookImporter.Failure.invalidField(key) }
        return text
    }
    func decimal(_ key: String) throws -> Decimal? {
        guard let value = fields[key] else { return nil }
        guard case let .decimal(number) = value, !number.isNaN else { throw SharedBookImporter.Failure.invalidField(key) }
        return number
    }
    func date(_ key: String) throws -> Date? {
        guard let value = fields[key] else { return nil }
        guard case let .date(date) = value, date.timeIntervalSince1970.isFinite else { throw SharedBookImporter.Failure.invalidField(key) }
        return date
    }
    func flag(_ key: String) throws -> Bool? {
        guard let value = fields[key] else { return nil }
        guard case let .flag(flag) = value else { throw SharedBookImporter.Failure.invalidField(key) }
        return flag
    }
    func integer(_ key: String) throws -> Int? {
        guard let value = fields[key] else { return nil }
        guard case let .integer(number) = value else { throw SharedBookImporter.Failure.invalidField(key) }
        return number
    }
    func number(_ key: String) throws -> Double? {
        guard let value = fields[key] else { return nil }
        guard case let .number(number) = value, number.isFinite else { throw SharedBookImporter.Failure.invalidField(key) }
        return number
    }
    func reference(_ key: String, kind: SharedRecordID.Kind) throws -> SharedRecordID? {
        guard let value = fields[key] else { return nil }
        guard case let .reference(reference) = value, reference.kind == kind else { throw SharedBookImporter.Failure.invalidField(key) }
        return reference
    }
    func references(_ key: String, kind: SharedRecordID.Kind) throws -> [SharedRecordID] {
        guard let value = fields[key] else { return [] }
        guard case let .references(references) = value, references.allSatisfy({ $0.kind == kind }),
              Set(references).count == references.count else { throw SharedBookImporter.Failure.invalidField(key) }
        return references
    }
    func enumeration<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T? where T.RawValue == String {
        guard let raw = try text(key) else { return nil }
        guard let value = T(rawValue: raw) else { throw SharedBookImporter.Failure.invalidField(key) }
        return value
    }
}
