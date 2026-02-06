import SwiftUI
import SwiftData
import FinanceCore

struct TransactionDetailView: View {
    let transaction: FinanceTransaction
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    private var amountColor: Color {
        switch transaction.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .primary
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income: return "+"
        case .expense: return "-"
        case .transfer: return ""
        }
    }

    private var typeBadge: (label: String, icon: String, color: Color) {
        switch transaction.type {
        case .income:
            return ("Entrata", "arrow.down.circle.fill", .green)
        case .expense:
            return ("Uscita", "arrow.up.circle.fill", .red)
        case .transfer:
            return ("Trasferimento", "arrow.left.arrow.right.circle.fill", .blue)
        }
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: transaction.date)
        let hasTime = (components.hour != 0 || components.minute != 0)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        dateFormatter.dateFormat = hasTime ? "d MMMM yyyy 'alle' HH:mm" : "d MMMM yyyy"
        return dateFormatter.string(from: transaction.date)
    }

    var body: some View {
        List {
            // Hero section
            Section {
                VStack(spacing: 10) {
                    Text(amountPrefix + (transaction.amount ?? Decimal(0)).currencyFormatted)
                        .font(.title.bold())
                        .foregroundStyle(amountColor)

                    HStack(spacing: 6) {
                        Image(systemName: typeBadge.icon)
                        Text(typeBadge.label)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(typeBadge.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(typeBadge.color.opacity(0.12))
                    .clipShape(Capsule())

                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Informazioni
            Section("Informazioni") {
                LabeledContent("Descrizione") {
                    Text(transaction.transactionDescription ?? transaction.category?.name ?? "—")
                }

                if transaction.type != .transfer, let category = transaction.category {
                    LabeledContent("Categoria") {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon ?? "tag")
                                .foregroundStyle(Color(hex: category.color ?? "#007AFF"))
                            Text(category.name ?? "—")
                        }
                    }
                }
            }

            // Account
            Section("Account") {
                if let fromConto = transaction.fromConto {
                    LabeledContent(transaction.type == .transfer ? "Da" : "Account") {
                        HStack(spacing: 6) {
                            Image(systemName: fromConto.type?.icon ?? "creditcard")
                                .foregroundStyle(.secondary)
                            Text(fromConto.name ?? "—")
                        }
                    }
                }

                if let toConto = transaction.toConto {
                    LabeledContent(transaction.type == .transfer ? "A" : "Account") {
                        HStack(spacing: 6) {
                            Image(systemName: toConto.type?.icon ?? "creditcard")
                                .foregroundStyle(.secondary)
                            Text(toConto.name ?? "—")
                        }
                    }
                }
            }

            // Ricorrenza
            if transaction.isRecurring == true {
                Section("Ricorrenza") {
                    LabeledContent("Frequenza") {
                        Text(transaction.recurrenceFrequency?.displayName ?? "—")
                    }

                    if let endDate = transaction.recurrenceEndDate {
                        LabeledContent("Fine ricorrenza") {
                            Text(endDate, format: .dateTime.day().month(.wide).year())
                        }
                    }
                }
            }

            // Note
            if let notes = transaction.notes, !notes.isEmpty {
                Section("Note") {
                    Text(notes)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dettaglio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    Menu {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditTransactionView(transaction: transaction)
        }
        .alert("Elimina Transazione", isPresented: $showingDeleteAlert) {
            Button("Elimina", role: .destructive) {
                deleteTransaction()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Sei sicuro di voler eliminare questa transazione? Questa azione non può essere annullata.")
        }
    }

    private func deleteTransaction() {
        modelContext.delete(transaction)
        try? modelContext.save()
        appState.triggerDataRefresh()
        dismiss()
    }
}
