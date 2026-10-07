import SwiftUI

struct SavingsRateHero: View {
    let rate: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SavingsRateHeroValue(rate: rate)
            SavingsRateGauge(rate: rate)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A scale with a moving marker, rather than a completion percentage.
/// Signed and above-100% values keep their real value; the scale expands to include them.
struct SavingsRateGauge: View {
    let rate: Decimal
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var value: Double { NSDecimalNumber(decimal: rate).doubleValue }
    private var lower: Double { value < 0 ? -max(1, ceil(abs(value))) : 0 }
    private var upper: Double { max(1, ceil(value)) }
    private var position: Double { (value - lower) / (upper - lower) }
    private var zero: Double { -lower / (upper - lower) }
    private var tint: Color { rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - 20)
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgiaPalette.savings.opacity(0.16))
                        .frame(height: compact ? 6 : 10)
                    if lower < 0 {
                        UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                            .fill(ForgiaPalette.deficit.opacity(0.22))
                            .frame(width: width * zero, height: compact ? 6 : 10)
                    }
                    Rectangle().fill(ForgiaPalette.mutedText.opacity(0.6))
                        .frame(width: 2, height: compact ? 12 : 18)
                        .offset(x: width * zero)
                    Circle().fill(tint)
                        .frame(width: compact ? 14 : 20, height: compact ? 14 : 20)
                        .overlay { Circle().stroke(.background, lineWidth: 3) }
                        .shadow(color: tint.opacity(0.2), radius: 3, y: 2)
                        .offset(x: width * (appeared || reduceMotion ? position : zero) - (compact ? 7 : 10))
                }
                .frame(width: width, height: 24)
                .padding(.horizontal, 10)
            }.frame(height: 24)
            if !compact {
                GeometryReader { geometry in
                    HStack {
                        Text(lower, format: .percent.precision(.fractionLength(0)))
                        Spacer()
                        Text(upper, format: .percent.precision(.fractionLength(0)))
                    }
                    if lower < 0 {
                        Text("0%").position(x: 10 + (geometry.size.width - 20) * zero, y: 8)
                    }
                }
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText).monospacedDigit()
                .frame(height: 20)
            }
        }
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: rate)
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { appeared = true }
        }
    }
}

private struct SavingsRateHeroValue: View {
    let rate: Decimal
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rate, format: .percent.precision(.fractionLength(1)))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings)
                .financeNumericMotion(rate)
                .minimumScaleFactor(0.7).lineLimit(1).monospacedDigit()
            Text(rate < 0 ? "Spese oltre le entrate" : rate == 0 ? "Entrate interamente spese" : "Margine sulle entrate")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
        }.accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct SavingsGaugeVisualFixture: View {
    @State private var rate: Decimal = Decimal(28) / 100
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Tasso di risparmio · dati illustrativi").font(.headline)
                SavingsRateHero(rate: rate).unifiedCard()
                HStack {
                    Button("Margine") { rate = Decimal(28) / 100 }
                    Button("Deficit") { rate = Decimal(-12) / 100 }
                    Button("Correzione") { rate = Decimal(125) / 100 }
                }.buttonStyle(.bordered)
            }.padding(22)
        }.themedBackground()
    }
}
#endif
