//
//  SpendingRiskBanner.swift
//  Personal Finance
//
//  Avviso in evidenza mentre si inserisce una spesa: budget al limite o conto in negativo
//

import SwiftUI
import SwiftData
import FinanceCore

/// One reason the amount being typed deserves attention.
struct SpendingRisk: Identifiable, Equatable {
    enum Level: Int, Comparable {
        case near = 1, atLimit, over
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let level: Level
    let title: String
    let detail: String
    /// Budget name, when the risk comes from a budget: several of them collapse into one alert.
    var budgetName: String? = nil
}

/// Watches budgets and the account balance for a proposed expense and reports the worst level,
/// so the form can react (shake the amount, haptics) while the banner explains why.
struct SpendingRiskBanner: View {
    let amount: Decimal
    let categoryID: UUID?
    let accountID: UUID?
    let conto: Conto?
    let date: Date
    let currency: String
    var onLevelChange: (SpendingRisk.Level?) -> Void = { _ in }

    @Query(filter: #Predicate<Budget> { $0.isActive == true }) private var budgets: [Budget]
    @Query private var transactions: [FinanceTransaction]

    init(amount: Decimal, categoryID: UUID?, accountID: UUID?, conto: Conto?, date: Date, currency: String,
         onLevelChange: @escaping (SpendingRisk.Level?) -> Void = { _ in }) {
        self.amount = amount
        self.categoryID = categoryID
        self.accountID = accountID
        self.conto = conto
        self.date = date
        self.currency = currency
        self.onLevelChange = onLevelChange
        // Same bounded window as the budget preview: the year and week around the date.
        let calendar = Calendar.current
        let year = calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
        let week = calendar.dateInterval(of: .weekOfYear, for: date) ?? year
        let start = min(year.start, week.start)
        let end = max(year.end, week.end)
        let expense = TransactionType.expense.rawValue
        _transactions = Query(filter: #Predicate<FinanceTransaction> {
            $0.date >= start && $0.date < end && $0.typeRaw == expense
        })
    }

    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency)) }

    private var risks: [SpendingRisk] {
        guard amount > 0 else { return [] }
        var risks: [SpendingRisk] = []
        if let categoryID, let accountID {
            let previews = BudgetService.previewExpense(
                amount: amount, categoryID: categoryID, accountID: accountID, date: date,
                budgets: budgets, transactions: transactions, excludingTransactionID: nil
            )
            for preview in previews {
                switch preview.status {
                case .overLimit:
                    risks.append(SpendingRisk(id: "budget-\(preview.id)", level: .over,
                                              title: "Sforeresti «\(preview.name)»",
                                              detail: "Andresti oltre il limite di \(money(-preview.remaining)).",
                                              budgetName: preview.name))
                case .atLimit:
                    risks.append(SpendingRisk(id: "budget-\(preview.id)", level: .atLimit,
                                              title: "Esauriresti «\(preview.name)»",
                                              detail: "Dopo questa spesa il budget sarebbe a zero.",
                                              budgetName: preview.name))
                case .approachingLimit:
                    risks.append(SpendingRisk(id: "budget-\(preview.id)", level: .near,
                                              title: "Sei vicino al limite di «\(preview.name)»",
                                              detail: "Resterebbero \(money(preview.remaining)).",
                                              budgetName: preview.name))
                case .withinLimit:
                    break
                }
            }
        }
        // Credit cards normally run negative; for everything else a negative balance is worth flagging.
        if let conto, conto.type != .credit {
            let after = conto.balance - amount
            if after < 0 {
                risks.append(SpendingRisk(id: "balance-\(conto.id)", level: .over,
                                          title: "\(conto.name ?? "Il conto") andrebbe in negativo",
                                          detail: "Il saldo passerebbe da \(money(conto.balance)) a \(money(after))."))
            }
        }
        return risks.sorted { $0.level > $1.level }
    }

    @State private var budgetsExpanded = false

    var body: some View {
        let risks = risks
        let budgetRisks = risks.filter { $0.budgetName != nil }
        VStack(spacing: 8) {
            if budgetRisks.count > 1 {
                groupedBudgets(budgetRisks)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(budgetRisks.count > 1 ? risks.filter { $0.budgetName == nil } : risks) { risk in
                row(risk)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: risks)
        .onChange(of: risks.first?.level, initial: true) { _, level in onLevelChange(level) }
        .accessibilityIdentifier("spending-risk-banner")
    }

    /// Several budgets in trouble read as one alert; tapping it lists each one and by how much.
    private func groupedBudgets(_ risks: [SpendingRisk]) -> some View {
        let over = risks.filter { $0.level == .over }.count
        let worst = risks.map(\.level).max() ?? .near
        let title = over == risks.count ? "Sforeresti \(over) budget"
            : over > 0 ? "\(risks.count) budget oltre o vicini al limite"
            : "\(risks.count) budget vicini al limite"
        return Button {
            withAnimation(.snappy) { budgetsExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                header(level: worst, title: title,
                       detail: budgetsExpanded ? "Ecco quali e di quanto:" : "Tocca per vedere quali e di quanto.",
                       trailing: Image(systemName: "chevron.down").rotationEffect(.degrees(budgetsExpanded ? 180 : 0)))
                if budgetsExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(risks) { risk in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(risk.level == .over ? Color.red : Color.orange)
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(risk.budgetName ?? "Budget").font(.subheadline.weight(.semibold))
                                    Text(risk.detail).font(.subheadline).foregroundStyle(Color.primary.opacity(0.75))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(.leading, 48)
                    .transition(.opacity)
                }
            }
            .modifier(RiskBackground(severe: worst == .over))
        }
        .buttonStyle(.plain)
        .accessibilityHint(budgetsExpanded ? "Comprimi l'elenco" : "Mostra quali budget")
    }

    private func header<Trailing: View>(level: SpendingRisk.Level, title: String, detail: String, trailing: Trailing) -> some View {
        let severe = level == .over
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: severe ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(severe ? Color.red : Color.orange)
                .frame(width: 36, height: 36)
                .background(ForgiaPalette.surface.opacity(0.85), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)
                .padding(.top, 8)
        }
    }

    private func row(_ risk: SpendingRisk) -> some View {
        header(level: risk.level, title: risk.title, detail: risk.detail, trailing: EmptyView())
            .modifier(RiskBackground(severe: risk.level == .over))
            .accessibilityElement(children: .combine)
    }
}

private struct RiskBackground: ViewModifier {
    let severe: Bool

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(severe ? Color.red.opacity(0.12) : ForgiaPalette.apricotSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder((severe ? Color.red : Color.orange).opacity(0.35), lineWidth: 1)
            }
    }
}

/// Horizontal shake driven by an ever-increasing counter: each increment plays one shake.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}
