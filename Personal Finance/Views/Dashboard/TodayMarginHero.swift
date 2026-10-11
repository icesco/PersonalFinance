import SwiftUI

struct TodayMarginHero: View {
    let margin: Decimal
    let available: Decimal
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var hasBoundedShare: Bool { available > 0 && margin >= 0 && margin <= available }
    private var share: Double { NSDecimalNumber(decimal: margin / available).doubleValue }

    var body: some View {
        VStack(spacing: 18) {
            if !dynamicTypeSize.isAccessibilitySize && hasBoundedShare {
                FinancialRing(share: share, tint: ForgiaPalette.margin) {
                    MarginHeroValue(margin: margin, currency: currency, share: share)
                }
            } else {
                MarginHeroValue(margin: margin, currency: currency,
                                share: hasBoundedShare ? share : nil)
                    .padding(.vertical, 20)
            }
            if hasBoundedShare {
                MarginHeroBreakdown(available: available, outgoings: available - margin, currency: currency)
                Text("La quota del saldo netto che resta dopo le uscite stimate.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MarginHeroValue: View {
    let margin: Decimal
    let currency: String
    let share: Double?
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 10) {
            Text("Margine stimato")
                .font(.subheadline.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText)
            Text(margin, format: .currency(code: currency))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .financeNumericMotion(margin)
                .minimumScaleFactor(0.55).lineLimit(1).monospacedDigit()
                .foregroundStyle(margin >= 0 ? ForgiaPalette.margin : ForgiaPalette.deficit)
            if let share {
                HStack(spacing: 4) {
                    Text(share, format: .percent.precision(.fractionLength(0))).fontWeight(.bold)
                    Text("del saldo netto")
                }
                .font(.caption).foregroundStyle(ForgiaPalette.margin)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(ForgiaPalette.margin.opacity(0.1), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MarginHeroBreakdown: View {
    let available: Decimal
    let outgoings: Decimal
    let currency: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            MarginHeroReference(title: "Saldo netto", amount: available, currency: currency,
                                tint: ForgiaPalette.margin, icon: "wallet.bifold")
            MarginHeroReference(title: "Uscite stimate", amount: outgoings, currency: currency,
                                tint: ForgiaPalette.spending, icon: "arrow.up.right")
        }
        .padding(14)
        .background(ForgiaPalette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MarginHeroReference: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let currency: String
    let tint: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            Text(amount, format: .currency(code: currency))
                .font(.system(.headline, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
