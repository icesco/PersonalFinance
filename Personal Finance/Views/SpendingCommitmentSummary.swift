import SwiftUI
import FinanceCore

struct SpendingCommitmentSummary: View {
    let direction: SpendingDirection
    let currency: String
    var scopeContoIDs: Set<UUID>? = nil

    /// One colour family per card: the brand accent, with a lighter shade for the variable share.
    private var tint: Color { ForgiaPalette.accent }
    private var variableTint: Color { ForgiaPalette.accent.opacity(0.35) }

    private var total: Decimal { direction.recentRecurringExpenses + direction.recentVariableExpenses }
    private var recurringShare: Double {
        total > 0 ? NSDecimalNumber(decimal: direction.recentRecurringExpenses / total).doubleValue : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalysisPreviewHeading(title: "Ricorrenti e variabili", icon: "repeat", tint: tint,
                                   accessory: "30 giorni", showsChevron: false)
            HStack(alignment: .top, spacing: 12) {
                amountColumn("Ricorrenti", amount: direction.recentRecurringExpenses, tint: tint)
                amountColumn("Variabili", amount: direction.recentVariableExpenses, tint: variableTint)
            }
            if total > 0 {
                splitBar
            }
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(tint)
                Text("Ricorrenti previste nei prossimi 30 giorni")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(direction.upcoming30DaysRecurringExpenses, format: .currency(code: currency))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(12)
            .cardInset()
            .accessibilityElement(children: .combine)
            if direction.availability != .staleData,
               let category = direction.largestVariableOutflow, category.amount > 0 {
                suggestion(category)
            }
            Text("Le ricorrenti sono le spese che hai contrassegnato come tali.")
                .font(.caption2).foregroundStyle(ForgiaPalette.mutedText)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard(tint: tint)
        .financeCardEntrance()
    }

    private func amountColumn(_ title: LocalizedStringKey, amount: Decimal, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(ForgiaPalette.mutedText)
            }
            Text(amount, format: .currency(code: currency))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .financeNumericMotion(amount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var splitBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                if recurringShare > 0 {
                    Capsule().fill(tint)
                        .frame(width: max(4, (proxy.size.width - 3) * recurringShare))
                }
                if recurringShare < 1 {
                    Capsule().fill(variableTint)
                }
            }
        }
        .frame(height: 8)
        .financeChartReveal()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func suggestion(_ category: CategoryOutflow) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.subheadline)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Da dove iniziare?").font(.subheadline.weight(.semibold))
                Text("\(category.name) è la variabile che pesa di più: \(category.amount, format: .currency(code: currency)).")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if category.categoryID != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(ForgiaPalette.mutedText).accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))

        if let categoryID = category.categoryID {
            NavigationLink {
                TransactionListView(initialCategoryID: categoryID, initialInterval: DateInterval(start: Calendar.current.date(byAdding: .day, value: -30, to: Date())!, end: Date()), expensesOnly: true, scopeContoIDs: scopeContoIDs,
                                    isPushed: true, pushedTitle: category.name)
            } label: { content }
            .buttonStyle(.plain)
            .accessibilityHint("Rivedi questa categoria")
        } else {
            content
        }
    }
}

struct PurchaseCheckView: View {
    let margin: Decimal?
    let currency: String
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    private var amount: Decimal? {
        guard let value = MarginScenario.expense(from: amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quanto vorresti spendere?") {
                    TextField("Importo in \(currency)", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("purchase-check-amount")
                }
                if let margin, let amount {
                    Section("Dopo questa spesa") {
                        Text(margin - amount, format: .currency(code: currency))
                            .font(.largeTitle.bold()).monospacedDigit()
                            .foregroundStyle(margin >= amount ? ForgiaPalette.accent : .red)
                        Text(margin >= amount
                             ? "La spesa rientra nel margine stimato."
                             : "La spesa supera il margine stimato: valuta di ridurla o rimandarla.")
                        Text("Il calcolo tiene già conto delle scadenze e delle spese abituali stimate fino alla prossima entrata. Non registra alcun movimento e dipende dalla completezza dei tuoi dati.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(margin == nil ? "Completa i dati nella Home per valutare una spesa." : "Inserisci un importo maggiore di zero.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Valuta una spesa")
            .toolbar {
                FinanceDismissToolbar(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}
