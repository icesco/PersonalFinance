import SwiftUI

struct TodayMarginHero: View {
    let margin: Decimal
    let available: Decimal
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize && available > 0 && margin >= 0 && margin <= available {
                FinancialRing(share: NSDecimalNumber(decimal: margin / available).doubleValue, tint: ForgiaPalette.margin) {
                    MarginHeroValue(margin: margin, currency: currency)
                }
                Text("L'anello mostra la quota del saldo, al netto delle carte, che resta dopo le uscite stimate.")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    .multilineTextAlignment(.center)
            } else {
                MarginHeroValue(margin: margin, currency: currency).padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MarginHeroValue: View {
    let margin: Decimal
    let currency: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    var body: some View {
        VStack(spacing: 6) {
            Text(margin, format: .currency(code: currency))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .financeNumericMotion(margin)
                .minimumScaleFactor(0.6).lineLimit(1).monospacedDigit()
                .foregroundStyle(margin >= 0 ? ForgiaPalette.margin : ForgiaPalette.deficit)
            Text("Margine stimato")
                .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
        }.accessibilityElement(children: .combine)
    }
}
