import Foundation
import SwiftData

/// Portable identity metadata, synchronized only in the person's private store.
/// Server change tokens and CKRecord system fields remain device-local.
@Model
public final class SharedBookMembership {
    #Index<SharedBookMembership>([\.scopeKey])
    public var scopeKey: String = ""
    public var ownerName: String = ""
    public var remoteBookID: UUID = UUID()
    public var localBookID: UUID = UUID()
    public var isOwner: Bool = false
    public var importNamespace: UUID? = nil
    public init(scopeKey: String, ownerName: String, remoteBookID: UUID, localBookID: UUID, isOwner: Bool = false) {
        self.scopeKey = scopeKey; self.ownerName = ownerName
        self.remoteBookID = remoteBookID; self.localBookID = localBookID
        self.isOwner = isOwner
    }
}

@Model
public final class SharedBookRecordLink {
    #Index<SharedBookRecordLink>([\.scopeKey], [\.remoteRecordName])
    public var scopeKey: String = ""
    public var remoteRecordName: String = ""
    public var localIdentity: String = ""
    public init(scopeKey: String, remoteRecordName: String, localIdentity: String) {
        self.scopeKey = scopeKey; self.remoteRecordName = remoteRecordName; self.localIdentity = localIdentity
    }
}

/// Records a confirmed departure without retaining any live sharing identity.
/// A later invitation must allocate a fresh namespace, preserving private copies.
@Model
public final class SharedBookDeparture {
    #Index<SharedBookDeparture>([\.scopeKey])
    public var scopeKey: String = ""
    public var localBookID: UUID = UUID()
    public init(scopeKey: String, localBookID: UUID) {
        self.scopeKey = scopeKey; self.localBookID = localBookID
    }
}
