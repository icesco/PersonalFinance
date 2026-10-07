import SwiftUI
import SwiftData
import FinanceCore
import MapKit

struct TransactionDetailView: View {
    let transaction: FinanceTransaction
    /// True when presented in a sheet; pushed screens rely on Back.
    var showsCloseButton = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingDeleteError = false

    private var currency: String {
        transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? "EUR"
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income: return "+"
        case .expense: return "−"
        case .transfer: return ""
        }
    }

    private var typeBadge: (label: String, icon: String) {
        switch transaction.type {
        case .income: return ("Entrata", "arrow.down.left")
        case .expense: return ("Spesa", "arrow.up.right")
        case .transfer: return ("Trasferimento", "arrow.left.arrow.right")
        }
    }

    /// Same palette as the quick-entry form: sage for income, apricot for spending.
    private var tint: Color {
        switch transaction.type {
        case .income: return ForgiaPalette.sageSurface
        case .expense: return ForgiaPalette.apricotSurface
        case .transfer: return ForgiaPalette.canvas
        }
    }

    private var title: String {
        transaction.transactionDescription ?? transaction.category?.name ?? typeBadge.label
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: transaction.date)
        let hasTime = (components.hour != 0 || components.minute != 0)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        dateFormatter.dateFormat = hasTime ? "EEEE d MMMM yyyy 'alle' HH:mm" : "EEEE d MMMM yyyy"
        let text = dateFormatter.string(from: transaction.date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var body: some View {
        List {
            Section {
                hero
                    .listRowBackground(
                        LinearGradient(colors: [tint, tint.mix(with: ForgiaPalette.surface, by: 0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            Section {
                if transaction.type != .transfer, let category = transaction.category {
                    DetailRow(icon: category.icon ?? "tag", tint: tint, title: "Categoria",
                              value: category.displayPath)
                }
                if let fromConto = transaction.fromConto {
                    DetailRow(icon: fromConto.type?.icon ?? "creditcard", tint: ForgiaPalette.sageSurface,
                              title: transaction.type == .transfer ? "Dal conto" : "Conto",
                              value: fromConto.name ?? "—")
                }
                if let toConto = transaction.toConto {
                    DetailRow(icon: toConto.type?.icon ?? "creditcard", tint: ForgiaPalette.sageSurface,
                              title: transaction.type == .transfer ? "Al conto" : "Conto",
                              value: toConto.name ?? "—")
                }
                DetailRow(icon: "calendar", tint: ForgiaPalette.canvas, title: "Data", value: formattedDate)
                if transaction.isRecurring == true {
                    DetailRow(icon: "arrow.triangle.2.circlepath", tint: ForgiaPalette.canvas, title: "Ricorrenza",
                              value: recurrenceText)
                }
            } header: {
                sectionHeader("Dettagli")
            }
            .listRowBackground(ForgiaPalette.surface)

            if transaction.type == .transfer, let received = transaction.destinationAmount {
                Section {
                    DetailRow(icon: "arrow.down.to.line", tint: ForgiaPalette.sageSurface, title: "Importo ricevuto",
                              value: received.formatted(.currency(code: transaction.toConto?.account?.currency ?? "EUR")))
                } header: {
                    sectionHeader("Trasferimento")
                }
                .listRowBackground(ForgiaPalette.surface)
            }

            if let original = transaction.originalAmount, let originalCurrency = transaction.originalCurrency,
               let rate = transaction.exchangeRate {
                Section {
                    DetailRow(icon: "arrow.left.arrow.right", tint: ForgiaPalette.canvas, title: "Importo originale",
                              value: original.formatted(.currency(code: originalCurrency)))
                    DetailRow(icon: "percent", tint: ForgiaPalette.canvas, title: "Cambio applicato",
                              value: rate.formatted(),
                              caption: transaction.exchangeRateDate.map { "\(transaction.exchangeRateSource ?? "Cambio") · \($0)" } ?? "Cambio manuale")
                } header: {
                    sectionHeader("Valuta estera")
                }
                .listRowBackground(ForgiaPalette.surface)
            }

            if transaction.placeName != nil || transaction.latitude != nil {
                Section {
                    DetailRow(icon: "mappin.and.ellipse", tint: ForgiaPalette.apricotSurface, title: "Luogo",
                              value: transaction.placeName ?? "Posizione salvata",
                              caption: coordinatesText)
                    if let latitude = transaction.latitude, let longitude = transaction.longitude,
                       CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                        Button("Apri in Mappe", systemImage: "map") {
                            let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
                            item.name = transaction.placeName ?? "Luogo del movimento"
                            item.openInMaps()
                        }
                        .tint(ForgiaPalette.accent)
                    }
                } header: {
                    sectionHeader("Luogo")
                }
                .listRowBackground(ForgiaPalette.surface)
            }

            if let notes = transaction.notes, !notes.isEmpty {
                Section {
                    Text(notes)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                } header: {
                    sectionHeader("Note")
                }
                .listRowBackground(ForgiaPalette.surface)
            }

            TransactionAttachmentsSection(transaction: transaction)
                .listRowBackground(ForgiaPalette.surface)

            Section {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Elimina movimento", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowBackground(ForgiaPalette.surface)
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
            // Pushed screens already have Back; only a modal presentation needs its own way out.
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Modifica", systemImage: "pencil") { showingEditSheet = true }
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

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: transaction.category?.icon ?? typeBadge.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 64, height: 64)
                .background(ForgiaPalette.surface.opacity(0.85), in: Circle())

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(amountPrefix + (transaction.amount ?? Decimal(0)).formatted(.currency(code: currency)))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(transaction.type == .income ? ForgiaPalette.accent : Color.primary)

            HStack(spacing: 8) {
                Label(typeBadge.label, systemImage: typeBadge.icon)
                if transaction.isRecurring == true {
                    Label(transaction.recurrenceFrequency?.displayName ?? "Ricorrente", systemImage: "repeat")
                }
            }
            .labelStyle(CapsuleLabelStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private var recurrenceText: String {
        let frequency = transaction.recurrenceFrequency?.displayName ?? "Frequenza non impostata"
        if let endDate = transaction.recurrenceEndDate {
            return "\(frequency) · fino al \(endDate.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "it_IT"))))"
        }
        return frequency
    }

    private var coordinatesText: String? {
        guard let latitude = transaction.latitude, let longitude = transaction.longitude else { return nil }
        return "\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ForgiaPalette.mutedText)
            .textCase(nil)
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

/// A detail line in the style of the quick-entry form: tinted icon, caption title, value.
private struct DetailRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    var caption: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ForgiaPalette.accent)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ForgiaPalette.mutedText)
                Text(value)
                    .font(.body)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(ForgiaPalette.mutedText)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ForgiaPalette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ForgiaPalette.surface.opacity(0.85), in: Capsule())
    }
}
