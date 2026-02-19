//
//  DateFormatPickerView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import FinanceCore

struct DateFormatPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: CSVDateFormat

    @State private var searchText = ""

    private var filteredFormats: [CSVDateFormat] {
        if searchText.isEmpty {
            return CSVDateFormat.allCases
        }
        return CSVDateFormat.allCases.filter {
            $0.rawValue.lowercased().contains(searchText.lowercased()) ||
            $0.example.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredFormats) { format in
                        DateFormatRow(
                            format: format,
                            isSelected: format == selection
                        ) {
                            selection = format
                            dismiss()
                        }
                    }
                } header: {
                    Text("Seleziona il formato che corrisponde ai dati nel CSV")
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: "Cerca formato")
            .navigationTitle("Formato Data")
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
}

// MARK: - Date Format Row

private struct DateFormatRow: View {
    let format: CSVDateFormat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("Es: \(format.example)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    DateFormatPickerView(selection: .constant(.iso8601Offset))
}
