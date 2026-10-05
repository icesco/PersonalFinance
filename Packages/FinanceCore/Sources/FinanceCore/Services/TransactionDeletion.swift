import Foundation
import SwiftData

@MainActor
public struct TransactionDeletion {
    public enum Failure: Error { case selectionChanged }
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void

    public init(context: ModelContext) { self.init(context: context, save: { try $0.save() }) }
    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void) { self.context = context; self.save = save }

    public func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        let requestedIDs = Array(ids)
        let selected = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate {
            requestedIDs.contains($0.id)
        }))
        guard selected.count == ids.count, Set(selected.map(\.id)) == ids else { throw Failure.selectionChanged }
        // Commit prior edits first: a failed preparation must leave those drafts intact.
        if context.hasChanges { try save(context) }
        // Flush relationship snapshots before and after cascading deletions. Without
        // this, rollback can encounter future backing data for external attachments.
        context.processPendingChanges()
        for transaction in selected { context.delete(transaction) }
        context.processPendingChanges()
        do { try save(context) }
        catch {
            // No suspension or unrelated edits occurred after the save boundary.
            context.rollback()
            throw error
        }
    }
}
