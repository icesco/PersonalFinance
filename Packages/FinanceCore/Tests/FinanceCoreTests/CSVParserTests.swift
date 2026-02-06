//
//  CSVParserTests.swift
//  FinanceCoreTests
//
//  Tests for CSVParser pure parsing logic using real CSV data.
//

import Testing
import Foundation
@testable import FinanceCore

// MARK: - Helper

private func loadRealCSV() throws -> String {
    guard let url = Bundle.module.url(forResource: "Conto-Principale", withExtension: "csv", subdirectory: "Resources") else {
        throw CSVTestError.resourceNotFound
    }
    return try String(contentsOf: url, encoding: .utf8)
}

private enum CSVTestError: Error {
    case resourceNotFound
}

// MARK: - Group 1: Basic Parsing

struct CSVParserBasicTests {

    @Test func parseCSVContent_shouldExtractHeadersFromRealCSV() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        #expect(result.headers.count == 14)
        #expect(result.headers[0] == "Date")
        #expect(result.headers[1] == "Amount")
        #expect(result.headers[6] == "Source Account")
        #expect(result.headers[7] == "Target Account")
        #expect(result.headers[9] == "Category")
        #expect(result.headers[12] == "Notes")
        #expect(result.headers[13] == "Pending")
    }

    @Test func parseCSVContent_shouldExtractCorrectRowCountFromRealCSV() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        #expect(result.rowCount == 811)
    }

    @Test func parseAmount_shouldParseNegativeAmount() {
        let amount = CSVParser.parseAmount("-304.0")
        #expect(amount == Decimal(string: "-304.0"))
    }

    @Test func parseAmount_shouldParsePositiveAmount() {
        let amount = CSVParser.parseAmount("1442.0")
        #expect(amount == Decimal(string: "1442.0"))
    }

    @Test func parseAmount_shouldParseZeroAmount() {
        let amount = CSVParser.parseAmount("0")
        #expect(amount == Decimal(0))
    }

    @Test func parseAmount_shouldParseEuropeanFormat() {
        // European: comma as decimal separator
        let amount = CSVParser.parseAmount("1234,56")
        #expect(amount == Decimal(string: "1234.56"))
    }

    @Test func parseAmount_shouldParseEuropeanFormatWithThousandsSeparator() {
        // European: dot as thousands, comma as decimal
        let amount = CSVParser.parseAmount("1.234,56")
        #expect(amount == Decimal(string: "1234.56"))
    }

    @Test func parseCSVContent_shouldHandleQuotedFieldsWithCommas() {
        let csv = """
        Name,Description
        Test,"Description with, comma inside"
        """
        let result = CSVParser.parseCSVContent(csv)
        #expect(result.rows[0][1] == "Description with, comma inside")
    }

    @Test func parseCSVContent_shouldHandleEmptyContent() {
        let result = CSVParser.parseCSVContent("")
        #expect(result.headers.isEmpty)
        #expect(result.rowCount == 0)
    }

    @Test func parseCSVContent_shouldHandleHeaderOnly() {
        let result = CSVParser.parseCSVContent("Date,Amount,Category")
        #expect(result.headers.count == 3)
        #expect(result.rowCount == 0)
    }

    @Test func parseCSVContent_shouldHandleCustomDelimiter() {
        let csv = """
        Date;Amount;Category
        2025-01-01;100;Food
        """
        var options = CSVImportOptions()
        options.delimiter = ";"
        let result = CSVParser.parseCSVContent(csv, options: options)

        #expect(result.headers == ["Date", "Amount", "Category"])
        #expect(result.rows[0] == ["2025-01-01", "100", "Food"])
    }
}

// MARK: - Group 2: Date Parsing

struct CSVParserDateTests {

