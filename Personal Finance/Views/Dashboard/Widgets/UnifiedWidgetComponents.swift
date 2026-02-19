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

/// Gradient-tinted card background matching the dashboard background strategy.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.cardTint) private var cardTint
    @Environment(\.tintedBackgrounds) private var tintedBackgrounds
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if tintedBackgrounds {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            RadialGradient(
                                colors: colorScheme == .dark
                                    ? [cardTint.opacity(0.10), cardTint.opacity(0.02), .clear]
                                    : [cardTint.opacity(0.14), cardTint.opacity(0.04), .clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 300
                            )
                        )
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }
}

// MARK: - Card Modifier

private struct UnifiedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background { TintedCardBackground(cornerRadius: 16) }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

extension View {
    func unifiedCard() -> some View {
        modifier(UnifiedCardModifier())
    }

    /// Applies the themed gradient background used across all main screens.
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
                if tintedBackgrounds {
                    SubtleMeshGradient(baseColor: cardTint)
                        .ignoresSafeArea()
                } else {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
    }
}

// MARK: - Percentage Bar (GeometryReader-free)

struct PercentageBar: View {
    let fraction: CGFloat
    let color: Color
    var height: CGFloat = 8
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.tertiarySystemFill))
            .frame(height: height)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.gradient)
                    .scaleEffect(x: min(max(fraction, 0), 1), anchor: .leading)
                    .animation(.easeOut(duration: 0.6), value: fraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Unified Action Button

struct UnifiedActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(color)
                    }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Unified Stat Cell

struct UnifiedStatCell: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background { TintedCardBackground(cornerRadius: 12) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Widget Help Sheet

struct WidgetHelpSheet: View {
    let section: DashboardSection
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(section.minimumLevel.iconColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: section.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(section.minimumLevel.iconColor)
                }
                .padding(.top, 24)
                
                // Title + level badge
                VStack(spacing: 8) {
                    Text(section.displayName)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    
                    Text(section.minimumLevel.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(section.minimumLevel.iconColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(section.minimumLevel.iconColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                // Help text
                Text(section.helpText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding()
        }.safeAreaBar(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Chiudi")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(section.minimumLevel.iconColor)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        
        .presentationDetents([.medium])
    }
}
