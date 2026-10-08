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

            VStack(spacing: 12) {
                ForEach(ranked.prefix(2), id: \.id) { item in
                    row(item)
                }
            }
        }
        .unifiedCard()
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    private func row(_ snapshot: TodayBudgetSnapshot) -> some View {
        let color = Color(hex: snapshot.colorHex)
        return HStack(spacing: 12) {
            Image(systemName: snapshot.icon)
                .font(.system(size: 15.2, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(snapshot.status == .over ? "Oltre di \(snapshot.money(-snapshot.remaining))"
                         : "Restano \(snapshot.money(snapshot.remaining))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(snapshot.status == .over ? Color.red : ForgiaPalette.mutedText)
                }
                BudgetMeter(share: snapshot.share, threshold: snapshot.threshold, color: snapshot.color, height: 6)
            }
        }
        .accessibilityElement(children: .combine)
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