    @Test func parseDate_shouldParseISO8601WithPositiveOffset0100() {
        let dateString = "2025-01-02T00:00:00+0100"
        let date = CSVParser.parseDate(dateString, format: .iso8601Offset)

        #expect(date != nil)
        if let date = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: TimeZone(identifier: "Europe/Rome")!, from: date)
            #expect(components.year == 2025)
            #expect(components.month == 1)
            #expect(components.day == 2)
        }
    }

    @Test func parseDate_shouldParseISO8601WithPositiveOffset0200() {
        // Summer time (CEST)
        let dateString = "2025-04-09T00:00:00+0200"
        let date = CSVParser.parseDate(dateString, format: .iso8601Offset)

        #expect(date != nil)
        if let date = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: TimeZone(identifier: "Europe/Rome")!, from: date)
            #expect(components.year == 2025)
            #expect(components.month == 4)
            #expect(components.day == 9)
        }
    }

    @Test func parseDate_shouldParseEuropeanDateOnly() {
        let dateString = "02/01/2025"
        let date = CSVParser.parseDate(dateString, format: .euSlashDateOnly)

        #expect(date != nil)
    }

    @Test func parseDate_shouldParseISODateOnly() {
        let dateString = "2025-01-02"
        let date = CSVParser.parseDate(dateString, format: .iso8601DateOnly)

        #expect(date != nil)
    }

    @Test func parseDate_shouldReturnNilForInvalidDate() {
        let date = CSVParser.parseDate("invalid-date", format: .iso8601Offset)
        #expect(date == nil)
    }
}

// MARK: - Group 3: Auto-Detection

struct CSVParserAutoDetectionTests {

    @Test func detectColumnMapping_shouldDetectFromRealCSVHeaders() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)

        let mappingDict = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field, $0) })

        #expect(mappingDict[.date]?.csvColumnIndex == 0)
        #expect(mappingDict[.amount]?.csvColumnIndex == 1)
        #expect(mappingDict[.sourceAccount]?.csvColumnIndex == 6)
        #expect(mappingDict[.targetAccount]?.csvColumnIndex == 7)
        #expect(mappingDict[.category]?.csvColumnIndex == 9)
        #expect(mappingDict[.notes]?.csvColumnIndex == 12)
    }

    @Test func detectColumnMapping_shouldDetectItalianHeaders() {
        let headers = ["Data", "Importo", "Categoria", "Descrizione"]
        let mappings = CSVParser.detectColumnMapping(headers: headers)
        let mappingDict = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field, $0) })

        #expect(mappingDict[.date]?.csvColumnIndex == 0)
        #expect(mappingDict[.amount]?.csvColumnIndex == 1)
        #expect(mappingDict[.category]?.csvColumnIndex == 2)
        #expect(mappingDict[.description]?.csvColumnIndex == 3)
    }

    @Test func detectColumnMapping_shouldHandleMixedCaseHeaders() {
        let headers = ["DATE", "amount", "Category"]
        let mappings = CSVParser.detectColumnMapping(headers: headers)
        let mappingDict = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field, $0) })

        #expect(mappingDict[.date]?.csvColumnIndex == 0)
        #expect(mappingDict[.amount]?.csvColumnIndex == 1)
        #expect(mappingDict[.category]?.csvColumnIndex == 2)
    }

    @Test func detectColumnMapping_shouldReturnNilForNoMatch() {
        let headers = ["Col1", "Col2", "Col3"]
        let mappings = CSVParser.detectColumnMapping(headers: headers)

        // None of the required fields should be matched
        let dateMapping = mappings.first { $0.field == .date }
        let amountMapping = mappings.first { $0.field == .amount }

        #expect(dateMapping?.csvColumnIndex == nil)
        #expect(amountMapping?.csvColumnIndex == nil)
    }

    @Test func detectColumnMapping_shouldDetectExchangeRate() {
        let headers = ["Date", "Amount", "Exchange Rate"]
        let mappings = CSVParser.detectColumnMapping(headers: headers)
        let mappingDict = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field, $0) })

        #expect(mappingDict[.exchangeRate]?.csvColumnIndex == 2)
    }
}

// MARK: - Group 4: Account Filtering with Real Data

struct CSVParserAccountFilterTests {

