import Foundation
import CloudKit

public enum SharedBookInvitation {
    public enum Failure: Error { case foreignContainer, invalidZone, invalidOwner, unsupportedShare, unsupportedPermission }
    public static func scope(containerIdentifier: String, zoneName: String, ownerName: String,
                             shareRecordName: String, hierarchical: Bool) throws -> SharedBookScope {
        guard containerIdentifier == FinanceCoreModule.cloudKitContainerIdentifier else { throw Failure.foreignContainer }
        guard !hierarchical, shareRecordName == CKRecordNameZoneWideShare else { throw Failure.unsupportedShare }
        let prefix = "ForgiaBook-"
        guard zoneName.hasPrefix(prefix), let id = UUID(uuidString: String(zoneName.dropFirst(prefix.count))),
              SharedBookCloudCodec.zoneName(bookID: id) == zoneName else { throw Failure.invalidZone }
        guard !ownerName.isEmpty, ownerName != CKCurrentUserDefaultName, ownerName.utf8.count <= 255,
              !ownerName.contains("\u{0}") else { throw Failure.invalidOwner }
        return SharedBookScope(ownerName: ownerName, bookID: id)
    }
    public static func scope(metadata: CKShare.Metadata) throws -> SharedBookScope {
        let zone = metadata.share.recordID.zoneID
        return try scope(containerIdentifier: metadata.containerIdentifier, zoneName: zone.zoneName, ownerName: zone.ownerName,
                         shareRecordName: metadata.share.recordID.recordName, hierarchical: metadata.hierarchicalRootRecordID != nil)
    }
}
