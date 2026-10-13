import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct FormiCLIAccountSplitTests {
    private func fixture() throws -> (ModelContainer, FormiCLIRequest, UUID, UUID) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let card = Conto(name: "AMEX", type: .credit)
        let bank = Conto(name: "Banca", type: .checking)
        card.account = book; bank.account = book; book.conti = [card, bank]
        container.mainContext.insert(book); try container.mainContext.save()
        var input = FormiCLIRequest(command: "import", movements: [
            .init(requestID: UUID(), accountID: card.id, amount: "25", currency: "EUR", date: "2026-09-03"),
            .init(requestID: UUID(), accountID: bank.id, type: "transfer", amount: "50", currency: "EUR", date: "2026-09-05", toAccountID: card.id)
        ], commit: true)
        input.version = 4
        _ = try FormiCLIService.execute(input, container: container)
        let ids = try ModelContext(container).fetch(FetchDescriptor<Transaction>()).map(\.id)
        var request = try FormiCLIArguments.parse(["account-split", "-"], read: { _ in
            try JSONSerialization.data(withJSONObject: ["sourceAccountID": card.id.uuidString,
                "destinationAccountID": UUID().uuidString, "sourceName": "Blu", "destinationName": "Altra carta",
                "transactionIDs": ids.map(\.uuidString)])
        }, today: "2026-10-12")
        request.commit = false
        return (container, request, card.id, bank.id)
    }

    @Test func previewCommitAndRetryPreserveRowsAndBothTransferSides() throws {
        let (container, original, sourceID, bankID) = try fixture()
        var request = original
        let before = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        let snapshot = Dictionary(uniqueKeysWithValues: before.map { ($0.id, ($0.amount, $0.date, $0.externalID)) })
        let preview = try FormiCLIAccountSplitService.execute(request, container: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conto>()) == 2)
        request.commit = true; request.accountSplit?.revision = preview["revision"] as? String
        _ = try FormiCLIAccountSplitService.execute(request, container: container)
        let rows = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 2)
        for row in rows {
            let old = try #require(snapshot[row.id])
            #expect(row.amount == old.0 && row.date == old.1 && row.externalID == old.2)
            #expect(row.fromContoId != sourceID && row.toContoId != sourceID)
            if row.type == .transfer { #expect(row.fromContoId == bankID) }
        }
        let retry = try FormiCLIAccountSplitService.execute(request, container: container)
        #expect(retry["alreadyRecorded"] as? Bool == true)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conto>()) == 3)
    }

    @Test func stalePreviewCannotCreateAccountOrMoveAnyRows() throws {
        let (container, original, _, _) = try fixture()
        var request = original
        let preview = try FormiCLIAccountSplitService.execute(request, container: container)
        let context = ModelContext(container)
        let row = try #require(context.fetch(FetchDescriptor<Transaction>()).first)
        row.amount = 99; try context.save()
        request.commit = true; request.accountSplit?.revision = preview["revision"] as? String
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIAccountSplitService.execute(request, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conto>()) == 2)
    }

    @Test func missingRowRejectsEntirePlan() throws {
        let (container, original, _, _) = try fixture()
        var request = original
        request.accountSplit?.transactionIDs.append(UUID())
        #expect(throws: FormiCLIService.Failure.self) {
            try FormiCLIAccountSplitService.execute(request, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conto>()) == 2)
    }
}