    @Test func extractUniqueAccountValues_shouldFind4SourceAccounts() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        // Source Account = column 6
        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)

        #expect(accountValues.count == 4)

        let names = Set(accountValues.map(\.value))
        #expect(names.contains("Conto Crédit Agricole"))
        #expect(names.contains("AMEX"))
        #expect(names.contains("Revolut"))
        #expect(names.contains("PAC"))
    }

    @Test func extractUniqueAccountValues_shouldCountCreditAgricoleCorrectly() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)
        let ca = accountValues.first { $0.value == "Conto Crédit Agricole" }

        #expect(ca?.rowCount == 393)
    }

    @Test func extractUniqueAccountValues_shouldCountAMEXCorrectly() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)
        let amex = accountValues.first { $0.value == "AMEX" }

        #expect(amex?.rowCount == 331)
    }

    @Test func extractUniqueAccountValues_shouldCountRevolutCorrectly() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)
        let revolut = accountValues.first { $0.value == "Revolut" }

        #expect(revolut?.rowCount == 75)
    }

    @Test func extractUniqueAccountValues_shouldCountPACCorrectly() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)
        let pac = accountValues.first { $0.value == "PAC" }

        #expect(pac?.rowCount == 12)
    }

    @Test func extractUniqueAccountValues_shouldBeSortedByFrequencyDescending() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 6)

        // First should be the most frequent
        #expect(accountValues[0].value == "Conto Crédit Agricole")
        #expect(accountValues[0].rowCount == 393)

        // Verify ordering
        for i in 0..<(accountValues.count - 1) {
            #expect(accountValues[i].rowCount >= accountValues[i + 1].rowCount)
        }
    }

    @Test func extractUniqueAccountValues_shouldFindTargetAccounts() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        // Target Account = column 7
        let targetValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 7)

        let names = Set(targetValues.map(\.value))
        #expect(names.contains("PAC"))
        #expect(names.contains("Conto Crédit Agricole"))
    }

    @Test func filterRows_shouldFilterPACBySourceAccount() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 6, value: "PAC")

        #expect(filtered.rowCount == 12)
    }

    @Test func filterRows_shouldFilterPACByTargetAccount() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")

        #expect(filtered.rowCount == 12)
    }

    @Test func filterRows_shouldFilterAMEXBySourceAccount() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 6, value: "AMEX")

        #expect(filtered.rowCount == 331)
    }

    @Test func filterRows_shouldFilterRevolutBySourceAccount() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 6, value: "Revolut")

        #expect(filtered.rowCount == 75)
    }

    @Test func filterRows_shouldReturnZeroForNonExistentValue() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 6, value: "NonExistent")

        #expect(filtered.rowCount == 0)
    }

    @Test func filterRows_shouldPreserveHeaders() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 6, value: "PAC")

        #expect(filtered.headers == result.headers)
        #expect(filtered.columnCount == result.columnCount)
    }

    @Test func extractUniqueAccountValues_shouldIgnoreEmptyColumns() {
        let csv = """
        Date,Amount,Account
        2025-01-01,100,
        2025-01-02,200,Conto A
        2025-01-03,150,
        """
        let result = CSVParser.parseCSVContent(csv)
        let accountValues = CSVParser.extractUniqueAccountValues(from: result, columnIndex: 2)

        #expect(accountValues.count == 1)
        #expect(accountValues.first?.value == "Conto A")
    }
}

// MARK: - Group 5: Transaction Type Detection

struct CSVParserTransactionTypeTests {

