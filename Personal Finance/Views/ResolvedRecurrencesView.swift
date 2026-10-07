import SwiftUI
import SwiftData
import FinanceCore

struct ResolvedRecurrencesView: View {
    let contoIDs: Set<UUID>
    @Environment(\.modelContext) private var context
    @Environment(AppStateManager.self) private var appState
    @Query private var transactions: [FinanceTransaction]
    @Query(sort: \RecurrenceResolution.scheduledDate, order: .reverse) private var resolutions: [RecurrenceResolution]
    @State private var selectedTransaction: FinanceTransaction?
    @State private var error: String?

    private var scoped: [RecurrenceResolution] {
        let sources = Set(transactions.filter {
            ($0.fromContoId.map { contoIDs.contains($0) } ?? false) || ($0.toContoId.map { contoIDs.contains($0) } ?? false)
        }.map(\.id))
        return resolutions.filter { sources.contains($0.sourceID) }
    }

    var body: some View {
        List {
            if scoped.isEmpty {
                ContentUnavailableView("Nessuna scadenza gestita", systemImage: "checkmark.circle")
            }
            ForEach(scoped) { resolution in
                VStack(alignment: .leading, spacing: 8) {
                    Text(transactions.first { $0.id == resolution.sourceID }?.transactionDescription ?? "Ricorrenza").font(.headline)
                    Text(resolution.scheduledDate, format: .dateTime.day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                    if resolution.isSkipped {
                        Text("Saltata").font(.subheadline)
                        Button("Ripristina scadenza") { restore(resolution) }.buttonStyle(.bordered)
                    } else if let transaction = transactions.first(where: { $0.id == resolution.transactionID }) {
                        Button("Apri movimento registrato") { selectedTransaction = transaction }
                            .buttonStyle(.bordered)
                    } else {
                        Text("Movimento non disponibile: eliminato o non ancora sincronizzato.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .financeEmptyOverlay(isPresented: scoped.isEmpty) {
            ContentUnavailableView("Nessuna scadenza gestita", systemImage: "checkmark.circle",
                                   description: Text("Qui ritroverai le scadenze registrate o saltate."))
        }
        .navigationTitle("Scadenze gestite")
        .financePresentation(item: $selectedTransaction, title: "Movimento") { transaction in
            NavigationStack { TransactionDetailView(transaction: transaction, showsCloseButton: true) }
        }
        .alert("Impossibile ripristinare", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func restore(_ resolution: RecurrenceResolution) {
        guard resolution.isSkipped else { return }
        // Isolate the deletion so a failed save cannot roll back unrelated edits.
        let editor = ModelContext(context.container)
        editor.autosaveEnabled = false
        let key = resolution.key
        do {
            let matches = try editor.fetch(FetchDescriptor<RecurrenceResolution>(predicate: #Predicate { $0.key == key }))
            for match in matches where match.isSkipped { editor.delete(match) }
            try editor.save()
            appState.triggerDataRefresh()
        } catch {
            editor.rollback()
            self.error = error.localizedDescription
        }
    }
}
