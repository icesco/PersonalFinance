import Foundation
import SwiftData
import Testing
import CoreGraphics
@testable import FinanceCore

@MainActor struct CaptureTests {
    @Test func futureCaptureIsPlannedWithAttachmentAndDoesNotChangeCurrentBalance() throws {
        let (store, conto, category) = try ledger()
        let now = Date()
        let future = now.addingTimeInterval(86_400 * 10)
        let input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, categoryID: category.id,
            amount: 25, currency: "EUR", date: future, paymentConfirmed: false,
            filename: "fattura.pdf", contentType: "com.adobe.pdf", document: pdf(), planned: true)
        let id = try CaptureApproval.approve(input, in: store, now: now)
        #expect(try CaptureApproval.approve(input, in: store, now: now) == id)
        let transaction = try #require(ModelContext(store).fetch(FetchDescriptor<Transaction>()).first)
        #expect(transaction.date == future)
        #expect(transaction.attachments?.count == 1)
        #expect(transaction.fromConto?.balance == 500)
        let events = FinanceCalendarEvents.build(transactions: [transaction], resolutions: [], contoIDs: [conto.id],
            interval: DateInterval(start: now, end: future.addingTimeInterval(1)), now: now)
        #expect(events.first?.kind == .planned)
        var invalid = input
        invalid.captureID = UUID(); invalid.date = now
        #expect(throws: CaptureApproval.Failure.invalidDate) { try CaptureApproval.approve(invalid, in: store, now: now) }
        invalid.date = future; invalid.paymentConfirmed = true
        #expect(throws: CaptureApproval.Failure.unconfirmedPayment) { try CaptureApproval.approve(invalid, in: store, now: now) }
    }
    @Test func paginationKeepsEqualDatesAndSurvivesRemovalAndNewArrivals() throws {
        let inbox = try CaptureStore.container(inMemory: true)
        let context = ModelContext(inbox)
        let base = Date(timeIntervalSince1970: 1_000)
        var expected = Set<UUID>()
        for index in 0..<71 {
            let capture = PendingCapture(source: "share", sourceName: "Test", text: "EUR 10")
            capture.createdAt = base.addingTimeInterval(Double(index / 10))
            expected.insert(capture.id)
            context.insert(capture)
        }
        try context.save()
        #expect(try CaptureStore.pendingCount(in: inbox) == 71)
        var loaded = try CaptureStore.pendingPage(in: inbox, limit: 7)
        #expect(loaded.count == 7)
        let removedID = try #require(loaded.first?.id)
        try CaptureStore.discard(id: removedID, in: inbox)
        let newer = PendingCapture(source: "notification", sourceName: "Nuova", text: "EUR 20")
        newer.createdAt = base.addingTimeInterval(100)
        try CaptureStore.enqueue(newer, in: inbox)
        while let last = loaded.last {
            let ids = loaded.filter { $0.createdAt == last.createdAt }.map(\.id)
            let next = try CaptureStore.pendingPage(in: inbox, before: last.createdAt, excludingBoundaryIDs: ids, limit: 7)
            if next.isEmpty { break }
            #expect(next.count <= 7)
            #expect(next.allSatisfy { $0.createdAt <= last.createdAt })
            loaded.append(contentsOf: next)
        }
        #expect(loaded.count == 71)
        #expect(Set(loaded.map(\.id)) == expected)
        #expect(try CaptureStore.pendingPage(in: inbox, limit: 7).first?.id == newer.id)
        #expect(try CaptureStore.pendingCount(in: inbox) == 71)
    }
    private func ledger() throws -> (ModelContainer, Conto, FinanceCore.Category) {
        let store = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Personale", currency: "EUR")
        let conto = Conto(name: "Banca", type: .checking, initialBalance: 500)
        let category = FinanceCore.Category(name: "Alimentari")
        conto.account = book; category.account = book
        book.conti = [conto]; book.categories = [category]
        store.mainContext.insert(book); try store.mainContext.save()
        return (store, conto, category)
    }
    private func pdf() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        return data as Data
    }
    @Test func intakeAndDiscardNeverChangeLedger() throws {
        let (ledger, conto, _) = try ledger()
        let inbox = try CaptureStore.container(inMemory: true)
        let proposal = PendingCapture(source: "notification", sourceName: "Banca", text: "Pagamento 24,90 EUR presso Esselunga")
        try CaptureStore.enqueue(proposal, in: inbox)
        #expect(try CaptureStore.pending(in: inbox).count == 1)
        #expect(conto.balance == 500)
        #expect(try ledger.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        try CaptureStore.discard(id: proposal.id, in: inbox)
        #expect(try CaptureStore.pending(in: inbox).isEmpty)
        #expect(conto.balance == 500)
    }
    @Test func intakeRetryKeepsOneProposalAndRejectsReusedIDs() throws {
        let inbox = try CaptureStore.container(inMemory: true)
        let id = UUID()
        try CaptureStore.enqueue(PendingCapture(id: id, source: "notification", sourceName: "Banca", text: "EUR 25"), in: inbox)
        try CaptureStore.enqueue(PendingCapture(id: id, source: "notification", sourceName: "Banca", text: "EUR 25"), in: inbox)
        #expect(try CaptureStore.pending(in: inbox).count == 1)
        #expect(throws: CaptureStore.Failure.reusedID) {
            try CaptureStore.enqueue(PendingCapture(id: id, source: "notification", sourceName: "Banca", text: "EUR 50"), in: inbox)
        }
        #expect(throws: CaptureStore.Failure.empty) {
            try CaptureStore.enqueue(PendingCapture(source: "share", sourceName: "Mail", text: "  "), in: inbox)
        }
        #expect(throws: CaptureStore.Failure.tooLarge) {
            try CaptureStore.enqueue(PendingCapture(source: "notification", sourceName: "Banca", text: String(repeating: "a", count: 30_001)), in: inbox)
        }
        #expect(try CaptureStore.pending(in: inbox).count == 1)
    }
    @Test func approvalIsAtomicAndRetrySafeEvenAfterDeletion() throws {
        let (store, conto, category) = try ledger()
        let input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, categoryID: category.id, amount: 25, currency: "EUR", paymentConfirmed: true,
            filename: "fattura.pdf", contentType: "com.adobe.pdf", document: pdf())
        let id = try CaptureApproval.approve(input, in: store)
        #expect(try CaptureApproval.approve(input, in: store) == id)
        let check = ModelContext(store)
        let transaction = try #require(check.fetch(FetchDescriptor<Transaction>()).first)
        #expect(transaction.amount == 25)
        #expect(transaction.fromContoId == conto.id)
        #expect(transaction.categoryId == category.id)
        #expect(transaction.attachments?.count == 1)
        #expect(transaction.fromConto?.balance == 475)
        check.delete(transaction); try check.save()
        #expect(try CaptureApproval.approve(input, in: store) == id)
        #expect(try check.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }
    @Test func unconfirmedInvoiceCurrencyAndWrongCategoryCannotChangeBalance() throws {
        let (store, conto, _) = try ledger()
        var input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, amount: 25, currency: "EUR", paymentConfirmed: false)
        #expect(throws: CaptureApproval.Failure.unconfirmedPayment) { try CaptureApproval.approve(input, in: store) }
        input.paymentConfirmed = true; input.currency = "USD"
        #expect(throws: CaptureApproval.Failure.currencyMismatch) { try CaptureApproval.approve(input, in: store) }
        input.currency = "EUR"; input.categoryID = UUID()
        #expect(throws: CaptureApproval.Failure.invalidSelection) { try CaptureApproval.approve(input, in: store) }
        #expect(conto.balance == 500)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }
    @Test func incomeUsesIncomingAccountAndFutureDatesAreRejected() throws {
        let (store, conto, _) = try ledger()
        var input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, amount: 50, currency: "EUR", type: .income, date: Date().addingTimeInterval(3600), paymentConfirmed: true)
        #expect(throws: CaptureApproval.Failure.invalidDate) { try CaptureApproval.approve(input, in: store) }
        input.date = Date().addingTimeInterval(-10)
        try CaptureApproval.approve(input, in: store)
        let item = try #require(ModelContext(store).fetch(FetchDescriptor<Transaction>()).first)
        #expect(item.toContoId == conto.id)
        #expect(item.fromContoId == nil)
        #expect(item.toConto?.balance == 550)
    }
    @Test func invalidDocumentDoesNotCreateMovementOrReceipt() throws {
        let (store, conto, _) = try ledger()
        let input = CaptureApprovalInput(captureID: UUID(), contoID: conto.id, amount: 20, currency: "EUR", paymentConfirmed: true,
            filename: "fattura.pdf", contentType: "com.adobe.pdf", document: Data("not a pdf".utf8))
        #expect(throws: CaptureApproval.Failure.invalidDocument) { try CaptureApproval.approve(input, in: store) }
        #expect(try store.mainContext.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<CaptureApprovalReceipt>()) == 0)
    }
    @Test func notificationParserDoesNotConfuseBalanceWithPayment() {
        #expect(CaptureTextParser.money(in: "Pagamento 24,90 EUR presso Esselunga") == [CaptureMoney(amount: Decimal(string: "24.90")!, currency: "EUR")])
        #expect(CaptureTextParser.money(in: "€ 1.234,56").first?.amount == Decimal(string: "1234.56"))
        #expect(CaptureTextParser.money(in: "USD 1,234.56").first?.amount == Decimal(string: "1234.56"))
        #expect(CaptureTextParser.money(in: "Pagamento EUR 25. Saldo EUR 500").count == 2)
        #expect(CaptureTextParser.decimal("1,2,3") == nil)
        #expect(CaptureTextParser.money(in: "$ 25").first?.currency == "")
        #expect(CaptureTextParser.money(in: "24,90 senza valuta").isEmpty)
        #expect(CaptureTextParser.money(in: "Pagamento 25 EUR").first?.amount == 25)
        #expect(CaptureTextParser.merchant(in: "Pagamento 24,90 EUR presso Esselunga") == "Esselunga")
    }
}
