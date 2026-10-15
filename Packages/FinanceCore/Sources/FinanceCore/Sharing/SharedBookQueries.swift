import Foundation
import SwiftData

@MainActor
enum SharedBookQueries {
    static func touching(contiIDs: Set<UUID>, in context: ModelContext) throws -> [Transaction] {
        guard !contiIDs.isEmpty else { return [] }
        let ids = Array(contiIDs)
        let indexed = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
            $0.fromContoId.flatMap { ids.contains($0) } == true || $0.toContoId.flatMap { ids.contains($0) } == true
        })
        let legacyFrom = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
            $0.fromContoId == nil && $0.fromConto.flatMap { ids.contains($0.id) } == true
        })
        let legacyTo = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
            $0.toContoId == nil && $0.toConto.flatMap { ids.contains($0.id) } == true
        })
        return try unique([indexed, legacyFrom, legacyTo].flatMap { try context.fetch($0) })
    }

    static func unique<T: PersistentModel>(_ rows: [T]) -> [T] {
        var seen: Set<PersistentIdentifier> = []
        return rows.filter { seen.insert($0.persistentModelID).inserted }
    }

    /// The importer used to reject duplicate UUIDs anywhere in each entity table.
    /// Preserve that check while projecting just identity columns in bounded batches.
    static func validateIdentities<T: PersistentModel>(in context: ModelContext, key: KeyPath<T, UUID>) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.propertiesToFetch = [key]
        var seen: Set<UUID> = []
        try context.enumerate(descriptor, batchSize: 512) { row in
            guard seen.insert(row[keyPath: key]).inserted else { throw SharedBookImporter.Failure.identityCollision }
        }
    }

    static func transactions(in context: ModelContext, contoIDs: Set<UUID>, incomingIDs: [UUID],
                             deletedCategoryIDs: [UUID], deletedTransactionIDs: [UUID]) throws -> [Transaction] {
        var rows = try touching(contiIDs: contoIDs, in: context)
        if !incomingIDs.isEmpty {
            rows += try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { incomingIDs.contains($0.id) }))
        }
        if !deletedCategoryIDs.isEmpty {
            rows += try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
                $0.categoryId.flatMap { deletedCategoryIDs.contains($0) } == true
                    || $0.category.flatMap { deletedCategoryIDs.contains($0.id) } == true
            }))
        }
        if !deletedTransactionIDs.isEmpty {
            rows += try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> {
                $0.recurrenceSourceID.flatMap { deletedTransactionIDs.contains($0) } == true
            }))
        }
        return unique(rows)
    }
}
