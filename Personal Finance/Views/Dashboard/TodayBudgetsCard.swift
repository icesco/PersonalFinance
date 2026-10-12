//
//  TodayBudgetsCard.swift
//  Personal Finance
//
//  Budget a colpo d'occhio nella schermata Oggi: i più a rischio per primi
//

import SwiftUI
import FinanceCore

struct TodayBudgetsCard: View {
    let budgets: [TodayBudgetSnapshot]
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            if budgets.isEmpty { invitation } else { summary(budgets) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-budgets")
    }

    private func summary(_ ranked: [TodayBudgetSnapshot]) -> some View {
        let over = ranked.filter { $0.status == .over }.count
        let warning = ranked.filter { $0.status == .warning }.count
        return VStack(alignment: .leading, spacing: 14) {
            AnalysisPreviewHeading(title: "I tuoi budget", icon: "target", tint: ForgiaPalette.accent,
                                   accessory: ranked.count > 2 ? "Vedi tutti (\(ranked.count))" : nil)

            Label {
                Text(over > 0 ? (over == 1 ? "Un budget è oltre il limite" : "\(over) budget oltre il limite")
                 : warning > 0 ? (warning == 1 ? "Un budget vicino al limite" : "\(warning) budget vicini al limite")
                 : "Tutti i budget sono in linea")
            } icon: {
                Image(systemName: over > 0 ? "exclamationmark.circle.fill" : warning > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(over > 0 ? ForgiaPalette.deficit : warning > 0 ? Color.orange : ForgiaPalette.margin)
            }
            .font(.system(.title3, design: .serif, weight: .semibold))

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(ranked.prefix(2), id: \.id) { item in
                    TodayBudgetTile(snapshot: item)
                }
            }
        }
        .foregroundStyle(.primary)
        .unifiedCard(tint: ForgiaPalette.accent)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .financeCardEntrance()
    }

    private var invitation: some View {
        HStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 48, height: 48)
                .background(ForgiaPalette.sageSurface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Imposta un budget")
                    .font(.headline)
                Text("Dai un limite alle categorie che vuoi tenere d'occhio.")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.accent)
        }
        .unifiedCard()
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct TodayBudgetTile: View {
    let snapshot: TodayBudgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: snapshot.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: snapshot.colorHex))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: snapshot.colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(snapshot.name).font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(snapshot.spent, format: .currency(code: snapshot.currency))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit().foregroundStyle(snapshot.color)
                Text("/ \(snapshot.money(snapshot.limit))")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            BudgetMeter(share: snapshot.share, threshold: snapshot.threshold, color: snapshot.color, height: 6)
                .accessibilityHidden(true)
            Text(snapshot.status == .over ? "Oltre di \(snapshot.money(-snapshot.remaining))"
                 : "Restano \(snapshot.money(snapshot.remaining))")
                .font(.caption.weight(.medium))
                .foregroundStyle(snapshot.status == .over ? ForgiaPalette.deficit : ForgiaPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .cardInset(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

private extension TodayBudgetSnapshot {
    enum Status { case onTrack, warning, over }
    var status: Status { spent > limit ? .over : share >= threshold ? .warning : .onTrack }
    var color: Color {
        switch status {
        case .onTrack: ForgiaPalette.accent
        case .warning: .orange
        case .over: ForgiaPalette.deficit
        }
    }
    func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }
}
