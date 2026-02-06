//
//  CSVService.swift
//  Personal Finance
//
//  SwiftData import/export service. Delegates pure parsing to CSVParser (FinanceCore).
//

import Foundation
import SwiftData
import FinanceCore

actor CSVService {

    // MARK: - File I/O Parsing

    func parseCSV(from url: URL, options: CSVImportOptions = CSVImportOptions()) throws -> CSVParseResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let content = try String(contentsOf: url, encoding: options.encoding)
        return CSVParser.parseCSVContent(content, options: options)
    }

    // MARK: - Import

    func importTransactions(
        from result: CSVParseResult,
        mapping: [FieldMapping],
        options: CSVImportOptions,
        container: ModelContainer,
        accountId: UUID,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> CSVImportResult {
        let context = ModelContext(container)

        let accountPredicate = #Predicate<Account> { $0.id == accountId }
        var accountDescriptor = FetchDescriptor(predicate: accountPredicate)
        accountDescriptor.fetchLimit = 1
        guard let account = try context.fetch(accountDescriptor).first else {
            return CSVImportResult(
                totalRows: result.rowCount,
                importedCount: 0,
                skippedCount: 0,
                errorCount: 1,
                errors: [ImportError(rowNumber: 0, message: "Account non trovato", field: nil, rawValue: nil)],
                duplicatesSkipped: 0,
                zeroAmountsSkipped: 0
            )
        }

        let existingCategories = try context.fetch(FetchDescriptor<FinanceCore.Category>())
        let existingConti = try context.fetch(FetchDescriptor<Conto>())

        var importedCount = 0
        var skippedCount = 0
        var errorCount = 0
        var errors: [ImportError] = []
        var duplicatesSkipped = 0
        var zeroAmountsSkipped = 0

        var createdCategories: [String: FinanceCore.Category] = [:]

        let mappingDict = Dictionary(uniqueKeysWithValues: mapping.map { ($0.field, $0) })

        let existingTransactions = try fetchExistingTransactions(context: context)

        let totalRows = result.rows.count

        for (rowIndex, row) in result.rows.enumerated() {
            let rowNumber = rowIndex + (options.hasHeader ? 2 : 1)

            progressCallback?(rowIndex + 1, totalRows)

            do {
                // Parse amount
                guard let amountMapping = mappingDict[.amount],
                      let amountIndex = amountMapping.csvColumnIndex,
                      amountIndex < row.count else {
                    throw ImportRowError.missingRequiredField(.amount)
                }

                let amountString = row[amountIndex]
                guard let amount = CSVParser.parseAmount(amountString) else {
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
                guard let date = CSVParser.parseDate(dateString, format: options.dateFormat) else {
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
                let transactionType = CSVParser.determineTransactionType(
                    row: row,
                    amount: amount,
                    mapping: mappingDict
                )

                // Find or create category
                let category = findOrCreateCategory(
                    row: row,
                    mapping: mappingDict,
                    existingCategories: existingCategories,
                    createdCategories: &createdCategories,
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
                    let sourceConto = findSourceConto(row: row, mapping: mappingDict, existingConti: existingConti)
                    let targetConto = findTargetConto(row: row, mapping: mappingDict, existingConti: existingConti)

                    if let sourceConto {
                        transaction.setFromConto(sourceConto)
                    }
                    if let targetConto {
                        transaction.setToConto(targetConto)
                    }

                    // When neither source nor target account is explicitly mapped,
                    // use the original amount sign to determine direction
                    if sourceConto == nil && targetConto == nil, let conto = conto {
                        if amount < 0 {
                            transaction.setFromConto(conto) // Money leaving → outgoing
                        } else {
                            transaction.setToConto(conto)   // Money arriving → incoming
                        }
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

    // MARK: - SwiftData Helpers

    private func findOrCreateCategory(
        row: [String],
        mapping: [CSVField: FieldMapping],
        existingCategories: [FinanceCore.Category],
        createdCategories: inout [String: FinanceCore.Category],
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

        let normalizedName = categoryName.lowercased()

        if let created = createdCategories[normalizedName] {
            return created
        }

        if let existing = existingCategories.first(where: { $0.name?.lowercased() == normalizedName }) {
            return existing
        }

        if options.createMissingCategories {
            let newCategory = FinanceCore.Category(name: categoryName)
            newCategory.account = account
            context.insert(newCategory)
            createdCategories[normalizedName] = newCategory
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
        if let defaultContoId = options.defaultContoId {
            return existingConti.first { $0.id == defaultContoId }
        }

        let contoField: CSVField = transactionType == .income ? .targetAccount : .sourceAccount

        if let contoMapping = mapping[contoField],
           let contoIndex = contoMapping.csvColumnIndex,
           contoIndex < row.count {
            let contoName = row[contoIndex].trimmingCharacters(in: .whitespaces)
            if let conto = existingConti.first(where: { $0.name?.lowercased() == contoName.lowercased() }) {
                return conto
            }
        }

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
        let tolerance: TimeInterval = 5 * 60

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

        if options.includeHeader {
            let headerFields = options.includeFields.sorted { $0.rawValue < $1.rawValue }
            let header = headerFields.map { $0.rawValue }.joined(separator: options.delimiter)
            lines.append(header)
        }

        var filteredTransactions = transactions

        if let dateFrom = options.dateFrom {
            filteredTransactions = filteredTransactions.filter { $0.date >= dateFrom }
        }

        if let dateTo = options.dateTo {
            filteredTransactions = filteredTransactions.filter { $0.date <= dateTo }
        }

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

        filteredTransactions.sort { $0.date > $1.date }

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
                values.append(CSVParser.escapeCSVValue(value, delimiter: options.delimiter))
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
}
