//
//  UnifiedWidgetComponents.swift
//  Personal Finance
//
//  Shared view modifier and reusable components for unified dashboard widgets.
//

import SwiftUI

// MARK: - Card Tint Environment Key

private struct CardTintKey: EnvironmentKey {
    static let defaultValue: Color = .clear
}

private struct TintedBackgroundsKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var cardTint: Color {
        get { self[CardTintKey.self] }
        set { self[CardTintKey.self] = newValue }
    }

    var tintedBackgrounds: Bool {
        get { self[TintedBackgroundsKey.self] }
        set { self[TintedBackgroundsKey.self] = newValue }
    }
}

// MARK: - Tinted Card Background

/// The tint washes the whole card so it reads against the canvas without an outline,
/// and deepens at the heading to identify the card.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    var identityTint: Color? = nil
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color { identityTint ?? cardTint }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(ForgiaPalette.surface)
            .overlay {
                if tintedBackgrounds {
                    shape.fill(tint.opacity(isDark ? 0.10 : 0.07))
                    shape.fill(LinearGradient(
                        colors: [tint.opacity(isDark ? 0.22 : 0.16), tint.opacity(0)],
                        startPoint: .topLeading, endPoint: UnitPoint(x: 0.7, y: 0.8)
                    ))
                }
            }
    }
}

// MARK: - Card Modifier

private struct UnifiedCardModifier: ViewModifier {
    var identityTint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background { TintedCardBackground(cornerRadius: 22, identityTint: identityTint) }
            .clipShape(shape)
            // Elevation lives outside the clip so the shadow is not cut off.
            .background {
                shape.fill(ForgiaPalette.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.08), radius: 18, y: 8)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.04), radius: 2, y: 1)
            }
    }
}

private struct CompactCardBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ForgiaPalette.surface)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07), radius: 12, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 1.5, y: 1)
    }
}

private struct CardInsetBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // A neutral veil over the card's own wash: recessed in light mode, lifted in dark mode.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
    }
}

extension View {
    /// Elevated surface for small rows (shortcuts, inbox entry) matching the card language.
    func compactCard(cornerRadius: CGFloat = 16) -> some View {
        background { CompactCardBackground(cornerRadius: cornerRadius) }
    }

    /// Secondary well inside a card (tiles, highlights), set apart by tone rather than an outline.
    func cardInset(cornerRadius: CGFloat = 14) -> some View {
        background { CardInsetBackground(cornerRadius: cornerRadius) }
    }
}

extension View {
    func unifiedCard(tint: Color? = nil) -> some View {
        modifier(UnifiedCardModifier(identityTint: tint))
    }

    /// Applies the calm surface used across the main screens.
    func themedBackground(tint: Color? = nil) -> some View {
        modifier(ThemedBackgroundModifier(identityTint: tint))
    }
}

// MARK: - Themed Background Modifier

private struct ThemedBackgroundModifier: ViewModifier {
    var identityTint: Color? = nil
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .buttonBorderShape(.capsule)
            .background {
                ForgiaPalette.canvas
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if tintedBackgrounds {
                            LinearGradient(
                                colors: [(identityTint ?? cardTint).opacity(colorScheme == .dark ? 0.20 : 0.12), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 360)
                            .ignoresSafeArea()
                        }
                    }
            }
    }
}
