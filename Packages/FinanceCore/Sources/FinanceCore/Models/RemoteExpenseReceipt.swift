import Foundation
import SwiftData

/// Kept independently of the movement, so a late retry cannot recreate a
/// transaction that the user has subsequently edited or deleted.
@Model
public final class RemoteExpenseReceipt {
    #Index<RemoteExpenseReceipt>([\.requestID])
    public var requestID: UUID = UUID()
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
