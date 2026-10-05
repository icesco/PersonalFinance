//
//  CSVService.swift
//  Personal Finance
//
//  SwiftData import/export service. Delegates pure parsing to CSVParser (FinanceCore).
//

import Foundation
import SwiftData
import CryptoKit
import FinanceCore

actor CSVService {
    enum ImportFailure: Error {
        case invalidNewBook
    }

    private let save: @Sendable (ModelContext) throws -> Void

    init(save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() }) {
        self.save = save
    }


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
        newBookName: String? = nil,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> CSVImportResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let accountPredicate = #Predicate<Account> { $0.id == accountId }
        var accountDescriptor = FetchDescriptor(predicate: accountPredicate)
        accountDescriptor.fetchLimit = 1
        let existingAccount = try context.fetch(accountDescriptor).first
        let destination: Account?
        if let newBookName {
            let name = newBookName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, existingAccount == nil else { throw ImportFailure.invalidNewBook }
            let book = Account(name: name)
            book.id = accountId
            context.insert(book)
            destination = book
        } else {
            destination = existingAccount
        }
        guard let account = destination else {
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
            .filter { $0.account?.id == accountId }
        var existingConti = try context.fetch(FetchDescriptor<Conto>())
            .filter { $0.account?.id == accountId }

        var importedCount = 0
        var skippedCount = 0
        var errorCount = 0
        var errors: [ImportError] = []
        var duplicatesSkipped = 0
        var zeroAmountsSkipped = 0

        var createdCategories: [String: FinanceCore.Category] = [:]

        let mappingDict = Dictionary(uniqueKeysWithValues: mapping.map { ($0.field, $0) })

        let existingTransactions = try fetchExistingTransactions(context: context)
        var existingExternalIDs = Set(existingTransactions.map(\.externalID))
        var importedKeys = Set<String>()
        var identicalRowOccurrences: [String: Int] = [:]

        let totalRows = result.rows.count
        let isBudgetFlowExport = CSVParser.isBudgetFlowExport(result)
        let pendingIndex = result.headers.firstIndex { $0.caseInsensitiveCompare("Pending") == .orderedSame }

        for (rowIndex, row) in result.rows.enumerated() {
            let rowNumber = rowIndex + (options.hasHeader ? 2 : 1)

            progressCallback?(rowIndex + 1, totalRows)

            do {
                if let pendingIndex, pendingIndex < row.count,
                   ["true", "1", "yes"].contains(row[pendingIndex].trimmingCharacters(in: .whitespaces).lowercased()) {
                    skippedCount += 1
                    continue
                }
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

                func value(_ field: CSVField) -> String? {
                    guard let index = mappingDict[field]?.csvColumnIndex, index < row.count else { return nil }
                    let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
                let currency = account.currency ?? "EUR"
                for field in [CSVField.sourceCurrency, .targetCurrency] {
                    if let declared = value(field), declared.uppercased() != currency {
                        throw ImportRowError.invalidCurrency(declared)
                    }
                }
                let originalAmount = value(.originalAmount).flatMap(CSVParser.parseAmount)
                let originalCurrency = value(.originalCurrency)?.uppercased()
                let originalRate = value(.originalExchangeRate).flatMap(CSVParser.parseAmount)
                let hasOriginal = [.originalAmount, .originalCurrency, .originalExchangeRate].contains { value($0) != nil }
                if hasOriginal {
                    guard let originalAmount, let originalCurrency, let originalRate,
                          Locale.commonISOCurrencyCodes.contains(originalCurrency),
                          (try? CurrencyConversion.convert(originalAmount, rate: originalRate, currency: currency)) == abs(amount) else {
                        throw ImportRowError.invalidCurrency("Dati della conversione originale incompleti o incoerenti")
                    }
                }
                let destinationAmount = value(.destinationAmount).flatMap(CSVParser.parseAmount)
                if value(.destinationAmount) != nil && (destinationAmount == nil || destinationAmount! <= 0) {
                    throw ImportRowError.invalidAmount(value(.destinationAmount)!)
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
                   descIndex < row.count, !row[descIndex].isEmpty {
                    description = row[descIndex]
                } else if let payeeIndex = mappingDict[.payee]?.csvColumnIndex,
                          payeeIndex < row.count, !row[payeeIndex].isEmpty {
                    description = row[payeeIndex]
                } else if let notesIndex = mappingDict[.notes]?.csvColumnIndex,
                          notesIndex < row.count, !row[notesIndex].isEmpty {
                    description = row[notesIndex]
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

                // Determine transaction type
                let transactionType = CSVParser.determineTransactionType(
                    row: row,
                    amount: amount,
                    mapping: mappingDict,
                    amountConvention: options.amountConvention
                )

                // Resolve both sides before inserting anything. Unknown accounts must not
                // silently become the first account in another book.
                let sourceConto = try resolveConto(
                    field: .sourceAccount, row: row, mapping: mappingDict,
                    existingConti: &existingConti, options: options, account: account, context: context
                )
                let targetConto = try resolveConto(
                    field: .targetAccount, row: row, mapping: mappingDict,
                    existingConti: &existingConti, options: options, account: account, context: context
                )
                let conto = findConto(
                    row: row, mapping: mappingDict, existingConti: existingConti,
                    options: options, transactionType: transactionType
                )
                var fromConto: Conto?
                var toConto: Conto?
                switch transactionType {
                case .expense: fromConto = conto
                case .income: toConto = conto
                case .transfer:
                    if let sourceConto, let targetConto {
                        let explicitDirection = !isBudgetFlowExport &&
                            ["transfer", "trasferimento"].contains(value(.transactionType)?.lowercased() ?? "")
                        if amount < 0 || explicitDirection {
                            fromConto = sourceConto
                            toConto = targetConto
                        } else {
                            fromConto = targetConto
                            toConto = sourceConto
                        }
                    } else if sourceConto == nil && targetConto == nil, let conto {
                        if amount < 0 { fromConto = conto }
                        else { toConto = conto }
                    } else {
                        throw ImportRowError.contoNotFound("Conto del trasferimento")
                    }
                }
                guard fromConto != nil || toConto != nil else {
                    throw ImportRowError.contoNotFound("Seleziona un conto per il file o correggi il nome nella riga")
                }

                let duplicateKey = importKey(
                    date: date, amount: amount, type: transactionType,
                    description: description, fromContoId: fromConto?.id, toContoId: toConto?.id
                )
                var budgetFlowExternalID: String?
                if isBudgetFlowExport && transactionType != .transfer {
                    // Budget Flow has no row ID. Preserve identical legitimate rows by
                    // numbering each identical occurrence, then recognize it on reimport.
                    let rawRow = row.joined(separator: "\u{1F}")
                    let occurrence = identicalRowOccurrences[rawRow, default: 0]
                    identicalRowOccurrences[rawRow] = occurrence + 1
                    let fingerprint = SHA256.hash(data: Data(rawRow.utf8))
                        .map { String(format: "%02x", $0) }.joined()
                    budgetFlowExternalID = "budgetflow:\(accountId.uuidString):\(fingerprint):\(occurrence)"
                }
                let alreadyImported = if let budgetFlowExternalID {
                    existingExternalIDs.contains(budgetFlowExternalID)
                } else {
                    importedKeys.contains(duplicateKey) || isDuplicate(
                        date: date, amount: amount, type: transactionType,
                        description: description, fromContoId: fromConto?.id,
                        toContoId: toConto?.id, existing: existingTransactions
                    )
                }
                if options.ignoreDuplicates && alreadyImported {
                    duplicatesSkipped += 1
                    skippedCount += 1
                    continue
                }

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

                // Create transaction
                let transaction = Transaction(
                    amount: abs(amount),
                    type: transactionType,
                    date: date,
                    transactionDescription: description,
                    notes: notes
                )
                transaction.originalAmount = originalAmount
                transaction.originalCurrency = originalCurrency
                transaction.exchangeRate = originalRate
                transaction.exchangeRateDate = value(.originalRateDate)
                transaction.exchangeRateSource = value(.originalRateSource)
                if transactionType == .transfer { transaction.destinationAmount = destinationAmount }
                if let budgetFlowExternalID {
                    transaction.externalID = budgetFlowExternalID
                    existingExternalIDs.insert(budgetFlowExternalID)
                }

                // Set relationships
                if let category = category {
                    transaction.setCategory(category)
                }

                transaction.setFromConto(fromConto)
                transaction.setToConto(toConto)

                context.insert(transaction)
                importedKeys.insert(duplicateKey)
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

        if importedCount == 0 {
            context.rollback()
        } else {
            do { try save(context) }
            catch {
                context.rollback()
                throw error
            }
        }

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
        let preferred: CSVField = transactionType == .income ? .targetAccount : .sourceAccount
        let secondary: CSVField = transactionType == .income ? .sourceAccount : .targetAccount
        var hasNamedAccount = false
        for field in [preferred, secondary] {
            guard let index = mapping[field]?.csvColumnIndex, index < row.count else { continue }
            let name = row[index].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            hasNamedAccount = true
            if let match = existingConti.first(where: { $0.name?.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return match
            }
        }
        if hasNamedAccount { return nil }
        if let defaultContoId = options.defaultContoId {
            return existingConti.first { $0.id == defaultContoId }
        }
        return existingConti.count == 1 ? existingConti.first : nil
    }

    private func resolveConto(
        field: CSVField, row: [String], mapping: [CSVField: FieldMapping],
        existingConti: inout [Conto], options: CSVImportOptions,
        account: Account, context: ModelContext
    ) throws -> Conto? {
        guard let index = mapping[field]?.csvColumnIndex, index < row.count else { return nil }
        let name = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = existingConti.first(where: { $0.name?.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        guard options.createMissingConti,
              let rawType = options.missingContoTypes[name.lowercased()],
              let type = ContoType(rawValue: rawType) else {
            throw ImportRowError.contoNotFound(name)
        }
        let conto = Conto(name: name, type: type)
        // An imported ledger does not prove the account's opening balance.
        conto.initialBalance = nil
        conto.account = account
        context.insert(conto)
        existingConti.append(conto)
        return conto
    }

    private func isDuplicate(
        date: Date,
        amount: Decimal,
        type: TransactionType,
        description: String?,
        fromContoId: UUID?,
        toContoId: UUID?,
        existing: [Transaction]
    ) -> Bool {
        let tolerance: TimeInterval = 5 * 60

        return existing.contains { transaction in
            guard let transactionAmount = transaction.amount else { return false }

            let dateMatches = abs(transaction.date.timeIntervalSince(date)) <= tolerance
            let amountMatches = abs(transactionAmount - abs(amount)) < 0.01
            let descriptionMatches = type == .transfer ||
                transaction.transactionDescription == description

            return dateMatches && amountMatches && descriptionMatches &&
                transaction.type == type && transaction.fromContoId == fromContoId &&
                transaction.toContoId == toContoId
        }
    }

    private func importKey(
        date: Date, amount: Decimal, type: TransactionType,
        description: String?, fromContoId: UUID?, toContoId: UUID?
    ) -> String {
        let note = type == .transfer ? "" : (description ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return "\(date.timeIntervalSince1970)|\(abs(amount))|\(type.rawValue)|\(fromContoId?.uuidString ?? "")|\(toContoId?.uuidString ?? "")|\(note)"
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
        numberFormatter.maximumFractionDigits = 38
        numberFormatter.usesGroupingSeparator = false
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
                let signed = transaction.type == .income ? abs(amount) : -abs(amount)
                return numberFormatter.string(from: signed as NSDecimalNumber) ?? ""
            }
            return ""
        case .sourceCurrency:
            return transaction.fromConto?.account?.currency ?? transaction.toConto?.account?.currency ?? ""
        case .targetCurrency:
            return transaction.toConto?.account?.currency ?? transaction.fromConto?.account?.currency ?? ""
        case .exchangeRate:
            if transaction.type == .transfer, let amount = transaction.amount, amount > 0,
               let destination = transaction.destinationAmount {
                return NSDecimalNumber(decimal: destination / amount).stringValue
            }
            return "1"
        case .originalAmount:
            return transaction.originalAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        case .originalCurrency:
            return transaction.originalCurrency ?? ""
        case .originalExchangeRate:
            return transaction.exchangeRate.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        case .originalRateDate:
            return transaction.exchangeRateDate ?? ""
        case .originalRateSource:
            return transaction.exchangeRateSource ?? ""
        case .destinationAmount:
            return transaction.destinationAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
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
