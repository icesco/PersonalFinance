//
//  ThemeSelectionView.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

struct ThemeSelectionView: View {
    @Environment(AppStateManager.self) private var appState

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        @Bindable var appState = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(theme: theme, isSelected: appState.themeManager.currentTheme == theme) {
                            appState.themeManager.setTheme(theme)
                        }
                    }
                }

                Text("Ogni tema include colori dedicati a margine, risparmio, spese, saldo e calendario.")
                    .font(.footnote).foregroundStyle(ForgiaPalette.mutedText)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $appState.tintedBackgrounds) {
                        Label("Sfondi sfumati", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal")
                    }
                    .tint(ForgiaPalette.accent)
                    Text("Aggiunge una leggera sfumatura del colore del tema in cima alle schermate.")
                        .font(.footnote)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                .padding(16)
                .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
        .themedBackground()
        .navigationTitle("Aspetto")
        .toolbarTitleDisplayMode(.inline)
    }
}

/// A miniature of the app drawn with the theme's own palette, so each choice
/// shows its canvas, surfaces and accent together, in the current appearance.
struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    private var palette: ThemePalette { theme.palette }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview
                HStack {
                    Text(theme.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? palette.accent : Color.secondary.opacity(0.5))
                }
            }
            .padding(10)
            .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : ForgiaPalette.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tema \(theme.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: theme.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 22, height: 22)
                    .background(palette.accent, in: Circle())
                Capsule().fill(palette.mutedText.opacity(0.35)).frame(width: 46, height: 6)
            }
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(palette.accent).frame(width: 58, height: 8)
                Capsule().fill(palette.mutedText.opacity(0.3)).frame(height: 5)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6).fill(palette.indicators.margin)
                    RoundedRectangle(cornerRadius: 6).fill(palette.indicators.savings)
                    RoundedRectangle(cornerRadius: 6).fill(palette.indicators.spending)
                    RoundedRectangle(cornerRadius: 6).fill(palette.indicators.balance)
                    RoundedRectangle(cornerRadius: 6).fill(palette.indicators.calendar)
                }
                .frame(height: 20)
            }
            .padding(9)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.border))
        }
        .padding(10)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ThemeSelectionView()
            .environment(AppStateManager())
    }
}
