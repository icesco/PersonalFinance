//
//  ImportPreviewView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import FinanceCore

struct ImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let previewRows: [CSVPreviewRow]
    let totalRows: Int
    let onConfirm: () -> Void

    @State private var showingOnlyErrors = false

    private var filteredRows: [CSVPreviewRow] {
        if showingOnlyErrors {
            return previewRows.filter { $0.hasError }
        }
        return previewRows
    }

    private var errorCount: Int {
        previewRows.filter { $0.hasError }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    HStack {
                        Label("Righe totali", systemImage: "list.number")
                        Spacer()
                        Text("\(totalRows)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Anteprima", systemImage: "eye")
                        Spacer()
                        Text("\(previewRows.count) righe")
                            .foregroundColor(.secondary)
                    }

                    if errorCount > 0 {
                        HStack {
                            Label("Errori rilevati", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Spacer()
                            Text("\(errorCount)")
                                .foregroundColor(.orange)
                        }
                    }
                }

                // Filter toggle
                if errorCount > 0 {
                    Section {
                        Toggle("Mostra solo errori", isOn: $showingOnlyErrors)
                    }
                }

                // Preview rows
                Section {
                    ForEach(filteredRows) { row in
                        PreviewRowView(row: row)
                    }
                } header: {
                    Text("Anteprima transazioni")
                } footer: {
                    if previewRows.count < totalRows {
                        Text("Vengono mostrate solo le prime \(previewRows.count) righe come anteprima")
                    }
                }
            }
            .navigationTitle("Anteprima Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Importa") {
                        onConfirm()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview Row View

private struct PreviewRowView: View {
    let row: CSVPreviewRow

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row number and error indicator
            HStack {
                Text("Riga \(row.rowNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if row.hasError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Spacer()

                if let type = row.type {
                    Text(type)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Main content
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let description = row.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let date = row.date {
                            Text(dateFormatter.string(from: date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let category = row.category, !category.isEmpty {
                            Text(category)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        if let conto = row.conto, !conto.isEmpty {
                            Text(conto)
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                }

                Spacer()

                if let amount = row.amount {
                    Text(numberFormatter.string(from: amount as NSDecimalNumber) ?? "")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(amount >= 0 ? .green : .red)
                }
            }

            // Error message
            if row.hasError, let errorMessage = row.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ImportPreviewView(
        previewRows: [
            CSVPreviewRow(
                rowNumber: 2,
                date: Date(),
                amount: -45.50,
                type: "Spesa",
                category: "Alimentari",
                conto: "Conto Principale",
                description: "Spesa al supermercato",
                hasError: false,
                errorMessage: nil
            ),
            CSVPreviewRow(
                rowNumber: 3,
                date: nil,
                amount: 100,
                type: "Entrata",
                category: nil,
                conto: nil,
                description: "Rimborso",
                hasError: true,
                errorMessage: "Data non valida: invalid-date"
            )
        ],
        totalRows: 150,
        onConfirm: {}
    )
}
