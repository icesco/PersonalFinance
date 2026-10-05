import Foundation
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct SharedBookAutomaticRefreshTests {
    private func container() throws -> ModelContainer {
        try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
    }
    private func member(_ container: ModelContainer, owner: Bool = false) throws -> SharedBookMembership {
        let scope = SharedBookScope(ownerName: "owner", bookID: UUID())
        let value = SharedBookMembership(scopeKey: scope.key, ownerName: scope.ownerName,
                                        remoteBookID: scope.bookID, localBookID: UUID(), isOwner: owner)
        container.mainContext.insert(value)
        try container.mainContext.save()
        return value
    }

    @Test func disabledAndPrivateBooksNeverStartSynchronization() async throws {
        let container = try container()
        var enabled = false
        var calls = 0
        let service = SharedBookAutomaticRefresh(configuration: { (container, 1, enabled) }) { _, _ in
            calls += 1
            return .synchronized(localBookID: UUID())
        }
        await service.refresh()
        enabled = true
        container.mainContext.insert(Account(name: "Private", currency: "EUR"))
        try container.mainContext.save()
        await service.refresh()
        #expect(calls == 0)
        _ = try member(container)
        enabled = false
        await service.refresh()
        #expect(calls == 0)
    }

    @Test func refreshesExistingRolesDeduplicatesAndThrottles() async throws {
        let container = try container()
        let owner = try member(container, owner: true)
        let participant = try member(container)
        container.mainContext.insert(SharedBookMembership(scopeKey: owner.scopeKey, ownerName: owner.ownerName,
                                                          remoteBookID: owner.remoteBookID, localBookID: owner.localBookID, isOwner: true))
        try container.mainContext.save()
        var instant = Date(timeIntervalSince1970: 1_000)
        var roles: [String: SharedBookCloudTransport.Role] = [:]
        var calls = 0
        let service = SharedBookAutomaticRefresh(configuration: { (container, 1, true) }, now: { instant }) { scope, role in
            roles[scope.key] = role; calls += 1
            return .synchronized(localBookID: scope.key == owner.scopeKey ? owner.localBookID : participant.localBookID)
        }
        await service.refresh()
        await service.refresh()
        #expect(calls == 2)
        #expect(roles[owner.scopeKey] == .owner)
        #expect(roles[participant.scopeKey] == .participant)
        #expect(service.statuses[owner.localBookID] == .updated(instant))
        instant.addTimeInterval(61)
        await service.refresh()
        #expect(calls == 4)
    }

    @Test func reviewAndFailureDoNotStopOtherBooks() async throws {
        enum Failure: Error { case offline }
        let container = try container()
        let review = try member(container)
        let failure = try member(container)
        let success = try member(container)
        let instant = Date()
        let service = SharedBookAutomaticRefresh(configuration: { (container, 1, true) }, now: { instant }) { scope, _ in
            if scope.key == review.scopeKey { return .needsReview(conflicts: [], references: []) }
            if scope.key == failure.scopeKey { throw Failure.offline }
            return .synchronized(localBookID: success.localBookID)
        }
        await service.refresh()
        #expect(service.statuses[review.localBookID] == .needsReview)
        #expect(service.statuses[failure.localBookID] == .failed)
        #expect(service.statuses[success.localBookID] == .updated(instant))
    }

    @Test func disablingDuringRefreshDiscardsResponseAndStopsRemainingBooks() async throws {
        let container = try container()
        _ = try member(container); _ = try member(container)
        var enabled = true
        var version = 1
        var pending: CheckedContinuation<SharedBookSyncCoordinator.Outcome, Never>?
        var calls = 0
        let service = SharedBookAutomaticRefresh(configuration: { (container, version, enabled) }) { _, _ in
            calls += 1
            return await withCheckedContinuation { pending = $0 }
        }
        let task = Task { await service.refresh() }
        while pending == nil { await Task.yield() }
        await service.refresh()
        #expect(calls == 1)
        enabled = false; version += 1
        pending?.resume(returning: .synchronized(localBookID: UUID()))
        await task.value
        #expect(calls == 1)
        #expect(service.statuses.isEmpty)
        #expect(!service.isRefreshing)
    }
    @Test func inconsistentMembershipNeverStartsNetworkWork() async throws {
        let container = try container()
        let original = try member(container)
        let inconsistent = SharedBookMembership(scopeKey: original.scopeKey, ownerName: original.ownerName,
                                                remoteBookID: original.remoteBookID, localBookID: UUID())
        container.mainContext.insert(inconsistent)
        try container.mainContext.save()
        var calls = 0
        let service = SharedBookAutomaticRefresh(configuration: { (container, 1, true) }) { _, _ in
            calls += 1
            return .synchronized(localBookID: original.localBookID)
        }
        await service.refresh()
        #expect(calls == 0)
        #expect(service.statuses[original.localBookID] == .failed)
        #expect(service.statuses[inconsistent.localBookID] == .failed)
    }

    @Test func membershipRemovedWhileAnotherBookRefreshesIsNotContacted() async throws {
        let container = try container()
        let members = try [member(container), member(container)].sorted { $0.scopeKey < $1.scopeKey }
        let firstKey = members[0].scopeKey
        let firstID = members[0].localBookID
        var contacted: [String] = []
        let service = SharedBookAutomaticRefresh(configuration: { (container, 1, true) }) { scope, _ in
            contacted.append(scope.key)
            container.mainContext.delete(members[1])
            try container.mainContext.save()
            return .synchronized(localBookID: firstID)
        }
        await service.refresh()
        #expect(contacted == [firstKey])
    }

}
