//
//  UserExperienceLevel.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

enum UserExperienceLevel: String, CaseIterable, Codable, Identifiable {
    case beginner = "beginner"
    case standard = "standard"
    case advanced = "advanced"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Semplificata"
        case .standard: return "Standard"
        case .advanced: return "Avanzata"
        }
    }

    var subtitle: String {
        switch self {
        case .beginner: return "Per chi inizia"
        case .standard: return "Bilanciata"
        case .advanced: return "Wolf of Wall Street"
        }
    }

    var description: String {
        switch self {
        case .beginner:
            return "Interfaccia minimalista con solo le funzionalità essenziali. Perfetta per chi muove i primi passi nella gestione finanziaria."
        case .standard:
            return "Esperienza completa e bilanciata con tutte le funzionalità principali. Ideale per la maggior parte degli utenti."
        case .advanced:
            return "Dashboard completa con metriche avanzate, analisi dettagliate e terminologia professionale. Per utenti esperti."
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .standard: return "chart.bar.fill"
        case .advanced: return "chart.line.uptrend.xyaxis"
        }
    }

    var iconColor: Color {
        switch self {
        case .beginner: return .green
        case .standard: return .blue
        case .advanced: return .purple
        }
    }

    // MARK: - Feature Flags

    /// Mostra grafici avanzati nella dashboard
    var showAdvancedCharts: Bool {
        self == .advanced
    }

    /// Mostra metriche dettagliate (ROI, percentuali di crescita, etc.)
    var showDetailedMetrics: Bool {
        self == .standard || self == .advanced
    }

    /// Mostra analisi e insights automatici
    var showInsights: Bool {
        self == .advanced
    }

    /// Numero massimo di transazioni da mostrare nella dashboard
    var dashboardTransactionLimit: Int {
        switch self {
        case .beginner: return 3
        case .standard: return 5
        case .advanced: return 10
        }
    }

    /// Mostra categorie avanzate e subcategorie
    var showAdvancedCategories: Bool {
        self == .standard || self == .advanced
    }

    /// Mostra statistiche e comparazioni di periodo
    var showPeriodComparisons: Bool {
        self == .advanced
    }

    /// Mostra budget e obiettivi di risparmio
    var showBudgets: Bool {
        self == .standard || self == .advanced
    }

    /// Mostra filtri avanzati nelle transazioni
    var showAdvancedFilters: Bool {
        self == .advanced
    }

    /// Usa terminologia finanziaria professionale
    var useProfessionalTerminology: Bool {
        self == .advanced
    }

    // MARK: - Labels

    /// Label per il balance (varia in base al livello)
    var balanceLabel: String {
        switch self {
        case .beginner: return "I tuoi soldi"
        case .standard: return "Saldo totale"
        case .advanced: return "Patrimonio netto"
        }
    }

    /// Label per le transazioni
    var transactionsLabel: String {
        switch self {
        case .beginner: return "Movimenti"
        case .standard: return "Transazioni"
        case .advanced: return "Operazioni finanziarie"
        }
    }
}

/// Manager per la gestione del livello di esperienza utente
@Observable
final class ExperienceLevelManager {
    var currentLevel: UserExperienceLevel {
        didSet {
            saveLevel()
        }
    }

    init() {
        // Carica il livello salvato o usa il default (standard)
        if let savedLevel = UserDefaults.standard.string(forKey: "userExperienceLevel"),
           let level = UserExperienceLevel(rawValue: savedLevel) {
            self.currentLevel = level
        } else {
            self.currentLevel = .standard
        }
    }

    private func saveLevel() {
        UserDefaults.standard.set(currentLevel.rawValue, forKey: "userExperienceLevel")
    }

    func setLevel(_ level: UserExperienceLevel) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentLevel = level
        }
    }
}
