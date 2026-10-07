//
//  AppTheme.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

/// Curated themes. Each one is a complete, quiet palette (accent, canvas and
/// surfaces, light and dark) rather than a raw system colour, so text and
/// controls keep their contrast whatever the user picks.
enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case formi
    case ocean
    case lavender
    case forest
    case terracotta
    case plum
    case amber
    case graphite

    var id: String { rawValue }

    /// Reads a saved preference, mapping the colours of the previous theme list
    /// to the closest curated palette.
    init?(storedValue: String) {
        if let theme = AppTheme(rawValue: storedValue) {
            self = theme
            return
        }
        switch storedValue {
        case "forgia": self = .formi
        case "blue", "cyan": self = .ocean
        case "indigo", "purple": self = .lavender
        case "green", "teal", "mint": self = .forest
        case "orange", "red": self = .terracotta
        case "pink": self = .plum
        case "yellow": self = .amber
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .formi: return "Formi"
        case .ocean: return "Oceano"
        case .lavender: return "Lavanda"
        case .forest: return "Bosco"
        case .terracotta: return "Terracotta"
        case .plum: return "Prugna"
        case .amber: return "Ambra"
        case .graphite: return "Grafite"
        }
    }

    /// Icona rappresentativa del tema
    var icon: String {
        switch self {
        case .formi: return "leaf.fill"
        case .ocean: return "water.waves"
        case .lavender: return "sparkles"
        case .forest: return "tree.fill"
        case .terracotta: return "sun.max.fill"
        case .plum: return "heart.fill"
        case .amber: return "star.fill"
        case .graphite: return "circle.lefthalf.filled"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .formi:
            ThemePalette(indicators: indicatorPalette, accent: (0x255D5E, 0xB0D7CD), onAccent: (0xFFFFFF, 0x0E1E1E),
                         canvas: (0xF7F8F5, 0x101414), surface: (0xFFFFFF, 0x1A2521),
                         accentSurface: (0xE6EFEA, 0x1E3433), warmSurface: (0xF8EEE7, 0x3C2D26),
                         border: (0xE3E7E2, 0x323E3C), mutedText: (0x53615B, 0xBECDC3))
        case .ocean:
            ThemePalette(indicators: indicatorPalette, accent: (0x2B5C8A, 0x9CC3E6), onAccent: (0xFFFFFF, 0x0C1520),
                         canvas: (0xF5F7FA, 0x0C1117), surface: (0xFFFFFF, 0x151C25),
                         accentSurface: (0xE4EDF6, 0x182A3B), warmSurface: (0xF8EEE6, 0x33261F),
                         border: (0xE0E5EC, 0x26303C), mutedText: (0x55606E, 0xB3BFCC))
        case .lavender:
            ThemePalette(indicators: indicatorPalette, accent: (0x5B4F9A, 0xC4BBF0), onAccent: (0xFFFFFF, 0x15121F),
                         canvas: (0xF7F6FA, 0x100F16), surface: (0xFFFFFF, 0x1A1822),
                         accentSurface: (0xECE9F6, 0x241F38), warmSurface: (0xF8ECEA, 0x33221F),
                         border: (0xE4E2EC, 0x2C2936), mutedText: (0x5D5A6B, 0xBDB9CC))
        case .forest:
            ThemePalette(indicators: indicatorPalette, accent: (0x3D6B3F, 0xA9D3A4), onAccent: (0xFFFFFF, 0x0F160E),
                         canvas: (0xF6F8F4, 0x0E120D), surface: (0xFFFFFF, 0x171D16),
                         accentSurface: (0xE6EFE3, 0x1E2E1C), warmSurface: (0xF7EFE2, 0x2F2819),
                         border: (0xE1E7DD, 0x283126), mutedText: (0x56604F, 0xB7C3B1))
        case .terracotta:
            ThemePalette(indicators: indicatorPalette, accent: (0xA4513A, 0xF0B39E), onAccent: (0xFFFFFF, 0x1E120E),
                         canvas: (0xFAF7F4, 0x15110F), surface: (0xFFFFFF, 0x201916),
                         accentSurface: (0xF6E8E1, 0x3A241C), warmSurface: (0xE7EFEA, 0x1D2B25),
                         border: (0xECE4DE, 0x33291F), mutedText: (0x6B5B52, 0xCBBBB1))
        case .plum:
            ThemePalette(indicators: indicatorPalette, accent: (0x8E3E63, 0xEBAACB), onAccent: (0xFFFFFF, 0x1D1018),
                         canvas: (0xFAF6F8, 0x140F12), surface: (0xFFFFFF, 0x1F171B),
                         accentSurface: (0xF5E6ED, 0x36202B), warmSurface: (0xF7EEE4, 0x30271C),
                         border: (0xECE2E7, 0x31252B), mutedText: (0x66545D, 0xC9B7C0))
        case .amber:
            ThemePalette(indicators: indicatorPalette, accent: (0x8A6316, 0xEBC676), onAccent: (0xFFFFFF, 0x1C160A),
                         canvas: (0xFAF8F2, 0x13110C), surface: (0xFFFFFF, 0x1E1A13),
                         accentSurface: (0xF5EDD9, 0x34291A), warmSurface: (0xE6EEF0, 0x1B2A2E),
                         border: (0xEAE5D8, 0x302A20), mutedText: (0x625B4B, 0xC8BFAD))
        case .graphite:
            ThemePalette(indicators: indicatorPalette, accent: (0x3F4A56, 0xC5CED8), onAccent: (0xFFFFFF, 0x111316),
                         canvas: (0xF6F6F7, 0x0F1011), surface: (0xFFFFFF, 0x1A1B1D),
                         accentSurface: (0xECEEF1, 0x24272B), warmSurface: (0xF6EFE8, 0x2E2620),
                         border: (0xE3E4E7, 0x2C2E32), mutedText: (0x5A5E66, 0xBBBFC6))
        }
    }

    /// Stable identities across themes; each theme tunes the same colour families.
    private var indicatorPalette: ThemeIndicatorPalette {
        switch self {
        case .formi: .init(margin: (0x26705B, 0x8ED5B7), savings: (0x7354A6, 0xCEB2F3), spending: (0xA5532B, 0xF2B28C), balance: (0x356CB0, 0x9FC5F5), calendar: (0x876210, 0xEBC77B))
        case .ocean: .init(margin: (0x247464, 0x83D5C5), savings: (0x6556A8, 0xC4B6F1), spending: (0xA55336, 0xF1B79B), balance: (0x2B64A4, 0x9CC9EF), calendar: (0x826318, 0xE7CD82))
        case .lavender: .init(margin: (0x367258, 0xA0D3B7), savings: (0x7250AB, 0xCFB5F1), spending: (0xA1553D, 0xECB3A0), balance: (0x456AAB, 0xA9C2F0), calendar: (0x80631D, 0xE8CE8B))
        case .forest: .init(margin: (0x3E703A, 0xAFD49C), savings: (0x745593, 0xCCB4E4), spending: (0xA25A2E, 0xEFC09A), balance: (0x426A99, 0xAAC8E7), calendar: (0x7F641E, 0xE5CC8C))
        case .terracotta: .init(margin: (0x3C735E, 0xA3D1B9), savings: (0x875482, 0xDDB5D5), spending: (0xAD573B, 0xF1B49D), balance: (0x3C6F9C, 0xA9C9E6), calendar: (0x8A621D, 0xEDD08C))
        case .plum: .init(margin: (0x367362, 0x98D2BB), savings: (0x8D4A85, 0xE1B4DC), spending: (0xA65B37, 0xEDBB9B), balance: (0x4D68A5, 0xB2C3EB), calendar: (0x86631D, 0xE9CC8B))
        case .amber: .init(margin: (0x43733D, 0xB1D2A1), savings: (0x7E5799, 0xD6B8E7), spending: (0xA65A2D, 0xEFC098), balance: (0x3C709B, 0xA1CBE7), calendar: (0x8A6316, 0xEBC676))
        case .graphite: .init(margin: (0x3C705F, 0xABD0BF), savings: (0x716087, 0xC7BADC), spending: (0x996244, 0xDDBA9E), balance: (0x506C91, 0xB2C6E1), calendar: (0x7D682D, 0xDCCB97))
        }
    }

    var color: Color { palette.accent }

    /// Colore secondario complementare per gradienti e accenti
    var secondaryColor: Color { palette.accentSurface }

    /// Gradiente per elementi decorativi
    var gradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The semantic colours of a theme, each with a light and a dark variant.
