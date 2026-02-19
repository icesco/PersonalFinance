//
//  CSVServiceTests.swift
//  Personal FinanceTests
//
//  Integration tests for CSVService (SwiftData import/export).
//  Pure parsing tests are in FinanceCoreTests/CSVParserTests.swift.
//

import Testing
import Foundation
import SwiftData
@testable import Personal_Finance
@testable import FinanceCore

struct CSVServiceTests {

    let csvService = CSVService()

    // MARK: - Test CSV di esempio

    let sampleCSVContent = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Budget Book,Source Account,Target Account,Folder,Category,Payee,Tags,Notes,Pending
    2025-01-02T00:00:00+0100,-0.16,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tasse","Tasse conto/carta","","","Addebito commissioni SMS",False
    2025-01-02T00:00:00+0100,-304.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tempo libero","Regali Tech","","","POS APPLE STORE",False
    2025-01-02T00:00:00+0100,-73.96,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tempo libero","Acquisti","","","POS DECATHLON",False
    2025-01-10T00:00:00+0100,1442.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Redditi","Stipendio","","","RETRIBUZIONE DICEMBRE 2024",False
    2025-01-14T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","Trasferimento a PAC",False
    2025-01-14T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","Trasferimento da Conto",False
    """

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

        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
        #expect(!csv.hasPrefix("Importo"))
    }

    // MARK: - Integration Tests - Category Deduplication

    @Test func importTransactions_shouldNotCreateDuplicateCategories() async throws {
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        try context.save()

        let csvWithDuplicateCategories = """
        Date,Amount,Category
        2025-01-01,100,Alimentari
        2025-01-02,200,Alimentari
        2025-01-03,150,Alimentari
        """

        let result = CSVParser.parseCSVContent(csvWithDuplicateCategories)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)

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

        #expect(importResult.importedCount == 3)

        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let categories = try context.fetch(categoryDescriptor)

        #expect(categories.count == 1)
        #expect(categories.first?.name == "Alimentari")
    }

    @Test func importTransactions_shouldReuseExistingCategoriesWithDifferentCase() async throws {
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        try context.save()

        let csvWithMixedCaseCategories = """
        Date,Amount,Category
        2025-01-01,100,alimentari
        2025-01-02,200,ALIMENTARI
        2025-01-03,150,Alimentari
        """

        let result = CSVParser.parseCSVContent(csvWithMixedCaseCategories)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)

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

        #expect(importResult.importedCount == 3)

        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let categories = try context.fetch(categoryDescriptor)

        #expect(categories.count == 1)
    }

    @Test func importTransactions_shouldReusePreexistingCategory() async throws {
        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        let account = Account(name: "Test Account")
        context.insert(account)

        let conto = Conto(name: "Test Conto", type: .checking)
        conto.account = account
        context.insert(conto)

        let existingCategory = FinanceCore.Category(name: "Alimentari")
        existingCategory.account = account
        context.insert(existingCategory)

        try context.save()

        let csvContent = """
        Date,Amount,Category
        2025-01-01,100,Alimentari
        2025-01-02,200,Alimentari
        """

        let result = CSVParser.parseCSVContent(csvContent)
        let mappings = CSVParser.detectColumnMapping(headers: result.headers)

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

        #expect(importResult.importedCount == 2)

        let categoryDescriptor = FetchDescriptor<FinanceCore.Category>()
        let categoriesAfterImport = try context.fetch(categoryDescriptor)

        #expect(categoriesAfterImport.count == 1)
        #expect(categoriesAfterImport.first?.id == existingCategory.id)
    }

    // MARK: - PAC Account Import Simulation

    let pacCSVContent = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Budget Book,Source Account,Target Account,Folder,Category,Payee,Tags,Notes,Pending
    2025-01-02T00:00:00+0100,-304.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Tempo libero","Regali Tech","","","POS APPLE STORE",False
    2025-01-10T00:00:00+0100,1442.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","","Redditi","Stipendio","","","RETRIBUZIONE DICEMBRE",False
    2025-01-14T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-01-14T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-03-07T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-03-07T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-04-09T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-04-09T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-05-09T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-05-09T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-06-09T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-06-09T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-07-09T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-07-09T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-08-08T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-08-08T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-09-19T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-09-19T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-10-17T00:00:00+0200,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-10-17T00:00:00+0200,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-11-19T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-11-19T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2025-12-19T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2025-12-19T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    2026-01-19T00:00:00+0100,-300.0,EUR,EUR,1.0,"Conto Principale","Conto Crédit Agricole","PAC","Redditi","Risparmi","","","",False
    2026-01-19T00:00:00+0100,300.0,EUR,EUR,1.0,"Conto Principale","PAC","Conto Crédit Agricole","Redditi","Risparmi","","","",False
    """

    @Test func importPACAccount_shouldResultInBalance3600() async throws {
        let result = CSVParser.parseCSVContent(pacCSVContent)
        #expect(result.rowCount == 26)

        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")
        #expect(filtered.rowCount == 12)

        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        let account = Account(name: "Conto Principale")
        context.insert(account)

        let pacConto = Conto(name: "PAC", type: .investment)
        pacConto.account = account
        context.insert(pacConto)

        let caConto = Conto(name: "Conto Crédit Agricole", type: .checking)
        caConto.account = account
        context.insert(caConto)

        try context.save()

        let mappings = CSVParser.detectColumnMapping(headers: filtered.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset
        options.createMissingCategories = true
        options.ignoreDuplicates = false

        let importResult = try await csvService.importTransactions(
            from: filtered,
            mapping: mappings,
            options: options,
            container: container,
            accountId: account.id
        )

        #expect(importResult.importedCount == 12)
        #expect(importResult.errorCount == 0)

        let freshContext = ModelContext(container)
        let pacPredicate = #Predicate<Conto> { $0.name == "PAC" }
        var pacDescriptor = FetchDescriptor(predicate: pacPredicate)
        pacDescriptor.fetchLimit = 1
        let freshPAC = try freshContext.fetch(pacDescriptor).first!

        #expect(freshPAC.balance == Decimal(3600))
    }

    @Test func importPACAccount_allTransactionsShouldBeTransferType() async throws {
        let result = CSVParser.parseCSVContent(pacCSVContent)
        let filtered = CSVParser.filterRows(from: result, columnIndex: 7, value: "PAC")

        let container = try FinanceCoreModule.createModelContainer(
            appGroupIdentifier: FinanceCoreModule.defaultAppGroupIdentifier,
            enableCloudKit: false,
            inMemory: true
        )
        let context = ModelContext(container)

        let account = Account(name: "Conto Principale")
        context.insert(account)

        let pacConto = Conto(name: "PAC", type: .investment)
        pacConto.account = account
        context.insert(pacConto)

        let caConto = Conto(name: "Conto Crédit Agricole", type: .checking)
        caConto.account = account
        context.insert(caConto)

        try context.save()

        let mappings = CSVParser.detectColumnMapping(headers: filtered.headers)
        var options = CSVImportOptions()
        options.dateFormat = .iso8601Offset
        options.createMissingCategories = true
        options.ignoreDuplicates = false

        _ = try await csvService.importTransactions(
            from: filtered,
            mapping: mappings,
            options: options,
            container: container,
            accountId: account.id
        )

        let freshContext = ModelContext(container)
        let txDescriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let transactions = try freshContext.fetch(txDescriptor)

        #expect(transactions.count == 12)

        for tx in transactions {
            #expect(tx.type == .transfer)
            #expect(tx.amount == Decimal(300))
            #expect(tx.fromContoId == caConto.id)
            #expect(tx.toContoId == pacConto.id)
        }
    }
}
