import Foundation
import FinanceCore
import Testing
@testable import Personal_Finance

@MainActor
struct BookSelectionTests {
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "BookSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults)
    }

    @Test func relaunchRestoresLastBookRegardlessOfListOrder() {
        withDefaults { defaults in
            let first = Account(name: "Personale")
            let last = Account(name: "Famiglia")
            let state = AppStateManager(defaults: defaults)
            state.selectAccount(last)

            let relaunched = AppStateManager(defaults: defaults)
            relaunched.loadSelectedAccount(from: [first, last])
            #expect(relaunched.selectedAccount?.id == last.id)
            #expect(!relaunched.requiresAccountSelection(accounts: [first, last]))
            #expect(!relaunched.showAllAccounts)
        }
    }

    @Test func partialLoadingDoesNotReplaceSavedBookAndRestoresWhenItArrives() {
        withDefaults { defaults in
            let first = Account(name: "Personale")
            let saved = Account(name: "Condiviso")
            defaults.set(saved.id.uuidString, forKey: "selectedAccountID")
            let state = AppStateManager(defaults: defaults)
            state.loadSelectedAccount(from: [])
            state.loadSelectedAccount(from: [first])
            #expect(state.selectedAccount?.id == first.id)
            #expect(defaults.string(forKey: "selectedAccountID") == saved.id.uuidString)

            // Also retain the preference across a relaunch before sync completes.
            let relaunched = AppStateManager(defaults: defaults)
            relaunched.loadSelectedAccount(from: [first])
            relaunched.loadSelectedAccount(from: [first, saved])
            #expect(relaunched.selectedAccount?.id == saved.id)
            state.loadSelectedAccount(from: [first, saved])
            #expect(state.selectedAccount?.id == saved.id)
        }
    }

    @Test func explicitChoiceWhileLoadingTakesPrecedenceOverOldPreference() {
        withDefaults { defaults in
            let old = Account(name: "Vecchio")
            let available = Account(name: "Disponibile")
            defaults.set(old.id.uuidString, forKey: "selectedAccountID")
            let state = AppStateManager(defaults: defaults)
            state.loadSelectedAccount(from: [available])
            state.selectAccount(available)
            state.loadSelectedAccount(from: [old, available])
            #expect(state.selectedAccount?.id == available.id)
            #expect(defaults.string(forKey: "selectedAccountID") == available.id.uuidString)
        }
    }

    @Test func allBooksModeSurvivesRelaunchAndAllowsInitialSelection() {
        withDefaults { defaults in
            let books = [Account(name: "Personale"), Account(name: "Famiglia")]
            let state = AppStateManager(defaults: defaults)
            state.selectAllAccounts()
            #expect(!state.requiresAccountSelection(accounts: books))
            let relaunched = AppStateManager(defaults: defaults)
            relaunched.loadSelectedAccount(from: books)
            #expect(relaunched.showAllAccounts)
            #expect(!relaunched.requiresAccountSelection(accounts: books))
        }
    }

    @Test func unavailableOrArchivedSavedBookUsesAnActiveBook() {
        withDefaults { defaults in
            let archived = Account(name: "Archiviato")
            archived.isActive = false
            let active = Account(name: "Attivo")
            defaults.set(archived.id.uuidString, forKey: "selectedAccountID")
            let state = AppStateManager(defaults: defaults)
            state.loadSelectedAccount(from: [archived, active])
            #expect(state.selectedAccount?.id == active.id)
            state.loadSelectedAccount(from: [archived])
            #expect(state.selectedAccount == nil)
            #expect(state.requiresAccountSelection(accounts: [archived]))
            #expect(defaults.string(forKey: "selectedAccountID") == archived.id.uuidString)
        }
    }

    @Test func draftWindowCannotOverwriteRememberedBook() {
        withDefaults { defaults in
            let saved = Account(name: "Personale")
            let other = Account(name: "Famiglia")
            let state = AppStateManager(defaults: defaults)
            state.selectAccount(saved)
            let draft = state.windowSnapshot()
            draft.selectAccount(other)
            #expect(defaults.string(forKey: "selectedAccountID") == saved.id.uuidString)
        }
    }
}
