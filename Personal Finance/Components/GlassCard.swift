//
//  GlassCard.swift
//  Personal Finance
//
//  Reusable glassmorphism card component for crypto-style dashboard
//

import SwiftUI

/// A glassmorphic card with dark tinted background, blur, and subtle border
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let topCornersOnly: Bool
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = 24,
        topCornersOnly: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.topCornersOnly = topCornersOnly
        self.content = content
    }

    var body: some View {
        content()
            .background {
                if topCornersOnly {
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: cornerRadius
                    )
                    .fill(.ultraThinMaterial)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: cornerRadius
                        )
                        .fill(Color.black.opacity(0.6))
                    }
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: cornerRadius
                        )
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color.black.opacity(0.6))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        }
                }
            }
    }
}

/// A simple glass-style circular button
struct GlassCircleButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.black, .green.opacity(0.4), .green.opacity(0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                Text("Regular Glass Card")
                    .foregroundStyle(.white)
                    .padding(24)
            }

            GlassCard(topCornersOnly: true) {
                Text("Top Corners Only")
                    .foregroundStyle(.white)
                    .padding(24)
            }

            HStack(spacing: 32) {
                GlassCircleButton(icon: "plus", label: "Entrata") {}
                GlassCircleButton(icon: "minus", label: "Uscita") {}
            }
        }
        .padding()
    }
}
