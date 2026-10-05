import Testing
@testable import Personal_Finance

@MainActor
struct FinanceShortcutTests {
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
        _ = try await intent.perform()
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