    @Test func determineTransactionType_shouldReturnTransferWhenBothAccountsPresent() {
        let row = ["2025-01-14", "-300.0", "EUR", "EUR", "1.0", "Book", "Source", "Target", "", "Cat", "", "", "", ""]
        let mapping: [CSVField: FieldMapping] = [
            .sourceAccount: FieldMapping(field: .sourceAccount, csvColumnIndex: 6, csvColumnName: "Source Account"),
            .targetAccount: FieldMapping(field: .targetAccount, csvColumnIndex: 7, csvColumnName: "Target Account")
        ]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(-300), mapping: mapping)
        #expect(type == .transfer)
    }

    @Test func determineTransactionType_shouldReturnExpenseForNegativeAmountWithSourceOnly() {
        let row = ["2025-01-14", "-300.0", "EUR", "EUR", "1.0", "Book", "Source", "", "", "Cat", "", "", "", ""]
        let mapping: [CSVField: FieldMapping] = [
            .sourceAccount: FieldMapping(field: .sourceAccount, csvColumnIndex: 6, csvColumnName: "Source Account"),
            .targetAccount: FieldMapping(field: .targetAccount, csvColumnIndex: 7, csvColumnName: "Target Account")
        ]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(-300), mapping: mapping)
        #expect(type == .expense)
    }

    @Test func determineTransactionType_shouldReturnIncomeForPositiveAmountWithSourceOnly() {
        let row = ["2025-01-14", "300.0", "EUR", "EUR", "1.0", "Book", "Source", "", "", "Cat", "", "", "", ""]
        let mapping: [CSVField: FieldMapping] = [
            .sourceAccount: FieldMapping(field: .sourceAccount, csvColumnIndex: 6, csvColumnName: "Source Account"),
            .targetAccount: FieldMapping(field: .targetAccount, csvColumnIndex: 7, csvColumnName: "Target Account")
        ]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(300), mapping: mapping)
        #expect(type == .income)
    }

    @Test func determineTransactionType_shouldUseExplicitTypeColumn() {
        let row = ["2025-01-14", "300.0", "Entrata"]
        let mapping: [CSVField: FieldMapping] = [
            .transactionType: FieldMapping(field: .transactionType, csvColumnIndex: 2, csvColumnName: "Type")
        ]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(300), mapping: mapping)
        #expect(type == .income)
    }

    @Test func determineTransactionType_shouldDetectTransferFromExplicitType() {
        let row = ["2025-01-14", "-300.0", "Trasferimento"]
        let mapping: [CSVField: FieldMapping] = [
            .transactionType: FieldMapping(field: .transactionType, csvColumnIndex: 2, csvColumnName: "Type")
        ]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(-300), mapping: mapping)
        #expect(type == .transfer)
    }

    @Test func determineTransactionType_shouldReturnIncomeForZeroAmount() {
        let row = ["2025-01-14", "0"]
        let mapping: [CSVField: FieldMapping] = [:]

        let type = CSVParser.determineTransactionType(row: row, amount: Decimal(0), mapping: mapping)
        #expect(type == .income)
    }
}

// MARK: - Group 6: Validation

struct CSVParserValidationTests {

    @Test func validateMapping_shouldReturnErrorsForMissingRequiredFields() {
        let mappings = [
            FieldMapping(field: .amount),
            FieldMapping(field: .date),
            FieldMapping(field: .category, csvColumnIndex: 9, csvColumnName: "Category")
        ]

        let errors = CSVParser.validateMapping(mappings)

        #expect(errors.count == 2)
        #expect(errors.contains { $0.field == .amount })
        #expect(errors.contains { $0.field == .date })
    }

    @Test func validateMapping_shouldReturnNoErrorsWhenRequiredFieldsAssigned() {
        let mappings = [
            FieldMapping(field: .amount, csvColumnIndex: 1, csvColumnName: "Amount"),
            FieldMapping(field: .date, csvColumnIndex: 0, csvColumnName: "Date"),
            FieldMapping(field: .category)
        ]

        let errors = CSVParser.validateMapping(mappings)
        #expect(errors.isEmpty)
    }

    @Test func validateMapping_shouldAcceptCompleteMapping() {
        let mappings = CSVField.allCases.enumerated().map { index, field in
            FieldMapping(field: field, csvColumnIndex: index, csvColumnName: field.rawValue)
        }

        let errors = CSVParser.validateMapping(mappings)
        #expect(errors.isEmpty)
    }
}

// MARK: - Group 7: Preview Generation

struct CSVParserPreviewTests {

    @Test func generatePreview_shouldRespectMaxRows() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = CSVParser.generatePreview(from: result, mapping: mappings, options: options, maxRows: 5)

        #expect(preview.count == 5)
    }

    @Test func generatePreview_shouldParseDatesAndAmounts() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = CSVParser.generatePreview(from: result, mapping: mappings, options: options, maxRows: 5)

        for row in preview {
            #expect(row.date != nil)
            #expect(row.amount != nil)
        }
    }

    @Test func generatePreview_shouldUseDefaultMaxRows() {
        let csv = (0..<20).map { "2025-01-01,\($0)" }.joined(separator: "\n")
        let fullCSV = "Date,Amount\n" + csv

        let result = CSVParser.parseCSVContent(fullCSV)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601DateOnly

        let preview = CSVParser.generatePreview(from: result, mapping: mappings, options: options)

        #expect(preview.count == 10) // Default maxRows
    }
}

// MARK: - Group 8: PAC Integration with Real Data

struct CSVParserPACIntegrationTests {

    @Test func filterTargetPAC_shouldReturn12Rows() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        // Target Account (col 7) = "PAC"
        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")

