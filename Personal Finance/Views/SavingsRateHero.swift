import SwiftUI

struct SavingsRateHero: View {
    let rate: Decimal
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                SavingsRateHeroValue(rate: rate)
            } else {
                VStack(spacing: 14) {
                    SavingsRateGauge(rate: rate)
                    SavingsRateHeroValue(rate: rate)
                }
                .frame(maxWidth: compact ? 240 : 280)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// The scale expands for signed rates and corrections above 100%.
struct SavingsRateGauge: View {
    let rate: Decimal

    private var value: Double { NSDecimalNumber(decimal: rate).doubleValue }
    private var lower: Double { value < 0 ? -max(1, ceil(abs(value))) : 0 }
    private var upper: Double { max(1, ceil(value)) }
    private var position: Double { (value - lower) / (upper - lower) }
    private var tint: Color { rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings }

    private var sector: Int { min(5, Int(position * 6)) }
    private var sectorLower: Double { lower + Double(sector) / 6 * (upper - lower) }
    private var sectorUpper: Double { lower + Double(sector + 1) / 6 * (upper - lower) }

    var body: some View {
        FinancialRing(share: position, tint: tint) {
            HStack(spacing: 6) {
                Text(sectorLower, format: .percent.precision(.fractionLength(1)))
                Text("–")
                Text(sectorUpper, format: .percent.precision(.fractionLength(1)))
            }
            .font(.caption).foregroundStyle(ForgiaPalette.mutedText).monospacedDigit()
        }
        .accessibilityHidden(true)
    }
}

private struct SavingsRateHeroValue: View {
    let rate: Decimal
    var body: some View {
        VStack(spacing: 6) {
            Text(rate, format: .percent.precision(.fractionLength(1)))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings)
                .financeNumericMotion(rate)
                .minimumScaleFactor(0.7).lineLimit(1).monospacedDigit()
            Text(rate < 0 ? "Spese oltre le entrate" : rate == 0 ? "Entrate interamente spese" : "Margine sulle entrate")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct SavingsGaugeVisualFixture: View {
    @State private var rate: Decimal = Decimal(28) / 100
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("UITEST_GAUGE_MOTION") {
            SectorMotionVariantsFixture()
        } else {
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
}
#endif
