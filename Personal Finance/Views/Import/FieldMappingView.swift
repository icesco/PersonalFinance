//
//  FieldMappingView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import SwiftData
import FinanceCore

struct FieldMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) private var appState

    let parseResult: CSVParseResult

    @State private var mappings: [FieldMapping]
    @State private var options: CSVImportOptions
    @State private var selectedField: CSVField?
    @State private var showingDateFormatPicker = false
    @State private var showingPreview = false
    @State private var showingImportResult = false
    @State private var isImporting = false
    @State private var importResult: CSVImportResult?
    @State private var previewRows: [CSVPreviewRow] = []
    @State private var importProgress: Double = 0
    @State private var importedRowCount: Int = 0
    @State private var importTotalRowCount: Int = 0

    private let csvService = CSVService()

    private var availableConti: [Conto] {
        appState.selectedAccount?.activeConti ?? []
    }

    private var isMappingValid: Bool {
        let validationErrors = mappings.filter { $0.field.isRequired && !$0.isAssigned }
        return validationErrors.isEmpty
    }

    init(parseResult: CSVParseResult, initialMappings: [FieldMapping]? = nil) {
        self.parseResult = parseResult
        self._mappings = State(initialValue: initialMappings ?? [])
        self._options = State(initialValue: CSVImportOptions())
    }

    var body: some View {
        Form {
            descriptionSection

            ForEach(CSVFieldSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(fieldsForSection(section)) { mapping in
                        FieldMappingRow(
                            mapping: mapping,
                            onTap: { selectedField = mapping.field }
                        )
                    }
                }
            }

            dateFormatSection

            contoSelectionSection
            optionsSection

            previewSection
        }
        .navigationTitle("Assegna campi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Importa") {
                    performImport()
                }
                .disabled(!isMappingValid || isImporting)
            }
        }
        .sheet(item: $selectedField) { field in
            ColumnPickerView(
                field: field,
                headers: parseResult.headers,
                sampleValues: Array(parseResult.rows.prefix(3)),
                selection: bindingForField(field)
            )
        }
        .sheet(isPresented: $showingDateFormatPicker) {
            DateFormatPickerView(selection: $options.dateFormat)
        }
        .alert("Import completato", isPresented: $showingImportResult) {
            Button("OK") {
                dismiss()
            }
        } message: {
            if let result = importResult {
                Text(importResultMessage(result))
            }
        }
        .onAppear {
            initializeMappings()
        }
        .overlay {
            if isImporting {
                importProgressOverlay
            }
        }
    }

    // MARK: - Import Progress Overlay

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: importProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                VStack(spacing: 8) {
                    Text("Importazione in corso...")
                        .font(.headline)

                    Text("\(importedRowCount) di \(importTotalRowCount) righe")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("\(Int(importProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(32)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Assegna le colonne del file CSV ai campi corrispondenti.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("\(parseResult.rowCount) righe trovate")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(parseResult.columnCount) colonne")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var dateFormatSection: some View {
        Section("Formato Data") {
            Button {
                showingDateFormatPicker = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Formato data")
                            .foregroundColor(.primary)

                        Text(options.dateFormat.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var contoSelectionSection: some View {
        Section {
            Picker("Importa in", selection: $options.defaultContoId) {
                Text("Automatico").tag(nil as UUID?)
                ForEach(availableConti, id: \.id) { conto in
                    HStack {
                        Image(systemName: conto.type?.icon ?? "creditcard")
                        Text(conto.name ?? "Conto")
                    }
                    .tag(conto.id as UUID?)
                }
            }
        } header: {
            Text("Conto di destinazione")
        } footer: {
            Text("Seleziona il conto in cui importare le transazioni")
        }
    }

    private var optionsSection: some View {
        Section("Opzioni") {
            Toggle(isOn: $options.ignoreZeroAmounts) {
                HStack {
                    Image(systemName: "0.circle")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    Text("Ignora importi a zero")
                }
            }

            Toggle(isOn: $options.ignoreDuplicates) {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    Text("Ignora duplicati")
                }
            }

            Toggle(isOn: $options.createMissingCategories) {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.green)
                        .frame(width: 24)

                    Text("Crea categorie mancanti")
                }
            }
        }
    }

    private var previewSection: some View {
        Section {
            if isMappingValid {
                let preview = CSVParser.generatePreview(
                    from: parseResult,
                    mapping: mappings,
                    options: options,
                    maxRows: 5
                )
                if preview.isEmpty {
                    Text("Nessuna riga da mostrare")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preview) { row in
                        inlinePreviewRow(row)
                    }
                }
            } else {
                Text("Completa la mappatura dei campi obbligatori per vedere l'anteprima")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Anteprima (\(parseResult.rowCount) righe)")
        } footer: {
            if isMappingValid {
                Text("Prime 5 righe. Verifica che importi e tipi siano corretti.")
            }
        }
    }

    private func inlinePreviewRow(_ row: CSVPreviewRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let desc = row.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("Riga \(row.rowNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let amount = row.amount {
                    Text(amount >= 0 ? "+\(amount)" : "\(amount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(amount >= 0 ? .green : .red)
                }
            }

            HStack(spacing: 8) {
                if let date = row.date {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let type = row.type {
                    Text(type)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                if let category = row.category, !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                if row.hasError, let error = row.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helper Methods

    private func fieldsForSection(_ section: CSVFieldSection) -> [FieldMapping] {
        mappings.filter { $0.field.section == section }
    }

    private func bindingForField(_ field: CSVField) -> Binding<Int?> {
        Binding(
            get: {
                mappings.first { $0.field == field }?.csvColumnIndex
            },
            set: { newValue in
                if let index = mappings.firstIndex(where: { $0.field == field }) {
                    mappings[index].csvColumnIndex = newValue
                    mappings[index].csvColumnName = newValue.flatMap { parseResult.headers.indices.contains($0) ? parseResult.headers[$0] : nil }
                }
            }
        )
    }

    private func initializeMappings() {
        if mappings.isEmpty {
            mappings = CSVParser.detectColumnMapping(headers: parseResult.headers)
        }
    }


    private func performImport() {
        guard let account = appState.selectedAccount else { return }

        isImporting = true
        importProgress = 0
        importedRowCount = 0

        Task {
            do {
                let result = try await csvService.importTransactions(
                    from: parseResult,
                    mapping: mappings,
                    options: options,
                    container: modelContext.container,
                    accountId: account.id,
                    progressCallback: { current, total in
                        Task { @MainActor in
                            importedRowCount = current
                            importTotalRowCount = total
                            importProgress = Double(current) / Double(total)
                        }
                    }
                )

                await MainActor.run {
                    importResult = result
                    isImporting = false
                    showingImportResult = true
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importResult = CSVImportResult(
                        totalRows: parseResult.rowCount,
                        importedCount: 0,
                        skippedCount: 0,
                        errorCount: 1,
                        errors: [ImportError(rowNumber: 0, message: error.localizedDescription, field: nil, rawValue: nil)],
                        duplicatesSkipped: 0,
                        zeroAmountsSkipped: 0
                    )
                    showingImportResult = true
                }
            }
        }
    }

    private func importResultMessage(_ result: CSVImportResult) -> String {
        var message = "Importate \(result.importedCount) transazioni su \(result.totalRows)."

        if result.skippedCount > 0 {
            message += "\n\(result.skippedCount) righe saltate."
        }

        if result.duplicatesSkipped > 0 {
            message += "\n\(result.duplicatesSkipped) duplicati ignorati."
        }

        if result.zeroAmountsSkipped > 0 {
            message += "\n\(result.zeroAmountsSkipped) importi a zero ignorati."
        }

        if result.errorCount > 0 {
            message += "\n\(result.errorCount) errori."
        }

        return message
    }
}

// MARK: - Field Mapping Row

struct FieldMappingRow: View {
    let mapping: FieldMapping
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: mapping.field.icon)
                    .foregroundStyle(mapping.field.iconColor)
                    .frame(width: 32, height: 32)
                    .background(mapping.field.iconColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Field name
                Text(mapping.field.rawValue)
                    .foregroundStyle(.primary)

                Spacer()

                // Assignment status
                if mapping.field.isRequired && !mapping.isAssigned {
                    Text("Obbligatorio")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let columnName = mapping.csvColumnName {
                    Text(columnName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Non assegnato")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let parseResult = CSVParseResult(
        headers: ["Data", "Importo", "Descrizione", "Categoria"],
        rows: [
            ["2024-01-15", "125,50", "Spesa supermercato", "Alimentari"],
            ["2024-01-16", "-45,00", "Ristorante", "Ristoranti"]
        ]
    )

    return FieldMappingView(parseResult: parseResult)
        .environment(AppStateManager())
        .modelContainer(try! FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true))
}
