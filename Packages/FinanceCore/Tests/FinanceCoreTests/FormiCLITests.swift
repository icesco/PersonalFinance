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

@MainActor
struct FormiCLIRecurrenceTests {
    private func fixture() throws -> (ModelContainer, FormiCLIMovement, Calendar) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let account = Conto(name: "Banca", type: .checking, initialBalance: 100)
        account.account = book; book.conti = [account]
        container.mainContext.insert(book)
        try container.mainContext.save()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        return (container, .init(requestID: UUID(), accountID: account.id, amount: "75.72", currency: "EUR",
            date: "2026-10-15", description: "Prestito", recurrence: .init(frequency: "monthly", endDate: "2032-07-15")), calendar)
    }
    private func request(_ movements: [FormiCLIMovement], commit: Bool = false) -> FormiCLIRequest {
        var request = FormiCLIRequest(command: "import", movements: movements, commit: commit)
        request.version = 2
        return request
    }

    @Test func previewSaveRetryAndReadPreserveTheFinalOccurrence() throws {
        let (container, movement, calendar) = try fixture()
        let preview = try FormiCLIService.execute(request([movement]), container: container, calendar: calendar)
        #expect(preview.movements[0].recurrence == movement.recurrence)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        let saved = try FormiCLIService.execute(request([movement], commit: true), container: container, calendar: calendar)
        let retry = try FormiCLIService.execute(request([movement], commit: true), container: container, calendar: calendar)
        #expect(retry.movements[0].alreadyRecorded)
        #expect(saved.movements[0].transactionID == retry.movements[0].transactionID)
        let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        let transaction = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(transaction.isRecurring == true)
        #expect(transaction.recurrenceFrequency == .monthly)
        let end = try #require(transaction.recurrenceEndDate)
        #expect(calendar.component(.hour, from: end) == 23)
        let finalDay = try #require(calendar.date(from: DateComponents(year: 2032, month: 7, day: 15)))
        #expect(RecurrenceSchedule.dates(anchor: transaction.date, frequency: .monthly, after: transaction.date,
            through: end, ending: end, calendar: calendar).contains(finalDay))
        var read = FormiCLIRequest(command: "recurrences"); read.version = 2
        let listing = try FormiCLIService.recurrences(read, container: container, calendar: calendar,
            now: transaction.date.addingTimeInterval(-1))
        #expect(listing.count == 1)
        #expect(listing[0].recurrence == movement.recurrence)
        #expect(listing[0].nextDate == movement.date)
        #expect(listing[0].accountID == movement.accountID)
    }

    @Test func invalidRecurrenceRollsBackTheEntireBatchAndOldProtocolCannotWrite() throws {
        let (container, movement, calendar) = try fixture()
        for recurrence in [FormiCLIRecurrence(frequency: "month"), .init(frequency: "monthly", endDate: "2026-10-14"),
                           .init(frequency: "monthly", endDate: "2026-02-30")] {
            var invalid = movement; invalid.requestID = UUID(); invalid.recurrence = recurrence
            #expect(throws: FormiCLIService.Failure.self) {
                try FormiCLIService.execute(request([movement, invalid], commit: true), container: container, calendar: calendar)
            }
        }
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(.init(command: "add", movements: [movement], commit: true), container: container)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
    }

    @Test func existingScheduleBlocksMigrationWithDifferentAnchorDescriptionAndCategory() throws {
        let (container, movement, calendar) = try fixture()
        var original = movement; original.date = "2026-09-15"; original.description = "Vecchia nota"
        _ = try FormiCLIService.execute(request([original], commit: true), container: container, calendar: calendar)
        var migration = movement; migration.requestID = UUID()
        let preview = try FormiCLIService.execute(request([migration]), container: container, calendar: calendar)
        #expect(preview.movements[0].possibleDuplicate)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(request([migration], commit: true), container: container, calendar: calendar)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
        var changed = original; changed.recurrence?.endDate = "2031-07-15"
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(request([changed], commit: true), container: container, calendar: calendar)
        }
    }

    @Test func batchDuplicateAndEndedSeriesAreDistinguished() throws {
        let (container, movement, calendar) = try fixture()
        var duplicate = movement; duplicate.requestID = UUID(); duplicate.date = "2026-11-15"; duplicate.description = "Altro nome"
        let preview = try FormiCLIService.execute(request([movement, duplicate]), container: container, calendar: calendar)
        #expect(preview.movements[1].possibleDuplicate)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(request([movement, duplicate], commit: true), container: container, calendar: calendar)
        }
        var ended = movement; ended.date = "2026-09-15"; ended.recurrence?.endDate = "2026-09-15"
        _ = try FormiCLIService.execute(request([ended], commit: true), container: container, calendar: calendar)
        var fresh = movement; fresh.requestID = UUID()
        let result = try FormiCLIService.execute(request([fresh], commit: true), container: container, calendar: calendar)
        #expect(!result.movements[0].possibleDuplicate)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    @Test func recurrenceJSONRejectsMisspelledEndAndAllCadencesSave() throws {
        let invalid = Data(#"{"frequency":"monthly","enddate":"2027-10-15"}"#.utf8)
        #expect(throws: DecodingError.self) { try FormiCLIWire.decoder().decode(FormiCLIRecurrence.self, from: invalid) }
        for frequency in RecurrenceFrequency.allCases {
            let (container, input, calendar) = try fixture()
            var movement = input
            movement.recurrence = .init(frequency: frequency.rawValue)
            _ = try FormiCLIService.execute(request([movement], commit: true), container: container, calendar: calendar)
            let transaction = try #require(ModelContext(container).fetch(FetchDescriptor<Transaction>()).first)
            #expect(transaction.recurrenceFrequency == frequency)
            #expect(transaction.recurrenceEndDate == nil)
        }
    }

    @Test func parserNegotiatesProtocolAndOldPayloadEncodingStaysCompatible() throws {
        let id = UUID().uuidString
        let args = ["add", "--account", id, "--amount", "10", "--currency", "EUR", "--recurrence", "yearly"]
        let recurring = try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-11")
        #expect(recurring.version == 2)
        #expect(recurring.movements[0].recurrence?.frequency == "yearly")
        let reading = try FormiCLIArguments.parse(["recurrences"], read: { _ in Data() }, today: "2026-10-11")
        #expect(reading.version == 2 && !reading.commit)
        #expect(throws: FormiCLIArguments.Failure.self) {
            try FormiCLIArguments.parse(["add", "--account", id, "--amount", "10", "--currency", "EUR",
                "--recurrence-end", "2027-10-11"], read: { _ in Data() }, today: "2026-10-11")
        }
        let legacy = try FormiCLIArguments.parse(Array(args.dropLast(2)), read: { _ in Data() }, today: "2026-10-11")
        #expect(legacy.version == 1)
        let json = try #require(JSONSerialization.jsonObject(with: FormiCLIWire.encoder().encode(legacy.movements[0])) as? [String: Any])
        #expect(json["recurrence"] == nil)
        let data = try FormiCLIWire.encoder().encode(recurring.movements)
        let imported = try FormiCLIArguments.parse(["preview", "-"], read: { _ in data }, today: "2026-10-11")
        #expect(imported.version == 2 && imported.movements == recurring.movements)
    }
}
