//
//  CSVImportView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import UniformTypeIdentifiers
import FinanceCore

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStateManager.self) private var appState

    @State private var selectedFileURL: URL?
    @State private var parseResult: CSVParseResult?
    @State private var showingFilePicker = false
    @State private var showingFieldMapping = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let csvService = CSVService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header illustration
                Spacer()

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)

                VStack(spacing: 12) {
                    Text("Importa da CSV")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Seleziona un file CSV contenente le transazioni da importare. Potrai poi mappare le colonne ai campi corrispondenti.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Selected file info
                if let url = selectedFileURL {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)

                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                selectedFileURL = nil
                                parseResult = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        if let result = parseResult {
                            HStack {
                                Label("\(result.rowCount) righe", systemImage: "list.number")
                                Spacer()
                                Label("\(result.columnCount) colonne", systemImage: "tablecells")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                }

                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    if parseResult != nil {
                        Button {
                            showingFieldMapping = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Continua")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }

                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(selectedFileURL == nil ? "Seleziona file CSV" : "Cambia file")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(parseResult == nil ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(parseResult == nil ? .white : .primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Importa CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .fullScreenCover(isPresented: $showingFieldMapping) {
                if let parseResult = parseResult {
                    FieldMappingView(parseResult: parseResult)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Lettura file...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 10)
                }
            }
        }
    }

    // MARK: - File Handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadCSVFile(from: url)

        case .failure(let error):
            errorMessage = "Errore nella selezione del file: \(error.localizedDescription)"
        }
    }

    private func loadCSVFile(from url: URL) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await csvService.parseCSV(from: url)

                await MainActor.run {
                    selectedFileURL = url
                    parseResult = result
                    isLoading = false

                    if result.rowCount == 0 {
                        errorMessage = "Il file non contiene dati validi"
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Errore nella lettura del file: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    CSVImportView()
        .environment(AppStateManager())
}
