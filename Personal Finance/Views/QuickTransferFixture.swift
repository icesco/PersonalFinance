#if DEBUG
import SwiftUI
import SwiftData
import FinanceCore

/// A temporary ledger for testing movement creation without accessing user data.
struct QuickTransferFixture: View {
    @State private var appState: AppStateManager

    private static let data: (container: ModelContainer, book: Account) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Libro di prova", currency: "EUR")
        let source = Conto(name: "Corrente", type: .checking, initialBalance: 500)
        let destination = Conto(name: "Risparmio", type: .savings, initialBalance: 100)
        source.account = book
        destination.account = book
        book.conti = [source, destination]
        container.mainContext.insert(book)
        try! container.mainContext.save()
        return (container, book)
    }()

    init() {
        let state = AppStateManager()
        state.selectAccount(Self.data.book)
        _appState = State(initialValue: state)
    }

    var body: some View {
        QuickTransferWorkspace(book: Self.data.book)
            .modelContainer(Self.data.container)
            .environment(appState)
    }
}

private struct QuickTransferWorkspace: View {
    let book: Account
    @State private var showingCreation = true
    @Query private var transactions: [FinanceTransaction]

    var body: some View {
        NavigationStack {
            List {
                Button("Nuovo movimento") { showingCreation = true }
                ForEach(transactions) { transaction in
                    Text("\(transaction.type.rawValue): \(transaction.fromConto?.name ?? "-") → \(transaction.toConto?.name ?? "-")")
                        .accessibilityIdentifier("transfer-saved-route")
                    Text(transaction.amount?.description ?? "-")
                        .accessibilityIdentifier("transfer-saved-amount")
                    Text(transaction.category == nil ? "Senza categoria" : "Con categoria")
                }
                ForEach(book.activeConti) { conto in
                    Text("\(conto.name ?? "-"): \(conto.balance.description)")
                }
            }
            .sheet(isPresented: $showingCreation) { QuickTransactionModal() }
        }
    }
}
#endif
