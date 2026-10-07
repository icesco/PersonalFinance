import SwiftUI

public enum CalendarSpacing {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
}

public extension Animation {
    static var calendarEase: Animation { .easeInOut(duration: 0.3) }
}

enum CalendarNavigationDirection { case forward, backward }

/// Rubber band offset: full movement up to `limit`, then dampened beyond.
func calendarRubberBandOffset(_ offset: CGFloat, limit: CGFloat = 60) -> CGFloat {
    if abs(offset) < limit { return offset }
    let excess = abs(offset) - limit
    let dampened = limit + excess * 0.3
    return offset > 0 ? dampened : -dampened
}

/// Font richiesti dalla vista. Stesso patto della palette: il package non
/// conosce la scala tipografica dell'app, la riceve. Senza questo il calendario
/// resterebbe l'unica superficie a ignorare il font scelto nelle impostazioni.
public struct CalendarTypography {
    /// Titolo "Ottobre 2026" nell'header di navigazione.
    public let monthTitle: Font
    /// Iniziali dei giorni della settimana.
    public let weekdaySymbol: Font
    /// Numero del giorno nelle celle normali.
    public let dayNumber: Font
    /// Numero del giorno per oggi e per il giorno selezionato.
    public let dayNumberEmphasized: Font

    public init(
        monthTitle: Font,
        weekdaySymbol: Font,
        dayNumber: Font,
        dayNumberEmphasized: Font
    ) {
        self.monthTitle = monthTitle
        self.weekdaySymbol = weekdaySymbol
        self.dayNumber = dayNumber
        self.dayNumberEmphasized = dayNumberEmphasized
    }

    /// Scala di sistema: fallback per preview e per client senza design system.
    public static let system = CalendarTypography(
        monthTitle: .title2.weight(.semibold),
        weekdaySymbol: .caption.weight(.semibold),
        dayNumber: .callout,
        dayNumberEmphasized: .callout.weight(.semibold)
    )
}

/// Colori minimi richiesti dalla vista. Il client passa i colori del proprio
/// tema senza che il package dipenda dal design system dell'app.
public struct CalendarPalette {
    public let accent: Color
    public let foreground: Color
    public let foregroundSecondary: Color

    public init(accent: Color, foreground: Color, foregroundSecondary: Color) {
        self.accent = accent
        self.foreground = foreground
        self.foregroundSecondary = foregroundSecondary
    }
}
