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

/// Solid, quiet card surface. The optional tint stays below the content layer.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(ForgiaPalette.surface)
            .overlay {
                if tintedBackgrounds {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(cardTint.opacity(colorScheme == .dark ? 0.025 : 0.018))
                }
            }
    }
}

// MARK: - Card Modifier

private struct UnifiedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background { TintedCardBackground(cornerRadius: 22) }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(ForgiaPalette.border.opacity(0.8), lineWidth: 0.5).allowsHitTesting(false) }
    }
}

extension View {
    func unifiedCard() -> some View {
        modifier(UnifiedCardModifier())
    }

    /// Applies the calm surface used across the main screens.
    func themedBackground() -> some View {
        modifier(ThemedBackgroundModifier())
    }
}

// MARK: - Themed Background Modifier

private struct ThemedBackgroundModifier: ViewModifier {
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds

    func body(content: Content) -> some View {
        content
            .background {
                ForgiaPalette.canvas
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        if tintedBackgrounds {
                            RadialGradient(
                                colors: [cardTint.opacity(0.035), .clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 350
                            )
                            .ignoresSafeArea()
                        }
                    }
            }
    }
}
