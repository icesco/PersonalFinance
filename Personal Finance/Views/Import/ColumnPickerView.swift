//
//  ColumnPickerView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import FinanceCore

struct ColumnPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let field: CSVField
    let headers: [String]
    let sampleValues: [[String]]

    @Binding var selectedColumnIndex: Int?

    init(field: CSVField, headers: [String], sampleValues: [[String]] = [], selection: Binding<Int?>) {
        self.field = field
        self.headers = headers
        self.sampleValues = sampleValues
        self._selectedColumnIndex = selection
    }

    var body: some View {
        NavigationStack {
            List {
                // Unassigned option
                Section {
                    Button {
                        selectedColumnIndex = nil
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.secondary)
                                .frame(width: 32)

                            Text("Non assegnato")
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedColumnIndex == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Available columns
                Section {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        ColumnRow(
                            index: index,
                            header: header,
                            sampleValue: getSampleValue(for: index),
                            isSelected: selectedColumnIndex == index
                        ) {
                            selectedColumnIndex = index
                            dismiss()
                        }
                    }
                } header: {
                    Text("Colonne disponibili")
                } footer: {
                    if !sampleValues.isEmpty {
                        Text("Vengono mostrati i valori della prima riga come esempio")
                    }
                }
            }
            .navigationTitle(field.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func getSampleValue(for columnIndex: Int) -> String? {
        guard !sampleValues.isEmpty,
              columnIndex < sampleValues[0].count else {
            return nil
        }
        return sampleValues[0][columnIndex]
    }
}

// MARK: - Column Row

private struct ColumnRow: View {
    let index: Int
    let header: String
    let sampleValue: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary)
                            .clipShape(Capsule())

                        Text(header)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    if let sample = sampleValue, !sample.isEmpty {
                        Text(sample)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ColumnPickerView(
        field: .amount,
        headers: ["Data", "Importo", "Descrizione", "Categoria"],
        sampleValues: [["2024-01-15", "125,50", "Spesa supermercato", "Alimentari"]],
        selection: .constant(1)
    )
}
