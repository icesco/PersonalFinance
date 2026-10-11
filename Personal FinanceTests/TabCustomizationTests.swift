import Foundation
import Testing
@testable import Personal_Finance

@MainActor
struct TabCustomizationTests {
    @Test func defaultsAndPersistenceKeepFixedTabs() throws {
        let name = "tab-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppStateManager(defaults: defaults)
        #expect(state.compactTabs == [.dashboard, .transactions, .planning])
        state.setOptionalTabs([.calendar, .analysis])
        #expect(AppStateManager(defaults: defaults).compactTabs == [.dashboard, .transactions, .calendar, .analysis])
        state.setOptionalTabs([])
        #expect(AppStateManager(defaults: defaults).compactTabs == [.dashboard, .transactions])
    }

    @Test func corruptSavedChoicesAreSanitized() throws {
        let name = "tab-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set([999, AppTab.settings.rawValue, AppTab.dashboard.rawValue,
                      AppTab.calendar.rawValue, AppTab.calendar.rawValue, AppTab.budgets.rawValue,
                      AppTab.accounts.rawValue, AppTab.analysis.rawValue], forKey: "navigation.optionalTabs.v1")
        #expect(AppStateManager(defaults: defaults).compactTabs == [.dashboard, .transactions, .calendar, .budgets, .accounts])
    }

    @Test func transientWindowDoesNotOverwritePreferences() throws {
        let name = "tab-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        AppStateManager(persistsSelection: false, defaults: defaults).setOptionalTabs([.analysis])
        #expect(AppStateManager(defaults: defaults).optionalTabs == [.planning])
    }

    @Test func droppedTabsKeepOrderCapacityAndPersist() throws {
        let name = "tab-drag-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppStateManager(defaults: defaults)
        #expect(state.placeOptionalTab(.budgets, before: .planning))
        #expect(state.optionalTabs == [.budgets, .planning])
        #expect(state.placeOptionalTab(.calendar))
        #expect(!state.placeOptionalTab(.analysis))
        #expect(!state.placeOptionalTab(.dashboard))
        #expect(state.placeOptionalTab(.calendar, before: .budgets))
        #expect(state.optionalTabs == [.calendar, .budgets, .planning])
        #expect(state.placeOptionalTab(.calendar))
        #expect(state.optionalTabs == [.budgets, .planning, .calendar])
        #expect(!state.placeOptionalTab(.planning, before: .accounts))
        #expect(AppStateManager(defaults: defaults).optionalTabs == [.budgets, .planning, .calendar])
    }
}
