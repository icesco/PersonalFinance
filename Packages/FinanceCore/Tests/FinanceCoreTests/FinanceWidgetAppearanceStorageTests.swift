import Foundation
import Testing
@testable import FinanceCore

struct FinanceWidgetAppearanceStorageTests {
    @Test func changingThemePersistsForTheExtensionAndReloadsOnlyOnChange() throws {
        let name = "widget-appearance-\(UUID())"
        let app = try #require(UserDefaults(suiteName: name))
        let widget = try #require(UserDefaults(suiteName: name))
        defer { app.removePersistentDomain(forName: name) }
        #expect(FinanceWidgetAppearanceStorage.theme(defaults: widget) == nil)
        #expect(FinanceWidgetAppearanceStorage.setTheme("ocean", defaults: app))
        #expect(FinanceWidgetAppearanceStorage.theme(defaults: widget) == "ocean")
        #expect(!FinanceWidgetAppearanceStorage.setTheme("ocean", defaults: app))
        #expect(FinanceWidgetAppearanceStorage.setTheme("lavender", defaults: app))
        #expect(FinanceWidgetAppearanceStorage.theme(defaults: widget) == "lavender")
        #expect(!FinanceWidgetAppearanceStorage.setTheme("forest", defaults: nil))
    }
}
