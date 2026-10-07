//
//  BudgetView.swift
//  Personal Finance
//
//  Created by Claude on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore

/// Everything a budget card shows, computed once: the model's figures recalculate on each access.
struct BudgetSnapshot {
    enum Status { case onTrack, warning, over }

    let limit: Decimal
    let spent: Decimal
    let threshold: Double
    let outlook: BudgetOutlook
    let currency: String
    let periodRange: (start: Date, end: Date)

    init(_ budget: FinanceBudget) {
        limit = budget.amount ?? 0
        periodRange = budget.currentPeriodRange
        spent = budget.getSpent(for: periodRange)
        threshold = budget.alertThreshold ?? 0.8
        outlook = budget.spendingOutlook()
        currency = budget.account?.currency ?? "EUR"
    }

    var remaining: Decimal { limit - spent }
    var share: Double { limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0 }
    var status: Status { spent > limit ? .over : share >= threshold ? .warning : .onTrack }

    var color: Color {
        switch status {
        case .onTrack: ForgiaPalette.accent
        case .warning: .orange
        case .over: .red
        }
    }

    var statusLabel: (text: String, icon: String) {
        switch status {
        case .onTrack: ("In linea", "checkmark.circle.fill")
        case .warning: ("Da tenere d'occhio", "exclamationmark.circle.fill")
        case .over: ("Superato", "exclamationmark.triangle.fill")
        }
    }

    func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }
}

