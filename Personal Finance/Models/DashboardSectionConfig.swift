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
