import SwiftUI

struct FinancialRing<Content: View>: View {
    let share: Double
    let tint: Color
    var referenceShare: Double? = nil
    var entranceAnimation: Animation = .timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
    var entranceDuration: Double = 0.5
    var windowHeight: CGFloat = 100
    var selectedSectorGlow = false
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var markerAppeared = false
    @State private var markerArrived = false

    private var progress: Double { min(1, max(0, share)) }
    private var targetFocus: Double { (Double(min(5, Int(progress * 6))) + 0.5) * 32 }
    private var entryFocus: Double { targetFocus > 16 ? max(16, targetFocus - 64) : 80 }
    private var markerStart: Double {
        min(progress, Double(min(5, Int(progress * 6))) / 6 + 9.0 / (2 * 6 * 32))
    }

    var body: some View {
        VStack(spacing: 12) {
            FinancialRingWindow(progress: progress, tint: tint,
                                referenceShare: referenceShare,
                                focus: appeared || reduceMotion ? targetFocus : entryFocus,
                                markerScale: markerAppeared || reduceMotion ? 1 : 0,
                                markerPosition: markerArrived || reduceMotion ? progress : markerStart,
                                selectedSectorGlow: selectedSectorGlow)
                .frame(height: windowHeight)
                .clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: share)
                .animation(reduceMotion ? nil : entranceAnimation, value: appeared)
                .animation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.2), value: markerAppeared)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: markerArrived)
                .accessibilityHidden(true)
            content
        }
        .task {
            guard !appeared else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            appeared = true
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(max(0, entranceDuration) * 0.6))
                guard !Task.isCancelled else { return }
            }
            markerAppeared = true
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
            }
            markerArrived = true
        }
    }
}

#if DEBUG
struct SectorMotionVariantsFixture: View {
    @State private var replay = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rotazione del quadrante")
                    .font(.title2.weight(.semibold))
                Text("Stesso valore e stessa rotazione · dati illustrativi")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                VStack(spacing: 12) {
                    SectorMotionVariantRow(letter: "A", title: "Attuale", detail: "Morbida · 0,9 s",
                                          animation: .easeOut(duration: 0.9), duration: 0.9)
                    SectorMotionVariantRow(letter: "B", title: "Scatto secco", detail: "Parte veloce, si ferma netta · 0,5 s",
                                          animation: .timingCurve(0.16, 1, 0.3, 1, duration: 0.5), duration: 0.5)
                    SectorMotionVariantRow(letter: "C", title: "Accelerazione", detail: "Parte piano, accelera · 0,55 s",
                                          animation: .easeIn(duration: 0.55), duration: 0.55)
                    SectorMotionVariantRow(letter: "D", title: "Molla corta", detail: "Piccolo rimbalzo finale · 0,55 s",
                                          animation: .spring(duration: 0.55, bounce: 0.18), duration: 0.55)
                }
                .id(replay)
                Button { replay += 1 } label: {
                    Label("Ripeti tutte", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ForgiaPalette.savings)
                .accessibilityIdentifier("sector-motion-replay")
                if reduceMotion {
                    Text("Riduci movimento è attivo: le rotazioni sono disabilitate.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .padding(20)
        }
        .themedBackground()
        .task {
            guard ProcessInfo.processInfo.arguments.contains("UITEST_MOTION_RECORDING") else { return }
            for _ in 0..<2 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                replay += 1
            }
        }
    }
}

private struct SectorMotionVariantRow: View {
    let letter: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let animation: Animation
    let duration: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("\(letter) ·")
                    Text(title)
                }.font(.headline)
                Text(detail).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FinancialRing(share: 0.63, tint: ForgiaPalette.savings,
                          entranceAnimation: animation, entranceDuration: duration, windowHeight: 64) {
                Text(0.63, format: .percent.precision(.fractionLength(0)))
                    .font(.headline).monospacedDigit().foregroundStyle(ForgiaPalette.savings)
            }
            .frame(width: 170)
        }
        .padding(12)
        .background(ForgiaPalette.savings.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif

private struct FinancialRingWindow: View {
    let progress: Double
    let tint: Color
    let referenceShare: Double?
    let focus: Double
    let markerScale: Double
    let markerPosition: Double
    let selectedSectorGlow: Bool

    var body: some View {
        let drawing = FinancialRingDrawing(progress: progress, tint: tint,
                                           referenceShare: referenceShare, focus: focus,
                                           markerScale: markerScale, markerPosition: markerPosition,
                                           selectedSectorGlow: selectedSectorGlow)
        ZStack {
            drawing.mask(edgeMask(inverted: false))
            drawing.blur(radius: 3).mask(edgeMask(inverted: true))
        }
        .compositingGroup()
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.08),
                .init(color: .white, location: 0.92),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func edgeMask(inverted: Bool) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: inverted ? .white : .clear, location: 0),
            .init(color: inverted ? .clear : .white, location: 0.22),
            .init(color: inverted ? .clear : .white, location: 0.78),
            .init(color: inverted ? .white : .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// A fixed window follows the current value on a larger, cropped dial.
private struct FinancialRingDrawing: View, Animatable {
    var progress: Double
    let tint: Color
    let referenceShare: Double?
    var focus: Double
    var markerScale: Double
    var markerPosition: Double
    let selectedSectorGlow: Bool
    @Environment(\.colorScheme) private var colorScheme

    var animatableData: AnimatableValues<Double, Double, Double, Double> {
        get { AnimatableValues(progress, focus, markerScale, markerPosition) }
        set {
            progress = min(1, max(0, newValue.value.0))
            focus = newValue.value.1
            markerScale = newValue.value.2
            markerPosition = newValue.value.3
        }
    }

    var body: some View {
        Canvas { context, size in
            let radius = size.width * 1.05
            let center = CGPoint(x: size.width / 2, y: radius + 24)
            let thickness = CGFloat(22)
            let style = StrokeStyle(lineWidth: thickness, lineCap: .round)
            let sectorDegrees = 32.0
            let gapDegrees = 9.0
            let selected = min(5, Int(progress * 6))

            // Draw neighboring sectors beyond the scale ends to keep the window continuous.
            for index in -1...6 {
                let start = -90 + Double(index) * sectorDegrees - focus + gapDegrees / 2
                let end = start + sectorDegrees - gapDegrees
                var sector = Path()
                sector.addArc(center: center, radius: radius,
                              startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                let color = index == selected ? tint : ForgiaPalette.mutedText.opacity(0.25)
                if index == selected && selectedSectorGlow {
                    var selectedContext = context
                    selectedContext.addFilter(.shadow(color: tint.opacity(colorScheme == .dark ? 0.28 : 0.20),
                                                      radius: 7, x: 0, y: 2))
                    selectedContext.stroke(sector, with: .color(color), style: style)
                } else {
                    context.stroke(sector, with: .color(color), style: style)
                }
            }
            if let referenceShare {
                let angle = (-90 + min(1, max(0, referenceShare)) * 6 * sectorDegrees - focus) * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                let reference = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.fill(reference, with: .color(ForgiaPalette.spending))
            }
            let angle = (-90 + markerPosition * 6 * sectorDegrees - focus) * .pi / 180
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let markerRadius = 8 * max(0, markerScale)
            let marker = Path(ellipseIn: CGRect(x: point.x - markerRadius, y: point.y - markerRadius,
                                               width: markerRadius * 2, height: markerRadius * 2))
            context.opacity = min(1, max(0, markerScale))
            context.fill(marker, with: .color(tint))
            context.stroke(marker, with: .color(.white.opacity(0.85)), lineWidth: 2 * max(0, markerScale))
        }
    }
}
