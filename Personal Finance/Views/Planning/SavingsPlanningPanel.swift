import SwiftUI
import SwiftData
import FinanceCore

struct SavingsPlanningPanel: View {
    let account: Account
    @Query private var transactions: [FinanceTransaction]
    @State private var showingSetup = false
    @State private var showingGuides = false
    @State private var startsManual = false

    init(account: Account) {
        self.account = account
        let interval = Calendar.current.dateInterval(of: .month, for: Date())!
        let start = interval.start, end = interval.end
        _transactions = Query(filter: #Predicate<FinanceTransaction> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Il tuo piano di risparmio", systemImage: "leaf")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
            if let plan = account.budgetingPlan {
                Text(plan.method.title).font(.headline)
                Button("Modifica il piano e il calcolo") { startsManual = false; showingSetup = true }
                    .buttonStyle(.bordered).accessibilityIdentifier("planning-edit-method")
                if _transactions.fetchError != nil {
                    Label("Dati del mese non disponibili", systemImage: "exclamationmark.circle")
                } else {
                    let report = MonthlySavingsReport(account: account, transactions: transactions,
                        interval: Calendar.current.dateInterval(of: .month, for: Date())!, through: Date())
                    if report.hasInvalidAmounts {
                        Text("Alcuni movimenti hanno importi mancanti o non validi. Controllali prima di leggere margine e accantonamenti.")
                            .foregroundStyle(.secondary)
                    } else {
                        SavingsMonthSummary(plan: plan, report: report, currency: account.currency ?? "EUR")
                    }
                }
            } else {
                Text("Vuoi una mano a organizzare il tuo budget?").font(.headline)
                Button("Scopri i metodi") { startsManual = false; showingSetup = true }
                    .buttonStyle(.borderedProminent).tint(ForgiaPalette.accent)
                    .accessibilityIdentifier("planning-discover-methods")
                Button("Preferisco gestirlo da solo") { startsManual = true; showingSetup = true }
                    .buttonStyle(.bordered)
            }
            Button { showingGuides = true } label: { Label("Come funziona e consigli", systemImage: "info.circle") }
                .accessibilityIdentifier("planning-savings-guides")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
        .financePresentation(isPresented: $showingSetup, title: "Piano di risparmio", width: 720) {
            BudgetingSetupView(account: account, startsManual: startsManual)
        }
        .financePresentation(isPresented: $showingGuides, title: "Come funziona", width: 680) {
            SavingsExplanationView(plan: account.budgetingPlan,
                monthlyReport: _transactions.fetchError == nil ? MonthlySavingsReport(account: account, transactions: transactions,
                    interval: Calendar.current.dateInterval(of: .month, for: Date())!, through: Date()) : nil, currency: account.currency ?? "EUR")
        }
    }
}

private struct SavingsMonthSummary: View {
    let plan: BudgetingPlan
    let report: MonthlySavingsReport
    let currency: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questo mese, fino a oggi").font(.subheadline).foregroundStyle(.secondary)
            SavingsAmountRow(title: "Entrate registrate", amount: report.income, currency: currency)
            SavingsAmountRow(title: "Spese registrate", amount: report.expenses, currency: currency)
            SavingsAmountRow(title: "Margine del mese", amount: report.margin, currency: currency)
            SavingsAssessmentBadge(assessment: .margin(income: report.income, expenses: report.expenses), isInProgress: true)
            Divider()
            if plan.method != .manual {
                Text("Il mese rispetto al tuo piano").font(.headline)
                SavingsComparisonChart(title: "Necessità", actual: report.needsSpent,
                    reference: plan.roundedLimit(for: .needs, currency: currency), currency: currency,
                    isCeiling: true, isInProgress: true)
                SavingsComparisonChart(title: "Desideri", actual: report.wantsSpent,
                    reference: plan.roundedLimit(for: .wants, currency: currency), currency: currency,
                    isCeiling: true, isInProgress: true)
                if report.unclassifiedExpenses != 0 {
                    SavingsAmountRow(title: "Spese da classificare", amount: report.unclassifiedExpenses, currency: currency)
                }
            }
            SavingsComparisonChart(title: "Accantonamenti netti", actual: report.netSetAside,
                reference: plan.method == .manual ? nil : plan.roundedSavingsTarget(currency: currency), currency: currency,
                isCeiling: false, isInProgress: true)
            if report.needsSavingsReview {
                Label("Rivedi i conti scelti dal pulsante di modifica", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

        }
    }
}

struct SavingsAmountRow: View {
    let title: LocalizedStringResource
    let amount: Decimal
    let currency: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(amount, format: .currency(code: currency).locale(locale)).monospacedDigit().fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

extension BudgetingMethod {
    var title: LocalizedStringResource {
        switch self {
        case .fiftyThirtyTwenty: "Regola 50/30/20"
        case .custom: "Percentuali personalizzate"
        case .manual: "Gestione manuale"
        }
    }
    var explanation: LocalizedStringResource {
        switch self {
        case .fiftyThirtyTwenty: "50% alle necessità, 30% ai desideri, 20% al risparmio. Un punto di partenza da adattare alla tua situazione."
        case .custom: "Decidi quanto destinare a necessità e desideri. Il resto diventa il tuo obiettivo di risparmio."
        case .manual: "Mantieni i tuoi budget e scegli, se vuoi, come misurare gli accantonamenti."
        }
    }
}
