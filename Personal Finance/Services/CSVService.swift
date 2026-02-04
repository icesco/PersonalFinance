//
//  CSVService.swift
//  Personal Finance
//
//  Created by Claude on 04/02/26.
//

import Foundation
import SwiftData
import FinanceCore

actor CSVService {

    // MARK: - Parsing

    func parseCSV(from url: URL, options: CSVImportOptions = CSVImportOptions()) throws -> CSVParseResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let content = try String(contentsOf: url, encoding: options.encoding)
        return parseCSVContent(content, options: options)
    }

    func parseCSVContent(_ content: String, options: CSVImportOptions = CSVImportOptions()) -> CSVParseResult {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return CSVParseResult(headers: [], rows: [])
        }

        let delimiter = String(options.delimiter)

        // Parse headers
        let headers: [String]
        let dataLines: [String]

        if options.hasHeader {
            headers = parseCSVLine(lines[0], delimiter: delimiter)
            dataLines = Array(lines.dropFirst())
        } else {
            // Generate numbered headers
            let firstRow = parseCSVLine(lines[0], delimiter: delimiter)
            headers = (0..<firstRow.count).map { "Colonna \($0 + 1)" }
            dataLines = lines
        }

        // Parse data rows
        let rows = dataLines.map { parseCSVLine($0, delimiter: delimiter) }

        return CSVParseResult(headers: headers, rows: rows)
    }

    private func parseCSVLine(_ line: String, delimiter: String) -> [String] {
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

    /// Extracts unique values from a specific column with row counts
    func extractUniqueAccountValues(from result: CSVParseResult, columnIndex: Int) -> [CSVAccountValue] {
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

    /// Filters rows to only include those matching a specific account value
    func filterRows(from result: CSVParseResult, columnIndex: Int, value: String) -> CSVParseResult {
        let filteredRows = result.rows.filter { row in
            guard columnIndex < row.count else { return false }
            return row[columnIndex].trimmingCharacters(in: .whitespaces) == value
        }

        return CSVParseResult(headers: result.headers, rows: filteredRows)
    }

    // MARK: - Auto-Detection

    func detectColumnMapping(headers: [String]) -> [FieldMapping] {
        var mappings: [FieldMapping] = []

        for field in CSVField.allCases {
            var mapping = FieldMapping(field: field)

            // Try to auto-detect based on header names
            if let index = findMatchingColumn(for: field, in: headers) {
                mapping.csvColumnIndex = index
                mapping.csvColumnName = headers[index]
            }

            mappings.append(mapping)
        }

        return mappings
    }

    private func findMatchingColumn(for field: CSVField, in headers: [String]) -> Int? {
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

    func validateMapping(_ mappings: [FieldMapping]) -> [ValidationError] {
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

    // MARK: - Import

    func importTransactions(
        from result: CSVParseResult,
        mapping: [FieldMapping],
        options: CSVImportOptions,
        context: ModelContext,
        existingCategories: [FinanceCore.Category],
        existingConti: [Conto],
        account: Account,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> CSVImportResult {
        var importedCount = 0
        var skippedCount = 0
        var errorCount = 0
        var errors: [ImportError] = []
        var duplicatesSkipped = 0
        var zeroAmountsSkipped = 0

        // Create mapping dictionary for quick lookup
        let mappingDict = Dictionary(uniqueKeysWithValues: mapping.map { ($0.field, $0) })

        // Get existing transactions for duplicate detection
        let existingTransactions = try fetchExistingTransactions(context: context)

        let totalRows = result.rows.count

        for (rowIndex, row) in result.rows.enumerated() {
            let rowNumber = rowIndex + (options.hasHeader ? 2 : 1) // Account for header and 1-based indexing

            // Report progress
            progressCallback?(rowIndex + 1, totalRows)

            do {
                // Parse amount
                guard let amountMapping = mappingDict[.amount],
                      let amountIndex = amountMapping.csvColumnIndex,
                      amountIndex < row.count else {
                    throw ImportRowError.missingRequiredField(.amount)
                }

                let amountString = row[amountIndex]
                guard let amount = parseAmount(amountString) else {
                    throw ImportRowError.invalidAmount(amountString)
                }

                // Skip zero amounts if option enabled
                if options.ignoreZeroAmounts && amount == 0 {
                    zeroAmountsSkipped += 1
                    skippedCount += 1
                    continue
                }

                // Parse date
                guard let dateMapping = mappingDict[.date],
                      let dateIndex = dateMapping.csvColumnIndex,
                      dateIndex < row.count else {
                    throw ImportRowError.missingRequiredField(.date)
                }

                let dateString = row[dateIndex]
                guard let date = parseDate(dateString, format: options.dateFormat) else {
                    throw ImportRowError.invalidDate(dateString)
                }

                // Parse description
                let description: String?
                if let descMapping = mappingDict[.description],
                   let descIndex = descMapping.csvColumnIndex,
                   descIndex < row.count {
                    description = row[descIndex].isEmpty ? nil : row[descIndex]
                } else {
                    description = nil
                }

                // Parse notes
                let notes: String?
                if let notesMapping = mappingDict[.notes],
                   let notesIndex = notesMapping.csvColumnIndex,
                   notesIndex < row.count {
                    notes = row[notesIndex].isEmpty ? nil : row[notesIndex]
                } else {
                    notes = nil
                }

                // Check for duplicates
                if options.ignoreDuplicates {
                    if isDuplicate(date: date, amount: amount, description: description, existing: existingTransactions) {
                        duplicatesSkipped += 1
                        skippedCount += 1
                        continue
                    }
                }

                // Determine transaction type
                let transactionType = determineTransactionType(
                    row: row,
                    amount: amount,
                    mapping: mappingDict
                )

                // Find or create category
                let category = findOrCreateCategory(
                    row: row,
                    mapping: mappingDict,
                    existingCategories: existingCategories,
                    options: options,
                    context: context,
                    account: account
                )

                // Find conto
                let conto = findConto(
                    row: row,
                    mapping: mappingDict,
                    existingConti: existingConti,
                    options: options,
                    transactionType: transactionType
                )

                // Create transaction
                let transaction = Transaction(
                    amount: abs(amount),
                    type: transactionType,
                    date: date,
                    transactionDescription: description,
                    notes: notes
                )

                // Set relationships
                if let category = category {
                    transaction.setCategory(category)
                }

                switch transactionType {
                case .expense:
                    if let conto = conto {
                        transaction.setFromConto(conto)
                    }
                case .income:
                    if let conto = conto {
                        transaction.setToConto(conto)
                    }
                case .transfer:
                    // For transfers, try to set both source and target
                    if let sourceConto = findSourceConto(row: row, mapping: mappingDict, existingConti: existingConti) {
                        transaction.setFromConto(sourceConto)
                    }
                    if let targetConto = findTargetConto(row: row, mapping: mappingDict, existingConti: existingConti) {
                        transaction.setToConto(targetConto)
                    } else if let conto = conto {
                        transaction.setToConto(conto)
                    }
                }

                context.insert(transaction)
                importedCount += 1

            } catch let error as ImportRowError {
                errorCount += 1
                errors.append(ImportError(
                    rowNumber: rowNumber,
                    message: error.localizedDescription,
                    field: error.field,
                    rawValue: error.rawValue
                ))
            } catch {
                errorCount += 1
                errors.append(ImportError(
                    rowNumber: rowNumber,
                    message: error.localizedDescription,
                    field: nil,
                    rawValue: nil
                ))
            }
        }

        // Save context
        try context.save()

        return CSVImportResult(
            totalRows: result.rowCount,
            importedCount: importedCount,
            skippedCount: skippedCount,
            errorCount: errorCount,
            errors: errors,
            duplicatesSkipped: duplicatesSkipped,
            zeroAmountsSkipped: zeroAmountsSkipped
        )
    }

    // MARK: - Helper Methods

    private func parseAmount(_ string: String) -> Decimal? {
        var cleanedString = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")

        let hasComma = cleanedString.contains(",")
        let hasDot = cleanedString.contains(".")

        if hasComma && hasDot {
            // Both present: dot is thousands separator, comma is decimal (European format like 1.234,56)
            cleanedString = cleanedString
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else if hasComma && !hasDot {
            // Only comma: comma is decimal separator (European format like 1234,56)
            cleanedString = cleanedString.replacingOccurrences(of: ",", with: ".")
        }
        // If only dot or neither: dot is already decimal separator (International format like 1234.56)

        return Decimal(string: cleanedString)
    }

    func parseDate(_ string: String, format: CSVDateFormat) -> Date? {
        // Try the specified format first
        if let date = format.parse(string) {
            return date
        }

        // Try other common formats as fallback
        for otherFormat in CSVDateFormat.allCases where otherFormat != format {
            if let date = otherFormat.parse(string) {
                return date
            }
        }

        return nil
    }

    private func determineTransactionType(
        row: [String],
        amount: Decimal,
        mapping: [CSVField: FieldMapping]
    ) -> TransactionType {
        // Check if type is explicitly specified
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

        // Check if both source and target accounts are specified (transfer)
        let hasSourceAccount = mapping[.sourceAccount]?.isAssigned ?? false
        let hasTargetAccount = mapping[.targetAccount]?.isAssigned ?? false

        if hasSourceAccount && hasTargetAccount {
            // Check if both have values
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

        // Determine based on amount sign
        return amount >= 0 ? .income : .expense
    }

    private func findOrCreateCategory(
        row: [String],
        mapping: [CSVField: FieldMapping],
        existingCategories: [FinanceCore.Category],
        options: CSVImportOptions,
        context: ModelContext,
        account: Account
    ) -> FinanceCore.Category? {
        guard let categoryMapping = mapping[.category],
              let categoryIndex = categoryMapping.csvColumnIndex,
              categoryIndex < row.count else {
            return nil
        }

        let categoryName = row[categoryIndex].trimmingCharacters(in: .whitespaces)
        guard !categoryName.isEmpty else { return nil }

        // Try to find existing category
        if let existing = existingCategories.first(where: { $0.name?.lowercased() == categoryName.lowercased() }) {
            return existing
        }

        // Create new category if option enabled
        if options.createMissingCategories {
            let newCategory = FinanceCore.Category(name: categoryName)
            newCategory.account = account
            context.insert(newCategory)
            return newCategory
        }

        return nil
    }

    private func findConto(
        row: [String],
        mapping: [CSVField: FieldMapping],
        existingConti: [Conto],
        options: CSVImportOptions,
        transactionType: TransactionType
    ) -> Conto? {
        // Use default conto if specified
        if let defaultContoId = options.defaultContoId {
            return existingConti.first { $0.id == defaultContoId }
        }

        // Try source or target based on transaction type
        let contoField: CSVField = transactionType == .income ? .targetAccount : .sourceAccount

        if let contoMapping = mapping[contoField],
           let contoIndex = contoMapping.csvColumnIndex,
           contoIndex < row.count {
            let contoName = row[contoIndex].trimmingCharacters(in: .whitespaces)
            if let conto = existingConti.first(where: { $0.name?.lowercased() == contoName.lowercased() }) {
                return conto
            }
        }

        // Fallback to first conto
        return existingConti.first
    }

    private func findSourceConto(
        row: [String],
        mapping: [CSVField: FieldMapping],
        existingConti: [Conto]
    ) -> Conto? {
        guard let sourceMapping = mapping[.sourceAccount],
              let sourceIndex = sourceMapping.csvColumnIndex,
              sourceIndex < row.count else {
            return nil
        }

        let contoName = row[sourceIndex].trimmingCharacters(in: .whitespaces)
        return existingConti.first { $0.name?.lowercased() == contoName.lowercased() }
    }

    private func findTargetConto(
        row: [String],
        mapping: [CSVField: FieldMapping],
        existingConti: [Conto]
    ) -> Conto? {
        guard let targetMapping = mapping[.targetAccount],
              let targetIndex = targetMapping.csvColumnIndex,
              targetIndex < row.count else {
            return nil
        }

        let contoName = row[targetIndex].trimmingCharacters(in: .whitespaces)
        return existingConti.first { $0.name?.lowercased() == contoName.lowercased() }
    }

    private func isDuplicate(
        date: Date,
        amount: Decimal,
        description: String?,
        existing: [Transaction]
    ) -> Bool {
        let tolerance: TimeInterval = 5 * 60 // 5 minutes

        return existing.contains { transaction in
            guard let transactionAmount = transaction.amount else { return false }

            let dateMatches = abs(transaction.date.timeIntervalSince(date)) <= tolerance
            let amountMatches = abs(transactionAmount - abs(amount)) < 0.01
            let descriptionMatches = transaction.transactionDescription == description

            return dateMatches && amountMatches && descriptionMatches
        }
    }

    private func fetchExistingTransactions(context: ModelContext) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>()
        return try context.fetch(descriptor)
    }

    // MARK: - Export

    func exportTransactions(
        _ transactions: [Transaction],
        options: CSVExportOptions
    ) -> String {
        var lines: [String] = []

        // Add header if enabled
        if options.includeHeader {
            let headerFields = options.includeFields.sorted { $0.rawValue < $1.rawValue }
            let header = headerFields.map { $0.rawValue }.joined(separator: options.delimiter)
            lines.append(header)
        }

        // Filter transactions by date if specified
        var filteredTransactions = transactions

        if let dateFrom = options.dateFrom {
            filteredTransactions = filteredTransactions.filter { $0.date >= dateFrom }
        }

        if let dateTo = options.dateTo {
            filteredTransactions = filteredTransactions.filter { $0.date <= dateTo }
        }

        // Filter by conto if specified
        if !options.contoIds.isEmpty {
            filteredTransactions = filteredTransactions.filter { transaction in
                if let fromContoId = transaction.fromContoId, options.contoIds.contains(fromContoId) {
                    return true
                }
                if let toContoId = transaction.toContoId, options.contoIds.contains(toContoId) {
                    return true
                }
                return false
            }
        }

        // Sort by date descending
        filteredTransactions.sort { $0.date > $1.date }

        // Generate rows
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = options.dateFormat.rawValue
        dateFormatter.locale = Locale(identifier: "it_IT")

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.locale = Locale(identifier: "it_IT")

        for transaction in filteredTransactions {
            var values: [String] = []

            let sortedFields = options.includeFields.sorted { $0.rawValue < $1.rawValue }

            for field in sortedFields {
                let value = exportValue(for: field, from: transaction, dateFormatter: dateFormatter, numberFormatter: numberFormatter)
                values.append(escapeCSVValue(value, delimiter: options.delimiter))
            }

            lines.append(values.joined(separator: options.delimiter))
        }

        return lines.joined(separator: "\n")
    }

    private func exportValue(
        for field: CSVField,
        from transaction: Transaction,
        dateFormatter: DateFormatter,
        numberFormatter: NumberFormatter
    ) -> String {
        switch field {
        case .transactionType:
            return transaction.type.displayName
        case .amount:
            if let amount = transaction.amount {
                return numberFormatter.string(from: amount as NSDecimalNumber) ?? ""
            }
            return ""
        case .sourceCurrency, .targetCurrency:
            return "EUR"
        case .exchangeRate:
            return "1"
        case .sourceAccount:
            return transaction.fromConto?.name ?? ""
        case .targetAccount:
            return transaction.toConto?.name ?? ""
        case .category:
            return transaction.category?.name ?? ""
        case .payee:
            return ""
        case .date:
            return dateFormatter.string(from: transaction.date)
        case .notes:
            return transaction.notes ?? ""
        case .description:
            return transaction.transactionDescription ?? ""
        }
    }

    private func escapeCSVValue(_ value: String, delimiter: String) -> String {
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Preview Generation

    func generatePreview(
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
}

// MARK: - Import Row Error

enum ImportRowError: LocalizedError {
    case missingRequiredField(CSVField)
    case invalidAmount(String)
    case invalidDate(String)
    case contoNotFound(String)
    case categoryNotFound(String)

    var field: CSVField? {
        switch self {
        case .missingRequiredField(let field): return field
        case .invalidAmount: return .amount
        case .invalidDate: return .date
        case .contoNotFound: return .sourceAccount
        case .categoryNotFound: return .category
        }
    }

    var rawValue: String? {
        switch self {
        case .missingRequiredField: return nil
        case .invalidAmount(let value): return value
        case .invalidDate(let value): return value
        case .contoNotFound(let value): return value
        case .categoryNotFound(let value): return value
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Campo obbligatorio mancante: \(field.rawValue)"
        case .invalidAmount(let value):
            return "Importo non valido: \(value)"
        case .invalidDate(let value):
            return "Data non valida: \(value)"
        case .contoNotFound(let name):
            return "Conto non trovato: \(name)"
        case .categoryNotFound(let name):
            return "Categoria non trovata: \(name)"
        }
    }
}
