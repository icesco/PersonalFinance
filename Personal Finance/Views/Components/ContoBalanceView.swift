import SwiftUI
import FinanceCore

struct ContoBalanceView: View {
    let conto: Conto
    var compact = false

    private var currency: String { conto.account?.currency ?? "EUR" }
    private var title: LocalizedStringKey {
        if conto.type != .credit { return "Saldo attuale" }
        if conto.creditLimitRemaining != nil { return "Disponibile" }
        return conto.balance > 0 ? "Credito a favore" : "Da rimborsare"
    }

    var body: some View {
        VStack(alignment: compact ? .trailing : .leading, spacing: compact ? 2 : 6) {
            if !compact || conto.type == .credit {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(conto.displayBalance, format: .currency(code: currency))
                .font(compact ? .subheadline.weight(.medium) : .system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(conto.type != .credit && conto.balance < 0 ? Color.red : Color.primary)
            if conto.type == .credit, conto.creditLimitRemaining != nil {
                Text("Da rimborsare: \(conto.creditOutstandingBalance.formatted(.currency(code: currency)))")
                    .font(.caption).foregroundStyle(.secondary)
                if !compact, let limit = conto.creditLimit {
                    Text("Fido: \(limit.formatted(.currency(code: currency)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