struct ThemePalette {
    let indicators: ThemeIndicatorPalette
    let accent: Color
    let onAccent: Color
    let canvas: Color
    let surface: Color
    /// Soft surface tinted with the accent (income, positive states, selection).
    let accentSurface: Color
    /// Soft complementary surface (expenses, places, warnings).
    let warmSurface: Color
    let border: Color
    let mutedText: Color

    typealias Pair = (light: UInt32, dark: UInt32)

    init(indicators: ThemeIndicatorPalette, accent: Pair, onAccent: Pair, canvas: Pair, surface: Pair,
         accentSurface: Pair, warmSurface: Pair, border: Pair, mutedText: Pair) {
        self.indicators = indicators
        self.accent = Color(light: accent.light, dark: accent.dark)
        self.onAccent = Color(light: onAccent.light, dark: onAccent.dark)
        self.canvas = Color(light: canvas.light, dark: canvas.dark)
        self.surface = Color(light: surface.light, dark: surface.dark)
        self.accentSurface = Color(light: accentSurface.light, dark: accentSurface.dark)
        self.warmSurface = Color(light: warmSurface.light, dark: warmSurface.dark)
        self.border = Color(light: border.light, dark: border.dark)
        self.mutedText = Color(light: mutedText.light, dark: mutedText.dark)
    }
}

struct ThemeIndicatorPalette {
    let margin: Color
    let savings: Color
    let spending: Color
    let balance: Color
    let calendar: Color
    let deficit = Color(light: 0xB13B49, dark: 0xF7A0AA)

    init(margin: ThemePalette.Pair, savings: ThemePalette.Pair, spending: ThemePalette.Pair,
         balance: ThemePalette.Pair, calendar: ThemePalette.Pair) {
        self.margin = Color(light: margin.light, dark: margin.dark)
        self.savings = Color(light: savings.light, dark: savings.dark)
        self.spending = Color(light: spending.light, dark: spending.dark)
        self.balance = Color(light: balance.light, dark: balance.dark)
        self.calendar = Color(light: calendar.light, dark: calendar.dark)
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #else
        self.init(rgb: light)
        #endif
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#elseif os(macOS)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

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
        }
    }

    private init() {
        // Carica il tema salvato o usa il default (Formi)
        self.currentTheme = UserDefaults.standard.string(forKey: Self.storageKey)
            .flatMap(AppTheme.init(storedValue:)) ?? .formi
    }

    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }
}
