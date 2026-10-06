import Foundation
import CloudKit
import SwiftData
import Testing
@testable import FinanceCore

@MainActor
struct CloudLifecycleTests {
    #if DEBUG
    @Test func localUISessionIsIsolatedAndCannotEnableCloud() async throws {
        let first = DataStorageManager.makeLocalTestStorage()
        try await first.initializeContainer()
        let original = try #require(first.currentContainer)
        original.mainContext.insert(Account(name: "Synthetic UI book"))
        try original.mainContext.save()
        await first.performSyncToggle(enableCloud: true)
        #expect(!first.isCloudSyncEnabled)
        #expect(first.currentContainer === original)
        #expect(first.syncToggleError != nil)
        let second = DataStorageManager.makeLocalTestStorage()
        try await second.initializeContainer()
        let fresh = try #require(second.currentContainer)
        #expect(try fresh.mainContext.fetchCount(FetchDescriptor<Account>()) == 0)
    }
    #endif

    private func defaults() -> (UserDefaults, String) {
        let name = "CloudLifecycleTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func disabledStartupNeverRequestsCloudAccount() async throws {
        let (preferences, name) = defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        var configurations: [Bool] = []
        var requests = 0
        let manager = DataStorageManager(appGroupIdentifier: name, userDefaults: preferences, makeContainer: { enabled in
            configurations.append(enabled)
            return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }, requestAccountStatus: {
            requests += 1
            return .available
        })
        try await manager.initializeContainer()
        try await manager.initializeContainer()
        let status = await manager.cloudKitAccountStatus()
        let available = await manager.isCloudKitAvailable()
        await manager.performSyncToggle(enableCloud: false)
        #expect(configurations == [false])
        #expect(requests == 0)
        #expect(status == .couldNotDetermine)
        #expect(!available)
        #expect(manager.containerGeneration == 1)
    }

    @Test func failedTogglePreservesContainerAndPreference() async throws {
        enum Failure: Error { case opening }
        let (preferences, name) = defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        let manager = DataStorageManager(appGroupIdentifier: name, userDefaults: preferences, makeContainer: { enabled in
            if enabled { throw Failure.opening }
            return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }, requestAccountStatus: { .available })
        try await manager.initializeContainer()
        let original = manager.currentContainer
        await manager.performSyncToggle(enableCloud: true)
        #expect(manager.currentContainer === original)
        #expect(!manager.isCloudSyncEnabled)
        #expect(!preferences.bool(forKey: "CloudSyncEnabled"))
        #expect(manager.containerGeneration == 1)
        #expect(manager.syncToggleError != nil)
        #expect(!manager.isMigrating)
    }

    @Test func requestFromPreviousConfigurationCannotBecomeCurrentAgain() async throws {
        let (preferences, name) = defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(true, forKey: "CloudSyncEnabled")
        var pending: CheckedContinuation<CKAccountStatus, Never>?
        var configurations: [Bool] = []
        let manager = DataStorageManager(appGroupIdentifier: name, userDefaults: preferences, makeContainer: { enabled in
            configurations.append(enabled)
            return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }, requestAccountStatus: {
            await withCheckedContinuation { pending = $0 }
        })
        try await manager.initializeContainer()
        let request = Task { await manager.cloudKitAccountStatus() }
        // Yield until the injected service receives the request; no network is used.
        while pending == nil { await Task.yield() }
        await manager.performSyncToggle(enableCloud: false)
        #expect(!preferences.bool(forKey: "CloudSyncEnabled"))
        await manager.performSyncToggle(enableCloud: true)
        pending?.resume(returning: .available)
        let staleStatus = await request.value
        #expect(staleStatus == .couldNotDetermine)
        #expect(configurations == [true, false, true])
        #expect(manager.isCloudSyncEnabled)
        #expect(preferences.bool(forKey: "CloudSyncEnabled"))
        #expect(manager.containerGeneration == 3)
    }
    @Test func successfulDisableStopsSubsequentStatusRequests() async throws {
        let (preferences, name) = defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(true, forKey: "CloudSyncEnabled")
        var configurations: [Bool] = []
        var requests = 0
        let manager = DataStorageManager(appGroupIdentifier: name, userDefaults: preferences, makeContainer: { enabled in
            configurations.append(enabled)
            return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }, requestAccountStatus: {
            requests += 1
            return .available
        })
        try await manager.initializeContainer()
        #expect(await manager.cloudKitAccountStatus() == .available)
        #expect(requests == 1)
        await manager.performSyncToggle(enableCloud: false)
        for _ in 0..<3 {
            #expect(await manager.cloudKitAccountStatus() == .couldNotDetermine)
            #expect(await manager.isCloudKitAvailable() == false)
        }
        #expect(requests == 1)
        #expect(configurations == [true, false])
        #expect(!manager.isCloudSyncEnabled)
        #expect(!preferences.bool(forKey: "CloudSyncEnabled"))
        #expect(manager.containerGeneration == 2)
    }

    @Test func failedDisableDoesNotReportCloudAsDisabled() async throws {
        enum Failure: Error { case openingLocalStore }
        let (preferences, name) = defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(true, forKey: "CloudSyncEnabled")
        let manager = DataStorageManager(appGroupIdentifier: name, userDefaults: preferences, makeContainer: { enabled in
            guard enabled else { throw Failure.openingLocalStore }
            return try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        }, requestAccountStatus: { .available })
        try await manager.initializeContainer()
        let original = manager.currentContainer
        await manager.performSyncToggle(enableCloud: false)
        #expect(manager.currentContainer === original)
        #expect(manager.isCloudSyncEnabled)
        #expect(preferences.bool(forKey: "CloudSyncEnabled"))
        #expect(manager.containerGeneration == 1)
        #expect(manager.syncToggleError != nil)
        #expect(!manager.isMigrating)
    }

}