struct BudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @State private var showingCreateBudget = false
    @State private var selectedBudget: FinanceBudget?
    @State private var showingSaveError = false

    private var budgets: [FinanceBudget] {
        (appState.selectedAccount?.budgets?.filter { $0.isActive == true } ?? [])
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var archived: [FinanceBudget] {
        (appState.selectedAccount?.budgets ?? []).filter { $0.isActive == false }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let snapshots = budgets.map { ($0, BudgetSnapshot($0)) }
                    if snapshots.isEmpty {
                        emptyState
                    } else {
                        overview(snapshots.map(\.1))
                        ForEach(snapshots, id: \.0.id) { budget, snapshot in
                            Button { selectedBudget = budget } label: {
                                BudgetCard(budget: budget, snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !archived.isEmpty {
                        archivedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .financeEmptyOverlay(isPresented: budgets.isEmpty && archived.isEmpty) { emptyState }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fine") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateBudget = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nuovo budget")
                }
            }
        }
        .financePresentation(isPresented: $showingCreateBudget, title: "Nuovo budget") {
            if let account = appState.selectedAccount {
                CreateBudgetView(account: account)
            }
        }
        .financePresentation(item: $selectedBudget, title: "Budget") { budget in
            BudgetDetailView(budget: budget)
        }
        .alert("Impossibile salvare", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: { Text("La modifica non è stata salvata. Riprova.") }
    }

    // MARK: - Overview

    private func overview(_ snapshots: [BudgetSnapshot]) -> some View {
        let over = snapshots.filter { $0.status == .over }.count
        let warning = snapshots.filter { $0.status == .warning }.count
        let onTrack = snapshots.count - over - warning
        let tint = over > 0 ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface
        return VStack(alignment: .leading, spacing: 12) {
            Text(snapshots.count == 1 ? "1 BUDGET ATTIVO" : "\(snapshots.count) BUDGET ATTIVI")
                .font(.caption2.weight(.semibold)).tracking(1.1)
                .foregroundStyle(ForgiaPalette.mutedText)
            Text(over > 0 ? (over == 1 ? "Un budget è oltre il limite" : "\(over) budget sono oltre il limite")
                 : warning > 0 ? "Quasi tutto sotto controllo" : "Tutto sotto controllo")
                .font(.system(.title2, design: .serif, weight: .semibold))
            HStack(spacing: 8) {
                statusCount(onTrack, "In linea", "checkmark.circle.fill", ForgiaPalette.accent)
                statusCount(warning, "Attenzione", "exclamationmark.circle.fill", .orange)
                statusCount(over, "Superati", "exclamationmark.triangle.fill", .red)
            }
            Text("Ogni limite vale per il proprio periodo e le categorie scelte. Una spesa può rientrare in più budget.")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint, tint.mix(with: ForgiaPalette.surface, by: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
    }

    private func statusCount(_ count: Int, _ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(count)").monospacedDigit().fontWeight(.semibold)
            Text(title)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ForgiaPalette.surface.opacity(0.85), in: Capsule())
        .opacity(count == 0 ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Archived

    private var archivedSection: some View {
        FormCard(title: "Disattivati") {
            ForEach(Array(archived.enumerated()), id: \.element.id) { index, budget in
                if index > 0 { FormRowDivider() }
                FormRow(icon: "archivebox") {
                    Text(budget.name ?? "Budget")
                        .foregroundStyle(ForgiaPalette.mutedText)
                    Spacer(minLength: 8)
                    Button("Riattiva") {
                        do { try BudgetEdits(context: modelContext).setActive(true, for: budget) }
                        catch { showingSaveError = true }
                    }
                    .buttonStyle(.borderless)
                    .tint(ForgiaPalette.accent)
                    .accessibilityLabel("Riattiva \(budget.name ?? "budget")")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 72, height: 72)
                .background(ForgiaPalette.sageSurface, in: Circle())
            Text("Nessun budget attivo")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("Dai un limite alle categorie che vuoi tenere d'occhio: qui vedrai quanto ti resta in ogni periodo.")
                .font(.subheadline)
                .foregroundStyle(ForgiaPalette.mutedText)
                .multilineTextAlignment(.center)
            #if os(macOS)
            Button("Crea il primo budget", systemImage: "plus") { showingCreateBudget = true }
                .buttonStyle(.borderedProminent)
                .tint(ForgiaPalette.accent)
            #else
            Button {
                showingCreateBudget = true
            } label: {
                Text("Crea il primo budget")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(ForgiaPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(ForgiaPalette.onAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            #endif
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .unifiedCard()
    }
}

// MARK: - Budget Card

struct BudgetCard: View {
    let budget: FinanceBudget
    let snapshot: BudgetSnapshot

    private var categories: [FinanceCategory] {
        FinanceCategory.displayOrdered(budget.categories ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BudgetIcon(category: categories.first)
                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name ?? "Budget")
                        .font(.headline)
                        .lineLimit(1)
                    Text(periodText)
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                }
                Spacer(minLength: 8)
                BudgetStatusPill(snapshot: snapshot)
            }

            Text(snapshot.status == .over ? "Oltre di \(snapshot.money(-snapshot.remaining))" : "Restano \(snapshot.money(snapshot.remaining))")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(snapshot.status == .over ? Color.red : Color.primary)

            BudgetMeter(snapshot: snapshot)

            ViewThatFits(in: .horizontal) {
                HStack {
                    spentText
                    Spacer(minLength: 8)
                    dailyText
                }
                VStack(alignment: .leading, spacing: 4) {
                    spentText
                    dailyText
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(ForgiaPalette.mutedText)

            if !categories.isEmpty {
                HStack(spacing: 6) {
                    ForEach(categories.prefix(3), id: \.id) { CategoryChip(category: $0) }
                    if categories.count > 3 {
                        Text("+\(categories.count - 3)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.mutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(ForgiaPalette.canvas, in: Capsule())
                    }
                }
            }
        }
        .unifiedCard()
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre il dettaglio del budget")
    }

    private var spentText: Text {
        Text("Speso \(snapshot.money(snapshot.spent)) su \(snapshot.money(snapshot.limit))")
    }

    @ViewBuilder
    private var dailyText: some View {
        if snapshot.status != .over, snapshot.outlook.daysRemaining > 0 {
            Text("≈ \(snapshot.money(snapshot.outlook.dailyAllowance)) al giorno")
        }
    }

    private var periodText: String {
        let period = budget.period?.displayName ?? "Periodo"
        let days = snapshot.outlook.daysRemaining
        if days <= 0 { return "\(period) · periodo concluso" }
        return days == 1 ? "\(period) · ultimo giorno" : "\(period) · \(days) giorni rimasti"
    }
}

/// Spending against the limit, with a tick where the alert fires.
struct BudgetMeter: View {
    let snapshot: BudgetSnapshot
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ForgiaPalette.canvas)
                Capsule()
                    .fill(snapshot.color)
                    .frame(width: max(height, proxy.size.width * min(snapshot.share, 1)))
                Rectangle()
                    .fill(ForgiaPalette.mutedText.opacity(0.5))
                    .frame(width: 2, height: height + 6)
                    .offset(x: proxy.size.width * snapshot.threshold - 1)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct BudgetStatusPill: View {
    let snapshot: BudgetSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.statusLabel.icon).foregroundStyle(snapshot.color)
            Text(snapshot.statusLabel.text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ForgiaPalette.canvas, in: Capsule())
    }
}

/// The budget's lead category icon, in that category's colour.
struct BudgetIcon: View {
    let category: FinanceCategory?
    var size: CGFloat = 42

    var body: some View {
        let color = (category?.tint ?? Color(hex: CategoryPalette.fallback))
        Image(systemName: category?.icon?.isEmpty == false ? category!.icon! : "target")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: FinanceCategory

    var body: some View {
        HStack(spacing: 4) {
            if let icon = category.icon, !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundStyle(category.tint)
            }
            Text(category.name ?? "")
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(ForgiaPalette.canvas, in: Capsule())
    }
}

// MARK: - Budget Detail View

struct BudgetDetailView: View {
    let budget: FinanceBudget
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingArchive = false
    @State private var showingSaveError = false

    private var categories: [FinanceCategory] {
        FinanceCategory.displayOrdered(budget.categories ?? [])
    }

    var body: some View {
        let snapshot = BudgetSnapshot(budget)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(snapshot)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MetricTile(title: snapshot.status == .over ? "Oltre il limite" : "Rimanente",
                                   value: snapshot.money(abs(snapshot.remaining)),
                                   icon: "wallet.pass",
                                   tint: snapshot.status == .over ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface)
                        MetricTile(title: "Giorni rimasti", value: "\(max(snapshot.outlook.daysRemaining, 0))",
                                   icon: "calendar", tint: ForgiaPalette.canvas)
                        MetricTile(title: "Margine al giorno", value: snapshot.money(snapshot.outlook.dailyAllowance),
                                   icon: "sun.max", tint: ForgiaPalette.sageSurface)
                        MetricTile(title: "Stima fine periodo",
                                   value: snapshot.outlook.projectedTotal.map(snapshot.money) ?? "—",
                                   icon: "chart.line.uptrend.xyaxis",
                                   tint: (snapshot.outlook.projectedTotal ?? 0) > snapshot.limit ? ForgiaPalette.apricotSurface : ForgiaPalette.canvas)
                    }

                    Text("Il margine considera tutte le spese registrate nel periodo, anche future. La stima usa il ritmo delle spese variabili dei giorni conclusi e le ricorrenti già registrate; non aggiunge ricorrenze ancora da registrare. Disponibile dopo il primo giorno completo.")
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .padding(.horizontal, 4)

                    if !categories.isEmpty {
                        FormCard(title: "Categorie incluse") {
                            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                if index > 0 { FormRowDivider() }
                                HStack(spacing: 14) {
                                    BudgetIcon(category: category, size: 38)
                                    Text(category.name ?? "Categoria")
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 58)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationTitle(budget.name ?? "Budget")
            .toolbarTitleDisplayMode(.inline)
            .financePresentation(isPresented: $showingEdit, title: "Modifica budget") {
                if let account = budget.account {
                    if budget.planningGroupRaw != nil { BudgetingSetupView(account: account) }
                    else { CreateBudgetView(account: account, budget: budget) }
                }
            }
            .confirmationDialog("Disattivare questo budget?", isPresented: $confirmingArchive, titleVisibility: .visible) {
                Button("Disattiva budget", role: .destructive) {
                    do {
                        try BudgetEdits(context: modelContext).setActive(false, for: budget)
                        dismiss()
                    } catch { showingSaveError = true }
                }
            } message: {
                Text("Non riceverai più avvisi per questo budget. Le transazioni restano e potrai riattivarlo dai budget disattivati.")
            }
            .alert("Impossibile salvare", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text("Il budget non è stato disattivato. Riprova.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Modifica", systemImage: "pencil") { showingEdit = true }
                        Button("Disattiva budget", systemImage: "archivebox", role: .destructive) { confirmingArchive = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Azioni budget")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func hero(_ snapshot: BudgetSnapshot) -> some View {
        let tint = snapshot.status == .over ? ForgiaPalette.apricotSurface : ForgiaPalette.sageSurface
        let locale = Locale(identifier: "it_IT")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SPESO IN QUESTO PERIODO")
                    .font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Spacer(minLength: 8)
                BudgetStatusPill(snapshot: snapshot)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.money(snapshot.spent))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(snapshot.status == .over ? Color.red : Color.primary)
                Text("su \(snapshot.money(snapshot.limit))")
                    .font(.subheadline)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
            BudgetMeter(snapshot: snapshot, height: 10)
            HStack {
                Text("\(snapshot.periodRange.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(snapshot.periodRange.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))")
                Spacer(minLength: 8)
                Text("Avviso al \(Int((snapshot.threshold * 100).rounded()))%")
            }
            .font(.caption)
            .foregroundStyle(ForgiaPalette.mutedText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint, tint.mix(with: ForgiaPalette.surface, by: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
    }
}

/// A figure with its tinted icon, in the shape of the quick-action tiles.
private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForgiaPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(ForgiaPalette.border, lineWidth: 0.7) }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BudgetView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
