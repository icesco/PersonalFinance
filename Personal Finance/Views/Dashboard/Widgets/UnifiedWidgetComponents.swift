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

enum FinanceCardSurfaceStyle: Equatable, Sendable {
    case gradient
    case themed
}

private struct FinanceCardSurfaceStyleKey: EnvironmentKey {
    static let defaultValue: FinanceCardSurfaceStyle = .gradient
}

extension EnvironmentValues {
    var financeCardSurfaceStyle: FinanceCardSurfaceStyle {
        get { self[FinanceCardSurfaceStyleKey.self] }
        set { self[FinanceCardSurfaceStyleKey.self] = newValue }
    }

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

/// Themed cards use a satin material; gradient cards retain their section tint.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    var identityTint: Color? = nil
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.financeCardSurfaceStyle) private var surfaceStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tint: Color { identityTint ?? cardTint }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if surfaceStyle == .themed {
            if reduceTransparency {
                shape.fill(AnalysisPalette.cardSurface)
            } else {
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(ForgiaPalette.sageSurface.opacity(isDark ? 0.12 : 0.10)) }
            }
        } else {
            shape.fill(ForgiaPalette.surface)
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
}

// MARK: - Card Modifier

private struct UnifiedCardModifier: ViewModifier {
    var identityTint: Color? = nil
    var emphasized = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.financeCardSurfaceStyle) private var surfaceStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .foregroundStyle(surfaceStyle == .themed ? ForgiaPalette.accent : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .clipShape(shape)
            .background {
                TintedCardBackground(cornerRadius: 22, identityTint: identityTint)
                    .overlay {
                        if emphasized && surfaceStyle == .themed {
                            shape.fill(LinearGradient(
                                colors: [ForgiaPalette.accent.opacity(colorScheme == .dark ? 0.07 : 0.045), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        }
                    }
                    .shadow(color: .black.opacity(surfaceStyle != .gradient
                                                 ? (colorScheme == .dark ? 0.18 : 0.035)
                                                 : (colorScheme == .dark ? 0.40 : 0.08)),
                            radius: surfaceStyle != .gradient ? 8 : 18,
                            y: surfaceStyle != .gradient ? 3 : 8)
                    .shadow(color: .black.opacity(surfaceStyle != .gradient
                                                 ? (colorScheme == .dark ? 0.12 : 0.02)
                                                 : (colorScheme == .dark ? 0.30 : 0.04)), radius: 2, y: 1)
            }
    }
}

private struct CompactCardBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.financeCardSurfaceStyle) private var surfaceStyle

    var body: some View {
        surface
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07), radius: 12, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 1.5, y: 1)
    }

    @ViewBuilder private var surface: some View {
        if surfaceStyle == .themed {
            TintedCardBackground(cornerRadius: cornerRadius)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ForgiaPalette.surface)
        }
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
    func unifiedCard(tint: Color? = nil, emphasized: Bool = false) -> some View {
        modifier(UnifiedCardModifier(identityTint: tint, emphasized: emphasized))
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
    @Environment(\.financeCardSurfaceStyle) private var surfaceStyle

    func body(content: Content) -> some View {
        content
            .buttonBorderShape(.capsule)
            .background {
                if surfaceStyle == .themed {
                    ThemedAmbientBackground()
                } else {
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
}

private struct ThemedAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack(alignment: .top) {
            ForgiaPalette.canvas
            ForgiaPalette.accent.opacity(isDark ? 0.055 : 0.065)

            LinearGradient(
                colors: [ForgiaPalette.accent.opacity(isDark ? 0.18 : 0.13), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 460)
            .offset(y: -150)

            RadialGradient(
                colors: [
                    ForgiaPalette.canvas.opacity(isDark ? 0.10 : 0.24),
                    ForgiaPalette.accent.opacity(isDark ? 0.34 : 0.24),
                    ForgiaPalette.accent.opacity(isDark ? 0.12 : 0.086),
                    .clear
                ],
                center: .top,
                startRadius: 78,
                endRadius: 430
            )
            .frame(height: 430)
            .scaleEffect(x: 2.1, y: 0.72, anchor: .top)
            .offset(y: -150)
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
