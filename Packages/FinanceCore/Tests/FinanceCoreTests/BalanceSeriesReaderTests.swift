import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct BalanceSeriesReaderTests {
    @Test(arguments: ["outside", "source", "destination"])
    func materializedOccurrenceArrivingBeforeResolutionSuppressesVirtualCopy(endpoints: String) async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Conto(name: "A", type: .checking, initialBalance: 100)
        let b = Conto(name: "B", type: .checking, initialBalance: 0)
        let c = Conto(name: "C", type: .checking, initialBalance: 0)
        let d = Conto(name: "D", type: .checking, initialBalance: 0)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = Transaction(amount: 20, type: .transfer, date: now.addingTimeInterval(-86_400),
                                 isRecurring: true, recurrenceFrequency: .daily)
        source.setFromConto(a)
        source.setToConto(b)
        let scheduled = try #require(source.nextRecurrenceDate(after: now))
        source.recurrenceEndDate = scheduled
        for conto in [a, b, c, d] { context.insert(conto) }
        context.insert(source)
        try context.save()
        let interval = DateInterval(start: now.addingTimeInterval(-100), end: scheduled.addingTimeInterval(60))
        let reader = BalanceSeriesReader()
        let before = try await reader.load(container: container, contoIDs: [a.id], interval: interval, now: now)
        #expect(before.first?.projected.last?.balance == 60)

        // Simulate partial CloudKit delivery after editing the realized transfer's endpoints.
        let occurrence = Transaction(amount: 30, type: .transfer, date: scheduled)
        occurrence.setFromConto(endpoints == "source" ? a : c)
        occurrence.setToConto(endpoints == "destination" ? a : d)
        occurrence.recurrenceSourceID = source.id
        occurrence.externalID = RecurrenceResolution.key(sourceID: source.id, date: scheduled)
        context.insert(occurrence)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<RecurrenceResolution>()) == 0)
        let expected: Decimal = endpoints == "outside" ? 80 : endpoints == "source" ? 50 : 110
        for _ in 0..<2 {
            let actual = try await reader.load(container: container, contoIDs: [a.id], interval: interval, now: now)
            #expect(actual.map(\.id) == [a.id])
            #expect(actual.first?.points.last?.balance == 80)
            #expect(actual.first?.projected.last?.balance == expected)
        }

        // A later resolution must not change the result or count the occurrence twice.
        context.insert(RecurrenceResolution(sourceID: source.id, scheduledDate: scheduled, transactionID: occurrence.id))
        try context.save()
        let resolved = try await reader.load(container: container, contoIDs: [a.id], interval: interval, now: now)
        #expect(resolved.first?.projected.last?.balance == expected)
    }

    @Test func chartReaderScopesLegacyTransfersAndReusesPersistedHistory() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let cash = Conto(name: "Banca", type: .checking, initialBalance: 100)
        let foreign = Conto(name: "Altro", type: .checking, initialBalance: 0)
        let now = Date()
        let movement = Transaction(amount: 20, type: .transfer, date: now.addingTimeInterval(-60))
        movement.setFromConto(foreign)
        movement.setToConto(cash)
        movement.destinationAmount = 18
        // Older entries may only have relationships, without the indexed IDs.
        movement.fromContoId = nil
        movement.toContoId = nil
        let unrelated = Transaction(amount: 500, type: .expense, date: now)
        unrelated.setFromConto(foreign)
        for conto in [cash, foreign] { context.insert(conto) }
        context.insert(movement)
        context.insert(unrelated)
        try context.save()
        let interval = DateInterval(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600))
        let reader = BalanceSeriesReader()
        let first = try await reader.load(container: container, contoIDs: [cash.id], interval: interval, now: now)
        #expect(first.map(\.id) == [cash.id])
        #expect(first.first?.points.last?.balance == 118)
        let readContext = ModelContext(container)
        let id = cash.id
        let persisted = try #require(readContext.fetch(FetchDescriptor<Conto>(predicate: #Predicate { $0.id == id })).first)
        let json = try #require(persisted.ledgerCacheJSON)
        let second = try await reader.load(container: container, contoIDs: [cash.id], interval: interval, now: now)
        #expect(first.first?.points == second.first?.points)
        #expect(persisted.ledgerCacheJSON == json)
        movement.destinationAmount = 25
        try context.save()
        let edited = try await reader.load(container: container, contoIDs: [cash.id], interval: interval, now: now)
        #expect(edited.first?.points.last?.balance == 125)
    }
}
