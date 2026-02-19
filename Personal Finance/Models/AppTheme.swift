//
//  AppTheme.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case forgia = "forgia"  // Tema default - fuoco e forgiatura
    case blue = "blue"
    case indigo = "indigo"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case teal = "teal"
    case cyan = "cyan"
    case mint = "mint"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forgia: return "Forgia"
        case .blue: return "Blu"
        case .indigo: return "Indaco"
        case .purple: return "Viola"
        case .pink: return "Rosa"
        case .red: return "Rosso"
        case .orange: return "Arancione"
        case .yellow: return "Giallo"
        case .green: return "Verde"
        case .teal: return "Verde Acqua"
        case .cyan: return "Ciano"
        case .mint: return "Menta"
        }
    }

    var color: Color {
        switch self {
        case .forgia: return Color(red: 0.95, green: 0.45, blue: 0.15)  // Arancione fuoco
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .cyan: return .cyan
        case .mint: return .mint
        }
    }

    /// Colore secondario complementare per gradienti e accenti
    var secondaryColor: Color {
        switch self {
        case .forgia: return Color(red: 1.0, green: 0.65, blue: 0.2)  // Arancione dorato/brace
        case .blue: return .cyan
        case .indigo: return .purple
        case .purple: return .pink
        case .pink: return .red
        case .red: return .orange
        case .orange: return .yellow
        case .yellow: return .orange
        case .green: return .mint
        case .teal: return .cyan
        case .cyan: return .blue
        case .mint: return .green
        }
    }

    /// Gradiente per elementi decorativi
    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Gradiente scuro per la dashboard crypto-style
    var dashboardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.black,
                color.opacity(0.4),
                color.opacity(0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Icona rappresentativa del tema
    var icon: String {
        switch self {
        case .forgia: return "flame.fill"
        case .blue: return "drop.fill"
        case .indigo: return "sparkles"
        case .purple: return "crown.fill"
        case .pink: return "heart.fill"
        case .red: return "bolt.fill"
        case .orange: return "sun.max.fill"
        case .yellow: return "star.fill"
        case .green: return "leaf.fill"
        case .teal: return "water.waves"
        case .cyan: return "cloud.fill"
        case .mint: return "wind"
        }
    }
}

/// Manager per la gestione del tema dell'applicazione
@Observable
final class ThemeManager {
    var currentTheme: AppTheme {
        didSet {
            saveTheme()
        }
    }

    init() {
        // Carica il tema salvato o usa il default (Forgia)
        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .forgia
        }
    }

    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
    }

    func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }
}
