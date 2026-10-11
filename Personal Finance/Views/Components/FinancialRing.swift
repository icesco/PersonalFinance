import SwiftUI

/// A bounded share only. Signed amounts outside the share's domain use the caller's numeric layout.
struct FinancialRing<Content: View>: View {
    let share: Double
    let tint: Color
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var progress: Double { appeared || reduceMotion ? min(1, max(0, share)) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.12), tint.opacity(0.025), .clear],
                                     center: .center, startRadius: 10, endRadius: 145))
                .padding(20)
                .accessibilityHidden(true)
            Circle().trim(from: 0, to: 0.75)
                .stroke(tint.opacity(0.14), lineWidth: 1)
                .rotationEffect(.degrees(135))
                .padding(26)
                .accessibilityHidden(true)
            ForEach(0..<12) { segment in
                FinancialRingSegment(index: segment, progress: progress, tint: tint)
            }
            GeometryReader { geometry in
                let angle = (135 + progress * 270) * .pi / 180
                let radius = geometry.size.width / 2 - 10
                Circle().fill(tint)
                    .frame(width: 13, height: 13)
                    .overlay { Circle().stroke(ForgiaPalette.surface, lineWidth: 3) }
                    .position(x: geometry.size.width / 2 + radius * cos(angle),
                              y: geometry.size.height / 2 + radius * sin(angle))
                    .opacity(progress > 0 ? 1 : 0)
            }
            .accessibilityHidden(true)
            content.padding(36)
        }
        .frame(maxWidth: 300)
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: share)
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.75)) { appeared = true }
        }
    }
}

private struct FinancialRingSegment: View {
    let index: Int
    let progress: Double
    let tint: Color

    private var start: Double { Double(index) * 0.75 / 12 }
    private var end: Double { Double(index + 1) * 0.75 / 12 - 0.029 }

    var body: some View {
        ZStack {
            Circle().trim(from: start, to: end)
                .stroke(tint.opacity(0.13), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            Circle().trim(from: start, to: max(start, min(end, progress * 0.75)))
                .stroke(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .opacity(progress * 0.75 > start ? 1 : 0)
        }
        .rotationEffect(.degrees(135))
        .padding(10)
        .accessibilityHidden(true)
    }
}
