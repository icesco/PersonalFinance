//
//  AnimatedMeshGradient.swift
//  Personal Finance
//
//  Animated mesh gradient background for dashboard views
//

import SwiftUI

struct AnimatedMeshGradient: View {
    let colors: [Color]
    @State private var isVisible = false

    /// Initialize with explicit 16 colors for the 4x4 mesh grid
    init(colors: [Color] = [
        .purple, .indigo, .purple, .yellow,
        .pink, .purple, .pink, .yellow,
        .orange, .pink, .yellow, .orange,
        .yellow, .orange, .pink, .purple
    ]) {
        self.colors = colors
    }

    /// Initialize with a base color - generates a harmonious palette automatically
    init(baseColor: Color) {
        let mainColor = baseColor
        let lighterColor = mainColor.lighter(by: 0.3)
        let darkerColor = mainColor.darker(by: 0.3)
        let complementaryColor = mainColor.mix(with: .white, by: 0.5)

        // Create variations for the 4x4 mesh (16 colors)
        self.colors = [
            // Top row
            mainColor, lighterColor, mainColor, complementaryColor,
            // Second row
            darkerColor, mainColor, darkerColor, complementaryColor,
            // Third row
            lighterColor, darkerColor, complementaryColor, lighterColor,
            // Bottom row
            complementaryColor, lighterColor, darkerColor, mainColor
        ]
    }

    var body: some View {
        Group {
            if isVisible {
                TimelineView(.animation) { context in
                    meshGradientContent(for: context)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 3600.0)) { context in
                    meshGradientContent(for: context)
                }
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }

    @ViewBuilder
    private func meshGradientContent(for context: TimelineViewDefaultContext) -> some View {
        let time = context.date.timeIntervalSince1970
        let offsetX = Float(sin(time * 0.5)) * 0.15
        let offsetY = Float(cos(time * 0.5)) * 0.1

        MeshGradient(
            width: 4,
            height: 4,
            points: [
                // Top row - fixed
                [0.0, 0.0], [0.33, 0.0], [0.66, 0.0], [1.0, 0.0],
                // Second row - slight movement
                [0.0, 0.33], [0.25 + offsetX, 0.35 + offsetY], [0.75 + offsetX, 0.30 + offsetY], [1.0, 0.33],
                // Third row - slight movement
                [0.0, 0.66], [0.30 + offsetX, 0.70], [0.70 + offsetX, 0.65], [1.0, 0.66],
                // Bottom row - fixed
                [0.0, 1.0], [0.33, 1.0], [0.66, 1.0], [1.0, 1.0]
            ],
            colors: colors
        )
    }
}

// MARK: - Subtle Mesh Gradient (Static)

/// A static mesh gradient with very desaturated colors, used as a soft background
/// when "Sfondi Colorati" is enabled. No animation — just a gentle color wash.
struct SubtleMeshGradient: View {
    let baseColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let opacity = colorScheme == .dark ? 0.12 : 0.06
        let c1 = baseColor.opacity(opacity)
        let c2 = baseColor.lighter(by: 0.3).opacity(opacity * 0.7)
        let c3 = baseColor.darker(by: 0.2).opacity(opacity * 1.2)
        let c4 = baseColor.mix(with: .white, by: 0.5).opacity(opacity * 0.5)

        MeshGradient(
            width: 4,
            height: 4,
            points: [
                [0.0, 0.0], [0.33, 0.0], [0.66, 0.0], [1.0, 0.0],
                [0.0, 0.33], [0.25, 0.35],  [0.75, 0.30],  [1.0, 0.33],
                [0.0, 0.66], [0.30, 0.70],  [0.70, 0.65],  [1.0, 0.66],
                [0.0, 1.0], [0.33, 1.0], [0.66, 1.0], [1.0, 1.0]
            ],
            colors: [
                c1, c2, c1, c4,
                c3, c1, c3, c4,
                c2, c3, c4, c2,
                c4, c2, c3, c1
            ]
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        // Default colors
        AnimatedMeshGradient()
            .frame(height: 300)
            .ignoresSafeArea()

        // Orange/Fire theme (Forgia)
        AnimatedMeshGradient(baseColor: Color(red: 0.95, green: 0.45, blue: 0.15))
            .frame(height: 300)

        // Blue theme
        AnimatedMeshGradient(baseColor: .blue)
            .frame(height: 300)

        // Purple theme
        AnimatedMeshGradient(baseColor: .purple)
            .frame(height: 300)

        // Green theme
        AnimatedMeshGradient(baseColor: .green)
            .frame(height: 300)
    }
}
