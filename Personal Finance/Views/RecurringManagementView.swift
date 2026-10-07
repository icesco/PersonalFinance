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

    /// Series grouped as the list reads them: outgoing first, then incoming, then transfers.
    private var groups: [(title: String, items: [FinanceTransaction])] {
        let all = series
        return [("Uscite", TransactionType.expense), ("Entrate", .income), ("Trasferimenti", .transfer)].compactMap { title, type in
            let items = all.filter { $0.type == type }
            return items.isEmpty ? nil : (title, items)
        }
    }

    /// Monthly commitment of the active series; nil when currencies differ and a sum would mislead.
    private var monthlyCommitment: (currency: String, expenses: Decimal, income: Decimal)? {
        guard !showEnded else { return nil }
        let active = series.filter { $0.recurrenceFrequency != nil && $0.type != .transfer }
        let currencies = Set(active.map(currency(of:)))
        guard !active.isEmpty, currencies.count == 1, let code = currencies.first else { return nil }
        func total(_ type: TransactionType) -> Decimal {
            active.filter { $0.type == type }.reduce(Decimal(0)) { sum, transaction in
                sum + (transaction.recurrenceFrequency?.monthlyEquivalent(of: transaction.amount ?? 0) ?? 0)
            }
        }
        return (code, total(.expense), total(.income))
    }

    var body: some View {
        List {
            if _recurring.fetchError != nil {
                Text("Impossibile caricare le ricorrenze. Riapri la schermata per riprovare.")
                    .listRowBackground(ForgiaPalette.surface)
            } else if series.isEmpty {
                ContentUnavailableView {
                    Label(showEnded ? "Nessuna ricorrenza terminata" : "Nessuna ricorrenza attiva", systemImage: "repeat")
                } description: {
                    Text(showEnded
                         ? "Le ricorrenze che termini restano qui, con i movimenti già registrati."
                         : "Quando registri un movimento puoi renderlo ricorrente: lo ritroverai qui con la prossima scadenza.")
                }
                .foregroundStyle(ForgiaPalette.mutedText)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if let commitment = monthlyCommitment {
                    Section {
                        commitmentCard(commitment)
                            .listRowBackground(ForgiaPalette.surface)
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            seriesRow(transaction)
                                .listRowBackground(ForgiaPalette.surface)
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                }
            }

            Section {
                Text("Le date sono previsioni. Terminare una ricorrenza interrompe le scadenze future e conserva i movimenti già registrati. Per riattivarla, modifica la data di fine.")
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                    .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .themedBackground()
        .financeEmptyOverlay(isPresented: series.isEmpty && _recurring.fetchError == nil) {
            ContentUnavailableView {
                Label(showEnded ? "Nessuna ricorrenza terminata" : "Nessuna ricorrenza attiva", systemImage: "repeat")
            } description: {
                Text(showEnded
                     ? "Le ricorrenze che termini restano qui, con i movimenti già registrati."
                     : "Quando registri un movimento puoi renderlo ricorrente: lo ritroverai qui con la prossima scadenza.")
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            Picker("Ricorrenze", selection: $showEnded) {
                Text("Attive").tag(false)
                Text("Terminate").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle("Ricorrenze")
        .toolbarTitleDisplayMode(.inline)
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

    private func currency(of transaction: FinanceTransaction) -> String {
        transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR"
    }

    private func commitmentCard(_ commitment: (currency: String, expenses: Decimal, income: Decimal)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMPEGNO MEDIO AL MESE")
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(ForgiaPalette.mutedText)
            Text(commitment.expenses.formatted(.currency(code: commitment.currency)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("di uscite ricorrenti, riportate a cadenza mensile")
                .font(.caption)
                .foregroundStyle(ForgiaPalette.mutedText)
            if commitment.income > 0 {
                Label("\(commitment.income.formatted(.currency(code: commitment.currency))) di entrate ricorrenti al mese",
                      systemImage: "arrow.down.left")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ForgiaPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ForgiaPalette.sageSurface, in: Capsule())
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func seriesRow(_ transaction: FinanceTransaction) -> some View {
        let isIncome = transaction.type == .income
        let amount = transaction.amount ?? 0
        let next = transaction.nextRecurrenceDate()
        let locale = Locale(identifier: "it_IT")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: transaction.category?.icon ?? "repeat")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isIncome ? ForgiaPalette.accent : ForgiaPalette.mutedText)
                    .frame(width: 44, height: 44)
                    .background(isIncome ? ForgiaPalette.sageSurface : ForgiaPalette.canvas, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.transactionDescription ?? transaction.category?.name ?? "Ricorrenza")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text([transaction.recurrenceFrequency?.displayName ?? "Frequenza non impostata",
                          transaction.fromConto?.name ?? transaction.toConto?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .lineLimit(1)
                    if let next {
                        Label("Prossima: \(next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)))",
                              systemImage: "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ForgiaPalette.accent)
                    } else if let end = transaction.recurrenceEndDate {
                        Label("Terminata il \(end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))",
                              systemImage: "stop.circle")
                            .font(.caption)
                            .foregroundStyle(ForgiaPalette.mutedText)
                    }
                }

                Spacer(minLength: 8)

                Text((isIncome ? "+" : transaction.type == .expense ? "−" : "") + amount.formatted(.currency(code: currency(of: transaction))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isIncome ? ForgiaPalette.accent : Color.primary)
            }

            HStack(spacing: 8) {
                Button("Modifica", systemImage: "pencil") { editing = transaction }
                    .tint(ForgiaPalette.accent)
                if !showEnded {
                    Button("Termina", systemImage: "stop.circle", role: .destructive) { terminating = transaction }
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(.leading, 56)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recurring-series-\(transaction.transactionDescription ?? transaction.id.uuidString)")
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
