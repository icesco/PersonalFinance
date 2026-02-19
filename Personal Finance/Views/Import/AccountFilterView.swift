//
//  AccountFilterView.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import SwiftUI
import FinanceCore

// MARK: - Account Filter Step View (for NavigationStack)

struct AccountFilterStepView: View {
    let parseResult: CSVParseResult
    let onContinue: (CSVParseResult) -> Void

    @State private var currentStep: FilterStep = .askMultiAccount
    @State private var isMultiAccount: Bool? = nil
    @State private var selectedColumnIndex: Int? = nil
    @State private var selectedAccountValue: String? = nil
    @State private var accountValues: [CSVAccountValue] = []

    private enum FilterStep {
        case askMultiAccount
        case selectColumn
        case selectAccount
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Step indicator
            stepIndicator

            Spacer()

            // Content based on current step
            switch currentStep {
            case .askMultiAccount:
                askMultiAccountView
            case .selectColumn:
                selectColumnView
            case .selectAccount:
                selectAccountView
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Filtro Conti")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(stepIndex >= index ? Color.accentColor : Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var stepIndex: Int {
        switch currentStep {
        case .askMultiAccount: return 0
        case .selectColumn: return 1
        case .selectAccount: return 2
        }
    }

    // MARK: - Step 1: Ask Multi-Account

    private var askMultiAccountView: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Il CSV contiene transazioni di piu conti?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Se il file contiene dati da piu conti bancari, puoi filtrare per importare solo le transazioni di un conto specifico.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button {
                    isMultiAccount = false
                    onContinue(parseResult)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "1.circle.fill")
                            .font(.title)
                        Text("No, solo uno")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button {
                    isMultiAccount = true
                    currentStep = .selectColumn
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "building.2.fill")
                            .font(.title)
                        Text("Si, piu conti")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Step 2: Select Column

    private var selectColumnView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tablecells")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Quale colonna identifica il conto?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Seleziona la colonna che contiene il nome del conto o della banca.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<parseResult.headers.count, id: \.self) { index in
                        let header = parseResult.headers[index]
                        Button {
                            selectedColumnIndex = index
                            loadAccountValues(columnIndex: index)
                        } label: {
                            HStack {
                                Text(header)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                if selectedColumnIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding()
                            .background(selectedColumnIndex == index ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
            .padding(.horizontal)

            if selectedColumnIndex != nil {
                Button {
                    currentStep = .selectAccount
                } label: {
                    HStack {
                        Text("Continua")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }

            Button {
                currentStep = .askMultiAccount
                selectedColumnIndex = nil
            } label: {
                Text("Indietro")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Step 3: Select Account

    private var selectAccountView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text("Quale conto vuoi importare?")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Seleziona il conto le cui transazioni vuoi importare.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(accountValues) { accountValue in
                        Button {
                            selectedAccountValue = accountValue.value
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(accountValue.value)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Text("\(accountValue.rowCount) transazioni")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedAccountValue == accountValue.value {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding()
                            .background(selectedAccountValue == accountValue.value ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
            .padding(.horizontal)

            if let selectedValue = selectedAccountValue, let columnIndex = selectedColumnIndex {
                let transactionCount = accountValues.first { $0.value == selectedValue }?.rowCount ?? 0

                Button {
                    let filteredResult = CSVParser.filterRows(
                        from: parseResult,
                        columnIndex: columnIndex,
                        value: selectedValue
                    )
                    onContinue(filteredResult)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Importa \(transactionCount) transazioni")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }

            Button {
                currentStep = .selectColumn
                selectedAccountValue = nil
            } label: {
                Text("Indietro")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func loadAccountValues(columnIndex: Int) {
        accountValues = CSVParser.extractUniqueAccountValues(from: parseResult, columnIndex: columnIndex)
    }
}

#Preview {
    NavigationStack {
        AccountFilterStepView(
            parseResult: CSVParseResult(
                headers: ["Data", "Importo", "Conto", "Descrizione"],
                rows: [
                    ["01/01/2024", "100", "Conto A", "Test 1"],
                    ["02/01/2024", "200", "Conto B", "Test 2"],
                    ["03/01/2024", "150", "Conto A", "Test 3"]
                ]
            )
        ) { _ in }
    }
}
