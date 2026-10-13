import AppIntents
import Foundation
import FinanceCore

struct CaptureTransactionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Info transazione bancaria")
    static let defaultQuery = CaptureTransactionQuery()
    var id: UUID
    @Property(title: "Importo") var amount: Double?
    @Property(title: "Valuta") var currency: String?
    @Property(title: "Data") var date: Date?
    @Property(title: "Categoria") var category: String?
    @Property(title: "Beneficiario") var payee: String?
    @Property(title: "Testo originale") var originalText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(payee ?? String(originalText.prefix(80)))")
    }

    @MainActor init(capture: PendingCapture) {
        id = capture.id
        originalText = capture.originalText
        date = capture.notificationDate ?? capture.createdAt
        payee = CaptureTextParser.merchant(in: capture.originalText)
        category = nil
        let amounts = CaptureTextParser.money(in: capture.originalText)
        if amounts.count == 1, let money = amounts.first {
            amount = NSDecimalNumber(decimal: money.amount).doubleValue
            currency = money.currency.isEmpty ? nil : money.currency
        } else {
            amount = nil
            currency = nil
        }
    }
}

struct CaptureTransactionQuery: EntityQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [CaptureTransactionEntity] {
        let store = try CaptureStore.container()
        return try CaptureStore.captures(ids: identifiers, in: store).map { CaptureTransactionEntity(capture: $0) }
    }

    @MainActor func suggestedEntities() async throws -> [CaptureTransactionEntity] {
        let store = try CaptureStore.container()
        return try CaptureStore.pendingPage(in: store, limit: 20)
            .filter { $0.source == "notification" }
            .map { CaptureTransactionEntity(capture: $0) }
    }
}

struct CaptureShortcutDraft: Equatable, Sendable {
    let id: UUID
    let amount: String?
    let note: String?
    var type: TransactionType = .expense
}
