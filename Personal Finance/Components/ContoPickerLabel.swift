import SwiftUI
import FinanceCore

struct ContoPickerLabel: View {
    let conto: Conto
    private var title: String {
        let balance = conto.balance.formatted(.currency(code: conto.account?.currency ?? "EUR"))
        return "\(conto.name ?? "Conto") · \(balance)"
    }
    var body: some View {
        Label { Text(title) } icon: {
            Image(systemName: conto.type?.icon ?? "creditcard")
                .foregroundStyle(Color(hex: conto.displayColorHex))
        }
    }
}
