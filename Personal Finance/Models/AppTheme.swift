import FinanceCore
import SwiftUI
import WidgetKit

/// Manager per la gestione del tema dell'applicazione.
/// Shared so that `ForgiaPalette` can read it: views that use the palette are
/// observed and redraw when the theme changes.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private static let storageKey = "appTheme"

    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.storageKey)
            syncWidgets()
        }
    }

    private init() {
        // Carica il tema salvato o usa il default (Formi)
        self.currentTheme = UserDefaults.standard.string(forKey: Self.storageKey)
            .flatMap(AppTheme.init(storedValue:)) ?? .formi
        syncWidgets()
    }

    private func syncWidgets() {
        guard FinanceWidgetAppearanceStorage.setTheme(currentTheme.rawValue) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: FinanceWidgetStorage.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: FinanceWidgetStorage.balanceKind)
        WidgetCenter.shared.reloadTimelines(ofKind: FinanceWidgetStorage.upcomingKind)
    }

    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }
}
