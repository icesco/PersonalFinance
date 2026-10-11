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
            HStack(alignment: .firstTextBaseline) {
                Text("I TUOI BUDGET")
                    .font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(ranked.count > 2 ? "Vedi tutti (\(ranked.count))" : "Apri")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.accent)
            }

            Text(over > 0 ? (over == 1 ? "Un budget è oltre il limite" : "\(over) budget oltre il limite")
                 : warning > 0 ? (warning == 1 ? "Un budget vicino al limite" : "\(warning) budget vicini al limite")
                 : "Tutti i budget sono in linea")
                .font(.system(.title3, design: .serif, weight: .semibold))

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(ranked.prefix(2), id: \.id) { item in
                    TodayBudgetTile(snapshot: item)
                }
            }
        }
        .unifiedCard(tint: ForgiaPalette.accent)
        .contentShape(RoundedRectangle(cornerRadius: 22))
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
            HStack(alignment: .top) {
                Text(snapshot.name).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: snapshot.icon)
                    .foregroundStyle(Color(hex: snapshot.colorHex))
                    .accessibilityHidden(true)
            }
            Text(snapshot.spent, format: .currency(code: snapshot.currency))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().foregroundStyle(snapshot.color)
                .lineLimit(1).minimumScaleFactor(0.75)
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
        .background(ForgiaPalette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
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
        case .over: .red
        }
    }
    func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }
}
