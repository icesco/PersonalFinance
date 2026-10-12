import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FormiCLITransactionTests {
    private func fixture() throws -> (ModelContainer, Account, Conto, Conto, Calendar) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let source = Conto(name: "Banca", type: .checking)
        let destination = Conto(name: "Carta", type: .checking)
        source.account = book; destination.account = book; book.conti = [source, destination]
        container.mainContext.insert(book)
        try container.mainContext.save()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        return (container, book, source, destination, calendar)
    }

    private func request(_ query: FormiCLITransactionQuery = .init(), bookID: UUID? = nil) -> FormiCLIRequest {
        var request = FormiCLIRequest(command: "transactions", bookID: bookID)
        request.version = 3; request.transactionQuery = query
        return request
    }

    @Test func finalDSTDayIncludesLateTransactionsAndReadNeverWrites() throws {
        let (container, book, source, destination, calendar) = try fixture()
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(nextDay.timeIntervalSince(start) == 25 * 3600)
        let transfer = Transaction.createTransfer(amount: 12.34, fromConto: source, toConto: destination,
                                                   date: nextDay.addingTimeInterval(-1), notes: "Bonifico")
        container.mainContext.insert(transfer)
        let later = Transaction(amount: 5, type: .expense, date: nextDay)
        later.setFromConto(source); container.mainContext.insert(later)
        source.isActive = false
        try container.mainContext.save()
        let result = try FormiCLITransactionService.read(request(.init(accountID: source.id,
            from: "2026-10-25", to: "2026-10-25"), bookID: book.id), container: container, calendar: calendar, now: nextDay)
        #expect(result.total == 1)
        let row = try #require(result.transactions.first)
        #expect(row.transactionID == transfer.id)
        #expect(row.date == "2026-10-25")
        #expect(row.type == "transfer")
        #expect(row.amount == "12.34")
        #expect(row.fromAccountID == source.id && row.toAccountID == destination.id)
        #expect(row.notes == "Bonifico")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func paginationIsStableForSameDatesAndRejectsChangedHistory() throws {
        let (container, _, source, _, calendar) = try fixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<3 {
            let row = Transaction(amount: 2, type: .expense, date: now)
            row.setFromConto(source); container.mainContext.insert(row)
        }
        try container.mainContext.save()
        let first = try FormiCLITransactionService.read(request(.init(limit: 2)), container: container, calendar: calendar, now: now)
        #expect(first.total == 3 && first.nextOffset == 2)
        let second = try FormiCLITransactionService.read(request(.init(limit: 2, offset: 2, revision: first.revision)),
            container: container, calendar: calendar, now: now)
        #expect(second.transactions.count == 1 && second.nextOffset == nil)
        #expect(Set((first.transactions + second.transactions).map(\.transactionID)).count == 3)
        let row = try #require(container.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        row.notes = "Modificata"; try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLITransactionService.read(request(.init(offset: 2, revision: first.revision)),
                container: container, calendar: calendar, now: now)
        }
    }

    @Test func plannedRowsAreExplicitAndRecurrencesAreNotExpanded() throws {
        let (container, _, source, _, calendar) = try fixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let seed = Transaction(amount: 10, type: .expense, date: now.addingTimeInterval(-86400 * 90),
                               isRecurring: true, recurrenceFrequency: .monthly)
        seed.setFromConto(source); container.mainContext.insert(seed)
        let future = Transaction(amount: 4, type: .income, date: now.addingTimeInterval(1))
        future.setToConto(source); container.mainContext.insert(future)
        try container.mainContext.save()
        let recorded = try FormiCLITransactionService.read(request(), container: container, calendar: calendar, now: now)
        #expect(recorded.total == 1)
        #expect(recorded.transactions[0].recurrence?.frequency == "monthly")
        let all = try FormiCLITransactionService.read(request(.init(includePlanned: true)), container: container, calendar: calendar, now: now)
        #expect(all.total == 2)
        #expect(all.transactions.last?.planned == true)
    }

    @Test func invalidSelectionsDatesAndWireMutationsFail() throws {
        let (container, _, source, _, calendar) = try fixture()
        for query in [FormiCLITransactionQuery(from: "2026-02-30"), .init(from: "2026-10-02", to: "2026-10-01"),
                      .init(limit: 501), .init(offset: -1), .init(accountID: UUID()), .init(offset: Int.max)] {
            #expect(throws: FormiCLIService.Failure.self) {
                try FormiCLITransactionService.read(request(query), container: container, calendar: calendar)
            }
        }
        let otherBook = Account(name: "Altro", currency: "USD")
        container.mainContext.insert(otherBook); try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLITransactionService.read(request(.init(accountID: source.id), bookID: otherBook.id), container: container)
        }
        var invalid = request(); invalid.commit = true
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLITransactionService.read(invalid, container: container) }
        invalid = request(); invalid.version = 2
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLITransactionService.read(invalid, container: container) }
        let empty = try FormiCLITransactionService.read(request(), container: container)
        #expect(empty.total == 0 && empty.transactions.isEmpty && empty.nextOffset == nil)
    }
}

struct FormiCLITransactionArgumentTests {
    @Test func filtersRoundTripAndOldCommandsKeepTheirProtocol() throws {
        let id = UUID()
        let parsed = try FormiCLIArguments.parse(["transactions", "--account", id.uuidString, "--from", "2026-09-01",
            "--to", "2026-10-12", "--limit", "500", "--offset", "200", "--revision", "token", "--include-planned"],
            read: { _ in Issue.record("Read commands must not read files"); return Data() }, today: "2026-10-12")
        let decoded = try FormiCLIWire.decoder().decode(FormiCLIRequest.self, from: FormiCLIWire.encoder().encode(parsed))
        #expect(decoded.version == 3 && !decoded.commit)
        #expect(decoded.transactionQuery?.accountID == id)
        #expect(decoded.transactionQuery?.limit == 500 && decoded.transactionQuery?.offset == 200)
        #expect(decoded.transactionQuery?.includePlanned == true && decoded.transactionQuery?.revision == "token")
        #expect(try FormiCLIArguments.parse(["accounts"], read: { _ in Data() }, today: "2026-10-12").version == 1)
    }

    @Test func invalidFlagsAndPaginationCannotBeSilentlyIgnored() {
        for args in [["--yes"], ["--allow-duplicates"], ["--limit", "0"], ["--limit", "501"],
                     ["--offset", "-1"], ["--offset", "wat"], ["--account", "wat"], ["--from"],
                     ["--limit", "2", "--limit", "3"], ["--include-planned", "--include-planned"]] {
            #expect(throws: FormiCLIArguments.Failure.self) {
                try FormiCLIArguments.parse(["transactions"] + args, read: { _ in Data() }, today: "2026-10-12")
            }
        }
    }
}
