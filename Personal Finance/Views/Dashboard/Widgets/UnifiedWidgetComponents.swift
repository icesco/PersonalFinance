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

/// The tint identifies the card at its heading and fades beneath the details.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    var identityTint: Color? = nil
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(ForgiaPalette.surface)
            .overlay {
                if tintedBackgrounds {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(
                            colors: [(identityTint ?? cardTint).opacity(colorScheme == .dark ? 0.18 : 0.11), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
            }
    }
}

// MARK: - Card Modifier

private struct UnifiedCardModifier: ViewModifier {
    var identityTint: Color? = nil
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background { TintedCardBackground(cornerRadius: 22, identityTint: identityTint) }
            .clipShape(RoundedRectangle(cornerRadius: 22))
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
