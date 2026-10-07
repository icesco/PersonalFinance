import SwiftUI
import SwiftData
import FinanceCore

struct SavingsAccountSummary: View {
    let conto: Conto
    var allowsActions = true
    @Query private var transactions: [FinanceCore.Transaction]
    @State private var showingRateEditor = false
    private var currency: String { conto.account?.currency ?? "EUR" }

    var body: some View {
        let value = conto.savingsSnapshot(at: Date(), transactions: transactions)
        VStack(alignment: .leading, spacing: 22) {
            SavingsValueHeader(value: value, currency: currency,
                rate: conto.savingsRates.last(where: { $0.effectiveDate <= Date() })?.annualPercent,
                tint: Color(hex: conto.displayColorHex))
            if allowsActions {
                HStack(spacing: 10) {
                    Button { showingRateEditor = true } label: {
                        SavingsActionLabel(title: "Aggiorna tasso", icon: "percent", tint: Color(hex: conto.displayColorHex))
                    }
                    NavigationLink {
                        CreateTransactionView(conto: conto, transactionType: .income, savingsInterest: true)
                    } label: {
                        SavingsActionLabel(title: "Registra interessi", icon: "plus", tint: Color(hex: conto.displayColorHex))
                    }
                    .accessibilityLabel("Registra interessi accreditati")
                }
                .buttonStyle(.plain)
            }
            if let goal = conto.linkedSavingsGoal {
                SavingsGoalSummary(goal: goal, currency: currency, tint: Color(hex: conto.displayColorHex))
            }
            if !conto.savingsRates.isEmpty {
                SavingsRateHistory(rates: conto.savingsRates)
            }
            Text("Stima a interessi semplici sul saldo registrato. Imposte e costi non vengono dedotti automaticamente.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingRateEditor) { SavingsRateEditor(conto: conto) }
    }
}

private struct SavingsActionLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(tint)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SavingsValueHeader: View {
    let value: SavingsValue
    let currency: String
    let rate: Decimal?
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Il tuo risparmio", systemImage: "banknote")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Spacer()
                if let rate {
                    Text("\(rate.formatted(.number))% annuo")
                        .font(.caption.weight(.semibold)).foregroundStyle(rate < 0 ? Color(hex: "#C06748") : tint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(tint.opacity(0.09), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Controvalore stimato").font(.caption).foregroundStyle(.secondary)
                Text(value.estimatedValue, format: .currency(code: currency))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(value.estimatedValue < value.capital ? Color(hex: "#C06748") : tint).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            }.accessibilityElement(children: .combine)
            if value.estimatedValue < 0 {
                Text("Saldo sotto zero")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color(hex: "#C06748"))
            }
            HStack {
                Text("Capitale versato netto").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value.capital, format: .currency(code: currency))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(value.capital < 0 ? Color(hex: "#C06748") : .primary)
            }.accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 12) {
                SavingsInterestMetric(title: "Accreditati", amount: value.creditedInterest, currency: currency, icon: "checkmark.circle", tint: tint)
                SavingsInterestMetric(title: value.pendingInterest < 0 ? "Perdita stimata" : "In maturazione", amount: value.pendingInterest, currency: currency, icon: "clock", tint: tint)
            }
        }
    }
}

