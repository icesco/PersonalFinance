import Foundation

/// Appearance is shared independently of the financial snapshot, including when data is hidden.
public enum FinanceWidgetAppearanceStorage {
    public static let themeKey = "widgets.appTheme"

    public static func theme(defaults: UserDefaults? = sharedDefaults) -> String? {
        defaults?.string(forKey: themeKey)
    }

    /// Returns whether widgets need to be reloaded.
    @discardableResult
    public static func setTheme(_ value: String, defaults: UserDefaults? = sharedDefaults) -> Bool {
        guard let defaults, defaults.string(forKey: themeKey) != value else { return false }
        defaults.set(value, forKey: themeKey)
        return true
    }

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: FinanceCoreModule.defaultAppGroupIdentifier)
    }
}