        #expect(filtered.rowCount == 12)
    }

    @Test func filterTargetPAC_allAmountsShouldBeMinus300() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")

        for row in filtered.rows {
            let amount = CSVParser.parseAmount(row[1])
            #expect(amount == Decimal(string: "-300.0"))
        }
    }

    @Test func filterTargetPAC_datesShouldCoverJan2025ToJan2026() throws {
        let content = try loadRealCSV()
        let result = CSVParser.parseCSVContent(content)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")

        let dates = filtered.rows.compactMap { row -> Date? in
            CSVParser.parseDate(row[0], format: .iso8601Offset)
        }

        #expect(dates.count == 12)

        // Verify date range
        let calendar = Calendar.current
        let tz = TimeZone(identifier: "Europe/Rome")!

        let earliest = dates.min()!
        let latest = dates.max()!

        let earliestComponents = calendar.dateComponents(in: tz, from: earliest)
        let latestComponents = calendar.dateComponents(in: tz, from: latest)

        #expect(earliestComponents.year == 2025)
        #expect(earliestComponents.month == 1)
        #expect(latestComponents.year == 2026)
        #expect(latestComponents.month == 1)
    }
}

// MARK: - CSV Escaping

struct CSVParserEscapingTests {

    @Test func escapeCSVValue_shouldEscapeCommas() {
        let result = CSVParser.escapeCSVValue("hello, world", delimiter: ",")
        #expect(result == "\"hello, world\"")
    }

    @Test func escapeCSVValue_shouldEscapeQuotes() {
        let result = CSVParser.escapeCSVValue("say \"hello\"", delimiter: ",")
        #expect(result == "\"say \"\"hello\"\"\"")
    }

    @Test func escapeCSVValue_shouldNotEscapeSimpleValue() {
        let result = CSVParser.escapeCSVValue("hello", delimiter: ",")
        #expect(result == "hello")
    }
}

// MARK: - Group 9: Bank CSV (Crédit Agricole export, semicolon-delimited, European format)

private func loadBankCSV() throws -> String {
    guard let url = Bundle.module.url(
        forResource: "Lista Movimenti_CAI_conto_personale",
        withExtension: "csv",
        subdirectory: "Resources"
    ) else {
        throw CSVTestError.resourceNotFound
    }
    return try String(contentsOf: url, encoding: .utf8)
}

private func parseBankCSV() throws -> CSVParseResult {
    let content = try loadBankCSV()
    var options = CSVImportOptions()
    options.delimiter = ";"
    return CSVParser.parseCSVContent(content, options: options)
}

struct BankCSVParsingTests {

    @Test func bankCSV_shouldParseWith6Columns() throws {
        let result = try parseBankCSV()

        #expect(result.headers.count == 6)
        #expect(result.headers[0] == "Data Op.")
        #expect(result.headers[1] == "Data Val.")
        #expect(result.headers[2] == "Causale")
        #expect(result.headers[3] == "Descrizione")
        #expect(result.headers[4] == "Importo")
        #expect(result.headers[5] == "Divisa")
    }

    @Test func bankCSV_shouldHave367DataRows() throws {
        let result = try parseBankCSV()
        #expect(result.rowCount == 367)
    }

    @Test func bankCSV_shouldAutoDetectDateAndAmount() throws {
        let result = try parseBankCSV()
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        let mappingDict = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field, $0) })

        // "Data Op." contains "data" -> date at col 0
        #expect(mappingDict[.date]?.csvColumnIndex == 0)
        // "Importo" -> amount at col 4
        #expect(mappingDict[.amount]?.csvColumnIndex == 4)
        // "Descrizione" -> description at col 3
        #expect(mappingDict[.description]?.csvColumnIndex == 3)
    }
}

// MARK: - Bank CSV: Amount Parsing (apostrophe + European format)

struct BankCSVAmountTests {

    @Test func parseAmount_shouldHandleApostrophePrefixedNegative() {
        // Italian bank CSV format: '-300,00
        let amount = CSVParser.parseAmount("'-300,00")
        #expect(amount == Decimal(string: "-300"))
    }

    @Test func parseAmount_shouldHandleApostrophePrefixedSmallNegative() {
        let amount = CSVParser.parseAmount("'-4,90")
        #expect(amount == Decimal(string: "-4.9"))
    }

