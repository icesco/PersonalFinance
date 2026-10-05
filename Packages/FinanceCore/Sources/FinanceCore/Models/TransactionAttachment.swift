import Foundation
import SwiftData

@Model
public final class TransactionAttachment {
    public var id: UUID = UUID()
    public var filename: String = "Allegato"
    public var contentType: String = "public.data"
    @Attribute(.externalStorage) public var data: Data?
    public var createdAt: Date = Date()
    public var transaction: Transaction?

    public init(id: UUID = UUID(), filename: String, contentType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}
