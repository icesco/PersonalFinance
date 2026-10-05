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

    @Test func groupedInternationalAmountsImportWithoutChangingMagnitude() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let csv = CSVParser.parseCSVContent("""
        Date,Amount,Source Account,Description
        2026-09-01,"-1,234.56",Banca,US
        2026-09-02,"-1.234,56",Banca,EU
        2026-09-03,"-12,34.56",Banca,Invalid
        """)
        var options = CSVImportOptions(createMissingConti: true)
        options.missingContoTypes = ["banca": ContoType.checking.rawValue]
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: options, container: container, accountId: UUID(), newBookName: "Importato"
        )
        #expect(result.importedCount == 2)
        #expect(result.errorCount == 1)
        let transactions = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 2)
        #expect(transactions.allSatisfy { $0.amount == Decimal(string: "1234.56") && $0.type == .expense })
    }

    @Test func newBookAndImportedTransactionsCommitTogether() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let bookID = UUID()
        let csv = CSVParser.parseCSVContent("Date,Amount,Source Account\n2026-09-01,-20,Banca")
        var options = CSVImportOptions(createMissingConti: true)
        options.missingContoTypes = ["banca": ContoType.checking.rawValue]
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: options, container: container, accountId: bookID, newBookName: "  Importato  "
        )
        let context = ModelContext(container)
        #expect(result.importedCount == 1)
        let books = try context.fetch(FetchDescriptor<Account>())
        #expect(books.count == 1)
        #expect(books.first?.id == bookID)
        #expect(books.first?.name == "Importato")
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Conto>()).first?.account?.id == bookID)
    }

    @Test func unsuccessfulImportLeavesNoNewBookOrAccounts() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let csv = CSVParser.parseCSVContent("Date,Amount,Source Account\n2026-09-01,invalid,Banca")
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: CSVImportOptions(createMissingConti: true), container: container,
            accountId: UUID(), newBookName: "Vuoto"
        )
        let context = ModelContext(container)
        #expect(result.importedCount == 0)
        #expect(result.errorCount == 1)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 0)
    }

    @Test func failedImportSaveLeavesStoreUntouchedAndCanRetry() async throws {
        enum SaveFailure: Error { case injected }
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        context.insert(Account(name: "Preesistente"))
        try context.save()
        let bookID = UUID()
        let csv = CSVParser.parseCSVContent("Date,Amount,Source Account\n2026-09-01,-20,Banca")
        var options = CSVImportOptions(createMissingConti: true)
        options.missingContoTypes = ["banca": ContoType.checking.rawValue]
        do {
            _ = try await CSVService(save: { _ in throw SaveFailure.injected }).importTransactions(
                from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
                options: options, container: container, accountId: bookID, newBookName: "Importato"
            )
            Issue.record("Expected save failure")
        } catch SaveFailure.injected { }
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<Conto>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        let retry = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: options, container: container, accountId: bookID, newBookName: "Importato"
        )
        #expect(retry.importedCount == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<Account>()) == 2)
    }

    @Test func newBookImportCannotReplaceAnExistingBook() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let existing = Account(name: "Da preservare")
        context.insert(existing)
        try context.save()
        let csv = CSVParser.parseCSVContent("Date,Amount,Source Account\n2026-09-01,-20,Banca")
        do {
            _ = try await csvService.importTransactions(
                from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
                options: CSVImportOptions(createMissingConti: true), container: container,
                accountId: existing.id, newBookName: "Sostituto"
            )
            Issue.record("Expected destination collision rejection")
        } catch CSVService.ImportFailure.invalidNewBook { }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(existing.name == "Da preservare")
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 0)
    }

    @Test func importDoesNotAssignAnUnknownAccountToAnotherBook() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let personal = Account(name: "Personale")
        let household = Account(name: "Casa")
        context.insert(personal)
        context.insert(household)
        let personalConto = Conto(name: "Personale", type: .checking)
        personalConto.account = personal
        context.insert(personalConto)
        let householdConto = Conto(name: "Casa", type: .checking)
        householdConto.account = household
        context.insert(householdConto)
        try context.save()

        let csv = CSVParser.parseCSVContent("Date,Amount,Source Account\n2026-09-01,-20,Casa")
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: CSVImportOptions(), container: container, accountId: personal.id
        )
        #expect(result.importedCount == 0)
        #expect(result.errorCount == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func mirroredTransferRowsProduceOneTransfer() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let account = Account(name: "Personale")
        context.insert(account)
        let bank = Conto(name: "Banca", type: .checking)
        bank.account = account
        context.insert(bank)
        let savings = Conto(name: "Risparmio", type: .savings)
        savings.account = account
        context.insert(savings)
        try context.save()

        let csv = CSVParser.parseCSVContent("""
        Date,Amount,Source Account,Target Account,Description
        2026-09-01,-100,Banca,Risparmio,Giroconto
        2026-09-01,100,Risparmio,Banca,Giroconto
        """)
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: CSVImportOptions(), container: container, accountId: account.id
        )
        #expect(result.importedCount == 1)
        #expect(result.duplicatesSkipped == 1)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.first?.fromContoId == bank.id)
        #expect(transactions.first?.toContoId == savings.id)
    }

    @Test func budgetFlowImportCreatesReviewedAccountsAndSkipsPendingRows() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let book = Account(name: "Libro personale")
        context.insert(book)
        try context.save()

        let csv = CSVParser.parseCSVContent("""
        Date,Amount,Budget Book,Source Account,Target Account,Category,Payee,Pending
        2026-09-03T00:00:00+0200,-100.0,Libro personale,Banca,PAC,Risparmi,,False
        2026-09-03T00:00:00+0200,100.0,Libro personale,PAC,Banca,Risparmi,,False
        2026-09-03T12:00:00+0200,-19.99,Libro personale,Banca,,Subscriptions,Servizio,False
        2026-09-04T12:00:00+0200,-50.0,Libro personale,Banca,,Acquisti,In attesa,True
        """)
        var options = CSVImportOptions(dateFormat: .iso8601Z, createMissingConti: true)
        options.missingContoTypes = ["banca": ContoType.checking.rawValue,
                                    "pac": ContoType.investment.rawValue]
        let result = try await csvService.importTransactions(
            from: csv, mapping: CSVParser.detectColumnMapping(headers: csv.headers),
            options: options, container: container, accountId: book.id
        )
        #expect(result.importedCount == 2)
        #expect(result.duplicatesSkipped == 1)
        #expect(result.skippedCount == 2)
        #expect(result.errorCount == 0)
        let conti = try context.fetch(FetchDescriptor<Conto>())
        #expect(conti.count == 2)
        #expect(conti.first(where: { $0.name == "PAC" })?.type == .investment)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 2)
        #expect(transactions.first(where: { $0.type == .expense })?.transactionDescription == "Servizio")
    }

    @Test func budgetFlowKeepsIdenticalChargesAndRecognizesThemOnReimport() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let book = Account(name: "Libro")
        context.insert(book)
        try context.save()
        let csv = CSVParser.parseCSVContent("""
        Date,Amount,Budget Book,Source Account,Target Account,Category,Payee,Notes,Pending
        2026-09-03T00:00:00+0200,-2.0,Libro,Carta,,Commissioni,,Canone,False
        2026-09-03T00:00:00+0200,-2.0,Libro,Carta,,Commissioni,,Canone,False
        """)
        var options = CSVImportOptions(dateFormat: .iso8601Z, createMissingConti: true)
        options.missingContoTypes = ["carta": ContoType.credit.rawValue]
        let mapping = CSVParser.detectColumnMapping(headers: csv.headers)
        let first = try await csvService.importTransactions(
            from: csv, mapping: mapping, options: options,
            container: container, accountId: book.id
        )
        #expect(first.importedCount == 2)
        let second = try await csvService.importTransactions(
            from: csv, mapping: mapping, options: options,
            container: container, accountId: book.id
        )
        #expect(second.importedCount == 0)
        #expect(second.duplicatesSkipped == 2)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).allSatisfy { $0.transactionDescription == "Canone" })
    }

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

    @Test func convertedExpenseRoundTripPreservesCurrencyPrecisionAndOriginalQuote() async throws {
        let sourceBook = Account(name: "Viaggio", currency: "KWD")
        let bank = Conto(name: "Banca", type: .checking)
        bank.account = sourceBook
        let expense = Transaction(amount: Decimal(string: "12.345")!, type: .expense, transactionDescription: "Acquisto")
        expense.setFromConto(bank)
        expense.originalAmount = 10
        expense.originalCurrency = "USD"
        expense.exchangeRate = Decimal(string: "1.2345")!
        expense.exchangeRateDate = "2026-10-01"
        expense.exchangeRateSource = "Manuale"
        let text = await csvService.exportTransactions([expense], options: CSVExportOptions())
        let parsed = CSVParser.parseCSVContent(text)
        let mapping = CSVParser.detectColumnMapping(headers: parsed.headers)
        let sourceIndex = try #require(mapping.first { $0.field == .sourceCurrency }?.csvColumnIndex)
        #expect(parsed.rows[0][sourceIndex] == "KWD")
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(target)
        let book = Account(name: "Importato", currency: "KWD")
        context.insert(book)
        try context.save()
        var importOptions = CSVImportOptions(createMissingConti: true)
        importOptions.missingContoTypes = ["banca": ContoType.checking.rawValue]
        let result = try await csvService.importTransactions(from: parsed, mapping: mapping,
            options: importOptions, container: target, accountId: book.id)
        #expect(result.importedCount == 1, "\(result.errors.map(\.message)) | \(text)")
        #expect(result.errorCount == 0)
        let imported = try #require(ModelContext(target).fetch(FetchDescriptor<Transaction>()).first)
        #expect(imported.amount == expense.amount)
        #expect(imported.originalAmount == 10)
        #expect(imported.originalCurrency == "USD")
        #expect(imported.exchangeRate == expense.exchangeRate)
        #expect(imported.exchangeRateDate == "2026-10-01")
        #expect(imported.exchangeRateSource == "Manuale")
        #expect(imported.type == .expense)
    }

    @Test func currencyMismatchIsReportedBeforeCreatingAccounts() async throws {
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(target)
        let book = Account(name: "Euro", currency: "EUR")
        context.insert(book)
        try context.save()
        let parsed = CSVParser.parseCSVContent("Data,Importo,Valuta di origine,Conto (Da)\n2026-10-01,10,USD,Banca")
        let result = try await csvService.importTransactions(from: parsed,
            mapping: CSVParser.detectColumnMapping(headers: parsed.headers), options: CSVImportOptions(createMissingConti: true),
            container: target, accountId: book.id)
        #expect(result.importedCount == 0)
        #expect(result.errorCount == 1)
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 0)
    }

    @Test func inconsistentOrMalformedOriginalQuotesDoNotImport() async throws {
        let target = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(target)
        let book = Account(name: "Euro", currency: "EUR")
        context.insert(book)
        try context.save()
        let parsed = CSVParser.parseCSVContent("""
        Data,Importo,Valuta di origine,Importo originale,Valuta originale,Cambio originale,Conto (Da),Tipo
        2026-10-01,9,EUR,10,USD,2,Banca,Spesa
        2026-10-01,9,EUR,10,USD,0.9invalid,Banca,Spesa
        """)
        let result = try await csvService.importTransactions(from: parsed,
            mapping: CSVParser.detectColumnMapping(headers: parsed.headers), options: CSVImportOptions(createMissingConti: true),
            container: target, accountId: book.id)
        #expect(result.importedCount == 0)
        #expect(result.errorCount == 2)
        #expect(try context.fetchCount(FetchDescriptor<Conto>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func transferExportPreservesBothCurrenciesAndDestinationAmount() async throws {
        let eur = Account(name: "Euro", currency: "EUR")
        let usd = Account(name: "Dollari", currency: "USD")
        let from = Conto(name: "Origine", type: .checking)
        let to = Conto(name: "Destinazione", type: .checking)
        from.account = eur; to.account = usd
        let transfer = Transaction(amount: 100, type: .transfer)
        transfer.setFromConto(from); transfer.setToConto(to)
        transfer.destinationAmount = 110
        let csv = CSVParser.parseCSVContent(await csvService.exportTransactions([transfer], options: CSVExportOptions()))
        func field(_ field: CSVField) throws -> String {
            csv.rows[0][try #require(csv.headers.firstIndex(of: field.rawValue))]
        }
        #expect(try field(.sourceCurrency) == "EUR")
        #expect(try field(.targetCurrency) == "USD")
        #expect(try field(.exchangeRate) == "1.1")
        #expect(try field(.destinationAmount) == "110")
    }

    @Test func transferRoundTripKeepsItsDirectionAndDoesNotDuplicateOnRetry() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let book = Account(name: "Libro")
        let from = Conto(name: "Banca", type: .checking)
        let to = Conto(name: "Risparmio", type: .savings)
        from.account = book; to.account = book
        context.insert(book); context.insert(from); context.insert(to)
        try context.save()
        let transaction = Transaction(amount: 75, type: .transfer)
        transaction.setFromConto(from); transaction.setToConto(to)
        let text = await csvService.exportTransactions([transaction], options: CSVExportOptions())
        let parsed = CSVParser.parseCSVContent(text)
        let mappings = CSVParser.detectColumnMapping(headers: parsed.headers)
        let first = try await csvService.importTransactions(from: parsed, mapping: mappings,
            options: CSVImportOptions(), container: container, accountId: book.id)
        #expect(first.importedCount == 1)
        let imported = try #require(ModelContext(container).fetch(FetchDescriptor<Transaction>()).first)
        #expect(imported.fromContoId == from.id)
        #expect(imported.toContoId == to.id)
        #expect(imported.amount == 75)
        let retry = try await csvService.importTransactions(from: parsed, mapping: mappings,
            options: CSVImportOptions(), container: container, accountId: book.id)
        #expect(retry.importedCount == 0)
        #expect(retry.duplicatesSkipped == 1)
    }

    @Test func explicitTransferTypeKeepsSourceAndTargetForUnsignedCSV() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = ModelContext(container)
        let book = Account(name: "Libro")
        let from = Conto(name: "Banca", type: .checking)
        let to = Conto(name: "Risparmio", type: .savings)
        from.account = book; to.account = book
        context.insert(book); context.insert(from); context.insert(to)
        try context.save()
        let parsed = CSVParser.parseCSVContent("Date,Amount,Type,Source Account,Target Account\n2026-10-01,75,Transfer,Banca,Risparmio")
        let result = try await csvService.importTransactions(from: parsed,
            mapping: CSVParser.detectColumnMapping(headers: parsed.headers), options: CSVImportOptions(),
            container: container, accountId: book.id)
        #expect(result.importedCount == 1)
        let imported = try #require(ModelContext(container).fetch(FetchDescriptor<Transaction>()).first)
        #expect(imported.fromContoId == from.id)
        #expect(imported.toContoId == to.id)
    }

    @Test func exportSignsRemainUnambiguousWithoutTypeColumn() async throws {
        let expense = Transaction(amount: 12, type: .expense, transactionDescription: "Uscita")
        let income = Transaction(amount: 30, type: .income, transactionDescription: "Entrata")
        let options = CSVExportOptions(includeFields: [.amount, .description])
        let parsed = CSVParser.parseCSVContent(await csvService.exportTransactions([expense, income], options: options))
        let index = try #require(parsed.headers.firstIndex(of: CSVField.amount.rawValue))
        let values = parsed.rows.compactMap { CSVParser.parseAmount($0[index]) }
        #expect(Set(values) == [-12, 30])
    }

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
