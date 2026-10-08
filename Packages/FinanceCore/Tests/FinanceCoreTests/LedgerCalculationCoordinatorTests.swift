import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct LedgerCalculationCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func simultaneousConsumersComputeOnceAndReuseAcrossScopes() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let a = LedgerCacheAccount(id: UUID(), initialBalance: 100)
        let b = LedgerCacheAccount(id: UUID(), initialBalance: 50)
        let entry = TransactionSnapshot(amount: 10, type: .transfer, date: now, fromContoId: a.id, toContoId: b.id, destinationAmount: 8)
        let coordinator = LedgerCalculationCoordinator()
        let results = try await withThrowingTaskGroup(of: LedgerCachePreparation.self) { group in
            for _ in 0..<20 { group.addTask { try await coordinator.prepare(container: container, accounts: [a, b], transactions: [entry], now: now) } }
            var values: [LedgerCachePreparation] = []
            for try await result in group { values.append(result) }
            return values
        }
        for result in results {
            #expect(result.snapshots[a.id]?.balance == 90)
            #expect(result.snapshots[b.id]?.balance == 58)
            #expect(result.updates == results.first?.updates)
        }
        #expect(await coordinator.calculationCount == 2)
        #expect(await coordinator.memoryReuseCount == 38)
        let scope = try await coordinator.prepare(container: container, accounts: [a], transactions: [entry], now: now.addingTimeInterval(60))
        #expect(scope.reusedCount == 1)
        #expect(await coordinator.calculationCount == 2)
    }

    @Test func sameCountEditsAndMovedEndpointsRecomputeOnlyAffectedAccounts() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let accounts = (0..<3).map { _ in LedgerCacheAccount(id: UUID(), initialBalance: 100) }
        let id = UUID()
        let coordinator = LedgerCalculationCoordinator()
        let first = TransactionSnapshot(id: id, amount: 10, type: .transfer, date: now, fromContoId: accounts[0].id, toContoId: accounts[1].id)
        _ = try await coordinator.prepare(container: container, accounts: accounts, transactions: [first], now: now)
        let edit = TransactionSnapshot(id: id, amount: 20, type: .transfer, date: now, fromContoId: accounts[0].id, toContoId: accounts[2].id, destinationAmount: 18)
        let result = try await coordinator.prepare(container: container, accounts: accounts, transactions: [edit], now: now)
        #expect(result.snapshots[accounts[0].id]?.balance == 80)
        #expect(result.snapshots[accounts[1].id]?.balance == 100)
        #expect(result.snapshots[accounts[2].id]?.balance == 118)
        #expect(await coordinator.calculationCount == 6)
        _ = try await coordinator.prepare(container: container, accounts: accounts, transactions: [edit], now: now)
        #expect(await coordinator.calculationCount == 6)
    }

    @Test func singleAccountEditKeepsSiblingMemoizedAndCorruptPayloadIsRepaired() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let a = LedgerCacheAccount(id: UUID(), initialBalance: 100), b = LedgerCacheAccount(id: UUID(), initialBalance: 100)
        let coordinator = LedgerCalculationCoordinator()
        let first = TransactionSnapshot(amount: 1, type: .expense, date: now, fromContoId: a.id)
        _ = try await coordinator.prepare(container: container, accounts: [a, b], transactions: [first], now: now)
        let edit = TransactionSnapshot(id: first.id, amount: 2, type: .expense, date: now, fromContoId: a.id)
        _ = try await coordinator.prepare(container: container, accounts: [a, b], transactions: [edit], now: now)
        #expect(await coordinator.calculationCount == 3)
        let corrupt = LedgerCacheAccount(id: a.id, initialBalance: 100, ledgerCacheJSON: "bad")
        let repaired = try await coordinator.prepare(container: container, accounts: [corrupt], transactions: [edit], now: now)
        #expect(repaired.snapshots[a.id]?.balance == 98)
        #expect(repaired.updates[a.id] != nil)
    }

    @Test func payloadAlreadySavedDoesNotRequestAnotherSaveAndFutureMaturityIsObserved() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let account = LedgerCacheAccount(id: UUID(), initialBalance: 100)
        let entries = [TransactionSnapshot(amount: 5, type: .expense, date: now.addingTimeInterval(1), fromContoId: account.id)]
        let coordinator = LedgerCalculationCoordinator()
        let first = try await coordinator.prepare(container: container, accounts: [account], transactions: entries, now: now)
        let saved = LedgerCacheAccount(id: account.id, initialBalance: 100, ledgerCacheJSON: first.updates[account.id])
        let second = try await coordinator.prepare(container: container, accounts: [saved], transactions: entries, now: now)
        #expect(second.updates.isEmpty)
        #expect(await coordinator.calculationCount == 1)
        let next = try await coordinator.prepare(container: container, accounts: [saved], transactions: entries, now: now.addingTimeInterval(1))
        #expect(next.snapshots[account.id]?.balance == 95)
        #expect(await coordinator.calculationCount == 2)
    }

    @Test func containerReplacementAndCalendarChangesDoNotShareWrongResults() async throws {
        let firstContainer = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let secondContainer = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let account = LedgerCacheAccount(id: UUID(), initialBalance: 100)
        let coordinator = LedgerCalculationCoordinator()
        _ = try await coordinator.prepare(container: firstContainer, accounts: [account], transactions: [], now: now)
        _ = try await coordinator.prepare(container: secondContainer, accounts: [account], transactions: [], now: now)
        var alternate = Calendar.current
        alternate.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        _ = try await coordinator.prepare(container: secondContainer, accounts: [account], transactions: [], now: now, calendar: alternate)
        #expect(await coordinator.calculationCount == 3)
    }

    @Test func boundedMemoryAndCancellationCannotPoisonLaterRequests() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let accounts = (0..<8).map { _ in LedgerCacheAccount(id: UUID(), initialBalance: 100) }
        let coordinator = LedgerCalculationCoordinator(maximumEntries: 3)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.prepare(container: container, accounts: accounts, transactions: [], now: now)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled request returned values") }
        catch is CancellationError {}
        #expect(await coordinator.calculationCount == 0)
        let value = try await coordinator.prepare(container: container, accounts: accounts, transactions: [], now: now)
        #expect(value.snapshots.count == 8)
        #expect(await coordinator.retainedEntryCount == 3)
    }
}
