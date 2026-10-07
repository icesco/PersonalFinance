import SwiftUI

/// Quiet semantic surfaces for the main financial journey, taken from the
/// selected theme. Reading them inside `body` makes the view observe
/// `ThemeManager`, so a new theme redraws every screen in place.
enum ForgiaPalette {
    private static var palette: ThemePalette { ThemeManager.shared.currentTheme.palette }

    static var canvas: Color { palette.canvas }
    static var surface: Color { palette.surface }
    static var accent: Color { palette.accent }
    static var margin: Color { palette.indicators.margin }
    static var savings: Color { palette.indicators.savings }
    static var spending: Color { palette.indicators.spending }
    static var balance: Color { palette.indicators.balance }
    static var calendar: Color { palette.indicators.calendar }
    static var deficit: Color { palette.indicators.deficit }
    static var onAccent: Color { palette.onAccent }
    static var sageSurface: Color { palette.accentSurface }
    static var apricotSurface: Color { palette.warmSurface }
    static var border: Color { palette.border }
    static var mutedText: Color { palette.mutedText }
}
