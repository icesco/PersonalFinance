import SwiftUI
import FinanceCore

/// Keeps the exact draft text visible. Invalid input never leaves an older numeric value behind.
struct CurrencyAmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let currency: String
    let identifier: String

    private var invalid: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let value = BalanceInput.parse(text, currency: currency) else { return true }
        return value <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                TextField("0,00", text: $text)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
                Text(currency).font(.caption).foregroundStyle(.secondary)
            }
            if invalid {
                Text("Inserisci un importo positivo valido per questa valuta, senza separatori delle migliaia.")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier(identifier + "-invalid")
            }
        }
    }
}
