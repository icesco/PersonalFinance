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
