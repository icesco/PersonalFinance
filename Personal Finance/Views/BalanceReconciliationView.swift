import SwiftUI
import SwiftData
import FinanceCore

/// Aligns the imported ledger with a balance checked in the bank or card app.
struct BalanceReconciliationView: View {
    let account: Account
    @Environment(\.dismiss) private var dismiss

    private var conti: [Conto] {
        account.activeConti.filter { [.checking, .savings, .cash, .credit].contains($0.type) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(conti) { conto in
                        NavigationLink {
                            BalanceEntryView(conto: conto, currency: account.currency ?? "EUR")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conto.name ?? "Conto")
                                    Text(conto.type?.displayName ?? "Conto")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: conto.initialBalance == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                                    .foregroundStyle(conto.initialBalance == nil ? .orange : ForgiaPalette.accent)
                            }
                        }
                    }
                } footer: {
                    Text("Confronta ogni saldo con l'app della banca o della carta dopo aver importato i movimenti più recenti. I conti d'investimento non entrano nel margine di spesa.")
                }
            }
            .navigationTitle("Verifica saldi")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }
}

private struct BalanceEntryView: View {
    let conto: Conto
    let currency: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var enteredBalance = ""
    @State private var errorMessage: String?

    private var status: BalanceReconciliation.Status { BalanceReconciliation.status(for: conto) }
    private var latestMovement: Date? { status.latestMovement }
    private var movementsAreRecent: Bool { status.canReconcile }
    private var amountIsValid: Bool {
        !enteredBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && BalanceInput.parse(enteredBalance, currency: currency) != nil
    }

    var body: some View {
        Form {
            Section("Saldo registrato") {
                Text(status.balance, format: .currency(code: currency))
                    .font(.title3.weight(.semibold))
                if let latestMovement {
                    Text("Ultimo movimento: \(latestMovement.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Es. -125,40", text: $enteredBalance)
                    .accessibilityIdentifier("reconciliation-balance")
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                if !enteredBalance.isEmpty && !amountIsValid {
                    Text("Inserisci un saldo valido, senza separatori delle migliaia.").foregroundStyle(.red)
                }
                if conto.type == .credit {
                    Text("Per una carta, inserisci con il segno meno l'importo ancora da rimborsare.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Saldo verificato")
            } footer: {
                Text("Inserisci il saldo che vedi oggi nella banca o nella carta. Formi allinea il registro senza aggiungere un movimento fittizio.")
            }
            if !movementsAreRecent {
                Section {
                    Label("Importa prima i movimenti recenti di questo conto; l'ultimo dato è troppo vecchio per allineare il saldo di oggi.", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(conto.name ?? "Saldo")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Conferma") { confirmBalance() }
                    .disabled(!movementsAreRecent || !amountIsValid)
                    .accessibilityIdentifier("reconciliation-confirm")
            }
        }
    }

    private func confirmBalance() {
        do {
            // Flush pending ledger edits before calculating the absolute correction.
            try modelContext.save()
            let now = Date()
            let opening = try BalanceReconciliation.apply(contoID: conto.id, enteredBalance: enteredBalance, container: modelContext.container, now: now)
            // The entry may retain a model already registered in this context.
            // Mirror only the values that the isolated context actually committed.
            conto.initialBalance = opening
            conto.updatedAt = now
            dismiss()
        } catch BalanceReconciliation.Failure.invalidAmount {
            errorMessage = "Inserisci un saldo valido nella valuta del libro."
        } catch BalanceReconciliation.Failure.staleMovements {
            errorMessage = "Aggiorna prima i movimenti del conto, poi verifica nuovamente il saldo."
        } catch {
            errorMessage = "Il saldo non è stato aggiornato. Il valore inserito resta qui: riprova."
        }
    }
}

#if DEBUG
/// Real reconciliation flow backed only by an isolated in-memory ledger.
struct BalanceReconciliationFixture: View {
    private static let data: (container: ModelContainer, book: Account) = {
        let container = try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let book = Account(name: "Libro demo", currency: "EUR")
        let conto = Conto(name: "Conto demo", type: .checking, initialBalance: 100)
        conto.account = book; book.conti = [conto]
        container.mainContext.insert(book)
        let income = Transaction(amount: 20, type: .income, date: Date().addingTimeInterval(-86_400))
        income.setToConto(conto)
        let future = Transaction(amount: 50, type: .expense, date: Date().addingTimeInterval(86_400))
        future.setFromConto(conto)
        container.mainContext.insert(income); container.mainContext.insert(future)
        try! container.mainContext.save()
        return (container, book)
    }()
    var body: some View {
        BalanceReconciliationView(account: Self.data.book)
            .modelContainer(Self.data.container)
    }
}
#endif
