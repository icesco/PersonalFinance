//
//  CSVServiceTests.swift
//  Personal FinanceTests
//
//  Created by Claude on 04/02/26.
//

import Testing
import Foundation
import SwiftData
@testable import Personal_Finance
@testable import FinanceCore

struct CSVServiceTests {

    let csvService = CSVService()

    // MARK: - Test CSV di esempio

    /// Contenuto CSV di esempio basato sul file reale Conto-Principale-2026-02-04T15-37-37.csv
    let sampleCSVContent = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Budget Book,Source Account,Target Account,Folder,Category,Payee,Tags,Notes,Pending
    2025-01-02T00:00:00+0100,-0.16,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tasse","Tasse conto/carta","","","Addebito commissioni SMS",False
    2025-01-02T00:00:00+0100,-304.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tempo libero","Regali Tech","","","POS APPLE STORE",False
    2025-01-02T00:00:00+0100,-73.96,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tempo libero","Acquisti","","","POS DECATHLON",False
    2025-01-10T00:00:00+0100,1442.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Redditi","Stipendio","","","RETRIBUZIONE DICEMBRE 2024",False
    2025-01-14T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","Trasferimento a PAC",False
    2025-01-14T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","Trasferimento da Conto",False
    """

    // MARK: - Parsing Tests

    @Test func parseCSVContent_shouldExtractHeaders() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        #expect(result.headers.count == 14)
        #expect(result.headers[0] == "Date")
        #expect(result.headers[1] == "Amount")
        #expect(result.headers[9] == "Category")
        #expect(result.headers[12] == "Notes")
    }

    @Test func parseCSVContent_shouldExtractCorrectRowCount() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        #expect(result.rowCount == 6)
    }

    @Test func parseCSVContent_shouldParseAmountsCorrectly() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Prima riga: -0.16
        #expect(result.rows[0][1] == "-0.16")
        // Seconda riga: -304.0
        #expect(result.rows[1][1] == "-304.0")
        // Quarta riga (stipendio): 1442.0
        #expect(result.rows[3][1] == "1442.0")
    }

    @Test func parseCSVContent_shouldParseDatesCorrectly() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        #expect(result.rows[0][0] == "2025-01-02T00:00:00+0100")
        #expect(result.rows[3][0] == "2025-01-10T00:00:00+0100")
    }

    @Test func parseCSVContent_shouldParseCategoriesCorrectly() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Category è alla colonna 9
        #expect(result.rows[0][9] == "Tasse conto/carta")
        #expect(result.rows[1][9] == "Regali Tech")
        #expect(result.rows[3][9] == "Stipendio")
    }

    @Test func parseCSVContent_shouldParseSourceAccountCorrectly() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Source Account è alla colonna 6
        #expect(result.rows[0][6] == "Conto Crédit Agricole")
        #expect(result.rows[5][6] == "PAC") // Trasferimento
    }

    @Test func parseCSVContent_shouldParseTargetAccountForTransfers() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Target Account è alla colonna 7
        // Riga 5 (indice 4): trasferimento verso PAC
        #expect(result.rows[4][7] == "PAC")
        // Riga 6 (indice 5): trasferimento da PAC
        #expect(result.rows[5][7] == "Conto Crédit Agricole")
    }

    @Test func parseCSVContent_shouldHandleQuotedFields() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Budget Book è alla colonna 5, contiene "Conto Principale"
        #expect(result.rows[0][5] == "Conto Principale")
    }

    // MARK: - Auto-Detection Tests

    @Test func detectColumnMapping_shouldDetectDateColumn() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        let dateMapping = mappings.first { $0.field == .date }
        #expect(dateMapping?.csvColumnIndex == 0)
        #expect(dateMapping?.csvColumnName == "Date")
    }

    @Test func detectColumnMapping_shouldDetectAmountColumn() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        let amountMapping = mappings.first { $0.field == .amount }
        #expect(amountMapping?.csvColumnIndex == 1)
        #expect(amountMapping?.csvColumnName == "Amount")
    }

    @Test func detectColumnMapping_shouldDetectCategoryColumn() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        let categoryMapping = mappings.first { $0.field == .category }
        #expect(categoryMapping?.csvColumnIndex == 9)
        #expect(categoryMapping?.csvColumnName == "Category")
    }

    @Test func detectColumnMapping_shouldDetectSourceAccountColumn() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        let sourceMapping = mappings.first { $0.field == .sourceAccount }
        #expect(sourceMapping?.csvColumnIndex == 6)
    }

    @Test func detectColumnMapping_shouldDetectNotesColumn() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        let notesMapping = mappings.first { $0.field == .notes }
        #expect(notesMapping?.csvColumnIndex == 12)
    }

    // MARK: - Date Parsing Tests

    @Test func parseDate_shouldParseISO8601WithOffset() async throws {
        let dateString = "2025-01-02T00:00:00+0100"
        let date = await csvService.parseDate(dateString, format: .iso8601Offset)

        #expect(date != nil)

        if let date = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents(in: TimeZone(identifier: "Europe/Rome")!, from: date)
            #expect(components.year == 2025)
            #expect(components.month == 1)
            #expect(components.day == 2)
        }
    }

    @Test func parseDate_shouldReturnNilForInvalidDate() async throws {
        let dateString = "invalid-date"
        let date = await csvService.parseDate(dateString, format: .iso8601Offset)

        #expect(date == nil)
    }

    // MARK: - Validation Tests

    @Test func validateMapping_shouldReturnErrorForMissingRequiredFields() async throws {
        let mappings = [
            FieldMapping(field: .amount, csvColumnIndex: nil, csvColumnName: nil),
            FieldMapping(field: .date, csvColumnIndex: nil, csvColumnName: nil),
            FieldMapping(field: .category, csvColumnIndex: 9, csvColumnName: "Category")
        ]

        let errors = await csvService.validateMapping(mappings)

        #expect(errors.count == 2)
        #expect(errors.contains { $0.field == .amount })
        #expect(errors.contains { $0.field == .date })
    }

    @Test func validateMapping_shouldReturnNoErrorsWhenRequiredFieldsAssigned() async throws {
        let mappings = [
            FieldMapping(field: .amount, csvColumnIndex: 1, csvColumnName: "Amount"),
            FieldMapping(field: .date, csvColumnIndex: 0, csvColumnName: "Date"),
            FieldMapping(field: .category, csvColumnIndex: nil, csvColumnName: nil)
        ]

        let errors = await csvService.validateMapping(mappings)

        #expect(errors.isEmpty)
    }

    // MARK: - Preview Generation Tests

    @Test func generatePreview_shouldGenerateCorrectNumberOfRows() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = await csvService.generatePreview(
            from: result,
            mapping: mappings,
            options: options,
            maxRows: 3
        )

        #expect(preview.count == 3)
    }

    @Test func generatePreview_shouldParseAmountsInPreview() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = await csvService.generatePreview(
            from: result,
            mapping: mappings,
            options: options,
            maxRows: 5
        )

        // Prima riga: -0.16
        #expect(preview[0].amount == Decimal(string: "-0.16"))
        // Quarta riga: 1442.0 (stipendio)
        #expect(preview[3].amount == Decimal(string: "1442.0"))
    }

    @Test func generatePreview_shouldParseDatesInPreview() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = await csvService.generatePreview(
            from: result,
            mapping: mappings,
            options: options,
            maxRows: 5
        )

        // Tutte le date devono essere parsate correttamente
        #expect(preview[0].date != nil)
        #expect(preview[1].date != nil)
        #expect(preview[2].date != nil)
        #expect(preview[3].date != nil)
    }

    @Test func generatePreview_shouldExtractCategories() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset

        let preview = await csvService.generatePreview(
            from: result,
            mapping: mappings,
            options: options,
            maxRows: 5
        )

        #expect(preview[0].category == "Tasse conto/carta")
        #expect(preview[3].category == "Stipendio")
    }

    // MARK: - Export Tests

    @Test func exportTransactions_shouldGenerateValidCSV() async throws {
        let transaction = Transaction(
            amount: 100,
            type: .income,
            date: Date(),
            transactionDescription: "Test income",
            notes: "Test notes"
        )

        var options = CSVExportOptions()
        options.includeHeader = true
        options.dateFormat = .iso8601Offset
        options.includeFields = [.amount, .date, .description, .notes, .transactionType]

        let csv = await csvService.exportTransactions([transaction], options: options)

        #expect(csv.contains("Importo"))
        #expect(csv.contains("Data"))
        #expect(csv.contains("100"))
        #expect(csv.contains("Entrata"))
    }

    @Test func exportTransactions_shouldExcludeHeaderWhenDisabled() async throws {
        let transaction = Transaction(
            amount: 50,
            type: .expense,
            date: Date()
        )

        var options = CSVExportOptions()
        options.includeHeader = false
        options.includeFields = [.amount, .transactionType]

        let csv = await csvService.exportTransactions([transaction], options: options)

        // Non dovrebbe contenere "Importo" come header
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
        #expect(!csv.hasPrefix("Importo"))
    }

    // MARK: - Edge Cases

    @Test func parseCSVContent_shouldHandleEmptyContent() async throws {
        let result = await csvService.parseCSVContent("")

        #expect(result.headers.isEmpty)
        #expect(result.rowCount == 0)
    }

    @Test func parseCSVContent_shouldHandleHeaderOnly() async throws {
        let headerOnly = "Date,Amount,Category"
        let result = await csvService.parseCSVContent(headerOnly)

        #expect(result.headers.count == 3)
        #expect(result.rowCount == 0)
    }

    @Test func parseCSVContent_shouldHandleFieldsWithCommasInQuotes() async throws {
        let csvWithCommas = """
        Name,Description
        Test,"Description with, comma inside"
        """

        let result = await csvService.parseCSVContent(csvWithCommas)

        #expect(result.rows[0][1] == "Description with, comma inside")
    }

    // MARK: - Multi-Account Filter Tests

    @Test func extractUniqueAccountValues_shouldExtractUniqueValues() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Source Account è alla colonna 6
        let accountValues = await csvService.extractUniqueAccountValues(from: result, columnIndex: 6)

        #expect(accountValues.count == 2)

        let accountNames = accountValues.map { $0.value }
        #expect(accountNames.contains("Conto Crédit Agricole"))
        #expect(accountNames.contains("PAC"))
    }

    @Test func extractUniqueAccountValues_shouldCountRowsCorrectly() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Source Account è alla colonna 6
        let accountValues = await csvService.extractUniqueAccountValues(from: result, columnIndex: 6)

        // "Conto Crédit Agricole" appare 5 volte, "PAC" appare 1 volta
        let creditAgricole = accountValues.first { $0.value == "Conto Crédit Agricole" }
        let pac = accountValues.first { $0.value == "PAC" }

        #expect(creditAgricole?.rowCount == 5)
        #expect(pac?.rowCount == 1)
    }

    @Test func extractUniqueAccountValues_shouldBeSortedByRowCount() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        let accountValues = await csvService.extractUniqueAccountValues(from: result, columnIndex: 6)

        // Il primo elemento dovrebbe essere quello con più righe
        #expect(accountValues.first?.value == "Conto Crédit Agricole")
        #expect(accountValues.first?.rowCount == 5)
    }

    @Test func filterRows_shouldFilterByAccountValue() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Filtra solo le righe con "PAC" come Source Account (colonna 6)
        let filtered = await csvService.filterRows(from: result, columnIndex: 6, value: "PAC")

        #expect(filtered.rowCount == 1)
        #expect(filtered.rows[0][6] == "PAC")
    }

    @Test func filterRows_shouldPreserveHeaders() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        let filtered = await csvService.filterRows(from: result, columnIndex: 6, value: "PAC")

        #expect(filtered.headers == result.headers)
        #expect(filtered.columnCount == result.columnCount)
    }

    @Test func filterRows_shouldFilterMultipleRows() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        // Filtra le righe con "Conto Crédit Agricole" come Source Account
        let filtered = await csvService.filterRows(from: result, columnIndex: 6, value: "Conto Crédit Agricole")

        #expect(filtered.rowCount == 5)

        // Verifica che tutte le righe filtrate abbiano il valore corretto
        for row in filtered.rows {
            #expect(row[6] == "Conto Crédit Agricole")
        }
    }

    @Test func filterRows_shouldReturnEmptyForNonExistentValue() async throws {
        let result = await csvService.parseCSVContent(sampleCSVContent)

        let filtered = await csvService.filterRows(from: result, columnIndex: 6, value: "Conto Inesistente")

        #expect(filtered.rowCount == 0)
        #expect(filtered.headers == result.headers)
    }

    @Test func extractUniqueAccountValues_shouldHandleEmptyColumn() async throws {
        let csvWithEmpty = """
        Date,Amount,Account
        2025-01-01,100,
        2025-01-02,200,Conto A
        2025-01-03,150,
        """

        let result = await csvService.parseCSVContent(csvWithEmpty)
        let accountValues = await csvService.extractUniqueAccountValues(from: result, columnIndex: 2)

        // Solo "Conto A" dovrebbe essere estratto (le righe vuote vengono ignorate)
        #expect(accountValues.count == 1)
        #expect(accountValues.first?.value == "Conto A")
    }

    // MARK: - Integration Tests - Category Deduplication (Issue #1)

    @Test func importTransactions_shouldNotCreateDuplicateCategories() async throws {
        // Setup: create in-memory container
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        // Create account and conto
        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        try context.save()

        // CSV with the same category appearing multiple times
        let csvWithDuplicateCategories = """
        Date,Amount,Category
        2025-01-01,100,Alimentari
        2025-01-02,200,Alimentari
        2025-01-03,150,Alimentari
        """

        let result = await csvService.parseCSVContent(csvWithDuplicateCategories)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        var options = CSVImportOptions()
        options.createMissingCategories = true
        options.dateFormat = .iso8601

        let importResult = try await csvService.importTransactions(
            from: result,
            mapping: mappings,
            options: options,
            container: container,
            accountId: account.id
        )

        // Verify all transactions were imported
        #expect(importResult.importedCount == 3)

        // Verify only ONE category was created (not 3 duplicates)
        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let categories = try context.fetch(categoryDescriptor)

        #expect(categories.count == 1)
        #expect(categories.first?.name == "Alimentari")
    }

    @Test func importTransactions_shouldReuseExistingCategoriesWithDifferentCase() async throws {
        // Setup: create in-memory container
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        // Create account and conto
        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        try context.save()

        // CSV with same category in different cases
        let csvWithMixedCaseCategories = """
        Date,Amount,Category
        2025-01-01,100,alimentari
        2025-01-02,200,ALIMENTARI
        2025-01-03,150,Alimentari
        """

        let result = await csvService.parseCSVContent(csvWithMixedCaseCategories)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        var options = CSVImportOptions()
        options.createMissingCategories = true
        options.dateFormat = .iso8601

        let importResult = try await csvService.importTransactions(
            from: result,
            mapping: mappings,
            options: options,
            container: container,
            accountId: account.id
        )

        // Verify all transactions were imported
        #expect(importResult.importedCount == 3)

        // Verify only ONE category was created (case-insensitive matching)
        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let categories = try context.fetch(categoryDescriptor)

        #expect(categories.count == 1)
    }

    @Test func importTransactions_shouldReusePreexistingCategory() async throws {
        // Setup: create in-memory container
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        // Create account and conto
        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        // Create a pre-existing category
        let existingCategory = FinanceCore.Category(name: "Alimentari")
        existingCategory.account = account
        context.insert(existingCategory)

        try context.save()

        // Fetch the existing category
        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let existingCategories = try context.fetch(categoryDescriptor)

        // CSV that references the existing category
        let csvContent = """
        Date,Amount,Category
        2025-01-01,100,Alimentari
        2025-01-02,200,Alimentari
        """

        let result = await csvService.parseCSVContent(csvContent)
        let mappings = await csvService.detectColumnMapping(headers: result.headers)

        var options = CSVImportOptions()
        options.createMissingCategories = true
        options.dateFormat = .iso8601

        let importResult = try await csvService.importTransactions(
            from: result,
            mapping: mappings,
            options: options,
            container: container,
            accountId: account.id
        )

        // Verify all transactions were imported
        #expect(importResult.importedCount == 2)

        // Verify still only ONE category exists (the pre-existing one was reused)
        let categoriesAfterImport = try context.fetch(categoryDescriptor)

        #expect(categoriesAfterImport.count == 1)
        #expect(categoriesAfterImport.first?.id == existingCategory.id)
    }
}
