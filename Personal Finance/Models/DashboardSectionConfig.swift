//
//  DashboardSectionConfig.swift
//  Personal Finance
//
//  Model and manager for unified dashboard section customization.
//

import SwiftUI

// MARK: - Dashboard Section

enum DashboardSection: String, CaseIterable, Codable, Identifiable {
    case monthlyStats
    case spendingDistribution
    case savingsRate
    case topExpenses
    case monthComparison
    case balanceTrend
    case contiList
    case recentTransactions
    case activeBudgets
    case spendingPace
    case upcomingRecurring
    case financialHealth
    case expenseHeatmap
    case spendingAnomalies
    case categorySparklines
    case cashFlowForecast
    case spendingByWeekday
    case incomeVsExpensesTimeline
    case topPayees
    case savingsGoal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthlyStats: return "Entrate / Uscite / Risparmi"
        case .spendingDistribution: return "Dove vanno i soldi"
        case .savingsRate: return "Tasso di Risparmio"
        case .topExpenses: return "Top Spese del Mese"
        case .monthComparison: return "Confronto Mese Precedente"
        case .balanceTrend: return "Andamento Saldo"
        case .contiList: return "I tuoi conti"
        case .recentTransactions: return "Ultime transazioni"
        case .activeBudgets: return "Budget in Corso"
        case .spendingPace: return "Velocità di Spesa"
        case .upcomingRecurring: return "Spese Ricorrenti in Arrivo"
        case .financialHealth: return "Financial Health Score"
        case .expenseHeatmap: return "Heatmap Spese"
        case .spendingAnomalies: return "Anomalie di Spesa"
        case .categorySparklines: return "Trend per Categoria"
        case .cashFlowForecast: return "Previsione Cash Flow"
        case .spendingByWeekday: return "Spese per Giorno"
        case .incomeVsExpensesTimeline: return "Entrate vs Uscite"
        case .topPayees: return "Top Destinatari"
        case .savingsGoal: return "Obiettivo Risparmio"
        }
    }

    /// Minimum experience level required for this section to appear in a preset.
    var minimumLevel: UserExperienceLevel {
        switch self {
        // Beginner: essential, easy-to-understand widgets
        case .monthlyStats, .spendingDistribution, .balanceTrend,
             .contiList, .recentTransactions:
            return .beginner

        // Standard: more detail but still intuitive
        case .savingsRate, .topExpenses, .activeBudgets, .monthComparison,
             .expenseHeatmap, .upcomingRecurring, .topPayees:
            return .standard

        // Advanced: technical/analytical widgets
        case .spendingPace, .financialHealth, .spendingAnomalies,
             .categorySparklines, .cashFlowForecast, .spendingByWeekday,
             .incomeVsExpensesTimeline, .savingsGoal:
            return .advanced
        }
    }

    var helpText: String {
        switch self {
        case .monthlyStats:
            return "Riepilogo di entrate, uscite e risparmi del periodo selezionato. I risparmi sono la differenza tra entrate e uscite."
        case .spendingDistribution:
            return "Grafico a torta che mostra come sono distribuite le spese per categoria. Le percentuali indicano il peso di ogni categoria sul totale delle uscite del periodo."
        case .savingsRate:
            return "Percentuale di entrate che riesci a risparmiare. Positivo = stai risparmiando, negativo = stai spendendo piu\u{0300} di quanto guadagni. Un tasso sopra il 20% e\u{0300} considerato ottimo."
        case .topExpenses:
            return "Le spese piu\u{0300} alte del periodo, ordinate per importo. Utile per identificare le uscite piu\u{0300} significative e dove intervenire."
        case .monthComparison:
            return "Confronta entrate e uscite del mese corrente con il mese precedente. Le percentuali mostrano la variazione: verde = miglioramento, rosso = peggioramento."
        case .balanceTrend:
            return "Andamento del saldo totale nel tempo. La linea continua mostra il passato, quella tratteggiata la proiezione futura basata sulle transazioni ricorrenti."
        case .contiList:
            return "Lista dei tuoi conti con il saldo attuale di ciascuno. Tocca un conto per vedere le sue transazioni."
        case .recentTransactions:
            return "Le ultime transazioni registrate in ordine cronologico. Tocca una transazione per vederne i dettagli."
        case .activeBudgets:
            return "I budget attivi con il progresso di spesa. La barra mostra quanto hai speso rispetto al limite impostato. Rosso = budget superato."
        case .spendingPace:
            return "Confronta il ritmo di spesa attuale del mese con la media giornaliera dei mesi precedenti. Se stai spendendo piu\u{0300} velocemente del solito, il widget lo segnala."
        case .upcomingRecurring:
            return "Transazioni ricorrenti previste nei prossimi giorni. Basato sulle ricorrenze impostate sulle transazioni (es. abbonamenti mensili, stipendio)."
        case .financialHealth:
            return "Punteggio da 0 a 100 che valuta la salute finanziaria complessiva. Composto da: capacita\u{0300} di risparmio (30pt), rispetto dei budget (25pt), stabilita\u{0300} delle entrate (20pt), trend delle spese (25pt)."
        case .expenseHeatmap:
            return "Calendario del mese con i flussi giornalieri. Verde = giorno con entrate dominanti, rosso = uscite dominanti. Piu\u{0300} il colore e\u{0300} intenso, maggiore l'importo. Tocca un giorno nel dettaglio per vedere le transazioni."
        case .spendingAnomalies:
            return "Identifica categorie dove stai spendendo significativamente piu\u{0300} della media degli ultimi 3 mesi. Utile per individuare spese fuori controllo prima che diventino un problema."
        case .categorySparklines:
            return "Mini-grafici che mostrano l'andamento delle spese per le categorie principali negli ultimi mesi. La freccia indica se il trend e\u{0300} in aumento (rosso) o diminuzione (verde)."
        case .cashFlowForecast:
            return "Previsione dei flussi di cassa per le prossime 4 settimane. Basata sulle transazioni ricorrenti programmate e sulla media delle spese non ricorrenti passate."
        case .spendingByWeekday:
            return "Media delle spese per giorno della settimana, calcolata sugli ultimi 3 mesi. Utile per capire in quali giorni tendi a spendere di piu\u{0300} (es. weekend vs. giorni lavorativi)."
        case .incomeVsExpensesTimeline:
            return "Confronto mensile tra entrate e uscite visualizzato come grafico a barre affiancate. Permette di vedere a colpo d'occhio i mesi in attivo e quelli in passivo."
        case .topPayees:
            return "Classifica dei destinatari a cui hai pagato di piu\u{0300} nel periodo, con importo totale e numero di transazioni per ciascuno."
        case .savingsGoal:
            return "Obiettivo di risparmio mensile calcolato automaticamente come media dei tuoi risparmi positivi degli ultimi 3 mesi. Mostra il progresso attuale e una proiezione di fine mese basata sul ritmo di risparmio giornaliero."
        }
    }

    var icon: String {
        switch self {
        case .monthlyStats: return "chart.bar.fill"
        case .spendingDistribution: return "chart.pie.fill"
        case .savingsRate: return "gauge.with.needle.fill"
        case .topExpenses: return "flame.fill"
        case .monthComparison: return "arrow.left.arrow.right"
        case .balanceTrend: return "chart.line.uptrend.xyaxis"
        case .contiList: return "creditcard.fill"
        case .recentTransactions: return "list.bullet.rectangle.fill"
        case .activeBudgets: return "target"
        case .spendingPace: return "speedometer"
        case .upcomingRecurring: return "calendar.badge.clock"
        case .financialHealth: return "heart.circle.fill"
        case .expenseHeatmap: return "square.grid.3x3.fill"
        case .spendingAnomalies: return "exclamationmark.triangle.fill"
        case .categorySparklines: return "chart.xyaxis.line"
        case .cashFlowForecast: return "chart.bar.xaxis.ascending"
        case .spendingByWeekday: return "calendar"
        case .incomeVsExpensesTimeline: return "chart.bar.fill"
        case .topPayees: return "person.2.fill"
        case .savingsGoal: return "flag.checkered"
        }
    }
}

