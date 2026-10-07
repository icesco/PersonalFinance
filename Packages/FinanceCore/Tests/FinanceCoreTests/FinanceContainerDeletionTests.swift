import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FinanceContainerDeletionTests {
    private func fixture() throws -> (ModelContainer, Account, Conto, Conto, Transaction) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Personal")
        let first = Conto(name: "Bank", type: .checking, initialBalance: 100)
        let second = Conto(name: "Cash", type: .cash, initialBalance: 50)
        first.account = book; second.account = book
        context.insert(book); context.insert(first); context.insert(second)
        let transfer = Transaction(amount: 20, type: .transfer)
        transfer.setFromConto(first); transfer.setToConto(second)
        context.insert(transfer)
        let expense = Transaction(amount: 10, type: .expense, isRecurring: true, recurrenceFrequency: .monthly)
        expense.setFromConto(first); context.insert(expense)
        let attachment = TransactionAttachment(filename: "receipt", contentType: "public.data", data: Data([1, 2]))
        attachment.transaction = expense; expense.attachments = [attachment]; context.insert(attachment)
        context.insert(RecurrenceResolution(sourceID: expense.id, scheduledDate: Date(), isSkipped: true))
        let retained = Transaction(amount: 5, type: .income)
        retained.setToConto(second); context.insert(retained)
        try context.save()
        return (container, book, first, second, retained)
    }

    @Test func contoDeletesBothTransferLegsAttachmentsAndRecurrenceMetadata() throws {
        let (container, book, first, second, retained) = try fixture()
        let context = container.mainContext
        let id = first.id
        let otherID = second.id
        #expect(second.balance == 75)
        let impact = try FinanceContainerDeletion(context: context).impact(of: .conto(id))
        #expect(impact.transactions == 2)
        #expect(impact.transfers == 1)
        try FinanceContainerDeletion(context: context).delete(.conto(id))
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Transaction>()).map(\.id) == [retained.id])
        #expect(try verify.fetch(FetchDescriptor<Conto>()).map(\.id) == [otherID])
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 0)
        #expect(try verify.fetch(FetchDescriptor<Account>()).first?.id == book.id)
        #expect(second.balance == 55)
    }

    @Test func bookDeletesArchivedContiCategoriesBudgetsGoalsAndIndexedOrphans() throws {
        let (container, book, first, _, _) = try fixture()
        let context = container.mainContext
        let id = book.id
        first.isActive = false
        let category = FinanceCore.Category(name: "Food"); category.account = book; context.insert(category)
        let budget = Budget(name: "Month", amount: 100, period: .monthly); budget.account = book; context.insert(budget)
        let goal = SavingsGoal(name: "Holiday", targetAmount: 500); goal.account = book; context.insert(goal)
        let orphan = Transaction(amount: 3, type: .expense); orphan.fromContoId = first.id; context.insert(orphan)
        let categoryOnly = Transaction(amount: 2, type: .expense); categoryOnly.setCategory(category); context.insert(categoryOnly)
        let other = Account(name: "Work"); context.insert(other)
        let otherConto = Conto(name: "Work bank", type: .checking); otherConto.account = other; context.insert(otherConto)
        let unrelated = Transaction(amount: 7, type: .income); unrelated.setToConto(otherConto); context.insert(unrelated)
        try context.save()
        try FinanceContainerDeletion(context: context).delete(.book(id))
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Account>()).map(\.id) == [other.id])
        #expect(try verify.fetch(FetchDescriptor<Transaction>()).map(\.id) == [unrelated.id])
        #expect(try verify.fetchCount(FetchDescriptor<Conto>()) == 1)
        #expect(try verify.fetchCount(FetchDescriptor<FinanceCore.Category>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<Budget>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<SavingsGoal>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 0)
    }

    @Test func sharedBookCannotBeDeletedOrLoseAConto() throws {
        let (container, book, first, _, _) = try fixture()
        let context = container.mainContext
        context.insert(SharedBookMembership(scopeKey: "shared", ownerName: "owner", remoteBookID: book.id, localBookID: book.id))
        try context.save()
        for target in [FinanceContainerDeletion.Target.book(book.id), .conto(first.id)] {
            #expect(throws: FinanceContainerDeletion.Failure.self) { try FinanceContainerDeletion(context: context).delete(target) }
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 3)
    }

    @Test func failureRollsBackCascadeAndKeepsPriorDraft() throws {
        enum SaveFailure: Error { case unavailable }
        let (container, book, first, _, _) = try fixture()
        let context = container.mainContext
        let id = first.id
        book.name = "Saved draft"
        var saves = 0
        let deletion = FinanceContainerDeletion(context: context, save: {
            saves += 1
            if saves == 1 { try $0.save() } else { throw SaveFailure.unavailable }
        })
        #expect(throws: SaveFailure.self) { try deletion.delete(.conto(id)) }
        let verify = ModelContext(container)
        #expect(try verify.fetchCount(FetchDescriptor<Transaction>()) == 3)
        #expect(try verify.fetchCount(FetchDescriptor<Conto>()) == 2)
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 1)
        #expect(try verify.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 1)
        #expect(try verify.fetch(FetchDescriptor<Account>()).first?.name == "Saved draft")
    }

    @Test func staleSelectionDoesNotSaveOrDelete() throws {
        let (container, _, _, _, _) = try fixture()
        var saves = 0
        let deletion = FinanceContainerDeletion(context: container.mainContext, save: { _ in saves += 1 })
        #expect(throws: FinanceContainerDeletion.Failure.self) { try deletion.delete(.book(UUID())) }
        #expect(saves == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 3)
    }
    @Test func diskStorePersistsCascadeAndKeepsRetryReceipts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = FinanceCoreModule.createSchema()
        let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("deletion.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Disk book")
        let conto = Conto(name: "Disk bank", type: .checking)
        conto.account = book; context.insert(book); context.insert(conto)
        let transaction = Transaction(amount: 12, type: .expense)
        transaction.setFromConto(conto); context.insert(transaction)
        let attachment = TransactionAttachment(filename: "receipt.bin", contentType: "public.data", data: Data(repeating: 9, count: 2 * 1024 * 1024))
        attachment.transaction = transaction; transaction.attachments = [attachment]; context.insert(attachment)
        context.insert(RemoteExpenseReceipt(requestID: UUID(), transactionID: transaction.id, requestDigest: Data([4]), createdAt: Date()))
        try context.save()
        try FinanceContainerDeletion(context: context).delete(.book(book.id))
        let reopened = try ModelContainer(for: schema, configurations: [config])
        let verify = ModelContext(reopened)
        #expect(try verify.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<Conto>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 1)
    }

    @Test func crossBookTransferDeletionRetainsOtherBookAndItsOwnMovements() throws {
        let (container, book, first, _, _) = try fixture()
        let context = container.mainContext
        let other = Account(name: "Work")
        let otherConto = Conto(name: "Work bank", type: .checking, initialBalance: 200)
        otherConto.account = other; context.insert(other); context.insert(otherConto)
        let transfer = Transaction(amount: 30, type: .transfer)
        transfer.setFromConto(first); transfer.setToConto(otherConto); context.insert(transfer)
        let income = Transaction(amount: 10, type: .income)
        income.setToConto(otherConto); context.insert(income)
        try context.save()
        #expect(otherConto.balance == 240)
        try FinanceContainerDeletion(context: context).delete(.book(book.id))
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Account>()).map(\.id) == [other.id])
        #expect(try verify.fetch(FetchDescriptor<Transaction>()).map(\.id) == [income.id])
        #expect(otherConto.balance == 210)
    }

    @Test func indexedTransferToSharedBookIsProtectedEvenBeforeRelationshipSync() throws {
        let (container, book, first, _, _) = try fixture()
        let context = container.mainContext
        let shared = Account(name: "Shared")
        let destination = Conto(name: "Shared bank", type: .checking)
        destination.account = shared; context.insert(shared); context.insert(destination)
        context.insert(SharedBookMembership(scopeKey: "shared", ownerName: "owner", remoteBookID: shared.id, localBookID: shared.id))
        let transfer = Transaction(amount: 8, type: .transfer)
        transfer.setFromConto(first); transfer.toContoId = destination.id; context.insert(transfer)
        try context.save()
        #expect(throws: FinanceContainerDeletion.Failure.self) {
            try FinanceContainerDeletion(context: context).delete(.book(book.id))
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 4)
    }

}
