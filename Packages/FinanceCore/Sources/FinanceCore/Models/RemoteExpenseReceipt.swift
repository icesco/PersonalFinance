import Foundation
import SwiftData

/// Kept independently of the result, so a late retry cannot recreate or overwrite
/// an entity that the user has subsequently edited or deleted.
/// CLI category commands also use this receipt; their digest has a separate domain.
@Model
public final class RemoteExpenseReceipt {
    #Index<RemoteExpenseReceipt>([\.requestID])
    public var requestID: UUID = UUID()
    /// Historical field name: resulting transaction or CLI category UUID.
    public var transactionID: UUID?
    public var requestDigest: Data?
    public var createdAt: Date = Date()

    public init(requestID: UUID, transactionID: UUID, requestDigest: Data, createdAt: Date) {
        self.requestID = requestID
        self.transactionID = transactionID
        self.requestDigest = requestDigest
        self.createdAt = createdAt
    }
}