private struct SavingsInterestMetric: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let currency: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: currency))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                .foregroundStyle(amount < 0 ? Color(hex: "#C06748") : .primary)
            Text(amount < 0 ? "Rendimento" : "Interessi").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct SavingsGoalSummary: View {
    let goal: SavingsGoal
    let currency: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "target").font(.title3).foregroundStyle(tint)
                    .padding(10).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Obiettivo di risparmio").font(.caption).foregroundStyle(.secondary)
                    Text(goal.name ?? "Risparmio").font(.headline)
                }
                Spacer(minLength: 8)
                Text(goal.progressPercentage / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(tint)
            }
            ProgressView(value: max(0, min(goal.progressPercentage / 100, 1))).tint(tint)
            HStack(alignment: .firstTextBaseline) {
                Text("\(goal.fundedAmount.formatted(.currency(code: currency))) di \((goal.targetAmount ?? 0).formatted(.currency(code: currency)))")
                    .font(.caption.weight(.medium)).monospacedDigit()
                Spacer(minLength: 0)
            }
            Text(goal.isCompleted ? "Obiettivo raggiunto" : "Mancano \(goal.remainingAmount.formatted(.currency(code: currency)))")
                .font(.subheadline.weight(.medium)).foregroundStyle(tint)
            NavigationLink {
                SavingsGoalContributionsView(goal: goal)
            } label: {
                HStack {
                    Label("Vedi i contributi", systemImage: "arrow.down.left.arrow.up.right")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }.font(.subheadline.weight(.medium)).padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(tint)
        }
        .padding(16)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SavingsRateHistory: View {
    let rates: [SavingsRate]
    var body: some View {
        DisclosureGroup {
            VStack(spacing: 12) {
                ForEach(rates.reversed()) { rate in
                    HStack {
                        Text(rate.effectiveDate, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(rate.annualPercent.formatted(.number))%")
                            .fontWeight(.semibold).monospacedDigit()
                    }.font(.subheadline)
                }
            }.padding(.top, 10)
        } label: {
            Label("Storico dei tassi", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct SavingsRateEditor: View {
    let conto: Conto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rate: Decimal?
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Tasso annuo (%)", value: $rate, format: .number)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    Button { rate = -(rate ?? 0) } label: { Image(systemName: "plus.forwardslash.minus") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cambia segno del rendimento")
                }
                Text("Un tasso negativo indica una perdita stimata. Il capitale versato resta separato dal rendimento.")
                    .font(.caption).foregroundStyle(.secondary)
                DatePicker("Valido dal", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("Il nuovo tasso si applica dalla data scelta. I periodi precedenti mantengono il loro tasso. Una voce alla stessa data viene sostituita.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Aggiorna tasso")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.disabled(rate == nil || rate?.isNaN == true)
                }
            }
            .onAppear { rate = conto.savingsRates.last?.annualPercent ?? 0 }
        }
    }
    private func save() {
        guard let rate, !rate.isNaN else { return }
        let editing = ModelContext(context.container)
        editing.autosaveEnabled = false
        do {
            let id = conto.id
            guard let target = try editing.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == id })).first else { return }
            try target.setSavingsRate(rate, effectiveDate: date)
            target.updatedAt = Date()
            try editing.save()
            dismiss()
        } catch {
            editing.rollback()
            self.error = "Non è stato possibile salvare il tasso. Riprova."
        }
    }
}

struct SavingsGoalContributionsView: View {
    let goal: SavingsGoal
    @Query private var transactions: [FinanceCore.Transaction]
    private var currency: String { goal.account?.currency ?? "EUR" }
    private var entries: [Contribution] {
        let conti = goal.linkedConti
        let ids = Set(conti.map(\.id))
        return transactions.filter { $0.date <= Date() }.compactMap { transaction in
            let from = (transaction.fromContoId ?? transaction.fromConto?.id).map(ids.contains) == true
            let to = (transaction.toContoId ?? transaction.toConto?.id).map(ids.contains) == true
            // Moving funds inside the same goal is not a new contribution.
            guard !(from && to), transaction.isSavingsInterest != true else { return nil }
            var amount: Decimal = 0
            if to && (transaction.type == .income || transaction.type == .transfer) {
                amount += transaction.type == .transfer ? (transaction.destinationAmount ?? transaction.amount ?? 0) : (transaction.amount ?? 0)
            }
            if from && (transaction.type == .expense || transaction.type == .transfer) { amount -= transaction.amount ?? 0 }
            guard amount != 0 else { return nil }
            return Contribution(transaction: transaction, amount: amount)
        }.sorted { $0.transaction.date > $1.transaction.date }
    }
    var body: some View {
        List {
            Section("Progresso") {
                LabeledContent("Capitale versato netto", value: goal.fundedAmount.formatted(.currency(code: currency)))
                LabeledContent("Obiettivo", value: (goal.targetAmount ?? 0).formatted(.currency(code: currency)))
                Text("Gli interessi sono separati dai contributi. Prelievi, modifiche e cancellazioni aggiornano automaticamente il progresso.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Saldo iniziale incluso") {
                ForEach(goal.linkedConti) { conto in
                    LabeledContent(conto.name ?? "Conto", value: (conto.initialBalance ?? 0).formatted(.currency(code: currency)))
                }
            }
            Section("Movimenti collegati") {
                ForEach(entries) { entry in
                    NavigationLink {
                        TransactionDetailView(transaction: entry.transaction)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.transaction.transactionDescription ?? (entry.amount >= 0 ? "Versamento" : "Prelievo"))
                            HStack {
                                Text(entry.transaction.date, format: .dateTime.day().month().year())
                                Spacer()
                                Text(entry.amount, format: .currency(code: currency))
                            }.font(.caption)
                        }
                    }
                }
            }
        }.navigationTitle(goal.name ?? "Obiettivo di risparmio")
    }
    private struct Contribution: Identifiable {
        let transaction: FinanceCore.Transaction
        let amount: Decimal
        var id: UUID { transaction.id }
    }
}
