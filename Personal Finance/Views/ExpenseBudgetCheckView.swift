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
            VStack(alignment: .leading, spacing: 12) {
                Label(excludingTransactionID == nil ? "Prima di spendere" : "Prima di salvare", systemImage: "checkmark.shield")
                    .font(.headline)
                if _budgets.fetchError != nil || _transactions.fetchError != nil {
                    Text("Verifica del budget non disponibile")
                        .font(.subheadline.weight(.semibold))
                    Text("Non riesco a leggere tutti i movimenti. Riprova prima di basarti su questo confronto.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                } else if previews.isEmpty {
                    Text("Nessun budget per questa categoria")
                        .font(.subheadline.weight(.semibold))
                    Text("Non posso confrontare questa spesa con un limite. Puoi impostare un budget da Pianifica.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                } else {
                    ForEach(previews) { preview in
                        ExpenseBudgetResultRow(preview: preview, currency: currency)
                    }
                    Text("Il confronto usa i movimenti già inseriti, comprese eventuali spese future. Rientrare nel budget non garantisce disponibilità sul conto.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                if excludingTransactionID != nil {
                    Text("La spesa originale è esclusa dal totale già inserito: il confronto usa il nuovo importo, la categoria e la data scelti.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
                if isRecurring {
                    Text("Stai verificando solo questa occorrenza, non le ripetizioni successive.")
                        .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                }
            }
            .accessibilityIdentifier("expense-budget-preview")
            .unifiedCard()
        }
    }
}

private struct ExpenseBudgetResultRow: View {
    let preview: ExpenseBudgetPreview
    let currency: String
    var compact = false

    private var color: Color {
        switch preview.status {
        case .overLimit: .red
        case .approachingLimit, .atLimit: .orange
        case .withinLimit: ForgiaPalette.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(preview.name).font(.subheadline.weight(.semibold))
            switch preview.status {
            case .overLimit:
                Label("Sforeresti di \(-preview.remaining, format: .currency(code: currency))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
            case .atLimit:
                Label("Raggiungeresti il limite del budget", systemImage: "exclamationmark.circle")
                    .foregroundStyle(color)
            case .approachingLimit:
                Label("Vicino al limite: resterebbero \(preview.remaining, format: .currency(code: currency))", systemImage: "exclamationmark.circle")
                    .foregroundStyle(color)
            case .withinLimit:
                Label("Rientra nel budget: resterebbero \(preview.remaining, format: .currency(code: currency))", systemImage: "checkmark.circle")
                    .foregroundStyle(color)
            }
            if !compact {
                Text("Già inseriti \(preview.spent, format: .currency(code: currency)) su \(preview.limit, format: .currency(code: currency))")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
                Text("Periodo: \(preview.period.start, format: .dateTime.day().month()) – \(preview.period.end.addingTimeInterval(-1), format: .dateTime.day().month().year())")
                    .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
