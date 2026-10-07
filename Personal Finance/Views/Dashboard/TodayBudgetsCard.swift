//
//  TodayBudgetsCard.swift
//  Personal Finance
//
//  Budget a colpo d'occhio nella schermata Oggi: i più a rischio per primi
//

import SwiftUI
import FinanceCore

struct TodayBudgetsCard: View {
    let budgets: [FinanceBudget]
    let onOpen: () -> Void

    /// Most at risk first: over the limit, then by share of the limit already spent.
    private var ranked: [(budget: FinanceBudget, snapshot: BudgetSnapshot)] {
        budgets.map { ($0, BudgetSnapshot($0)) }.sorted { lhs, rhs in
            let left = lhs.snapshot.status == .over ? 1 : 0
            let right = rhs.snapshot.status == .over ? 1 : 0
            return left != right ? left > right : lhs.snapshot.share > rhs.snapshot.share
        }
    }

    var body: some View {
        Button(action: onOpen) {
            if budgets.isEmpty { invitation } else { summary(ranked) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-budgets")
    }

    private func summary(_ ranked: [(budget: FinanceBudget, snapshot: BudgetSnapshot)]) -> some View {
        let over = ranked.filter { $0.snapshot.status == .over }.count
        let warning = ranked.filter { $0.snapshot.status == .warning }.count
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
                ForEach(ranked.prefix(2), id: \.budget.id) { item in
                    row(item.budget, item.snapshot)
                }
            }
        }
        .unifiedCard()
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    private func row(_ budget: FinanceBudget, _ snapshot: BudgetSnapshot) -> some View {
        let lead = FinanceCategory.displayOrdered(budget.categories ?? []).first
        return HStack(spacing: 12) {
            BudgetIcon(category: lead, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(budget.name ?? "Budget")
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
                BudgetMeter(snapshot: snapshot, height: 6)
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
