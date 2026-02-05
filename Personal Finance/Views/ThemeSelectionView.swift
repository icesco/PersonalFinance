//
//  ThemeSelectionView.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

struct ThemeSelectionView: View {
    @Environment(AppStateManager.self) private var appState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(appState.themeManager.currentTheme.gradient)
                        .padding(.top, 20)

                    Text("Scegli il tuo tema")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Seleziona un colore per personalizzare l'aspetto dell'app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 8)

                // Theme Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appState.themeManager.currentTheme == theme
                        ) {
                            appState.themeManager.setTheme(theme)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Tema")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(theme.gradient)
                        .frame(width: 70, height: 70)

                    Image(systemName: theme.icon)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }

                // Theme name
                Text(theme.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // Selected indicator
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Selezionato")
                            .font(.caption)
                    }
                    .foregroundStyle(theme.color)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: isSelected ? theme.color.opacity(0.3) : Color.black.opacity(0.05),
                           radius: isSelected ? 8 : 4,
                           x: 0,
                           y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? theme.color : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ThemeSelectionView()
            .environment(AppStateManager())
    }
}
