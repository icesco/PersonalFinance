import Foundation
import SwiftData

/// Intake lives in its own local store, never in the ledger or CloudKit schema.
@Model public final class PendingCapture {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var source: String = "share"
    public var sourceName: String = "Condivisione"
    public var originalText: String = ""
    public var destinationName: String = ""
    public var filename: String?
    public var contentType: String?
    /// Nil means this document has never been read. Empty/error outcomes are durable too.
    public var documentReadStatus: String?
    public var documentText: String?
    @Attribute(.externalStorage) public var document: Data?

    public init(id: UUID = UUID(), source: String, sourceName: String, text: String,
                destinationName: String = "", filename: String? = nil, contentType: String? = nil, document: Data? = nil) {
        self.id = id; self.source = source; self.sourceName = sourceName
        self.originalText = text; self.destinationName = destinationName
        self.filename = filename; self.contentType = contentType; self.document = document
    }
}

/// A durable receipt prevents approval retries from recreating a deleted movement.
@Model public final class CaptureApprovalReceipt {
    public var captureID: UUID = UUID()
    public var transactionID: UUID = UUID()
    public var createdAt: Date = Date()
    public init(captureID: UUID, transactionID: UUID) {
        self.captureID = captureID; self.transactionID = transactionID
    }
}
