import SwiftUI
import FinanceCore

struct AccountsBalanceOverview: View {
    let conti: [Conto]
    let currency: String
    let bookName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bookName).font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            Text("Saldo totale").font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            Text(conti.reduce(Decimal.zero) { $0 + $1.balance }, format: .currency(code: currency))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.7)
            Text(conti.count == 1 ? "1 conto attivo" : "\(conti.count) conti attivi")
                .font(.caption).foregroundStyle(ForgiaPalette.mutedText)
            let credit = conti.filter { $0.type == .credit }.reduce(Decimal.zero) { $0 + $1.creditOutstandingBalance }
            if credit > 0 {
                Label("Carte da rimborsare: \(credit.formatted(.currency(code: currency)))", systemImage: "creditcard")
                    .font(.subheadline).foregroundStyle(ForgiaPalette.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("accounts-balance-overview")
    }
}

struct AccountManagementRow: View {
    let conto: Conto
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var currency: String { conto.account?.currency ?? "EUR" }

    var body: some View {
        NavigationLink { FinanceContoDetailsView(conto: conto) } label: {
            HStack(spacing: 12) {
                ContoLogo(conto: conto, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Text(conto.name ?? "Conto").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(conto.displayBalance, format: .currency(code: currency))
                            .font(.subheadline.weight(.medium)).monospacedDigit()
                            .foregroundStyle(conto.type != .credit && conto.balance < 0 ? Color.red : Color.primary)
                    }
                    if conto.type == .credit {
                        Text(conto.creditLimitRemaining != nil
                             ? "Disponibile · da rimborsare \(conto.creditOutstandingBalance.formatted(.currency(code: currency)))"
                             : conto.balance > 0 ? "Credito a favore" : "Da rimborsare")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 44)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
