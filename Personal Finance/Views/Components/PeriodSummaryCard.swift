//
//  PeriodSummaryCard.swift
//  Personal Finance
//
//  Bilancio del periodo nella lista movimenti: saldo, entrate, uscite e quota spesa
//

import SwiftUI
import FinanceCore

struct PeriodSummaryCard: View {
    let title: String
    let summary: TransactionListSummary
    let currency: String
    let includesFuture: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The card heads the list: a sage wash when the period is in credit, apricot when it is not.
    static func background(balance: Decimal) -> LinearGradient {
        let tint = balance >= 0 ? ForgiaPalette.sageSurface : ForgiaPalette.apricotSurface
        return LinearGradient(
            colors: [tint, tint.mix(with: ForgiaPalette.surface, by: 0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var balance: Decimal { summary.balance }

    /// Share of income already spent; nil when there is no income to compare against.
    private var spentShare: Double? {
        guard summary.income > 0 else { return nil }
        return NSDecimalNumber(decimal: summary.expenses / summary.income).doubleValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                Spacer(minLength: 8)
                Text(summary.count == 1 ? "1 movimento" : "\(summary.count) movimenti")
                    .font(.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(summary.count)))
            }
            .foregroundStyle(ForgiaPalette.mutedText)

            Text((balance > 0 ? "+" : "") + balance.formatted(.currency(code: currency)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(balance >= 0 ? ForgiaPalette.accent : Color.primary)
                .contentTransition(.numericText(value: Self.double(balance)))
                .accessibilityLabel("Saldo \(balance.formatted(.currency(code: currency)))")

            if let spentShare {
                spendingMeter(spentShare)
                    .transition(.opacity)
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                metric("Entrate", amount: summary.income, icon: "arrow.down.left",
                       tint: ForgiaPalette.sageSurface, foreground: ForgiaPalette.accent)
                metric("Uscite", amount: summary.expenses, icon: "arrow.up.right",
                       tint: ForgiaPalette.apricotSurface, foreground: Color.primary)
            }

            if includesFuture {
                Label("Include movimenti con data futura", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        // Scoped to the card: the rows below update without animation.
        .animation(.snappy, value: summary)
        .animation(.snappy, value: title)
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func spendingMeter(_ share: Double) -> some View {
        let overspent = share > 1
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgiaPalette.surface.opacity(0.8))
                    Capsule()
                        .fill(overspent ? Color.red.opacity(0.75) : ForgiaPalette.accent)
                        .frame(width: max(6, proxy.size.width * min(share, 1)))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            Text(overspent
                 ? "Hai speso più di quanto è entrato: \(share.formatted(.percent.precision(.fractionLength(0))))"
                 : "Hai speso il \(share.formatted(.percent.precision(.fractionLength(0)))) delle entrate")
                .font(.caption)
                .foregroundStyle(overspent ? Color.red : ForgiaPalette.mutedText)
        }
    }

    private func metric(_ title: String, amount: Decimal, icon: String, tint: Color, foreground: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 32, height: 32)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(amount.formatted(.currency(code: currency)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(foreground)
                    .contentTransition(.numericText(value: Self.double(amount)))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForgiaPalette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
