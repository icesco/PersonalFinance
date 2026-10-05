import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct AccountCreationTests {
    enum SaveFailure: Error { case unavailable }
    @Test func createsBookWithItsOwnCompleteDefaultCategories() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let service = AccountCreation(context: context)
        let first = try service.create(name: "  Personal  ", currency: "EUR")
        let second = try service.create(name: "Travel", currency: "USD")
        let verify = ModelContext(container)
        let books = try verify.fetch(FetchDescriptor<Account>())
        #expect(books.count == 2)
        #expect(first.name == "Personal" && second.currency == "USD")
        for book in books {
            let categories = book.categories ?? []
            #expect(categories.count == FinanceCore.Category.defaultCategoryDefinitions.count)
            #expect(Set(categories.map(\.externalID)).count == categories.count)
            #expect(categories.allSatisfy { $0.account?.id == book.id && $0.externalID.hasPrefix("\(book.id)-") })
        }
        #expect(Set((first.categories ?? []).map(\.id)).isDisjoint(with: (second.categories ?? []).map(\.id)))
    }
    @Test func failureLeavesNoBookOrCategoriesAndPreservesOtherDrafts() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let existing = Account(name: "Existing")
        context.insert(existing); try context.save()
        existing.name = "Pending draft"
        let failing = AccountCreation(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) { try failing.create(name: "New", currency: "EUR") }
        #expect(existing.name == "Pending draft")
        try context.save()
        let verify = ModelContext(container)
        #expect(try verify.fetch(FetchDescriptor<Account>()).map(\.name) == ["Pending draft"])
        #expect(try verify.fetchCount(FetchDescriptor<FinanceCore.Category>()) == 0)
        _ = try AccountCreation(context: context).create(name: "Retry", currency: "EUR")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Account>()) == 2)
    }
    @Test func rejectsInvalidInputBeforeInsertingOrSaving() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        var saves = 0
        let service = AccountCreation(context: container.mainContext, save: { saves += 1 })
        #expect(throws: AccountCreation.Failure.invalidName) { try service.create(name: " \n ", currency: "EUR") }
        #expect(throws: AccountCreation.Failure.invalidCurrency) { try service.create(name: "Book", currency: "invalid") }
        #expect(saves == 0)
        #expect(!container.mainContext.hasChanges)
    }
    @Test func setupCreatesAllContiAndPreservesTheirDetails() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let cash = Conto(name: "Cash", type: .cash, initialBalance: 25)
        let card = Conto(name: "Card", type: .credit, initialBalance: -120,
                         creditLimit: 1000, statementClosingDay: 10, paymentDueDay: 20)
        let book = try AccountCreation(context: container.mainContext).create(name: "Setup", currency: "EUR", conti: [cash, card])
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Account>()).first)
        #expect(stored.id == book.id && stored.conti?.count == 2)
        let storedCard = try #require(stored.conti?.first { $0.id == card.id })
        #expect(storedCard.initialBalance == -120 && storedCard.creditLimit == 1000)
        #expect(storedCard.statementClosingDay == 10 && storedCard.paymentDueDay == 20)
        #expect(stored.totalBalance == -95)
    }

    @Test func setupFailureAndRetryDoNotDuplicateBookContiOrCategories() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let failing = AccountCreation(context: context, save: { throw SaveFailure.unavailable })
        #expect(throws: SaveFailure.self) {
            try failing.create(name: "Setup", currency: "EUR", conti: [Conto(name: "Cash", type: .cash, initialBalance: 25)])
        }
        try context.save()
        let verify = ModelContext(container)
        #expect(try verify.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<Conto>()) == 0)
        #expect(try verify.fetchCount(FetchDescriptor<FinanceCore.Category>()) == 0)
        _ = try AccountCreation(context: context).create(name: "Setup", currency: "EUR", conti: [Conto(name: "Cash", type: .cash, initialBalance: 25)])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conto>()) == 1)
    }

    @Test func setupRejectsExistingAccountsAndInvalidCurrencyPrecisionBeforeMutation() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let owned = Conto(name: "Existing", type: .checking)
        context.insert(owned); try context.save()
        let service = AccountCreation(context: context)
        #expect(throws: AccountCreation.Failure.invalidConti) { try service.create(name: "Book", currency: "EUR", conti: [owned]) }
        let fractional = Conto(name: "Yen", type: .cash, initialBalance: Decimal(string: "1.5")!)
        #expect(throws: AccountCreation.Failure.invalidConti) { try service.create(name: "Book", currency: "JPY", conti: [fractional]) }
        #expect(owned.account == nil && fractional.modelContext == nil)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

}
