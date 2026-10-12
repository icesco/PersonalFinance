import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FormiCLITransferTests {
    private func fixture() throws -> (ModelContainer, Conto, Conto, Conto, FinanceCore.Category) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let source = Conto(name: "Banca", type: .checking, initialBalance: 1000)
        let card = Conto(name: "AMEX", type: .checking)
        let savings = Conto(name: "PAC", type: .savings)
        let category = FinanceCore.Category(name: "Risparmi")
        book.conti = [source, card, savings]; book.categories = [category]
        for account in [source, card, savings] { account.account = book }
        category.account = book
        container.mainContext.insert(book); try container.mainContext.save()
        return (container, source, card, savings, category)
    }
    private func movement(_ source: Conto, _ destination: Conto, amount: String = "350.00") -> FormiCLIMovement {
        .init(requestID: UUID(), accountID: source.id, type: "transfer", amount: amount,
              currency: "EUR", date: "2026-09-18", description: "Versamento", toAccountID: destination.id)
    }
    private func request(_ inputs: [FormiCLIMovement], commit: Bool = false, allowDuplicates: Bool = false) -> FormiCLIRequest {
        var request = FormiCLIRequest(command: "import", movements: inputs, commit: commit, allowDuplicates: allowDuplicates)
        request.version = 4
        return request
    }

    @Test func oneTransferChangesBothBalancesAndNeverCountsAsIncomeOrExpense() throws {
        let (container, source, _, savings, category) = try fixture()
        var input = movement(source, savings); input.categoryID = category.id
        let preview = try FormiCLIService.execute(request([input]), container: container)
        #expect(!preview.saved && preview.movements[0].toAccountID == savings.id)
        #expect(preview.movements[0].accountID == source.id && preview.movements[0].toAccount == "PAC")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        let saved = try FormiCLIService.execute(request([input], commit: true), container: container)
        let retry = try FormiCLIService.execute(request([input], commit: true), container: container)
        #expect(retry.movements[0].alreadyRecorded)
        #expect(retry.movements[0].transactionID == saved.movements[0].transactionID)
        let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.type == .transfer)
        #expect(row.fromContoId == source.id && row.toContoId == savings.id && row.categoryId == category.id)
        let snapshot = TransactionSnapshot(from: row)
        #expect(BalanceCalculator.netChange(for: snapshot, contiIDs: [source.id]) == -350)
        #expect(BalanceCalculator.netChange(for: snapshot, contiIDs: [savings.id]) == 350)
        #expect(BalanceCalculator.netChange(for: snapshot, contiIDs: [source.id, savings.id]) == 0)
        let report = RecordedFlowReport.calculate(transactions: [.init(date: row.date, amount: 350, type: row.type,
            categoryID: category.id, categoryName: "Risparmi", isRecurring: false)], categories: [],
            interval: .init(start: row.date.addingTimeInterval(-1), end: row.date.addingTimeInterval(1)), now: row.date)
        #expect(report.income == 0 && report.expenses == 0)
    }

    @Test func duplicateDetectionUsesBothSidesAndIgnoresDescriptionAndLegacyIDs() throws {
        let (container, source, card, savings, _) = try fixture()
        let original = movement(source, card, amount: "100")
        _ = try FormiCLIService.execute(request([original], commit: true), container: container)
        let stored = try #require(container.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        stored.fromContoId = nil; stored.toContoId = nil; try container.mainContext.save()
        var duplicate = original; duplicate.requestID = UUID(); duplicate.description = "Descrizione diversa"
        let preview = try FormiCLIService.execute(request([duplicate]), container: container)
        #expect(preview.movements[0].possibleDuplicate)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(request([duplicate], commit: true), container: container)
        }
        var differentDestination = duplicate; differentDestination.requestID = UUID(); differentDestination.toAccountID = savings.id
        var reverse = duplicate; reverse.requestID = UUID(); reverse.accountID = card.id; reverse.toAccountID = source.id
        let accepted = try FormiCLIService.execute(request([differentDestination, reverse], commit: true), container: container)
        #expect(accepted.movements.allSatisfy { !$0.possibleDuplicate })
        _ = try FormiCLIService.execute(request([duplicate], commit: true, allowDuplicates: true), container: container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 4)
    }

    @Test func duplicateInBatchBlocksEveryWriteAndReceipt() throws {
        let (container, source, card, _, _) = try fixture()
        let first = movement(source, card); var second = first
        second.requestID = UUID(); second.description = "Altro estratto"
        let preview = try FormiCLIService.execute(request([first, second]), container: container)
        #expect(preview.movements[1].possibleDuplicate)
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIService.execute(request([first, second], commit: true), container: container)
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
    }

    @Test func malformedLastRowAndOldProtocolsCannotWriteMixedBatches() throws {
        let (container, source, card, _, _) = try fixture()
        let first = FormiCLIMovement(requestID: UUID(), accountID: source.id, amount: "5", currency: "EUR", date: "2026-09-18")
        let transfer = movement(source, card)
        var missing = transfer; missing.toAccountID = nil
        var same = transfer; same.toAccountID = source.id
        var nonexistent = transfer; nonexistent.toAccountID = UUID()
        var recurring = transfer; recurring.recurrence = .init(frequency: "monthly")
        var wrongType = transfer; wrongType.type = "income"
        var invalidAmount = transfer; invalidAmount.amount = "2.001"
        var invalidDate = transfer; invalidDate.date = "2026-02-30"
        for invalid in [missing, same, nonexistent, recurring, wrongType, invalidAmount, invalidDate] {
            #expect(throws: FormiCLIService.Failure.self) {
                try FormiCLIService.execute(request([first, invalid], commit: true), container: container)
            }
        }
        for version in [1, 2, 3] {
            var old = request([first, transfer], commit: true); old.version = version
            #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(old, container: container) }
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RemoteExpenseReceipt>()) == 0)
        var income = first; income.requestID = UUID(); income.type = "income"
        let result = try FormiCLIService.execute(request([first, transfer, income], commit: true), container: container)
        #expect(result.movements.count == 3)
    }

    @Test func bothBooksMustBePersonalActiveAndUseTheDeclaredCurrency() throws {
        let (container, source, card, _, category) = try fixture()
        let input = movement(source, card)
        let otherBook = Account(name: "Altro", currency: "EUR")
        card.account = otherBook; otherBook.conti = [card]
        container.mainContext.insert(otherBook); try container.mainContext.save()
        #expect(!(try FormiCLIService.execute(request([input]), container: container).movements[0].possibleDuplicate))
        otherBook.currency = "USD"; try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([input], commit: true), container: container) }
        otherBook.currency = "EUR"; otherBook.isActive = false; try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([input], commit: true), container: container) }
        otherBook.isActive = true; card.isActive = false; try container.mainContext.save()
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([input], commit: true), container: container) }
        card.isActive = true
        category.account = otherBook; try container.mainContext.save()
        var wrongCategory = input; wrongCategory.categoryID = category.id
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([wrongCategory], commit: true), container: container) }
        for bookID in [otherBook.id, try #require(source.account?.id)] {
            let membership = SharedBookMembership(scopeKey: "test", ownerName: "owner", remoteBookID: UUID(), localBookID: bookID)
            container.mainContext.insert(membership); try container.mainContext.save()
            #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([input], commit: true), container: container) }
            container.mainContext.delete(membership); try container.mainContext.save()
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        _ = try FormiCLIService.execute(request([input], commit: true), container: container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func sixPendingStatementTransfersSaveOnceWithZeroCombinedNetChange() throws {
        let (container, source, card, savings, _) = try fixture()
        let revolut = Conto(name: "Revolut", type: .checking)
        let book = try #require(source.account)
        revolut.account = book; book.conti?.append(revolut)
        container.mainContext.insert(revolut); try container.mainContext.save()
        let values: [(String, String, Conto)] = [
            ("2026-09-02", "103.98", card), ("2026-09-02", "691.22", card),
            ("2026-09-04", "10.00", revolut), ("2026-09-18", "350.00", savings),
            ("2026-10-05", "180.58", card), ("2026-10-05", "826.82", card)
        ]
        let inputs = values.map { date, amount, destination in
            var input = movement(source, destination, amount: amount); input.date = date; return input
        }
        let saved = try FormiCLIService.execute(request(inputs, commit: true), container: container)
        let retried = try FormiCLIService.execute(request(inputs, commit: true), container: container)
        #expect(saved.movements.count == 6 && retried.movements.allSatisfy(\.alreadyRecorded))
        let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 6 && rows.allSatisfy { $0.type == .transfer })
        let snapshots = rows.map { TransactionSnapshot(from: $0) }
        #expect(snapshots.reduce(Decimal.zero) { $0 + BalanceCalculator.netChange(for: $1, contiIDs: [source.id]) } == -Decimal(string: "2162.60")!)
        #expect(snapshots.reduce(Decimal.zero) { $0 + BalanceCalculator.netChange(for: $1, contiIDs: [source.id, card.id, savings.id, revolut.id]) } == 0)
    }

    @Test func receiptPreservesDestinationAndRetryCannotRecreateDeletedTransfer() throws {
        let (container, source, card, savings, _) = try fixture()
        let input = movement(source, card)
        _ = try FormiCLIService.execute(request([input], commit: true), container: container)
        var changed = input; changed.toAccountID = savings.id
        #expect(throws: FormiCLIService.Failure.self) { try FormiCLIService.execute(request([changed], commit: true), container: container) }
        let row = try #require(container.mainContext.fetch(FetchDescriptor<Transaction>()).first)
        container.mainContext.delete(row); try container.mainContext.save()
        let retry = try FormiCLIService.execute(request([input], commit: true), container: container)
        #expect(retry.movements[0].alreadyRecorded)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }
}

struct FormiCLITransferArgumentTests {
    @Test func transferArgumentsAndJSONNegotiateProtocolFour() throws {
        let source = UUID(), destination = UUID()
        let args = ["add", "--type", "transfer", "--account", source.uuidString, "--to-account", destination.uuidString,
                    "--amount", "10.00", "--currency", "EUR", "--date", "2026-09-04"]
        let parsed = try FormiCLIArguments.parse(args, read: { _ in Data() }, today: "2026-10-12")
        #expect(parsed.version == 4 && !parsed.commit && parsed.movements[0].toAccountID == destination)
        let data = try FormiCLIWire.encoder().encode(parsed.movements)
        let imported = try FormiCLIArguments.parse(["import", "-"], read: { _ in data }, today: "2026-10-12")
        #expect(imported.version == 4 && imported.movements == parsed.movements)
        let old = try FormiCLIArguments.parse(["add", "--account", source.uuidString, "--amount", "10", "--currency", "EUR"], read: { _ in Data() }, today: "2026-10-12")
        #expect(old.version == 1)
        let json = String(decoding: try FormiCLIWire.encoder().encode(old.movements[0]), as: UTF8.self)
        #expect(!json.contains("toAccountID"))
    }

    @Test func invalidDestinationsAndRecurringTransfersAreRejectedBeforeDelivery() {
        let source = UUID(); let base = ["add", "--account", source.uuidString, "--amount", "10", "--currency", "EUR"]
        for args in [["--type", "transfer"], ["--type", "transfer", "--to-account", source.uuidString],
                     ["--type", "transfer", "--to-account", "bad"], ["--to-account", UUID().uuidString],
                     ["--type", "transfer", "--to-account", UUID().uuidString, "--recurrence", "monthly"]] {
            #expect(throws: FormiCLIArguments.Failure.self) {
                try FormiCLIArguments.parse(base + args, read: { _ in Data() }, today: "2026-10-12")
            }
        }
    }
}
