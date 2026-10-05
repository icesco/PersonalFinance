import Foundation
import SwiftData
import Testing
import FinanceCore
@testable import Personal_Finance

@MainActor
struct PlaceDraftTests {
    @Test func placePersistsAndCanBeRemovedWithoutChangingAmount() throws {
        let container = try FinanceCoreModule.createModelContainer(inMemory: true)
        let transaction = FinanceTransaction(amount: 15, type: .expense)
        var draft = PlaceDraft()
        draft.name = "  Luogo di prova  "
        draft.latitude = 45
        draft.longitude = 9
        draft.accuracy = 100
        draft.apply(to: transaction)
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        let reader = ModelContext(container)
        let reloaded = try #require(reader.fetch(FetchDescriptor<FinanceTransaction>()).first)
        #expect(reloaded.placeName == "Luogo di prova")
        #expect(reloaded.latitude == 45)
        #expect(reloaded.longitude == 9)
        #expect(reloaded.locationAccuracy == 100)
        let restored = PlaceDraft(transaction: reloaded)
        #expect(restored.name == "Luogo di prova")
        PlaceDraft().apply(to: reloaded)
        try reader.save()
        #expect(reloaded.placeName == nil && reloaded.latitude == nil && reloaded.longitude == nil)
        #expect(reloaded.amount == 15)
    }
}
