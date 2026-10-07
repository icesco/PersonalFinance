import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct SettingsEditsTests {
    private enum SaveFailure: Error { case unavailable }

    private func fixture() throws -> (ModelContainer, Account, [FinanceCore.Category], [Conto]) {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Account(name: "Libro", currency: "EUR")
        context.insert(book)
        let categories = ["A", "B", "C"].map { FinanceCore.Category(name: $0) }
        for category in categories { category.account = book; context.insert(category) }
        let conti = ["Uno", "Due", "Tre"].map { Conto(name: $0, type: .checking, initialBalance: 100) }
        for conto in conti { conto.account = book; context.insert(conto) }
        try context.save()
        return (container, book, categories, conti)
    }

    @Test func archivesTheOriginalSelectionAndPreservesTransactionHistory() throws {
        let (container, _, categories, conti) = try fixture()
        let context = container.mainContext
        let transaction = Transaction(amount: 20, type: .expense, date: Date())
        transaction.category = categories[2]
        transaction.setFromConto(conti[2])
        context.insert(transaction)
        try context.save()
        let edits = SettingsEdits(context: context)
        try edits.archiveCategories(categories.filter { $0.isActive == true }, at: IndexSet([0, 2]))
        try edits.archiveConti(conti.filter { $0.isActive == true }, at: IndexSet([0, 2]))
        let verify = ModelContext(container)
        let storedCategories = try verify.fetch(FetchDescriptor<FinanceCore.Category>())
        #expect(Set(storedCategories.filter { $0.isActive == true }.compactMap(\.name)) == ["B"])
        #expect(try verify.fetch(FetchDescriptor<Conto>()).filter { $0.isActive == true }.map(\.name) == ["Due"])
        let storedTransaction = try #require(verify.fetch(FetchDescriptor<Transaction>()).first)
        #expect(storedTransaction.category?.id == categories[2].id)
        #expect(storedTransaction.fromConto?.id == conti[2].id)
        #expect(storedTransaction.amount == 20)
    }

    @Test func failedArchiveRestoresSelectionWithoutDiscardingAnotherDraft() throws {
        let (container, book, categories, conti) = try fixture()
        let context = container.mainContext
        book.name = "Bozza da conservare"
        let edits = SettingsEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try edits.archiveCategories(categories, at: IndexSet([0, 2])) }
        #expect(throws: SaveFailure.self) { try edits.archiveConti(conti, at: IndexSet([0, 2])) }
        #expect(categories.allSatisfy { $0.isActive == true })
        #expect(conti.allSatisfy { $0.isActive == true })
        #expect(book.name == "Bozza da conservare")
        try context.save()
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<FinanceCore.Category>()).allSatisfy { $0.isActive == true })
        #expect(try verify.fetch(FetchDescriptor<Conto>()).allSatisfy { $0.isActive == true })
    }

    @Test func invalidIndicesFailBeforeAnyMutationOrSave() throws {
        let (container, _, categories, _) = try fixture()
        var saves = 0
        let edits = SettingsEdits(context: container.mainContext, save: { saves += 1 })
        #expect(throws: SettingsEdits.Failure.invalidSelection) {
            try edits.archiveCategories(categories, at: IndexSet([0, 3]))
        }
        try edits.archiveCategories(categories, at: [])
        #expect(saves == 0)
        #expect(categories.allSatisfy { $0.isActive == true })
    }

    @Test func failedCreationLeavesNoGhostCategoryAndCanBeRetried() throws {
        let (container, book, _, _) = try fixture()
        let context = container.mainContext
        book.name = "Bozza"
        let failing = SettingsEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.createCategory(name: "Nuova", color: "#123456", icon: "tag", parentID: nil, account: book)
        }
        #expect(book.name == "Bozza")
        #expect(book.categories?.contains { $0.name == "Nuova" } == false)
        try context.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == 3)
        let created = try SettingsEdits(context: context).createCategory(
            name: "  Nuova \n", color: "#123456", icon: "tag", parentID: nil, account: book)
        #expect(created.name == "Nuova")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<FinanceCore.Category>()) == 4)
    }

    @Test func failedUpdateRestoresEveryFieldAndKeepsDrafts() throws {
        let (container, book, categories, _) = try fixture()
        let context = container.mainContext
        let category = categories[0]
        let originalDate = category.updatedAt
        book.name = "Bozza"
        let failing = SettingsEdits(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.updateCategory(category, name: "Cambio", color: "#FFFFFF", icon: "heart")
        }
        #expect(category.name == "A")
        #expect(category.color == CategoryPalette.fallback)
        #expect(category.icon == "tag")
        #expect(category.updatedAt == originalDate)
        #expect(book.name == "Bozza")
        try context.save()
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<FinanceCore.Category>()).first { $0.id == category.id }?.name == "A")
        try SettingsEdits(context: context).updateCategory(category, name: "  Cambio  ", color: "#FFFFFF", icon: "heart")
        #expect(category.name == "Cambio")
    }

    @Test func invalidNamesAndForeignParentsNeverPersist() throws {
        let (container, book, categories, _) = try fixture()
        var saves = 0
        let edits = SettingsEdits(context: container.mainContext, save: { saves += 1 })
        #expect(throws: SettingsEdits.Failure.invalidName) {
            try edits.updateCategory(categories[0], name: " \n ", color: "red", icon: "heart")
        }
        #expect(throws: SettingsEdits.Failure.invalidName) {
            try edits.createCategory(name: " ", color: "red", icon: "heart", parentID: nil, account: book)
        }
        #expect(throws: SettingsEdits.Failure.invalidParent) {
            try edits.createCategory(name: "Nuova", color: "red", icon: "heart", parentID: UUID(), account: book)
        }
        #expect(saves == 0)
        #expect(categories[0].name == "A")
    }
}
