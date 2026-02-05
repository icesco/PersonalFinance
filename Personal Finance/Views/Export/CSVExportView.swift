//
//  CSVExportView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import SwiftData
import FinanceCore

struct CSVExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    @Query private var conti: [Conto]

    @State private var options = CSVExportOptions()
    @State private var selectedConti: Set<UUID> = []
    @State private var dateFromEnabled = false
    @State private var dateToEnabled = false
    @State private var showingDateFormatPicker = false
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var showingFieldSelection = false
    @State private var transactionCount: Int = 0

    private let csvService = CSVService()

    var body: some View {
        NavigationStack {
            Form {
                // Account selection
                accountSection

                // Date range
                dateRangeSection

                // Fields to include
                fieldsSection

                // Format options
                formatSection

                // Preview info
                previewSection
            }
            .navigationTitle("Esporta CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Esporta") {
                        performExport()
                    }
                    .disabled(isExporting || transactionCount == 0)
                }
            }
            .sheet(isPresented: $showingDateFormatPicker) {
                DateFormatPickerView(selection: $options.dateFormat)
            }
            .sheet(isPresented: $showingFieldSelection) {
                FieldSelectionView(selectedFields: $options.includeFields)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .overlay {
                if isExporting {
                    ProgressView("Esportazione in corso...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
            }
            .onAppear {
                updateTransactionCount()
            }
            .onChange(of: selectedConti) { _, _ in
                updateTransactionCount()
            }
            .onChange(of: options.dateFrom) { _, _ in
                updateTransactionCount()
            }
            .onChange(of: options.dateTo) { _, _ in
                updateTransactionCount()
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if conti.isEmpty {
                Text("Nessun conto disponibile")
                    .foregroundColor(.secondary)
            } else {
                ForEach(conti, id: \.id) { conto in
                    Toggle(isOn: Binding(
                        get: { selectedConti.contains(conto.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedConti.insert(conto.id)
                            } else {
                                selectedConti.remove(conto.id)
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: conto.type?.icon ?? "creditcard")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading) {
                                Text(conto.name ?? "Conto")

                                Text(conto.balance.currencyFormatted)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Button {
                    if selectedConti.count == conti.count {
                        selectedConti.removeAll()
                    } else {
                        selectedConti = Set(conti.map { $0.id })
                    }
                } label: {
                    Text(selectedConti.count == conti.count ? "Deseleziona tutti" : "Seleziona tutti")
                }
            }
        } header: {
            Text("Conti da esportare")
        } footer: {
            if selectedConti.isEmpty {
                Text("Seleziona almeno un conto per esportare le transazioni")
            } else {
                Text("\(selectedConti.count) conti selezionati")
            }
        }
    }

    private var dateRangeSection: some View {
        Section("Periodo") {
            Toggle(isOn: $dateFromEnabled) {
                HStack {
                    Text("Data inizio")

                    if dateFromEnabled {
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { options.dateFrom ?? Date() },
                                set: { options.dateFrom = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
            }
            .onChange(of: dateFromEnabled) { _, newValue in
                options.dateFrom = newValue ? Calendar.current.date(byAdding: .month, value: -1, to: Date()) : nil
            }

            Toggle(isOn: $dateToEnabled) {
                HStack {
                    Text("Data fine")

                    if dateToEnabled {
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { options.dateTo ?? Date() },
                                set: { options.dateTo = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
            }
            .onChange(of: dateToEnabled) { _, newValue in
                options.dateTo = newValue ? Date() : nil
            }
        }
    }

    private var fieldsSection: some View {
        Section {
            Button {
                showingFieldSelection = true
            } label: {
                HStack {
                    Text("Campi da includere")

                    Spacer()

                    Text("\(options.includeFields.count) campi")
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)
        }
    }

    private var formatSection: some View {
        Section("Formato") {
            Button {
                showingDateFormatPicker = true
            } label: {
                HStack {
                    Text("Formato data")

                    Spacer()

                    Text(options.dateFormat.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .foregroundColor(.primary)

            Toggle("Includi intestazione", isOn: $options.includeHeader)
        }
    }

    private var previewSection: some View {
        Section {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.accentColor)

                Text("Transazioni da esportare")

                Spacer()

                Text("\(transactionCount)")
                    .fontWeight(.semibold)
                    .foregroundColor(transactionCount > 0 ? .primary : .secondary)
            }
        } footer: {
            if transactionCount == 0 {
                Text("Nessuna transazione corrisponde ai criteri selezionati")
            }
        }
    }

    // MARK: - Methods

    private func updateTransactionCount() {
        options.contoIds = selectedConti

        Task {
            let transactions = await fetchTransactions()
            await MainActor.run {
                transactionCount = transactions.count
            }
        }
    }

    private func fetchTransactions() async -> [FinanceTransaction] {
        var descriptor = FetchDescriptor<FinanceTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        // Build predicates
        var predicates: [Predicate<FinanceTransaction>] = []

        if let dateFrom = options.dateFrom {
            predicates.append(#Predicate<FinanceTransaction> { $0.date >= dateFrom })
        }

        if let dateTo = options.dateTo {
            predicates.append(#Predicate<FinanceTransaction> { $0.date <= dateTo })
        }

        // Apply compound predicate if any
        if !predicates.isEmpty {
            if predicates.count == 1 {
                descriptor.predicate = predicates[0]
            } else if predicates.count == 2 {
                let dateFrom = options.dateFrom!
                let dateTo = options.dateTo!
                descriptor.predicate = #Predicate<FinanceTransaction> {
                    $0.date >= dateFrom && $0.date <= dateTo
                }
            }
        }

        do {
            var transactions = try modelContext.fetch(descriptor)

            // Filter by conto if needed
            if !selectedConti.isEmpty {
                transactions = transactions.filter { transaction in
                    if let fromContoId = transaction.fromContoId, selectedConti.contains(fromContoId) {
                        return true
                    }
                    if let toContoId = transaction.toContoId, selectedConti.contains(toContoId) {
                        return true
                    }
                    return false
                }
            }

            return transactions
        } catch {
            print("Error fetching transactions: \(error)")
            return []
        }
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil

        Task {
            let transactions = await fetchTransactions()

            let csvContent = await csvService.exportTransactions(transactions, options: options)

            // Create temporary file
            let fileName = generateFileName()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    exportedFileURL = tempURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = "Errore durante l'esportazione: \(error.localizedDescription)"
                }
            }
        }
    }

    private func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let dateString = formatter.string(from: Date())

        let accountName = appState.selectedAccount?.name?.replacingOccurrences(of: " ", with: "-") ?? "Export"

        return "\(accountName)-\(dateString).csv"
    }
}

// MARK: - Field Selection View

struct FieldSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedFields: Set<CSVField>

    var body: some View {
        NavigationStack {
            List {
                ForEach(CSVFieldSection.allCases) { section in
                    Section(section.rawValue) {
                        ForEach(section.fields) { field in
                            Toggle(isOn: Binding(
                                get: { selectedFields.contains(field) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedFields.insert(field)
                                    } else {
                                        selectedFields.remove(field)
                                    }
                                }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: field.icon)
                                        .foregroundStyle(field.iconColor)
                                        .frame(width: 24)

                                    Text(field.rawValue)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Seleziona tutti") {
                        selectedFields = Set(CSVField.allCases)
                    }

                    Button("Deseleziona tutti") {
                        selectedFields.removeAll()
                    }
                }
            }
            .navigationTitle("Campi da esportare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    CSVExportView()
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
