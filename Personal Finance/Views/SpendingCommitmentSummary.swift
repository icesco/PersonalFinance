import SwiftUI
import FinanceCore

struct SpendingCommitmentSummary: View {
    let direction: SpendingDirection
    let currency: String
    var scopeContoIDs: Set<UUID>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ricorrenti e variabili").font(.headline)
            Text("Spese registrate · ultimi 30 giorni")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            amountRow("Ricorrenti", amount: direction.recentRecurringExpenses, symbol: "repeat")
            amountRow("Variabili", amount: direction.recentVariableExpenses, symbol: "cart")
            Divider()
            amountRow("Ricorrenti previste · prossimi 30 giorni",
                      amount: direction.upcoming30DaysRecurringExpenses, symbol: "calendar")
            Text("Le ricorrenti sono quelle che hai contrassegnato. Le scadenze future non sono incluse nelle spese già registrate.")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            if direction.availability != .staleData,
               let category = direction.largestVariableOutflow, category.amount > 0 {
                Text("Da dove iniziare?").font(.subheadline.weight(.semibold))
                Text("\(category.name) è la categoria variabile che pesa di più: \(category.amount, format: .currency(code: currency)). Rivedi i movimenti e scegli quali spese ridurre.")
                    .font(.subheadline)
                if let categoryID = category.categoryID {
                    NavigationLink {
                        TransactionListView(initialCategoryID: categoryID, initialInterval: DateInterval(start: Calendar.current.date(byAdding: .day, value: -30, to: Date())!, end: Date()), expensesOnly: true, scopeContoIDs: scopeContoIDs,
                                            isPushed: true, pushedTitle: category.name)
                    } label: {
                        Label("Rivedi questa categoria", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .unifiedCard()
    }

    private func amountRow(_ title: LocalizedStringKey, amount: Decimal, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: symbol)
                .foregroundStyle(ForgiaPalette.mutedText)
            Spacer(minLength: 4)
            Text(amount, format: .currency(code: currency))
                .fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }
}

struct PurchaseCheckView: View {
    let margin: Decimal?
    let currency: String
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    private var amount: Decimal? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        guard !amountText.isEmpty,
              amountText.allSatisfy({ $0.isNumber || $0 == "," }),
              amountText.filter({ $0 == "," }).count <= 1,
              let value = formatter.number(from: amountText)?.decimalValue,
              value > 0 else { return nil }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}
