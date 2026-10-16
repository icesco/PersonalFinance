import Foundation
import SwiftData

public struct CaptureDuplicateMatch: Identifiable {
    public let id: String
    public let description: String
    public let date: Date
    public let isRecurring: Bool
}

@MainActor public enum CaptureDuplicateCheck {
    /// Compare ledger currency, direction and account. Descriptions can differ between bank and manual entries.
    public static func matches(captureID: UUID, contoID: UUID, amount: Decimal, type: TransactionType,
                               date: Date, in context: ModelContext, calendar: Calendar = .current) throws -> [CaptureDuplicateMatch] {
        guard amount > 0, type != .transfer else { return [] }
        let start = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: date)) ?? date
        let end = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: date)) ?? date
        let externalID = "capture:\(captureID.uuidString)"
        func sameMovement(_ transaction: Transaction) -> Bool {
            let accountID = type == .expense
                ? (transaction.fromConto?.id ?? transaction.fromContoId)
                : (transaction.toConto?.id ?? transaction.toContoId)
            return transaction.externalID != externalID && transaction.amount == amount &&
                transaction.type == type && accountID == contoID
        }
        let recorded = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= start && $0.date < end }))
        var result = recorded.filter(sameMovement).map {
            CaptureDuplicateMatch(id: "transaction:\($0.id.uuidString)", description: $0.transactionDescription ?? "",
                                  date: $0.date, isRecurring: false)
        }
        let sources = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.isRecurring == true }))
        let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>(predicate: #Predicate { $0.scheduledDate >= start && $0.scheduledDate < end }))
        let resolvedKeys = Set(resolutions.map(\.key)).union(recorded.compactMap(\.externalID))
        for source in sources where sameMovement(source) {
            for occurrence in RecurrenceOccurrenceService.pendingDates(source: source,
                interval: DateInterval(start: start, end: end), resolvedKeys: resolvedKeys) {
                result.append(CaptureDuplicateMatch(id: RecurrenceResolution.key(sourceID: source.id, date: occurrence),
                    description: source.transactionDescription ?? "", date: occurrence, isRecurring: true))
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
