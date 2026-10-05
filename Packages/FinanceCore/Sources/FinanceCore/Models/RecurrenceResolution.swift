import Foundation
import SwiftData

/// No uniqueness constraint: compatible with CloudKit. The service reuses the logical key locally.
@Model
public final class RecurrenceResolution {
    public var key: String = ""
    public var sourceID: UUID = UUID()
    public var scheduledDate: Date = Date()
    public var transactionID: UUID?
    public var isSkipped: Bool = false
    public var createdAt: Date = Date()

    public init(sourceID: UUID, scheduledDate: Date, transactionID: UUID? = nil, isSkipped: Bool = false) {
        self.key = Self.key(sourceID: sourceID, date: scheduledDate)
        self.sourceID = sourceID
        self.scheduledDate = scheduledDate
        self.transactionID = transactionID
        self.isSkipped = isSkipped
    }

    public static func key(sourceID: UUID, date: Date) -> String {
        "recurrence:\(sourceID.uuidString):\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
    }
}