    @Test func parseAmount_shouldHandlePositiveEuropeanAmount() {
        // Positive amounts have no apostrophe: 1742,00
        let amount = CSVParser.parseAmount("1742,00")
        #expect(amount == Decimal(string: "1742"))
    }

    @Test func bankCSV_shouldParseAllAmountsSuccessfully() throws {
        let result = try parseBankCSV()

        var parsedCount = 0
        var failedCount = 0

        for row in result.rows {
            guard row.count > 4 else { continue }
            if CSVParser.parseAmount(row[4]) != nil {
                parsedCount += 1
            } else {
                failedCount += 1
            }
        }

        #expect(parsedCount == 367)
        #expect(failedCount == 0)
    }

    @Test func bankCSV_shouldHave339NegativeAmounts() throws {
        let result = try parseBankCSV()

        let negativeCount = result.rows.filter { row in
            guard row.count > 4, let amount = CSVParser.parseAmount(row[4]) else { return false }
            return amount < 0
        }.count

        #expect(negativeCount == 339)
    }

    @Test func bankCSV_shouldHave28PositiveAmounts() throws {
        let result = try parseBankCSV()

        let positiveCount = result.rows.filter { row in
            guard row.count > 4, let amount = CSVParser.parseAmount(row[4]) else { return false }
            return amount > 0
        }.count

        #expect(positiveCount == 28)
    }
}

// MARK: - Bank CSV: Date Parsing (dd/MM/yyyy European format)

struct BankCSVDateTests {

    @Test func bankCSV_shouldParseDatesWithEuropeanFormat() throws {
        let result = try parseBankCSV()

        // First row: 31/12/2025
        let date = CSVParser.parseDate(result.rows[0][0], format: .euSlashDateOnly)
        #expect(date != nil)

        if let date = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: TimeZone(identifier: "Europe/Rome")!, from: date)
            #expect(components.year == 2025)
            #expect(components.month == 12)
            #expect(components.day == 31)
        }
    }

    @Test func bankCSV_shouldParseAllDatesSuccessfully() throws {
        let result = try parseBankCSV()

        var parsedCount = 0
        for row in result.rows {
            if CSVParser.parseDate(row[0], format: .euSlashDateOnly) != nil {
                parsedCount += 1
            }
        }

        #expect(parsedCount == 367)
    }

    @Test func bankCSV_dateRangeShouldCoverFullYear2025() throws {
        let result = try parseBankCSV()

        let dates = result.rows.compactMap { CSVParser.parseDate($0[0], format: .euSlashDateOnly) }
        let calendar = Calendar.current
        let tz = TimeZone(identifier: "Europe/Rome")!

        let earliest = dates.min()!
        let latest = dates.max()!

        let earliestComponents = calendar.dateComponents(in: tz, from: earliest)
        let latestComponents = calendar.dateComponents(in: tz, from: latest)

        #expect(earliestComponents.year == 2025)
        #expect(earliestComponents.month == 1)
        #expect(latestComponents.year == 2025)
        #expect(latestComponents.month == 12)
    }
}

// MARK: - Bank CSV: Causale (Transaction Type) Analysis

struct BankCSVCausaleTests {

    @Test func bankCSV_shouldHave171POSPayments() throws {
        let result = try parseBankCSV()

        let posCount = result.rows.filter { $0[2] == "PAGAMENTO TRAMITE POS" }.count
        #expect(posCount == 171)
    }

    @Test func bankCSV_shouldHave49UtilityPayments() throws {
        let result = try parseBankCSV()

        let utilityCount = result.rows.filter { $0[2] == "PAGAMENTO UTENZE" }.count
        #expect(utilityCount == 49)
    }

    @Test func bankCSV_shouldHave46Transfers() throws {
        let result = try parseBankCSV()

        let transferCount = result.rows.filter { $0[2] == "GIROCONTO/BONIFICO" }.count
        #expect(transferCount == 46)
    }

    @Test func bankCSV_shouldHave13SalaryPayments() throws {
        let result = try parseBankCSV()

        let salaryCount = result.rows.filter { $0[2] == "ACCREDITO EMOLUMENTI" }.count
        #expect(salaryCount == 13)
    }

    @Test func bankCSV_shouldHave12UniqueTransactionTypes() throws {
        let result = try parseBankCSV()

        let uniqueCausale = Set(result.rows.map { $0[2] })
        #expect(uniqueCausale.count == 12)
    }
}

