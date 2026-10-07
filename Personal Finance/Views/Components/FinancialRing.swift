import SwiftUI

/// A bounded share only. Signed amounts outside the share's domain use the caller's numeric layout.
struct FinancialRing<Content: View>: View {
    let share: Double
    let tint: Color
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.12), lineWidth: 15)
            Circle().trim(from: 0, to: appeared || reduceMotion ? min(1, max(0, share)) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .accessibilityHidden(true)
            content.padding(28)
        }
        .frame(maxWidth: 300)
        .aspectRatio(1, contentMode: .fit)
        .padding(10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: share)
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { appeared = true }
        }
    }
}
