import SwiftUI
import SwiftData
import FinanceCore

struct RecurringManagementView: View {
    let contoIDs: Set<UUID>
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState
    @Query(filter: #Predicate<FinanceTransaction> { $0.isRecurring == true })
    private var recurring: [FinanceTransaction]
    @State private var editing: FinanceTransaction?
    @State private var terminating: FinanceTransaction?
    @State private var showEnded = false
    @State private var errorMessage: String?

    private var series: [FinanceTransaction] {
        recurring.filter { transaction in
            let id = transaction.type == .income ? transaction.toContoId : transaction.fromContoId
            guard let id, contoIDs.contains(id) else { return false }
            return (transaction.nextRecurrenceDate() == nil) == showEnded
        }.sorted {
            let left = $0.nextRecurrenceDate() ?? $0.date
            let right = $1.nextRecurrenceDate() ?? $1.date
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    var body: some View {
        List {
            if _recurring.fetchError != nil {
                Text("Impossibile caricare le ricorrenze. Riapri la schermata per riprovare.")
            } else if series.isEmpty {
                ContentUnavailableView(showEnded ? "Nessuna ricorrenza terminata" : "Nessuna ricorrenza attiva", systemImage: "repeat")
            } else {
                ForEach(series) { transaction in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(transaction.transactionDescription ?? transaction.category?.name ?? "Ricorrenza").font(.headline)
                            Spacer()
                            Text(transaction.amount ?? 0, format: .currency(code: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR"))
                        }
                        Text(transaction.recurrenceFrequency?.displayName ?? "Frequenza non impostata")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let next = transaction.nextRecurrenceDate() {
                            Text("Prossima: \(next.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                        } else if let end = transaction.recurrenceEndDate {
                            Text("Terminata il \(end.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                        }
                        HStack {
                            Button("Modifica") { editing = transaction }.buttonStyle(.bordered)
                            if !showEnded {
                                Button("Termina", role: .destructive) { terminating = transaction }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }.padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("recurring-series-\(transaction.transactionDescription ?? transaction.id.uuidString)")
                }
            }
            Section {
                Text("Le date sono previsioni. Terminare una ricorrenza interrompe le scadenze future e conserva i movimenti già registrati. Per riattivarla, modifica la data di fine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .financeEmptyOverlay(isPresented: series.isEmpty && _recurring.fetchError == nil) {
            ContentUnavailableView {
                Label(showEnded ? "Nessuna ricorrenza terminata" : "Nessuna ricorrenza attiva", systemImage: "repeat")
            } description: {
                Text(showEnded
                     ? "Le ricorrenze che termini restano qui, con i movimenti già registrati."
                     : "Quando registri un movimento puoi renderlo ricorrente: lo ritroverai qui con la prossima scadenza.")
            }
        }
        .safeAreaBar(edge: .top) {
            Picker("Ricorrenze", selection: $showEnded) {
                Text("Attive").tag(false)
                Text("Terminate").tag(true)
            }.pickerStyle(.segmented).padding(12)
        }
        .navigationTitle("Ricorrenze")
        .financePresentation(item: $editing, title: "Modifica ricorrenza") { EditTransactionView(transaction: $0) }
        .confirmationDialog("Terminare questa ricorrenza?", isPresented: Binding(
            get: { terminating != nil }, set: { if !$0 { terminating = nil } }
        ), titleVisibility: .visible) {
            Button("Termina ricorrenza", role: .destructive) {
                if let transaction = terminating { stop(transaction) }
            }
            Button("Annulla", role: .cancel) { terminating = nil }
        } message: {
            Text("I movimenti già registrati rimarranno invariati.")
        }
        .alert("Impossibile salvare", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func stop(_ transaction: FinanceTransaction) {
        let previousEnd = transaction.recurrenceEndDate
        let previousUpdate = transaction.updatedAt
        transaction.recurrenceEndDate = Date()
        transaction.updatedAt = Date()
        do {
            try modelContext.save()
            appState.triggerDataRefresh()
        } catch {
            transaction.recurrenceEndDate = previousEnd
            transaction.updatedAt = previousUpdate
            errorMessage = error.localizedDescription
        }
        terminating = nil
    }
}
