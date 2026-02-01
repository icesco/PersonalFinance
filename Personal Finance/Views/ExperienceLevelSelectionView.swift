//
//  ExperienceLevelSelectionView.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

struct ExperienceLevelSelectionView: View {
    @Environment(AppStateManager.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 50))
                        .foregroundStyle(appState.themeManager.currentTheme.gradient)
                        .padding(.top, 20)

                    Text("Modalità di utilizzo")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Scegli il livello di dettaglio più adatto a te")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 8)

                // Experience Levels
                VStack(spacing: 16) {
                    ForEach(UserExperienceLevel.allCases) { level in
                        ExperienceLevelCard(
                            level: level,
                            isSelected: appState.experienceLevelManager.currentLevel == level
                        ) {
                            appState.experienceLevelManager.setLevel(level)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Modalità")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExperienceLevelCard: View {
    let level: UserExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(level.iconColor.opacity(0.15))
                            .frame(width: 50, height: 50)

                        Image(systemName: level.icon)
                            .font(.title2)
                            .foregroundStyle(level.iconColor)
                    }

                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(level.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Selected indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(level.iconColor)
                    }
                }

                // Description
                Text(level.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Features preview
                VStack(alignment: .leading, spacing: 8) {
                    FeatureRow(
                        icon: "chart.xyaxis.line",
                        text: "Grafici avanzati",
                        enabled: level.showAdvancedCharts
                    )
                    FeatureRow(
                        icon: "percent",
                        text: "Metriche dettagliate",
                        enabled: level.showDetailedMetrics
                    )
                    FeatureRow(
                        icon: "lightbulb.fill",
                        text: "Insights automatici",
                        enabled: level.showInsights
                    )
                    FeatureRow(
                        icon: "target",
                        text: "Budget e obiettivi",
                        enabled: level.showBudgets
                    )
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected ? level.iconColor.opacity(0.3) : Color.black.opacity(0.05),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? level.iconColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(enabled ? .green : .secondary)

            Text(text)
                .font(.caption)
                .foregroundStyle(enabled ? .primary : .secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ExperienceLevelSelectionView()
            .environment(AppStateManager())
    }
}
