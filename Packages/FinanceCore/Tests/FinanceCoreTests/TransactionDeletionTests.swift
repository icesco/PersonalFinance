import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct TransactionDeletionTests {
    enum SaveFailure: Error { case unavailable }
    private func fixture() throws -> (ModelContainer, Account, Conto, Transaction, Transaction, TransactionAttachment) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Book")
        let conto = Conto(name: "Bank", type: .checking, initialBalance: 100)
        conto.account = book
        context.insert(book); context.insert(conto)
        let category = FinanceCore.Category(name: "Food")
        category.account = book; context.insert(category)
        let first = Transaction(amount: 20, type: .expense, date: Date())
        first.setFromConto(conto); first.setCategory(category)
        let second = Transaction(amount: 30, type: .expense, date: Date())
        second.setFromConto(conto); second.setCategory(category)
        context.insert(first); context.insert(second)
        let attachment = TransactionAttachment(filename: "receipt.txt", contentType: "public.text", data: Data("receipt".utf8))
        attachment.transaction = first
        context.insert(attachment)
        first.attachments = [attachment]
        try context.save()
        return (container, book, conto, first, second, attachment)
    }

    @Test func successfulBatchDeletesOnlySelectedEntriesAndTheirAttachments() throws {
        let (container, _, conto, first, second, _) = try fixture()
        let context = container.mainContext
        #expect(conto.balance == 50)
        let retained = Transaction(amount: 5, type: .income, date: Date())
        context.insert(retained); try context.save()
        try TransactionDeletion(context: context).delete(ids: [first.id, second.id])
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Transaction>()).map(\.id) == [retained.id])
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<Conto>()) == 1)
        #expect(try verify.fetchCount(FetchDescriptor<FinanceCore.Category>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(conto.balance == 100)
        try context.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func failedDeleteRestoresAttachmentsRelationshipsAndBalances() throws {
        let (container, _, conto, first, second, attachment) = try fixture()
        let context = container.mainContext
        let firstID = first.id
        let contoID = conto.id
        let attachmentID = attachment.id
        let failing = TransactionDeletion(context: context, save: { _ in throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try failing.delete(ids: [firstID, second.id]) }
        let restored = try #require(context.fetch(FetchDescriptor<Transaction>()).first { $0.id == firstID })
        #expect(restored.fromConto?.id == contoID)
        #expect(restored.category?.name == "Food")
        #expect(restored.attachments?.first?.id == attachmentID)
        #expect(restored.attachments?.first?.data == Data("receipt".utf8))
        #expect(conto.balance == 50)
        try context.save()
        let verify = ModelContext(container)
        #expect(try verify.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 1)
    }

    @Test func failedPreparationDoesNotDiscardPendingChangesOrDelete() throws {
        let (container, book, _, first, _, _) = try fixture()
        let context = container.mainContext
        book.name = "Pending draft"
        let failing = TransactionDeletion(context: context, save: { _ in throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try failing.delete(ids: [first.id]) }
        #expect(book.name == "Pending draft")
        #expect(!first.isDeleted)
        #expect(context.hasChanges)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    @Test func failedDeletionAfterPreparationKeepsPreviouslyPendingChanges() throws {
        let (container, book, _, first, _, _) = try fixture()
        let context = container.mainContext
        book.name = "Preserved draft"
        var calls = 0
        let failing = TransactionDeletion(context: context, save: { savingContext in
            calls += 1
            if calls == 1 { try savingContext.save() } else { throw SaveFailure.unavailable }
        })
        #expect(throws: SaveFailure.self) { try failing.delete(ids: [first.id]) }
        #expect(calls == 2)
        #expect(book.name == "Preserved draft")
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Account>()).first?.name == "Preserved draft")
        #expect(try verify.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    @Test func staleBatchFailsWithoutPartiallyDeletingOrSaving() throws {
        let (container, _, _, first, _, _) = try fixture()
        var saves = 0
        let edits = TransactionDeletion(context: container.mainContext, save: { _ in saves += 1 })
        #expect(throws: TransactionDeletion.Failure.selectionChanged) {
            try edits.delete(ids: [first.id, UUID()])
        }
        try edits.delete(ids: [])
        #expect(saves == 0)
        #expect(!first.isDeleted)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }
    @Test func fileBackedFailurePreservesExternalAttachmentBytesAndCanRetry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = FinanceCoreModule.createSchema()
        let configuration = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.autosaveEnabled = false
        let transaction = Transaction(amount: 50, type: .expense)
        let bytes = Data(repeating: 41, count: 2 * 1024 * 1024)
        let attachment = TransactionAttachment(filename: "receipt.bin", contentType: "public.data", data: bytes)
        transaction.attachments = [attachment]
        context.insert(transaction)
        try context.save()
        let id = transaction.id
        let failing = TransactionDeletion(context: context, save: { _ in throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try failing.delete(ids: [id]) }
        let retained = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        #expect(retained.attachments?.first?.data == bytes)
        #expect(try ModelContext(container).fetch(FetchDescriptor<TransactionAttachment>()).first?.data == bytes)
        try TransactionDeletion(context: context).delete(ids: [id])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
    }

}
