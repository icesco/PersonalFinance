import SwiftUI

struct SavingsRateHero: View {
    let rate: Decimal
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                SavingsRateHeroValue(rate: rate, compact: compact)
            } else {
                VStack(spacing: 14) {
                    SavingsRateGauge(rate: rate, compact: compact)
                    SavingsRateHeroValue(rate: rate, compact: compact)
                }
                .frame(maxWidth: .infinity)
            }
            SavingsRateLegend()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// The scale expands for signed rates and corrections above 100%.
struct SavingsRateGauge: View {
    let rate: Decimal
    var compact = false

    private var value: Double { NSDecimalNumber(decimal: rate).doubleValue }
    private var lower: Double { value < 0 ? -max(1, ceil(abs(value))) : 0 }
    private var upper: Double { max(1, ceil(value)) }
    private var position: Double { (value - lower) / (upper - lower) }
    private var tint: Color { rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings }

    private var sector: Int { min(5, Int(position * 6)) }
    private var sectorLower: Double { lower + Double(sector) / 6 * (upper - lower) }
    private var sectorUpper: Double { lower + Double(sector + 1) / 6 * (upper - lower) }

    var body: some View {
        FinancialRing(share: position, tint: tint, windowHeight: compact ? 80 : 100,
                      selectedSectorGlow: true) {
            HStack(spacing: 6) {
                Text(sectorLower, format: .percent.precision(.fractionLength(1)))
                Text("–")
                Text(sectorUpper, format: .percent.precision(.fractionLength(1)))
            }
            .font(.caption2.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText).monospacedDigit()
        }
        .accessibilityHidden(true)
    }
}

private struct SavingsRateLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { entries }
            VStack(alignment: .leading, spacing: 6) { entries }
        }
        .font(.caption)
        .foregroundStyle(ForgiaPalette.mutedText)
        .padding(.top, 4)
        .accessibilityIdentifier("savings-rate-legend")
    }

    @ViewBuilder private var entries: some View {
        Label {
            Text("Margine ≥ 0%")
        } icon: {
            Circle().fill(ForgiaPalette.savings).frame(width: 8, height: 8)
        }
        Label {
            Text("Deficit < 0%")
        } icon: {
            Circle().fill(ForgiaPalette.deficit).frame(width: 8, height: 8)
        }
    }
}

private struct SavingsRateHeroValue: View {
    let rate: Decimal
    var compact = false
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            Text(rate, format: .percent.precision(.fractionLength(1)))
                .font(.system(size: valueSize * (compact ? 0.94 : 1), weight: .bold))
                .tracking(-2)
                .foregroundStyle(rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings)
                .financeNumericMotion(rate)
                .minimumScaleFactor(0.55).lineLimit(1).monospacedDigit()
            Text(rate < 0 ? "Spese oltre le entrate" : rate == 0 ? "Entrate interamente spese" : "Margine sulle entrate")
                .font(.subheadline.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText)
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
                    SavingsRateHero(rate: rate)
                        .unifiedCard(tint: rate < 0 ? ForgiaPalette.deficit : ForgiaPalette.savings)
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
