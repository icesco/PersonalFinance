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

extension EnvironmentValues {
    var cardTint: Color {
        get { self[CardTintKey.self] }
        set { self[CardTintKey.self] = newValue }
    }
}

// MARK: - Tinted Card Background

/// Gradient-tinted card background matching the dashboard background strategy.
private struct TintedCardBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.cardTint) private var cardTint
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [cardTint.opacity(0.06), cardTint.opacity(0.01)]
                                : [cardTint.opacity(0.02), cardTint.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
