import SwiftUI
import SwiftData
import FinanceCore
import MapKit

struct TransactionDetailView: View {
    let transaction: FinanceTransaction
    var showsCloseButton = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingDeleteError = false

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
                    Text(amountPrefix + (transaction.amount ?? Decimal(0)).formatted(.currency(code: transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR")))
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

            if transaction.type == .transfer, let received = transaction.destinationAmount {
                Section("Importo ricevuto") {
                    Text(received, format: .currency(code: transaction.toConto?.account?.currency ?? "EUR"))
                }
            }
            if let original = transaction.originalAmount, let currency = transaction.originalCurrency, let rate = transaction.exchangeRate {
                Section("Importo originale") {
                    Text(original, format: .currency(code: currency))
                    Text("Cambio applicato: \(rate.formatted())")
                    Text(transaction.exchangeRateDate.map { "\(transaction.exchangeRateSource ?? "Cambio") · \($0)" } ?? "Cambio manuale")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

            if transaction.placeName != nil || transaction.latitude != nil {
                Section("Luogo") {
                    if let name = transaction.placeName { Text(name) }
                    if let latitude = transaction.latitude, let longitude = transaction.longitude {
                        Text("\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))")
                            .font(.caption).monospacedDigit().textSelection(.enabled)
                        if CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                            Button("Apri in Mappe", systemImage: "map") {
                                let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
                                item.name = transaction.placeName ?? "Luogo del movimento"
                                item.openInMaps()
                            }
                        }
                    }
                }
            }
            TransactionAttachmentsSection(transaction: transaction)

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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("Dettaglio")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
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
        .financePresentation(isPresented: $showingEditSheet, title: "Modifica movimento") {
            EditTransactionView(transaction: transaction)
        }
        .alert("Impossibile eliminare", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("La transazione non è stata eliminata. Riprova.")
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
        do {
            try TransactionDeletion(context: modelContext).delete(ids: [transaction.id])
            appState.triggerDataRefresh()
            dismiss()
        } catch {
            showingDeleteError = true
        }
    }
}
