import Foundation
import SwiftData
import Testing
@testable import FinanceCore

private final class ChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [FinanceDataChange] = []
    func append(_ value: FinanceDataChange) { lock.lock(); values.append(value); lock.unlock() }
    func take(container: ModelContainer) -> [FinanceDataChange] {
        lock.lock(); defer { lock.unlock() }
        let result = values.filter { $0.containerID == ObjectIdentifier(container) }
        values.removeAll()
        return result
    }
}

@MainActor
struct FinanceDataChangeTests {
    @Test func categorizedInsertAndTransferEditsRemainTargeted() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .checking), c = Conto(name: "C", type: .checking)
        let category = Category(name: "Spesa")
        for conto in [a, b, c] { context.insert(conto) }
        context.insert(category)
        try context.save()
        let recorder = ChangeRecorder()
        let observer = NotificationCenter.default.addObserver(forName: FinanceDataChangeCenter.notificationName, object: nil, queue: nil) {
            if let change = FinanceDataChange.from($0) { recorder.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        FinanceDataChangeCenter.shared.remember(container: container, transactions: [], accounts: [a, b, c].map(LedgerCacheAccount.init))
        FinanceDataChangeCenter.shared.rememberCategories(container: container, categories: [category])
        let entry = Transaction(amount: 10, type: .expense, date: .now)
        entry.setFromConto(a)
        entry.category = category
        context.insert(entry)
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == [a.id])
        entry.type = .transfer
        entry.setToConto(b)
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == [a.id, b.id])
        for index in 0..<30 {
            let old = entry.toContoId
            let destination = index % 2 == 0 ? c : b
            entry.setToConto(destination)
            entry.destinationAmount = Decimal(index + 1)
            try context.save()
            #expect(recorder.take(container: container).last?.contoIDs == Set([a.id, destination.id, old!]))
        }
        category.name = "Nuovo nome"
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == nil)
    }

    @Test func editsMovesAndDeletesNotifyOldAndNewEndpointsOnly() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let a = Conto(name: "A", type: .checking), b = Conto(name: "B", type: .checking), c = Conto(name: "C", type: .checking)
        for conto in [a, b, c] { context.insert(conto) }
        let entry = Transaction(amount: 10, type: .expense, date: .now)
        entry.setFromConto(a)
        context.insert(entry)
        try context.save()
        let recorder = ChangeRecorder()
        let observer = NotificationCenter.default.addObserver(forName: FinanceDataChangeCenter.notificationName, object: nil, queue: nil) {
            if let change = FinanceDataChange.from($0) { recorder.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        FinanceDataChangeCenter.shared.remember(container: container, transactions: [TransactionSnapshot(from: entry)], accounts: [a, b, c].map(LedgerCacheAccount.init))
        entry.amount = 20
        try context.save()
        let edit = try #require(recorder.take(container: container).last)
        #expect(edit.contoIDs == [a.id])
        #expect(edit.affects(container: container, contoIDs: [a.id]))
        #expect(!edit.affects(container: container, contoIDs: [c.id]))
        entry.setFromConto(b)
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == [a.id, b.id])
        context.delete(entry)
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == [b.id])
    }

    @Test func unknownOriginalEndpointFallsBackToAllAndContainerScopeIsRespected() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let other = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let entry = Transaction(amount: 10, type: .expense, date: .now)
        entry.fromContoId = UUID()
        context.insert(entry)
        try context.save()
        let recorder = ChangeRecorder()
        let observer = NotificationCenter.default.addObserver(forName: FinanceDataChangeCenter.notificationName, object: nil, queue: nil) {
            if let change = FinanceDataChange.from($0) { recorder.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // Use another transaction that was never remembered by the running readers.
        entry.id = UUID()
        entry.fromContoId = UUID()
        try context.save()
        let value = try #require(recorder.take(container: container).last)
        #expect(value.contoIDs == nil)
        #expect(value.affects(container: container, contoIDs: [UUID()]))
        #expect(!value.affects(container: other, contoIDs: nil))
    }

    @Test func cacheOnlySavesAreSilentButSourceAndConfigurationChangesAreNot() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let conto = Conto(name: "A", type: .checking)
        context.insert(conto)
        try context.save()
        let recorder = ChangeRecorder()
        let observer = NotificationCenter.default.addObserver(forName: FinanceDataChangeCenter.notificationName, object: nil, queue: nil) {
            if let change = FinanceDataChange.from($0) { recorder.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let cacheContext = ModelContext(container)
        cacheContext.autosaveEnabled = false
        let cached = try #require(cacheContext.fetch(FetchDescriptor<Conto>()).first)
        cached.ledgerCacheJSON = "cache"
        try FinanceDataChangeCenter.shared.saveCache(context: cacheContext)
        #expect(recorder.take(container: container).isEmpty)
        conto.initialBalance = 30
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == nil)
        let budget = Budget(name: "Budget", amount: 10, period: .monthly)
        context.insert(budget)
        try context.save()
        #expect(recorder.take(container: container).last?.contoIDs == nil)
    }
}