// MARK: - Bank CSV: PAC Subscriptions

struct BankCSVPACTests {

    @Test func bankCSV_shouldHave11PACSubscriptions() throws {
        let result = try parseBankCSV()

        // PAC subscriptions: Causale="PAGAMENTI DIVERSI" and description contains "PAC FONDI"
        let pacRows = result.rows.filter { row in
            row[2] == "PAGAMENTI DIVERSI" && row[3].contains("PAC FONDI")
        }

        #expect(pacRows.count == 11)
    }

    @Test func bankCSV_allPACAmountsShouldBeMinus300() throws {
        let result = try parseBankCSV()

        let pacRows = result.rows.filter { row in
            row[2] == "PAGAMENTI DIVERSI" && row[3].contains("PAC FONDI")
        }

        for row in pacRows {
            let amount = CSVParser.parseAmount(row[4])
            #expect(amount == Decimal(string: "-300"))
        }
    }

    @Test func bankCSV_PACDatesShouldCoverJanToDecember2025() throws {
        let result = try parseBankCSV()

        let pacRows = result.rows.filter { row in
            row[2] == "PAGAMENTI DIVERSI" && row[3].contains("PAC FONDI")
        }

        let dates = pacRows.compactMap { CSVParser.parseDate($0[0], format: .euSlashDateOnly) }
        #expect(dates.count == 11)

        let calendar = Calendar.current
        let tz = TimeZone(identifier: "Europe/Rome")!
        let months = Set(dates.map { calendar.dateComponents(in: tz, from: $0).month! })

        // 11 months out of 12 (February is missing)
        #expect(months.count == 11)
        #expect(!months.contains(2)) // No February PAC
    }
}

// MARK: - Bank CSV: Salary Analysis

struct BankCSVSalaryTests {

    @Test func bankCSV_shouldHave13SalaryEntries() throws {
        let result = try parseBankCSV()

        let salaryRows = result.rows.filter { $0[2] == "ACCREDITO EMOLUMENTI" }
        #expect(salaryRows.count == 13)
    }

    @Test func bankCSV_allSalariesShouldBePositive() throws {
        let result = try parseBankCSV()

        let salaryRows = result.rows.filter { $0[2] == "ACCREDITO EMOLUMENTI" }

        for row in salaryRows {
            let amount = CSVParser.parseAmount(row[4])
            #expect(amount != nil)
            #expect(amount! > 0)
        }
    }

    @Test func bankCSV_salaryTotalShouldMatchExpected() throws {
        let result = try parseBankCSV()

        let salaryRows = result.rows.filter { $0[2] == "ACCREDITO EMOLUMENTI" }
        let total = salaryRows.compactMap { CSVParser.parseAmount($0[4]) }.reduce(Decimal(0), +)

        // 1442 + 1898 + 1931 + 1890 + 1883 + 1890 + 4119 + 1882 + 1910 + 1902 + 1910 + 1966 + 1742 = 26365
        #expect(total == Decimal(26365))
    }
}

// MARK: - Bank CSV: Preview with Correct Options

struct BankCSVPreviewTests {

    @Test func bankCSV_previewShouldParseWithCorrectOptions() throws {
        let result = try parseBankCSV()
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.delimiter = ";"
        options.dateFormat = .euSlashDateOnly

        let preview = CSVParser.generatePreview(from: result, mapping: mappings, options: options, maxRows: 5)

        #expect(preview.count == 5)

        // All dates should parse correctly with European format
        for row in preview {
            #expect(row.date != nil)
        }

        // All amounts should parse correctly (including apostrophe prefix)
        for row in preview {
            #expect(row.amount != nil)
        }
    }

    @Test func bankCSV_previewFirstRowShouldBeTransfer() throws {
        let result = try parseBankCSV()
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.delimiter = ";"
        options.dateFormat = .euSlashDateOnly

        let preview = CSVParser.generatePreview(from: result, mapping: mappings, options: options, maxRows: 1)

        // First row: 31/12/2025, -300,00, GIROCONTO/BONIFICO
        #expect(preview[0].amount == Decimal(string: "-300"))
        #expect(preview[0].description?.contains("BIANCO FRANCESCO") == true)
    }
}
