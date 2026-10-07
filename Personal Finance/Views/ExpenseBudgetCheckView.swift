import SwiftUI
import SwiftData
import FinanceCore

/// Reactive preview scoped to the year/week of the proposed date, not the whole archive.
struct ExpenseBudgetCheckView: View {
    let amount: Decimal
    let categoryID: UUID
    let accountID: UUID
    let date: Date
    let currency: String
    let isRecurring: Bool
    let excludingTransactionID: UUID?
    let compact: Bool
    @Query(filter: #Predicate<Budget> { $0.isActive == true }) private var budgets: [Budget]
    @Query private var transactions: [FinanceTransaction]

    init(amount: Decimal, categoryID: UUID, accountID: UUID, date: Date, currency: String, isRecurring: Bool, excludingTransactionID: UUID? = nil, compact: Bool = false) {
        self.amount = amount
        self.categoryID = categoryID
        self.accountID = accountID
        self.date = date
        self.currency = currency
        self.isRecurring = isRecurring
        self.excludingTransactionID = excludingTransactionID
        self.compact = compact
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

    var body: some View {
        let previews = BudgetService.previewExpense(
            amount: amount, categoryID: categoryID, accountID: accountID, date: date,
            budgets: budgets, transactions: transactions, excludingTransactionID: excludingTransactionID
        )
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                if _budgets.fetchError != nil || _transactions.fetchError != nil {
                    Label("Verifica del budget non disponibile", systemImage: "exclamationmark.circle")
                } else if let preview = previews.first {
                    ExpenseBudgetResultRow(preview: preview, currency: currency, compact: true)
                    if previews.count > 1 {
                        Text("Altri \(previews.count - 1) budget nel dettaglio del modulo.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Nessun budget per questa categoria", systemImage: "info.circle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("expense-budget-compact")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.shield")
                    Text(excludingTransactionID == nil ? "PRIMA DI SPENDERE" : "PRIMA DI SALVARE")
                        .tracking(1.1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ForgiaPalette.mutedText)

                if _budgets.fetchError != nil || _transactions.fetchError != nil {
                    messageBlock("Verifica del budget non disponibile",
                                 "Non riesco a leggere tutti i movimenti. Riprova prima di basarti su questo confronto.")
                } else if previews.isEmpty {
                    messageBlock("Nessun budget per questa categoria",
                                 "Non posso confrontare questa spesa con un limite. Puoi impostare un budget da Pianifica.")
                } else {
                    ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                        if index > 0 { Divider().overlay(ForgiaPalette.border) }
                        ExpenseBudgetResultRow(preview: preview, currency: currency)
                    }
                    DisclosureGroup("Come funziona il confronto") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(footnotes, id: \.self) { note in
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(ForgiaPalette.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                    .font(.footnote.weight(.medium))
                    .tint(ForgiaPalette.accent)
                }
            }
            .accessibilityIdentifier("expense-budget-preview")
            .unifiedCard()
        }
    }

    private var footnotes: [String] {
        var notes = ["Il confronto usa i movimenti già inseriti, comprese eventuali spese future. Rientrare nel budget non garantisce disponibilità sul conto."]
        if excludingTransactionID != nil {
            notes.append("La spesa originale è esclusa dal totale già inserito: il confronto usa il nuovo importo, la categoria e la data scelti.")
        }
        if isRecurring {
            notes.append("Stai verificando solo questa occorrenza, non le ripetizioni successive.")
        }
        return notes
    }

    private func messageBlock(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(ForgiaPalette.mutedText)
        }
    }
}

private struct ExpenseBudgetResultRow: View {
    let preview: ExpenseBudgetPreview
    let currency: String
    var compact = false

    /// Icons carry the status colour; text stays primary so it reads on light and dark surfaces.
    private var color: Color {
        switch preview.status {
        case .overLimit: .red
        case .approachingLimit, .atLimit: .orange
        case .withinLimit: ForgiaPalette.accent
        }
    }

    private var statusLabel: (text: String, icon: String) {
        switch preview.status {
        case .overLimit: ("Oltre il limite", "exclamationmark.triangle.fill")
        case .atLimit: ("Raggiungeresti il limite del budget", "exclamationmark.circle.fill")
        case .approachingLimit: ("Vicino al limite", "exclamationmark.circle.fill")
        case .withinLimit: ("Rientra nel budget", "checkmark.circle.fill")
        }
    }

    private var outcome: String {
        preview.status == .overLimit
            ? "Sforeresti di \((-preview.remaining).formatted(.currency(code: currency)))"
            : "Resterebbero \(preview.remaining.formatted(.currency(code: currency)))"
    }

    private func share(_ value: Decimal) -> Double {
        guard preview.limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: value / preview.limit).doubleValue, 0), 1)
    }

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preview.name).font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                Image(systemName: statusLabel.icon).foregroundStyle(color)
                Text(preview.status == .withinLimit ? "Rientra nel budget: \(outcome.lowercased())" : outcome)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(preview.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: statusLabel.icon).foregroundStyle(color)
                    Text(statusLabel.text)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ForgiaPalette.canvas, in: Capsule())
            }

            Text(outcome)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(preview.status == .overLimit ? Color.red : Color.primary)

            GeometryReader { proxy in
                let spentWidth = proxy.size.width * share(preview.spent)
                let proposedWidth = proxy.size.width * min(share(preview.proposedAmount), 1 - share(preview.spent))
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgiaPalette.canvas)
                    HStack(spacing: 2) {
                        if spentWidth > 0 {
                            Capsule().fill(ForgiaPalette.mutedText.opacity(0.45)).frame(width: spentWidth)
                        }
                        Capsule().fill(color).frame(width: max(proposedWidth, 6))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text("Già inseriti \(preview.spent.formatted(.currency(code: currency))) + questa spesa")
                Spacer(minLength: 8)
                Text("su \(preview.limit.formatted(.currency(code: currency)))")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(ForgiaPalette.mutedText)

            Text("Periodo: \(preview.period.start, format: .dateTime.day().month()) – \(preview.period.end.addingTimeInterval(-1), format: .dateTime.day().month().year())")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
        }
        .accessibilityElement(children: .combine)
    }
}
