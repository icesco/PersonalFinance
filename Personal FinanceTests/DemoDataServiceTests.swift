import Foundation
import SwiftData
import Testing
@testable import Personal_Finance
import FinanceCore

@MainActor
struct DemoDataServiceTests {
    @Test func failedDemoSaveLeavesNoPartialBookAndRetryCreatesOneCompleteDemo() async throws {
        enum SaveFailure: Error { case injected }
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let callerContext = ModelContext(container)
        let existing = Account(name: "Libro personale")
        callerContext.insert(existing)
        try callerContext.save()
        existing.name = "Modifica non ancora salvata"
        var shouldFail = true
        let service = DemoDataService(modelContext: callerContext) { context in
            if shouldFail { throw SaveFailure.injected }
            try context.save()
        }

        do {
            try await service.generateDemoData()
            Issue.record("Expected demo save failure")
        } catch SaveFailure.injected { }

        let afterFailure = ModelContext(container)
        #expect(try afterFailure.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(try afterFailure.fetchCount(FetchDescriptor<Conto>()) == 0)
        #expect(try afterFailure.fetchCount(FetchDescriptor<FinanceCategory>()) == 0)
        #expect(try afterFailure.fetchCount(FetchDescriptor<FinanceTransaction>()) == 0)
        #expect(existing.name == "Modifica non ancora salvata")
        #expect(callerContext.hasChanges)

        shouldFail = false
        let demoID = try await service.generateDemoData()
        let afterRetry = ModelContext(container)
        let demo = try #require(afterRetry.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == demoID })).first)
        #expect(demo.name == "Demo")
        #expect(try afterRetry.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(demo.conti?.count == 1)
        #expect(demo.categories?.count == FinanceCategory.defaultCategoryDefinitions.count)
        #expect(try afterRetry.fetchCount(FetchDescriptor<FinanceTransaction>()) > 0)
        let personal = try #require(afterRetry.fetch(FetchDescriptor<Account>()).first { $0.id == existing.id })
        #expect(personal.name == "Libro personale")
    }
}
