import Foundation
import CloudKit
import CryptoKit

/// Encodes zone-scoped records without creating a CKContainer or making requests.
/// Uploads must use .ifServerRecordUnchanged and feed conflicts to SharedBookMerge.
public enum SharedBookCloudCodec {
    public enum Failure: Error { case unsupportedRecord, wrongBook, invalidIdentity, oversizedRecord, missingAsset, corruptAsset }
    public static let recordType = "ForgiaSharedItemV1"
    public static func zoneName(bookID: UUID) -> String { "ForgiaBook-\(bookID.uuidString.lowercased())" }

    public static func encode(_ value: SharedBookRecord, zoneID: CKRecordZone.ID,
                              existing: CKRecord? = nil, assetURL: URL? = nil) throws -> CKRecord {
        try validate(value, bookID: value.id.bookID)
        guard zoneID.zoneName == zoneName(bookID: value.id.bookID) else { throw Failure.wrongBook }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(value)
        guard payload.count <= 900_000 else { throw Failure.oversizedRecord }
        if value.id.kind == .attachment && !value.deleted {
            guard let assetURL else { throw Failure.missingAsset }
            try validateAsset(at: assetURL, record: value)
        }
        let id = CKRecord.ID(recordName: value.id.recordName, zoneID: zoneID)
        if let existing {
            guard existing.recordID == id, existing.recordType == recordType else { throw Failure.invalidIdentity }
        }
        let record = existing ?? CKRecord(recordType: recordType, recordID: id)
        record["payload"] = payload as CKRecordValue
        if value.id.kind == .attachment, !value.deleted, let assetURL {
            record.setObject(CKAsset(fileURL: assetURL), forKey: "file")
        } else { record.setObject(nil, forKey: "file") }
        return record
    }

    public static func decode(_ record: CKRecord, expectedBookID: UUID) throws -> SharedBookRecord {
        guard record.recordType == recordType, let payload = record["payload"] as? Data else { throw Failure.unsupportedRecord }
        guard payload.count <= 900_000 else { throw Failure.oversizedRecord }
        let value = try JSONDecoder().decode(SharedBookRecord.self, from: payload)
        try validate(value, bookID: expectedBookID)
        guard record.recordID.zoneID.zoneName == zoneName(bookID: expectedBookID),
              record.recordID.recordName == value.id.recordName else { throw Failure.invalidIdentity }
        if value.id.kind == .attachment && !value.deleted {
            guard let url = (record["file"] as? CKAsset)?.fileURL else { throw Failure.missingAsset }
            try validateAsset(at: url, record: value)
        }
        return value
    }

    private static func validate(_ value: SharedBookRecord, bookID: UUID) throws {
        guard value.version == 1 else { throw Failure.unsupportedRecord }
        guard value.id.bookID == bookID else { throw Failure.wrongBook }
        guard !value.id.entityID.isEmpty, value.id.entityID.utf8.count <= 160,
              !value.deleted || value.fields.isEmpty else { throw Failure.invalidIdentity }
        for field in value.fields.values {
            switch field {
            case let .reference(reference):
                guard reference.bookID == bookID else { throw Failure.wrongBook }
            case let .references(references):
                guard references.allSatisfy({ $0.bookID == bookID }) else { throw Failure.wrongBook }
            default: break
            }
        }
    }

    private static func validateAsset(at url: URL, record: SharedBookRecord) throws {
        guard url.isFileURL, let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 10 * 1024 * 1024 else { throw Failure.corruptAsset }
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count <= 10 * 1024 * 1024 else { throw Failure.corruptAsset }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard record.fields["contentDigest"] == .text(digest) else { throw Failure.corruptAsset }
    }
}
