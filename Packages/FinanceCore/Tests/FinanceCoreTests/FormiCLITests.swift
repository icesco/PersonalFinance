import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FormiCLIServiceTests {
    private func fixture(url: URL? = nil) throws -> (ModelContainer, FormiCLIMovement) {
        let container: ModelContainer
        if let url {
            container = try ModelContainer(for: FinanceCoreModule.createSchema(), configurations: [
                ModelConfiguration(schema: FinanceCoreModule.createSchema(), url: url, cloudKitDatabase: .none)
            ])
        } else {
            container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }
        let book = Account(name: "Personale", currency: "EUR")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let category = FinanceCore.Category(name: "Cibo", kind: .expense)
        conto.account = book; category.account = book
        book.conti = [conto]; book.categories = [category]
        container.mainContext.insert(book)
        try container.mainContext.save()
        return (container, FormiCLIMovement(requestID: UUID(), accountID: conto.id,
            categoryID: category.id, amount: "25.50", currency: "EUR", date: "2026-10-08", description: "Spesa"))
    }
    private func count(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Transaction>())
    }

    @Test func previewDoesNotWriteAndSaveRetryIsIdempotent() throws {
        let (container, input) = try fixture()
        let preview = try FormiCLIService.execute(.init(command: "add", movements: [input]), container: container)
        #expect(!preview.saved)
        #expect(preview.movements.first?.transactionID == nil)
        #expect(try count(container) == 0)
        let request = FormiCLIRequest(command: "add", movements: [input], commit: true)
        let first = try FormiCLIService.execute(request, container: container)
        let retry = try FormiCLIService.execute(request, container: container)
        #expect(retry.movements.first?.alreadyRecorded == true)
        #expect(first.movements.first?.transactionID == retry.movements.first?.transactionID)
        #expect(try count(container) == 1)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<Transaction>()).first)
        #expect(row.fromContoId == input.accountID)
        #expect(row.categoryId == input.categoryID)
    }

    @Test func invalidLastRowDoesNotSaveAnyOfTheBatch() throws {
        let (container, input) = try fixture()
        var invalid = input; invalid.requestID = UUID(); invalid.amount = "-5"
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "import", movements: [input, invalid], commit: true), container: container)
        }
        #expect(try count(container) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
    }

    @Test func incomeAndExpensesSaveTogetherAndRetriesDoNotRecreateDeletedRows() throws {
        let (container, input) = try fixture()
        var income = input; income.requestID = UUID(); income.type = "income"
        income.categoryID = nil; income.amount = "100"; income.description = "Stipendio"
        let request = FormiCLIRequest(command: "import", movements: [input, income], commit: true)
        _ = try FormiCLIService.execute(request, container: container)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 2)
        #expect(rows.first(where: { $0.type == .income })?.toContoId == input.accountID)
        for row in rows { context.delete(row) }
        try context.save()
        let retry = try FormiCLIService.execute(request, container: container)
        #expect(retry.movements.allSatisfy { $0.alreadyRecorded })
        #expect(try count(container) == 0)
    }

    @Test func reusedIDWithChangedPayloadFails() throws {
        let (container, input) = try fixture()
        _ = try FormiCLIService.execute(.init(command: "add", movements: [input], commit: true), container: container)
        var changed = input; changed.amount = "26"
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "add", movements: [changed], commit: true), container: container)
        }
        #expect(try count(container) == 1)
    }

    @Test func duplicateInBatchAndExistingStoreRequiresExplicitOverride() throws {
        let (container, input) = try fixture()
        var duplicate = input; duplicate.requestID = UUID()
        let preview = try FormiCLIService.execute(.init(command: "import", movements: [input, duplicate]), container: container)
        #expect(preview.movements[1].possibleDuplicate)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "import", movements: [input, duplicate], commit: true), container: container)
        }
        #expect(try count(container) == 0)
        _ = try FormiCLIService.execute(.init(command: "add", movements: [input], commit: true), container: container)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "add", movements: [duplicate], commit: true), container: container)
        }
        _ = try FormiCLIService.execute(.init(command: "add", movements: [duplicate], commit: true, allowDuplicates: true), container: container)
        #expect(try count(container) == 2)
    }

    @Test func wrongCurrencyCategoryPrecisionAndDateCannotWrite() throws {
        let (container, input) = try fixture()
        var wrongCurrency = input; wrongCurrency.currency = "USD"
        var precision = input; precision.amount = "1.001"
        var date = input; date.date = "2026-02-30"
        var category = input; category.type = "income"
        var archived = input; archived.accountID = UUID()
        var transfer = input; transfer.type = "transfer"
        for invalid in [wrongCurrency, precision, date, category, archived, transfer] {
            #expect(throws: FormiCLIService.Failure.self) {
                try FormiCLIService.execute(.init(command: "add", movements: [invalid], commit: true), container: container)
            }
        }
        #expect(try count(container) == 0)
    }

    @Test func receiptSurvivesReopeningTheStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("CLI.sqlite")
        let (input, transactionID) = try autoreleasepool {
            let (container, input) = try fixture(url: url)
            let result = try FormiCLIService.execute(.init(command: "add", movements: [input], commit: true), container: container)
            return (input, result.movements[0].transactionID)
        }
        let reopened = try ModelContainer(for: FinanceCoreModule.createSchema(), configurations: [
            ModelConfiguration(schema: FinanceCoreModule.createSchema(), url: url, cloudKitDatabase: .none)
        ])
        let retry = try FormiCLIService.execute(.init(command: "add", movements: [input], commit: true), container: reopened)
        #expect(retry.movements[0].alreadyRecorded)
        #expect(retry.movements[0].transactionID == transactionID)
        #expect(try count(reopened) == 1)
    }

    @Test func sharedBooksCannotBeWritten() throws {
        let (container, input) = try fixture()
        let book = try #require(container.mainContext.fetch(FetchDescriptor<Account>()).first)
        container.mainContext.insert(SharedBookMembership(scopeKey: "test", ownerName: "owner",
            remoteBookID: UUID(), localBookID: book.id))
        try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "add", movements: [input], commit: true), container: container)
        }
        #expect(try count(container) == 0)
    }
}

