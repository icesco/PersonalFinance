import Foundation
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor
struct WatchDraftTests {
    @Test func mailboxSurvivesRelaunchAndDeduplicatesDelivery() throws {
        let name = "WatchDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let draft = WatchExpenseDraft(id: UUID(), bookID: UUID(), amount: "12.50", note: "Pranzo")
        let first = WatchDraftMailbox(defaults: defaults)
        #expect(first.receive(draft) == .accepted)
        let restored = WatchDraftMailbox(defaults: defaults)
        #expect(restored.pending == draft)
        #expect(restored.receive(draft) == .accepted)
        restored.presented(draft.id)
        #expect(restored.awaitingPresentation == nil)
        #expect(WatchDraftMailbox(defaults: defaults).awaitingPresentation == draft)
        let other = WatchExpenseDraft(id: UUID(), bookID: nil, amount: "5", note: "")
        #expect(restored.receive(other) == .busy)
        restored.delivered(UUID())
        #expect(restored.pending == draft)
        restored.delivered(draft.id)
        let afterDelivery = WatchDraftMailbox(defaults: defaults)
        #expect(afterDelivery.receive(draft) == .accepted)
        #expect(afterDelivery.pending == nil)
        #expect(afterDelivery.receive(other) == .accepted)
    }

    @Test func malformedAmountsAndOversizedNotesAreRejected() {
        for amount in ["", "0", "-1", "1,000.50", "NaN", "1e3"] {
            #expect(WatchExpenseDraft(id: UUID(), bookID: nil, amount: amount, note: "").normalizedAmount == nil)
        }
        #expect(WatchExpenseDraft(id: UUID(), bookID: nil, amount: "12.50", note: "").normalizedAmount == "12,50")
        #expect(WatchExpenseDraft(id: UUID(), bookID: nil, amount: "12", note: String(repeating: "a", count: 201)).normalizedAmount == nil)
    }

    @Test func draftWaitsForUnlockAndUsesItsBook() throws {
        let keys = ["selectedAccountID", "selectedContoID", "showAllAccounts", "showAllConti"]
        let saved = keys.map { (key: $0, value: UserDefaults.standard.object(forKey: $0)) }
        defer { for item in saved { UserDefaults.standard.set(item.value, forKey: item.key) } }
        let book = Account(name: "Watch USD", currency: "USD")
        let draft = WatchExpenseDraft(id: UUID(), bookID: book.id, amount: "12.50", note: "Pranzo")
        let inbox = FinanceShortcutInbox()
        let state = AppStateManager()
        try inbox.submit(.watchExpense(draft))
        inbox.deliver(to: state, canAccessContent: false, accounts: [book])
        #expect(inbox.pending != nil)
        #expect(!state.showingQuickTransaction)
        inbox.deliver(to: state, accounts: [book])
        #expect(state.selectedAccount?.id == book.id)
        #expect(state.showingQuickTransaction)
        #expect(state.quickTransactionPrefill?.amount == "12,50")
        #expect(state.quickTransactionPrefill?.description == "Pranzo")
    }

    @Test func expiredOverviewCannotBeShown() {
        let snapshot = WatchOverview(generatedAt: Date(timeIntervalSince1970: 0), validUntil: Date(timeIntervalSince1970: 100), books: [], hidden: false)
        #expect(!snapshot.usable(at: Date(timeIntervalSince1970: 100)))
        #expect(!WatchOverview.redacted.usable(at: .now))
    }
}
