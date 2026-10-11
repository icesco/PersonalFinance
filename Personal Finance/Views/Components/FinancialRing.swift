import SwiftUI

struct FinancialRing<Content: View>: View {
    let share: Double
    let tint: Color
    var referenceShare: Double? = nil
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            FinancialRingDrawing(progress: min(1, max(0, share)), tint: tint,
                                 referenceShare: referenceShare)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: share)
                .accessibilityHidden(true)
            content.padding(18)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Interpolate one global progress value so segments are reached in order.
private struct FinancialRingDrawing: View, Animatable {
    var progress: Double
    let tint: Color
    let referenceShare: Double?

    var animatableData: Double {
        get { progress }
        set { progress = min(1, max(0, newValue)) }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 9
            let style = StrokeStyle(lineWidth: 9, lineCap: .round)
            for index in 0..<12 {
                let start = Double(index) / 12
                let end = Double(index + 1) / 12 - 0.048
                var track = Path()
                track.addArc(center: center, radius: radius,
                             startAngle: .degrees(135 + start * 270),
                             endAngle: .degrees(135 + end * 270), clockwise: false)
                context.stroke(track, with: .color(tint.opacity(0.13)), style: style)
                if let referenceShare, referenceShare > start {
                    var reference = Path()
                    reference.addArc(center: center, radius: radius,
                                     startAngle: .degrees(135 + start * 270),
                                     endAngle: .degrees(135 + min(end, referenceShare) * 270), clockwise: false)
                    context.stroke(reference, with: .color(ForgiaPalette.spending.opacity(0.4)), style: style)
                }
                if progress > start {
                    var filled = Path()
                    filled.addArc(center: center, radius: radius,
                                  startAngle: .degrees(135 + start * 270),
                                  endAngle: .degrees(135 + min(end, progress) * 270), clockwise: false)
                    context.stroke(filled, with: .color(tint), style: style)
                }
            }
        }
    }
}
