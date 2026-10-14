import Testing
import Foundation
import FinanceCore
@testable import Personal_Finance

@MainActor
struct FinanceShortcutTests {
    @Test func bankPreparationsStayInTheInboxWithoutOpeningAnEditor() throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "notification", sourceName: "Banca", text: "EUR 25")
        try CaptureStore.enqueue(capture, in: store)
        let expense = PrepareExpenseIntent()
        expense.transaction = CaptureTransactionEntity(capture: capture)
        expense.amount = "24.90"
        expense.note = "Spesa corretta"
        let state = AppStateManager(persistsSelection: false)
        #expect(!expense.openForReview)
        #expect(try expense.storeForBackgroundReview(expense.makeRequest(in: store), in: store))
        let storedExpense = try #require(CaptureStore.captures(ids: [capture.id], in: store).first)
        #expect(storedExpense.reviewType == .expense)
        #expect(storedExpense.proposedAmount == "24,90")
        #expect(storedExpense.proposedNote == "Spesa corretta")
        let income = PrepareIncomeIntent()
        income.transaction = expense.transaction
        #expect(!income.openForReview)
        let request = try income.makeRequest(in: store)
        #expect(try income.storeForBackgroundReview(request, in: store))
        #expect(try income.storeForBackgroundReview(request, in: store))
        let storedIncome = try #require(CaptureStore.captures(ids: [capture.id], in: store).first)
        #expect(storedIncome.reviewType == .income)
        #expect(storedIncome.proposedAmount == nil)
        #expect(storedIncome.proposedNote == nil)
        #expect(try CaptureStore.pendingCount(in: store) == 1)
        #expect(!state.showingQuickTransaction)
        #expect(FinanceShortcutInbox.shared.pending == nil)
        try CaptureStore.discard(id: capture.id, in: store)
        #expect(throws: FinanceShortcutError.self) { try income.storeForBackgroundReview(request, in: store) }
    }

    @Test func explicitReviewAndManualPreparationsUseTheForeground() throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "notification", sourceName: "Banca", text: "EUR 25")
        try CaptureStore.enqueue(capture, in: store)
        let expense = PrepareExpenseIntent()
        let income = PrepareIncomeIntent()
        #expect(try !expense.storeForBackgroundReview(expense.makeRequest(), in: store))
        #expect(try !income.storeForBackgroundReview(income.makeRequest(), in: store))
        expense.transaction = CaptureTransactionEntity(capture: capture)
        income.transaction = expense.transaction
        expense.openForReview = true
        income.openForReview = true
        #expect(try !expense.storeForBackgroundReview(expense.makeRequest(in: store), in: store))
        #expect(try !income.storeForBackgroundReview(income.makeRequest(in: store), in: store))
    }

    @Test func salaryNotificationPreparesAnIncomeWithTheSameProposal() throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "notification", sourceName: "Banca", text: "Accredito stipendio 2.150,50 EUR")
        try CaptureStore.enqueue(capture, in: store)
        let prepare = PrepareIncomeIntent()
        prepare.transaction = CaptureTransactionEntity(capture: capture)
        #expect(prepare.transaction?.amount == 2150.5)
        let request = try prepare.makeRequest(in: store)
        #expect(request == .capture(CaptureShortcutDraft(id: capture.id, amount: nil, note: nil, type: .income)))
        let inbox = FinanceShortcutInbox()
        try inbox.submit(request)
        let state = AppStateManager(persistsSelection: false)
        inbox.deliver(to: state, canAccessContent: false)
        #expect(!state.showingQuickTransaction)
        inbox.deliver(to: state)
        #expect(state.quickTransactionType == .income)
        #expect(state.captureShortcutDraft?.type == .income)
        #expect(state.captureShortcutDraft?.id == capture.id)
        #expect(try CaptureStore.pendingCount(in: store) == 1)
        try CaptureStore.discard(id: capture.id, in: store)
        #expect(throws: FinanceShortcutError.self) { try prepare.makeRequest(in: store) }
    }

    @Test func manualIncomeUsesTheIncomeEditorAndValidatesAmount() throws {
        let prepare = PrepareIncomeIntent()
        prepare.amount = "2150.50"
        prepare.note = "Stipendio"
        let inbox = FinanceShortcutInbox()
        try inbox.submit(prepare.makeRequest())
        let state = AppStateManager(persistsSelection: false)
        inbox.deliver(to: state)
        #expect(state.quickTransactionType == .income)
        #expect(state.quickTransactionPrefill?.amount == "2150,50")
        #expect(state.quickTransactionPrefill?.description == "Stipendio")
        #expect(state.captureShortcutDraft == nil)
        prepare.amount = "-100"
        #expect(throws: FinanceShortcutError.self) { try prepare.makeRequest() }
    }

    @Test func notificationOutputExposesRecognizedFieldsAndStableIdentity() throws {
        let intent = CaptureBankNotificationIntent()
        intent.notificationTitle = "Pagamento carta"
        intent.text = "24,90 EUR presso Esselunga"
        intent.notificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let capture = try intent.makeCapture()
        let entity = CaptureTransactionEntity(capture: capture)
        #expect(entity.id == capture.id)
        #expect(entity.amount == 24.9)
        #expect(entity.currency == "EUR")
        #expect(entity.date == intent.notificationDate)
        #expect(entity.payee == "Esselunga")
        #expect(entity.category == nil)
        #expect(entity.originalText == capture.originalText)
        capture.originalText = "Pagamento 25 EUR. Saldo 500 EUR."
        #expect(CaptureTransactionEntity(capture: capture).amount == nil)
        capture.originalText = "Pagamento $25"
        #expect(CaptureTransactionEntity(capture: capture).currency == nil)
    }

    @Test func prepareExpenseRoutesTheSameStoredProposalAndRejectsDiscardedResults() throws {
        let store = try CaptureStore.container(inMemory: true)
        let capture = PendingCapture(source: "notification", sourceName: "Banca", text: "EUR 25")
        try CaptureStore.enqueue(capture, in: store)
        let prepare = PrepareExpenseIntent()
        prepare.transaction = CaptureTransactionEntity(capture: capture)
        let inbox = FinanceShortcutInbox()
        try inbox.submit(prepare.makeRequest(in: store))
        let state = AppStateManager(persistsSelection: false)
        inbox.deliver(to: state, canAccessContent: false)
        #expect(!state.showingQuickTransaction)
        inbox.deliver(to: state)
        #expect(state.showingQuickTransaction)
        #expect(state.captureShortcutDraft?.id == capture.id)
        #expect(state.quickTransactionPrefill == nil)
        #expect(try CaptureStore.pendingCount(in: store) == 1)
        state.dismissQuickTransaction()
        #expect(state.captureShortcutDraft == nil)
        prepare.amount = "12.50"
        prepare.note = "Correzione manuale"
        #expect(try prepare.makeRequest(in: store) == .capture(CaptureShortcutDraft(id: capture.id, amount: "12,50", note: "Correzione manuale")))
        try CaptureStore.discard(id: capture.id, in: store)
        #expect(throws: FinanceShortcutError.self) { try prepare.makeRequest(in: store) }
    }

    @Test func bankNotificationKeepsAllFieldsAndOriginalDate() throws {
        let intent = CaptureBankNotificationIntent()
        intent.notificationTitle = " Pagamento carta "
        intent.subtitle = " Carta 1234 "
        intent.text = " 24,90 EUR presso Esselunga\n "
        intent.notificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let capture = try intent.makeCapture()
        #expect(capture.originalText == "Pagamento carta\nCarta 1234\n24,90 EUR presso Esselunga")
        #expect(capture.notificationDate == intent.notificationDate)
        #expect(capture.createdAt > capture.notificationDate!)
    }

    @Test func bankNotificationAcceptsLegacyTextAndMissingBody() throws {
        let legacy = CaptureBankNotificationIntent()
        legacy.text = "Pagamento EUR 25"
        #expect(try legacy.makeCapture().originalText == "Pagamento EUR 25")
        #expect(try legacy.makeCapture().notificationDate == nil)
        let titleOnly = CaptureBankNotificationIntent()
        titleOnly.notificationTitle = "Pagamento EUR 25"
        titleOnly.subtitle = "  "
        #expect(try titleOnly.makeCapture().originalText == "Pagamento EUR 25")
        #expect(throws: CaptureIntentFailure.self) { try CaptureBankNotificationIntent().makeCapture() }
        legacy.notificationTitle = String(repeating: "a", count: 30_000)
        #expect(throws: CaptureIntentFailure.self) { try legacy.makeCapture() }
    }

    @Test func iconActionWaitsForUnlockAndOpensAnEmptyExpense() {
        let inbox = FinanceShortcutInbox()
        let state = AppStateManager(persistsSelection: false)
        #expect(FinanceIconQuickAction.receive(FinanceIconQuickAction.newExpenseType, inbox: inbox))
        inbox.deliver(to: state, canAccessContent: false)
        #expect(!state.showingQuickTransaction)
        #expect(inbox.pending != nil)
        inbox.deliver(to: state)
        #expect(state.showingQuickTransaction)
        #expect(state.quickTransactionPrefill?.amount == "")
        #expect(inbox.pending == nil)
    }

    @Test func iconActionPreservesPendingRequestsAndRejectsUnknownActions() throws {
        let inbox = FinanceShortcutInbox()
        #expect(!FinanceIconQuickAction.receive("unknown", inbox: inbox))
        #expect(inbox.pending == nil)
        try inbox.submit(.expense(amount: "25", description: "Bozza da Siri"))
        #expect(!FinanceIconQuickAction.receive(FinanceIconQuickAction.newExpenseType, inbox: inbox))
        #expect(inbox.pending == .expense(amount: "25", description: "Bozza da Siri"))
        #expect(inbox.errorMessage != nil)
    }

    @Test func draftWaitsForExistingEditorAndIsDeliveredOnce() throws {
        let inbox = FinanceShortcutInbox()
        let state = AppStateManager()
        state.presentQuickTransaction()
        let request = FinanceShortcutRequest.expense(amount: "12,50", description: "Pranzo")
        try inbox.submit(request)
        inbox.deliver(to: state)
        #expect(inbox.pending == request)
        #expect(state.quickTransactionPrefill == nil)
        state.dismissQuickTransaction()
        inbox.deliver(to: state)
        #expect(inbox.pending == nil)
        #expect(state.showingQuickTransaction)
        #expect(state.quickTransactionPrefill?.amount == "12,50")
        #expect(state.quickTransactionPrefill?.description == "Pranzo")
        state.dismissQuickTransaction()
        inbox.deliver(to: state)
        #expect(!state.showingQuickTransaction)
        #expect(state.quickTransactionPrefill == nil)
    }

    @Test func requestSurvivesUntilMainInterfaceAndCannotBeOverwritten() throws {
        let inbox = FinanceShortcutInbox()
        try inbox.submit(.planning)
        try inbox.submit(.planning)
        #expect(throws: FinanceShortcutError.self) { try inbox.submit(.today) }
        let state = AppStateManager()
        inbox.deliver(to: state, canAccessContent: false)
        #expect(inbox.pending == .planning)
        #expect(state.selectedTab != .planning)
        state.showingAccountSelection = true
        inbox.deliver(to: state)
        #expect(inbox.pending == .planning)
        state.showingAccountSelection = false
        inbox.deliver(to: state)
        #expect(state.selectedTab == .planning)
        #expect(inbox.pending == nil)
    }

    @Test func intentPassesTheValidatedDraftToTheInterface() async throws {
        let intent = PrepareExpenseIntent()
        intent.amount = "24.90"
        intent.note = "Cena"
        try FinanceShortcutInbox.shared.submit(intent.makeRequest())
        let state = AppStateManager()
        FinanceShortcutInbox.shared.deliver(to: state)
        #expect(state.showingQuickTransaction)
        #expect(state.quickTransactionPrefill?.amount == "24,90")
        #expect(state.quickTransactionPrefill?.description == "Cena")
        #expect(FinanceShortcutInbox.shared.pending == nil)
    }

    @Test func amountDoesNotSilentlyTruncateOrInterpretGrouping() throws {
        #expect(try ShortcutAmount.normalized(" 12.50 ") == "12,50")
        #expect(try ShortcutAmount.normalized("12,50") == "12,50")
        #expect(try ShortcutAmount.normalized(nil) == "")
        for invalid in ["0", "-1", "12 euro", "1.000,50", "1e3", "nan", "12.5.0"] {
            #expect(throws: FinanceShortcutError.self) { try ShortcutAmount.normalized(invalid) }
        }
    }
}
