import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct SharedBookQueryTests {
    @Test func scopedExportSelectionMatchesFullScanIncludingLegacyAndTransfers() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Condiviso"), privateBook = Account(name: "Privato")
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .checking)
        a.account = book; b.account = privateBook
        context.insert(book); context.insert(privateBook); context.insert(a); context.insert(b)
        for index in 0..<100 {
            let row = Transaction(amount: Decimal(index), type: index % 3 == 0 ? .transfer : .expense)
            row.setFromConto(index % 2 == 0 ? a : b)
            if row.type == .transfer { row.setToConto(index % 2 == 0 ? b : a) }
            context.insert(row)
            if index % 5 == 0 { row.fromContoId = nil; row.toContoId = nil }
        }
        try context.save()
        let all = try context.fetch(FetchDescriptor<Transaction>())
        let expected = all.filter { ($0.fromContoId ?? $0.fromConto?.id) == a.id || ($0.toContoId ?? $0.toConto?.id) == a.id }
        let actual = try SharedBookQueries.touching(contiIDs: [a.id], in: context)
        #expect(Set(actual.map(\.persistentModelID)) == Set(expected.map(\.persistentModelID)))
        #expect(actual.count == expected.count)
        let export = try SharedBookExporter.export(bookID: book.id, container: container)
        #expect(Set(export.records.filter { $0.id.kind == .transaction }.map(\.id.entityID)) == Set(expected.map { $0.id.uuidString.lowercased() }))
        #expect(!export.records.contains { $0.fields["name"] == .text("Privato") })
    }

    @Test func projectedIdentityCheckStillRejectsUnrelatedDuplicateUUIDs() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Transaction(amount: 1, type: .expense), b = Transaction(amount: 2, type: .expense)
        b.id = a.id; context.insert(a); context.insert(b); try context.save()
        #expect(throws: SharedBookImporter.Failure.self) {
            try SharedBookQueries.validateIdentities(in: ModelContext(container), key: \Transaction.id)
        }
    }

    @Test func deletionQueriesIncludeForeignCategoryAndRecurrenceDependents() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .checking)
        let category = Category(name: "Categoria")
        context.insert(a); context.insert(b); context.insert(category)
        let source = Transaction(amount: 10, type: .expense); source.setFromConto(a); context.insert(source)
        let foreign = Transaction(amount: 20, type: .expense); foreign.setFromConto(b); foreign.setCategory(category); context.insert(foreign)
        let child = Transaction(amount: 30, type: .expense); child.setFromConto(b); child.recurrenceSourceID = source.id; context.insert(child)
        let unrelated = Transaction(amount: 40, type: .expense); unrelated.setFromConto(b); context.insert(unrelated)
        try context.save()
        let actual = try SharedBookQueries.transactions(in: context, contoIDs: [a.id], incomingIDs: [],
            deletedCategoryIDs: [category.id], deletedTransactionIDs: [source.id])
        #expect(Set(actual.map(\.id)) == [source.id, foreign.id, child.id])
    }
}
