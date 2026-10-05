import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct AttachmentPersistenceTests {
    @Test func persistsBytesAndCascadesWhenTransactionIsDeleted() throws {
        let container = try FinanceCoreModule.createModelContainer(inMemory: true)
        let context = container.mainContext
        let transaction = Transaction(amount: 42, type: .expense)
        let bytes = Data([1, 2, 3, 4])
        transaction.attachments = [TransactionAttachment(filename: "receipt.pdf", contentType: "com.adobe.pdf", data: bytes)]
        context.insert(transaction)
        try context.save()
        let other = ModelContext(container)
        let fetched = try #require(other.fetch(FetchDescriptor<Transaction>()).first)
        #expect(fetched.attachments?.count == 1)
        #expect(fetched.attachments?.first?.data == bytes)
        #expect(fetched.attachments?.first?.transaction?.id == transaction.id)
        other.delete(fetched)
        try other.save()
        #expect(try other.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
    }

    @Test func unsavedDraftDoesNotPersistAttachment() throws {
        let container = try FinanceCoreModule.createModelContainer(inMemory: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let transaction = Transaction(amount: 42, type: .expense)
        transaction.attachments = [TransactionAttachment(filename: "receipt.pdf", contentType: "com.adobe.pdf", data: Data([1]))]
        context.insert(transaction)
        context.rollback()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
    }
}