// MARK: - Section Config

struct DashboardSectionConfig: Codable, Identifiable {
    let section: DashboardSection
    var isVisible: Bool

    var id: String { section.rawValue }
}

// MARK: - Layout Manager

@Observable
final class DashboardLayoutManager {
    private static let storageKey = "unifiedDashboardLayout"

    var sections: [DashboardSectionConfig] = []

    init() {
        sections = Self.load()
    }

    // MARK: - Mutations

    func moveSection(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func toggleVisibility(for section: DashboardSection) {
        guard let index = sections.firstIndex(where: { $0.section == section }) else { return }
        sections[index].isVisible.toggle()
        save()
    }

    func reset() {
        sections = Self.defaultSections
        save()
    }

    /// Apply a preset based on experience level: sections at or below the given level
    /// become visible, others are hidden. Order is preserved.
    func applyPreset(for level: UserExperienceLevel) {
        let levelOrder: [UserExperienceLevel] = [.beginner, .standard, .advanced]
        guard let targetIndex = levelOrder.firstIndex(of: level) else { return }

        for i in sections.indices {
            let sectionLevel = sections[i].section.minimumLevel
            let sectionIndex = levelOrder.firstIndex(of: sectionLevel) ?? 0
            sections[i].isVisible = sectionIndex <= targetIndex
        }
        save()
    }

    // MARK: - Visible sections (in order)

    var visibleSections: [DashboardSection] {
        sections.filter(\.isVisible).map(\.section)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func load() -> [DashboardSectionConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([DashboardSectionConfig].self, from: data)
        else {
            return defaultSections
        }

        // Merge: keep saved order/visibility, append any new sections not yet in saved data
        let savedIDs = Set(saved.map(\.section))
        let missing = DashboardSection.allCases
            .filter { !savedIDs.contains($0) }
            .map { DashboardSectionConfig(section: $0, isVisible: true) }

        return saved + missing
    }

    static var defaultSections: [DashboardSectionConfig] {
        DashboardSection.allCases.map { DashboardSectionConfig(section: $0, isVisible: true) }
    }
}
