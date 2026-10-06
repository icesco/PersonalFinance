import Foundation
import CloudKit
import Observation
import SwiftData

/// Refreshes only existing memberships. It never creates a share or accepts an invitation.
@MainActor @Observable
public final class SharedBookAutomaticRefresh {
    public enum Status: Equatable, Sendable {
        case updated(Date), needsReview, failed
    }
    public private(set) var statuses: [UUID: Status] = [:]
    public private(set) var isRefreshing = false
    @ObservationIgnored private var generation: Int?
    @ObservationIgnored private var attempted: [String: Date] = [:]
    @ObservationIgnored private var retryNotBefore: [UUID: Date] = [:]
    @ObservationIgnored private let configuration: @MainActor () -> (ModelContainer?, Int, Bool)
    @ObservationIgnored private let synchronize: @MainActor (SharedBookScope, SharedBookCloudTransport.Role) async throws -> SharedBookSyncCoordinator.Outcome
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(configuration: @escaping @MainActor () -> (ModelContainer?, Int, Bool),
                now: @escaping @MainActor () -> Date = { Date() },
                synchronize: @escaping @MainActor (SharedBookScope, SharedBookCloudTransport.Role) async throws -> SharedBookSyncCoordinator.Outcome) {
        self.configuration = configuration; self.now = now; self.synchronize = synchronize
    }

    /// A successful manual action supersedes any earlier automatic warning.
    public func clearStatus(for bookID: UUID) {
        statuses.removeValue(forKey: bookID)
        retryNotBefore.removeValue(forKey: bookID)
    }

    public func refresh() async {
        guard !isRefreshing, !Task.isCancelled else { return }
        let (container, version, enabled) = configuration()
        guard enabled, let container else { return }
        if generation != version {
            generation = version; attempted = [:]; statuses = [:]; retryNotBefore = [:]
        }
        isRefreshing = true
        defer { isRefreshing = false }
        func isCurrent() -> Bool {
            let current = configuration()
            return !Task.isCancelled && current.2 && current.1 == version && current.0 === container
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let memberships = try context.fetch(FetchDescriptor<SharedBookMembership>())
            let groups = Dictionary(grouping: memberships, by: \.scopeKey)
            let liveIDs = Set(memberships.map(\.localBookID))
            statuses = statuses.filter { liveIDs.contains($0.key) }
            retryNotBefore = retryNotBefore.filter { liveIDs.contains($0.key) }
            attempted = attempted.filter { groups[$0.key] != nil }
            for key in groups.keys.sorted() {
                guard isCurrent() else { return }
                // A previous book awaited the network: re-read membership before starting the next one.
                let fresh = ModelContext(container)
                fresh.autosaveEnabled = false
                let entries = try fresh.fetch(FetchDescriptor<SharedBookMembership>(predicate: #Predicate { $0.scopeKey == key }))
                guard let member = entries.first else { continue }
                guard entries.allSatisfy({ $0.localBookID == member.localBookID && $0.remoteBookID == member.remoteBookID && $0.ownerName == member.ownerName && $0.isOwner == member.isOwner }) else {
                    for entry in entries { statuses[entry.localBookID] = .failed }
                    continue
                }
                let scope = SharedBookScope(ownerName: member.ownerName, bookID: member.remoteBookID)
                guard scope.key == key else { statuses[member.localBookID] = .failed; continue }
                // Multiple windows and saves must not produce bursts of identical requests.
                let instant = now()
                if let deadline = retryNotBefore[member.localBookID], instant < deadline { continue }
                if let last = attempted[key], instant.timeIntervalSince(last) >= 0, instant.timeIntervalSince(last) < 60 { continue }
                attempted[key] = instant
                let localID = member.localBookID
                do {
                    let outcome = try await synchronize(scope, member.isOwner ? .owner : .participant)
                    guard isCurrent() else { return }
                    retryNotBefore.removeValue(forKey: localID)
                    switch outcome {
                    case .synchronized: statuses[localID] = .updated(now())
                    case .needsReview: statuses[localID] = .needsReview
                    }
                } catch is CancellationError {
                    attempted.removeValue(forKey: key)
                    return
                } catch SharedBookSyncCoordinator.Failure.alreadySyncing {
                    // A manual operation owns this book; let it finish before the next pass.
                    continue
                } catch {
                    guard isCurrent() else { return }
                    statuses[localID] = .failed
                    if let delay = Self.retryDelay(for: error) {
                        // The interval starts when CloudKit returns the error, not
                        // when the request began. Other books can still refresh.
                        retryNotBefore[localID] = now().addingTimeInterval(delay)
                    }
                }
            }
        } catch {
            // Memberships could not be read: no network operation is started.
            return
        }
    }

    private static func retryDelay(for error: any Error, depth: Int = 0) -> TimeInterval? {
        guard depth < 8, let cloud = error as? CKError else { return nil }
        var delays: [TimeInterval] = []
        if let delay = cloud.retryAfterSeconds, delay.isFinite, delay > 0 { delays.append(delay) }
        if let failures = cloud.partialErrorsByItemID {
            delays += failures.values.compactMap { retryDelay(for: $0, depth: depth + 1) }
        }
        return delays.max()
    }
}
