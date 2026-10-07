import Foundation
import SwiftData

/// Explicitly resolves indexed IDs as well as relationships before cascading.
/// This also covers partially synchronized transactions whose relationship is missing.
@MainActor
public struct FinanceContainerDeletion {
    public enum Target: Equatable { case book(UUID), conto(UUID) }
    public enum Failure: LocalizedError {
        case selectionChanged, sharedBook
        public var errorDescription: String? {
            switch self {
            case .selectionChanged: return "Il libro o il conto non è più disponibile. Aggiorna la lista e riprova."
            case .sharedBook: return "Gestisci prima la condivisione del libro dalla schermata Condivisione del libro: interrompila o abbandonala prima di eliminare questi dati."
            }
        }
    }
    public struct Impact {
        public let transactions: Int
        public let transfers: Int
        public let conti: Int
    }
    private let context: ModelContext
    private let save: (ModelContext) throws -> Void
    public init(context: ModelContext) { self.init(context: context, save: { try $0.save() }) }
    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void) {
        self.context = context; self.save = save
    }
    private struct Selection {
        var book: Account?
        var conti: [Conto]
        var transactions: [Transaction]
        var categories: [Category]
        var budgets: [Budget]
        var goals: [SavingsGoal]
    }
    private func selection(_ target: Target) throws -> Selection {
        let books = try context.fetch(FetchDescriptor<Account>())
        let allConti = try context.fetch(FetchDescriptor<Conto>())
        var book: Account?
        let conti: [Conto]
        switch target {
        case .book(let id):
            guard let value = books.first(where: { $0.id == id }) else { throw Failure.selectionChanged }
            book = value
            let relatedIDs = Set((value.conti ?? []).map(\.id))
            conti = allConti.filter { $0.account?.id == id || relatedIDs.contains($0.id) }
        case .conto(let id):
            guard let value = allConti.first(where: { $0.id == id }) else { throw Failure.selectionChanged }
            conti = [value]
        }
        let ids = Set(conti.map(\.id))
        let categories = try context.fetch(FetchDescriptor<Category>()).filter { book != nil && $0.account?.id == book?.id }
        let categoryIDs = Set(categories.map(\.id))
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).filter {
            [$0.fromContoId, $0.toContoId, $0.fromConto?.id, $0.toConto?.id].compactMap { $0 }.contains { ids.contains($0) }
            || (book != nil && [$0.categoryId, $0.category?.id].compactMap { $0 }.contains { categoryIDs.contains($0) })
        }
        let linkedContoIDs = ids.union(transactions.flatMap {
            [$0.fromContoId, $0.toContoId, $0.fromConto?.id, $0.toConto?.id].compactMap { $0 }
        })
        let affectedBooks = Set(allConti.filter { linkedContoIDs.contains($0.id) }.compactMap { $0.account?.id }
                                + [book?.id].compactMap { $0 })
        if try context.fetch(FetchDescriptor<SharedBookMembership>()).contains(where: { affectedBooks.contains($0.localBookID) }) {
            throw Failure.sharedBook
        }
        return Selection(book: book, conti: conti, transactions: transactions, categories: categories,
                         budgets: try context.fetch(FetchDescriptor<Budget>()).filter { book != nil && $0.account?.id == book?.id },
                         goals: try context.fetch(FetchDescriptor<SavingsGoal>()).filter { book != nil && $0.account?.id == book?.id })
    }
    public func impact(of target: Target) throws -> Impact {
        let selected = try selection(target)
        return Impact(transactions: selected.transactions.count,
                      transfers: selected.transactions.filter { $0.type == .transfer }.count, conti: selected.conti.count)
    }
    public func delete(_ target: Target) throws {
        let selected = try selection(target)
        let ids = Set(selected.transactions.map(\.id))
        let resolutions = try context.fetch(FetchDescriptor<RecurrenceResolution>()).filter { ids.contains($0.sourceID) }
        let survivors = try context.fetch(FetchDescriptor<Transaction>()).filter {
            !ids.contains($0.id) && $0.recurrenceSourceID.map { ids.contains($0) } == true
        }
        if context.hasChanges { try save(context) }
        context.processPendingChanges()
        for value in resolutions { context.delete(value) }
        for value in survivors { value.recurrenceSourceID = nil }
        for value in selected.transactions { context.delete(value) }
        for value in selected.conti { context.delete(value) }
        for value in selected.categories { context.delete(value) }
        for value in selected.budgets { context.delete(value) }
        for value in selected.goals { context.delete(value) }
        if let book = selected.book { context.delete(book) }
        // RemoteExpenseReceipt deliberately survives: late Watch/widget retries must
        // not recreate a deleted transaction. It contains no financial payload.
        context.processPendingChanges()
        do { try save(context) }
        catch { context.rollback(); throw error }
    }
}
