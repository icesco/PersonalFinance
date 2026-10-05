import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct RemoteExpenseTests {
    private func fixture(url: URL? = nil) throws -> (ModelContainer, RemoteExpenseInput, Budget) {
        let container: ModelContainer
        if let url {
            container = try ModelContainer(for: FinanceCoreModule.createSchema(), configurations: [
                ModelConfiguration(schema: FinanceCoreModule.createSchema(), url: url, cloudKitDatabase: .none)
            ])
        } else {
            container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }
        let book = Account(name: "Personale", currency: "EUR")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 500)
        let category = Category(name: "Cibo")
        conto.account = book; category.account = book
        book.conti = [conto]; book.categories = [category]
        let budget = Budget(name: "Cibo", amount: 100, period: .monthly)
        budget.account = book; budget.categories = [category]
        container.mainContext.insert(book)
        container.mainContext.insert(budget)
        try container.mainContext.save()
        return (container, RemoteExpenseInput(requestID: UUID(), bookID: book.id, contoID: conto.id,
            categoryID: category.id, amount: 40, currency: "EUR", date: Date(), note: "Pranzo"), budget)
    }

    @Test func previewDoesNotSaveAndConfirmationCreatesExactlyOneMovement() throws {
        let (container, input, _) = try fixture()
        let quote = try RemoteExpenseService.preview(input, container: container)
        #expect(quote.budgets.first?.remaining == 60)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        let result = try RemoteExpenseService.save(input, confirmation: quote, container: container)
        #expect(!result.alreadyRecorded)
        let retry = try RemoteExpenseService.save(input, confirmation: quote, container: container)
        #expect(retry.alreadyRecorded)
        #expect(retry.transactionID == result.transactionID)
        let context = ModelContext(container)
        let transaction = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        #expect(transaction.fromContoId == input.contoID)
        #expect(transaction.categoryId == input.categoryID)
        #expect(transaction.amount == 40)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 1)
        // Editing/deleting a movement must not undo the receipt for its request.
        context.delete(transaction)
        try context.save()
        let afterDeletion = try RemoteExpenseService.save(input, confirmation: quote, container: container,
                                                          now: Date().addingTimeInterval(3600))
        #expect(afterDeletion.alreadyRecorded)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func changedBudgetRequiresNewConfirmationBeforeSaving() throws {
        let (container, input, budget) = try fixture()
        let quote = try RemoteExpenseService.preview(input, container: container)
        budget.amount = 30
        try container.mainContext.save()
        #expect(throws: RemoteExpenseService.Failure.confirmationChanged) {
            try RemoteExpenseService.save(input, confirmation: quote, container: container)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        let revised = try RemoteExpenseService.preview(input, container: container)
        #expect(revised.budgets.first?.remaining == -10)
        _ = try RemoteExpenseService.save(input, confirmation: revised, container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func legacyExpensesAreIncludedAndNewSpendingInvalidatesQuote() throws {
        let (container, input, _) = try fixture()
        let quote = try RemoteExpenseService.preview(input, container: container)
        let context = container.mainContext
        let old = Transaction(amount: 80, type: .expense, date: input.date)
        old.fromConto = try context.fetch(FetchDescriptor<Conto>()).first
        old.category = try context.fetch(FetchDescriptor<FinanceCore.Category>()).first
        context.insert(old)
        try context.save()
        #expect(old.fromContoId == nil)
        #expect(old.categoryId == nil)
        let revised = try RemoteExpenseService.preview(input, container: container)
        #expect(revised.budgets.first?.remaining == -20)
        #expect(throws: RemoteExpenseService.Failure.confirmationChanged) {
            try RemoteExpenseService.save(input, confirmation: quote, container: container)
        }
    }

    @Test func expiredConfirmationAndWrongBookCannotSave() throws {
        let (container, input, _) = try fixture()
        let quote = try RemoteExpenseService.preview(input, container: container)
        #expect(throws: RemoteExpenseService.Failure.confirmationExpired) {
            try RemoteExpenseService.save(input, confirmation: quote, container: container,
                                           now: quote.issuedAt.addingTimeInterval(301))
        }
        let other = RemoteExpenseInput(requestID: UUID(), bookID: UUID(), contoID: input.contoID,
            categoryID: input.categoryID, amount: input.amount, currency: input.currency, date: input.date, note: input.note)
        #expect(throws: RemoteExpenseService.Failure.invalidSelection) {
            try RemoteExpenseService.preview(other, container: container)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func reusedRequestWithDifferentPayloadIsRejected() throws {
        let (container, input, _) = try fixture()
        let quote = try RemoteExpenseService.preview(input, container: container)
        _ = try RemoteExpenseService.save(input, confirmation: quote, container: container)
        let changed = RemoteExpenseInput(requestID: input.requestID, bookID: input.bookID, contoID: input.contoID,
            categoryID: input.categoryID, amount: 90, currency: input.currency, date: input.date, note: input.note)
        #expect(throws: RemoteExpenseService.Failure.requestIDReused) {
            try RemoteExpenseService.save(changed, confirmation: quote, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Transaction>()) == 1)
    }
    @Test func receiptSurvivesReopeningDiskStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Finance.sqlite")
        let (input, quote, transactionID) = try autoreleasepool {
            let (container, input, _) = try fixture(url: url)
            let quote = try RemoteExpenseService.preview(input, container: container)
            let saved = try RemoteExpenseService.save(input, confirmation: quote, container: container)
            return (input, quote, saved.transactionID)
        }
        let reopened = try ModelContainer(for: FinanceCoreModule.createSchema(), configurations: [
            ModelConfiguration(schema: FinanceCoreModule.createSchema(), url: url, cloudKitDatabase: .none)
        ])
        let result = try RemoteExpenseService.save(input, confirmation: quote, container: reopened)
        #expect(result.alreadyRecorded)
        #expect(result.transactionID == transactionID)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func invalidPrecisionAndArchivedCategoryCannotBeSaved() throws {
        let (container, input, _) = try fixture()
        let fractional = RemoteExpenseInput(requestID: UUID(), bookID: input.bookID, contoID: input.contoID,
            categoryID: input.categoryID, amount: Decimal(string: "1.001")!, currency: "EUR", date: input.date, note: "")
        #expect(throws: RemoteExpenseService.Failure.invalidAmount) {
            try RemoteExpenseService.preview(fractional, container: container)
        }
        let quote = try RemoteExpenseService.preview(input, container: container)
        let category = try #require(container.mainContext.fetch(FetchDescriptor<FinanceCore.Category>()).first)
        category.isActive = false
        try container.mainContext.save()
        #expect(throws: RemoteExpenseService.Failure.invalidSelection) {
            try RemoteExpenseService.save(input, confirmation: quote, container: container)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

}
