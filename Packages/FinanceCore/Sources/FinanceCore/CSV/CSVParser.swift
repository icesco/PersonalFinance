//
//  CSVParser.swift
//  FinanceCore
//
//  Pure static CSV parsing functions with no SwiftData dependency.
//

import Foundation

public struct CSVParser: Sendable {

    // MARK: - Parsing

    public static func parseCSVContent(_ content: String, options: CSVImportOptions = CSVImportOptions()) -> CSVParseResult {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return CSVParseResult(headers: [], rows: [])
        }

        let delimiter = String(options.delimiter)

        let headers: [String]
        let dataLines: [String]

        if options.hasHeader {
            headers = parseCSVLine(lines[0], delimiter: delimiter)
            dataLines = Array(lines.dropFirst())
        } else {
            let firstRow = parseCSVLine(lines[0], delimiter: delimiter)
            headers = (0..<firstRow.count).map { "Colonna \($0 + 1)" }
            dataLines = lines
        }

        let rows = dataLines.map { parseCSVLine($0, delimiter: delimiter) }

        return CSVParseResult(headers: headers, rows: rows)
    }

    private static func parseCSVLine(_ line: String, delimiter: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if String(char) == delimiter && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    // MARK: - Multi-Account Filtering

    public static func extractUniqueAccountValues(from result: CSVParseResult, columnIndex: Int) -> [CSVAccountValue] {
        var valueCounts: [String: Int] = [:]

        for row in result.rows {
            guard columnIndex < row.count else { continue }
            let value = row[columnIndex].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                valueCounts[value, default: 0] += 1
            }
        }

        return valueCounts.map { CSVAccountValue(value: $0.key, rowCount: $0.value) }
            .sorted { $0.rowCount > $1.rowCount }
    }

    public static func filterRows(from result: CSVParseResult, columnIndex: Int, value: String) -> CSVParseResult {
        let filteredRows = result.rows.filter { row in
            guard columnIndex < row.count else { return false }
            return row[columnIndex].trimmingCharacters(in: .whitespaces) == value
        }

        return CSVParseResult(headers: result.headers, rows: filteredRows)
    }

    // MARK: - Auto-Detection

    public static func detectColumnMapping(headers: [String]) -> [FieldMapping] {
        var mappings: [FieldMapping] = []

        for field in CSVField.allCases {
            var mapping = FieldMapping(field: field)

            if let index = findMatchingColumn(for: field, in: headers) {
                mapping.csvColumnIndex = index
                mapping.csvColumnName = headers[index]
            }

            mappings.append(mapping)
        }

        return mappings
    }

    private static func findMatchingColumn(for field: CSVField, in headers: [String]) -> Int? {
        let lowercasedHeaders = headers.map { $0.lowercased() }

        let keywords: [String]
        switch field {
        case .transactionType:
            keywords = ["tipo", "type", "transaction type", "tipo transazione"]
        case .amount:
            keywords = ["importo", "amount", "valore", "value", "somma", "totale"]
        case .sourceCurrency:
            keywords = ["valuta origine", "source currency", "currency from"]
        case .targetCurrency:
            keywords = ["valuta destinazione", "target currency", "currency to"]
        case .exchangeRate:
            keywords = ["tasso", "exchange", "rate", "cambio"]
        case .sourceAccount:
            keywords = ["conto da", "conto origine", "from account", "source account", "conto"]
        case .targetAccount:
            keywords = ["conto a", "conto destinazione", "to account", "target account"]
        case .category:
            keywords = ["categoria", "category", "cat"]
        case .payee:
            keywords = ["beneficiario", "payee", "destinatario", "pagatore"]
        case .date:
            keywords = ["data", "date", "giorno", "quando"]
        case .notes:
            keywords = ["note", "notes", "commento", "memo"]
        case .description:
            keywords = ["descrizione", "description", "desc", "titolo", "oggetto"]
        }

        for (index, header) in lowercasedHeaders.enumerated() {
            for keyword in keywords {
                if header.contains(keyword) {
                    return index
                }
            }
        }

        return nil
    }

    // MARK: - Validation

    public static func validateMapping(_ mappings: [FieldMapping]) -> [ValidationError] {
        var errors: [ValidationError] = []

        for mapping in mappings {
            if mapping.field.isRequired && !mapping.isAssigned {
                errors.append(ValidationError(
                    field: mapping.field,
                    message: "Il campo '\(mapping.field.rawValue)' è obbligatorio ma non assegnato"
                ))
            }
        }

        return errors
    }

    // MARK: - Amount & Date Parsing

    public static func parseAmount(_ string: String) -> Decimal? {
        var cleanedString = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "'", with: "")

        let hasComma = cleanedString.contains(",")
        let hasDot = cleanedString.contains(".")

        if hasComma && hasDot {
            cleanedString = cleanedString
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else if hasComma && !hasDot {
            cleanedString = cleanedString.replacingOccurrences(of: ",", with: ".")
        }

        return Decimal(string: cleanedString)
    }

    public static func parseDate(_ string: String, format: CSVDateFormat) -> Date? {
        if let date = format.parse(string) {
            return date
        }

        for otherFormat in CSVDateFormat.allCases where otherFormat != format {
            if let date = otherFormat.parse(string) {
                return date
            }
        }

        return nil
    }

    // MARK: - Transaction Type Detection

    public static func determineTransactionType(
        row: [String],
        amount: Decimal,
        mapping: [CSVField: FieldMapping]
    ) -> TransactionType {
        // Check if type is explicitly specified in a dedicated column
        if let typeMapping = mapping[.transactionType],
           let typeIndex = typeMapping.csvColumnIndex,
           typeIndex < row.count {
            let typeString = row[typeIndex].lowercased()

            if typeString.contains("entrata") || typeString.contains("income") || typeString.contains("ricavo") {
                return .income
            } else if typeString.contains("trasferimento") || typeString.contains("transfer") || typeString.contains("giroconto") {
                return .transfer
            } else if typeString.contains("spesa") || typeString.contains("expense") || typeString.contains("uscita") {
                return .expense
            }
        }

        // Check if both source and target accounts are specified (indicates transfer)
        let hasSourceAccount = mapping[.sourceAccount]?.isAssigned ?? false
        let hasTargetAccount = mapping[.targetAccount]?.isAssigned ?? false

        if hasSourceAccount && hasTargetAccount {
            if let sourceMapping = mapping[.sourceAccount],
               let sourceIndex = sourceMapping.csvColumnIndex,
               sourceIndex < row.count,
               !row[sourceIndex].isEmpty,
               let targetMapping = mapping[.targetAccount],
               let targetIndex = targetMapping.csvColumnIndex,
               targetIndex < row.count,
               !row[targetIndex].isEmpty {
                return .transfer
            }
        }

        // Fallback: infer type from amount sign
        return amount >= 0 ? .income : .expense
    }

    // MARK: - Preview Generation

    public static func generatePreview(
        from result: CSVParseResult,
        mapping: [FieldMapping],
        options: CSVImportOptions,
        maxRows: Int = 10
    ) -> [CSVPreviewRow] {
        var previews: [CSVPreviewRow] = []
        let mappingDict = Dictionary(uniqueKeysWithValues: mapping.map { ($0.field, $0) })

        let rowsToPreview = min(result.rows.count, maxRows)

        for i in 0..<rowsToPreview {
            let row = result.rows[i]
            let rowNumber = i + (options.hasHeader ? 2 : 1)

            var date: Date?
            var amount: Decimal?
            var type: String?
            var category: String?
            var conto: String?
            var description: String?
            var hasError = false
            var errorMessage: String?

            // Parse date
            if let dateMapping = mappingDict[.date],
               let dateIndex = dateMapping.csvColumnIndex,
               dateIndex < row.count {
                let dateString = row[dateIndex]
                date = parseDate(dateString, format: options.dateFormat)
                if date == nil {
                    hasError = true
                    errorMessage = "Data non valida: \(dateString)"
                }
            } else {
                hasError = true
                errorMessage = "Data mancante"
            }

            // Parse amount
            if let amountMapping = mappingDict[.amount],
               let amountIndex = amountMapping.csvColumnIndex,
               amountIndex < row.count {
                let amountString = row[amountIndex]
                amount = parseAmount(amountString)
                if amount == nil {
                    hasError = true
                    errorMessage = "Importo non valido: \(amountString)"
                }
            } else {
                hasError = true
                errorMessage = "Importo mancante"
            }

            // Get type
            if let typeMapping = mappingDict[.transactionType],
               let typeIndex = typeMapping.csvColumnIndex,
               typeIndex < row.count {
                type = row[typeIndex]
            }

            // Get category
            if let categoryMapping = mappingDict[.category],
               let categoryIndex = categoryMapping.csvColumnIndex,
               categoryIndex < row.count {
                category = row[categoryIndex]
            }

            // Get conto
            if let contoMapping = mappingDict[.sourceAccount],
               let contoIndex = contoMapping.csvColumnIndex,
               contoIndex < row.count {
                conto = row[contoIndex]
            }

            // Get description
            if let descMapping = mappingDict[.description],
               let descIndex = descMapping.csvColumnIndex,
               descIndex < row.count {
                description = row[descIndex]
            }

            previews.append(CSVPreviewRow(
                rowNumber: rowNumber,
                date: date,
                amount: amount,
                type: type,
                category: category,
                conto: conto,
                description: description,
                hasError: hasError,
                errorMessage: errorMessage
            ))
        }

        return previews
    }

    // MARK: - CSV Escaping

    public static func escapeCSVValue(_ value: String, delimiter: String) -> String {
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
