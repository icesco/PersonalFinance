import Foundation
import CloudKit
import Testing
@testable import FinanceCore

struct SharedBookInvitationTests {
    @Test func parsesOnlyCanonicalForgiaZoneShares() throws {
        let bookID = UUID()
        let result = try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier,
                                                     zoneName: SharedBookCloudCodec.zoneName(bookID: bookID), ownerName: "owner-record",
                                                     shareRecordName: CKRecordNameZoneWideShare, hierarchical: false)
        #expect(result == SharedBookScope(ownerName: "owner-record", bookID: bookID))
        for zone in ["Other-\(bookID)", "ForgiaBook-", "ForgiaBook-\(bookID.uuidString.uppercased())", "ForgiaBook-\(bookID.uuidString.lowercased())-extra"] {
            #expect(throws: (any Error).self) { try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier,
                                                                              zoneName: zone, ownerName: "owner", shareRecordName: CKRecordNameZoneWideShare, hierarchical: false) }
        }
    }
    @Test func rejectsForeignContainerDefaultOwnerAndHierarchicalShares() throws {
        let zone = SharedBookCloudCodec.zoneName(bookID: UUID())
        for owner in ["", CKCurrentUserDefaultName, "bad\u{0}owner", String(repeating: "x", count: 256)] {
            #expect(throws: (any Error).self) { try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier,
                                                                              zoneName: zone, ownerName: owner, shareRecordName: CKRecordNameZoneWideShare, hierarchical: false) }
        }
        #expect(throws: (any Error).self) { try SharedBookInvitation.scope(containerIdentifier: "iCloud.other", zoneName: zone, ownerName: "owner", shareRecordName: CKRecordNameZoneWideShare, hierarchical: false) }
        #expect(throws: (any Error).self) { try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier, zoneName: zone, ownerName: "owner", shareRecordName: CKRecordNameZoneWideShare, hierarchical: true) }
        #expect(throws: (any Error).self) { try SharedBookInvitation.scope(containerIdentifier: FinanceCoreModule.cloudKitContainerIdentifier, zoneName: zone, ownerName: "owner", shareRecordName: "other-share", hierarchical: false) }
    }
}
