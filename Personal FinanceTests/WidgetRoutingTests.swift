import Foundation
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor
struct WidgetRoutingTests {
    @Test func widgetSelectsItsBookAfterUnlockBeforeOpeningExpense() throws {
        let keys = ["selectedAccountID", "selectedContoID", "showAllAccounts", "showAllConti"]
        let saved = keys.map { (key: $0, value: UserDefaults.standard.object(forKey: $0)) }
        defer { for item in saved { UserDefaults.standard.set(item.value, forKey: item.key) } }
        let selected = Account(name: "Libro del widget", currency: "USD")
        let other = Account(name: "Altro", currency: "EUR")
        let state = AppStateManager()
        let inbox = FinanceShortcutInbox()
        try inbox.submit(.widget(FinanceWidgetRoute(destination: .expense, bookID: selected.id)))
        inbox.deliver(to: state, canAccessContent: false, accounts: [other, selected])
        #expect(!state.showingQuickTransaction)
        #expect(inbox.pending != nil)
        inbox.deliver(to: state, accounts: [other, selected])
        #expect(state.selectedAccount?.id == selected.id)
        #expect(state.showingQuickTransaction)
        #expect(inbox.pending == nil)
    }

    @Test func missingBookNeverFallsBackToAnotherBook() throws {
        let state = AppStateManager()
        let inbox = FinanceShortcutInbox()
        try inbox.submit(.widget(FinanceWidgetRoute(destination: .expense, bookID: UUID())))
        inbox.deliver(to: state, accounts: [])
        #expect(!state.showingQuickTransaction)
        #expect(inbox.errorMessage != nil)
        #expect(inbox.pending == nil)
    }
}
