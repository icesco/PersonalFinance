import SwiftUI
import FinanceCore

struct CreditAccountCard: View {
    let conto: Conto

    private var currency: String { conto.account?.currency ?? "EUR" }
    private var balanceTitle: LocalizedStringKey {
        if conto.creditLimitRemaining != nil { return "Disponibile" }
        return conto.balance > 0 ? "Credito a favore" : "Da rimborsare"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(conto.name ?? "Carta di credito")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Carta di credito").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                if conto.logoData != nil {
                    ContoLogo(conto: conto, size: 44)
                        .padding(5)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            CardChip()

            VStack(alignment: .leading, spacing: 6) {
                Text(balanceTitle).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                Text(conto.displayBalance, format: .currency(code: currency))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if conto.creditLimitRemaining != nil, let limit = conto.creditLimit {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        CardAmount(label: "Da rimborsare", amount: conto.creditOutstandingBalance, currency: currency)
                        Spacer(minLength: 0)
                        CardAmount(label: "Fido totale", amount: limit, currency: currency)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        CardAmount(label: "Da rimborsare", amount: conto.creditOutstandingBalance, currency: currency)
                        CardAmount(label: "Fido totale", amount: limit, currency: currency)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 440, minHeight: 270, alignment: .topLeading)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(hex: conto.displayColorHex).opacity(0.38))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("credit-account-card")
    }
}

private struct CardAmount: View {
    let label: LocalizedStringKey
    let amount: Decimal
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
            Text(amount, format: .currency(code: currency))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct CardChip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.82, green: 0.76, blue: 0.59))
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 0))
                    path.addLine(to: CGPoint(x: 12, y: 28))
                    path.move(to: CGPoint(x: 24, y: 0))
                    path.addLine(to: CGPoint(x: 24, y: 28))
                    path.move(to: CGPoint(x: 0, y: 9))
                    path.addLine(to: CGPoint(x: 36, y: 9))
                    path.move(to: CGPoint(x: 0, y: 19))
                    path.addLine(to: CGPoint(x: 36, y: 19))
                }
                .stroke(.black.opacity(0.25), lineWidth: 0.8)
            }
            .frame(width: 36, height: 28)
            .accessibilityHidden(true)
    }
}