struct FormiCLIArgumentTests {
    @Test func singleExpenseDefaultsToPreviewAndRequiresYesForWrites() throws {
        let args = ["add", "--account", UUID().uuidString, "--amount", "25.50", "--currency", "EUR"]
        let preview = try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-08")
        #expect(!preview.commit)
        #expect(preview.movements.count == 1)
        #expect(preview.movements[0].type == "expense")
        #expect(preview.movements[0].date == "2026-10-08")
        let commit = try FormiCLIArguments.parse(args + ["--yes"], read: { _ in Data() }, today: "2026-10-08")
        #expect(commit.commit)
    }
    @Test func typosAndRepeatedFlagsCannotSilentlyChangeCommandMeaning() throws {
        for args in [["accounts", "--yes"], ["preview", "file.json", "--yes"],
                     ["accounts", "--unknown"], ["import", "file.json", "--yes", "--yes"]] {
            #expect(throws: FormiCLIArguments.Failure.self) {
                try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-08")
            }
        }
    }
    @Test func JSONAcceptsSingleObjectOrArrayFromStdinWithStableIDs() throws {
        let input = FormiCLIMovement(requestID: UUID(), accountID: UUID(), amount: "25.50", currency: "EUR", date: "2026-10-08")
        for data in [try FormiCLIWire.encoder().encode(input), try FormiCLIWire.encoder().encode([input])] {
            let request = try FormiCLIArguments.parse(["import", "-", "--yes"], read: { _ in data }, today: "2026-10-08")
            #expect(request.movements == [input])
            #expect(request.commit)
        }
    }
}
