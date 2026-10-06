import SwiftUI
import FinanceCore

struct TransactionAddButtonModifier: ViewModifier {
    var isVisible = true

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 8) {
            if isVisible {
                TransactionAddButton()
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
        }
    }
}

private struct TransactionAddButton: View {
    @Environment(AppStateManager.self) private var appState

    var body: some View {
        Menu {
            Button("Nuova spesa", systemImage: "arrow.up.right") {
                appState.presentQuickTransaction(type: .expense)
            }
            Button("Nuova entrata", systemImage: "arrow.down.left") {
                appState.presentQuickTransaction(type: .income)
            }
            if appState.activeConti(for: appState.selectedAccount).count >= 2 {
                Button("Nuovo trasferimento", systemImage: "arrow.left.arrow.right") {
                    appState.presentQuickTransaction(type: .transfer)
                }
            }
        } label: {
            Label("Aggiungi movimento", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(ForgiaPalette.accent).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transactions-add")
    }
}
