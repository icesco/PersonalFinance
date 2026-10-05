import Foundation
import Testing
@testable import Personal_Finance

@MainActor
struct AppLockTests {
    @MainActor final class FakeAuthentication: DeviceAuthenticating {
        var accept = true
        var duringAuthentication: (() -> Void)?
        func authenticate(reason: String) async throws -> Bool {
            duringAuthentication?()
            return accept
        }
        func cancel() { }
    }

    @Test func activationRequiresAuthenticationAndRelaunchStartsLocked() async {
        let name = "lock-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let auth = FakeAuthentication()
        let lock = AppLock(defaults: defaults, authenticator: auth)
        auth.accept = false
        await lock.setEnabled(true)
        #expect(!lock.isEnabled)
        auth.accept = true
        await lock.setEnabled(true)
        #expect(lock.isEnabled && !lock.isLocked)
        #expect(AppLock(defaults: defaults, authenticator: auth).isLocked)
        lock.sceneChanged(.inactive)
        #expect(lock.shouldConceal)
        #if os(iOS)
        #expect(!lock.isLocked)
        #endif
        lock.sceneChanged(.active)
        await lock.unlock()
        #expect(!lock.isLocked)
        auth.accept = false
        await lock.setEnabled(false)
        #expect(lock.isEnabled)
    }

    @Test func protectionPreservesSessionAndRequiresUnlockAfterBackground() async {
        let name = "lock-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let auth = FakeAuthentication()
        let lock = AppLock(defaults: defaults, authenticator: auth)
        await lock.setEnabled(true)
        #expect(lock.hasUnlockedInSession)
        lock.sceneChanged(.inactive)
        #expect(lock.shouldConceal)
        #expect(lock.hasUnlockedInSession)
        lock.sceneChanged(.active)
        #if os(iOS)
        #expect(!lock.shouldConceal)
        #endif
        lock.sceneChanged(.background)
        #expect(lock.isLocked && lock.shouldConceal && lock.hasUnlockedInSession)
        lock.sceneChanged(.active)
        #expect(lock.isLocked && lock.shouldConceal)
        await lock.unlock()
        #expect(!lock.shouldConceal && lock.hasUnlockedInSession)
    }

    @Test func successfulAuthenticationFinishesWhenItsSystemPromptCloses() async {
        let name = "lock-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppLock.preferenceKey)
        let auth = FakeAuthentication()
        let lock = AppLock(defaults: defaults, authenticator: auth)
        #expect(!lock.hasUnlockedInSession)
        auth.duringAuthentication = { lock.sceneChanged(.inactive) }
        await lock.unlock()
        #expect(lock.shouldConceal && !lock.hasUnlockedInSession)
        lock.sceneChanged(.active)
        #expect(!lock.shouldConceal && lock.hasUnlockedInSession)
    }

    @Test func backgroundInvalidatesSuccessfulButLateAuthentication() async {
        let name = "lock-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppLock.preferenceKey)
        let auth = FakeAuthentication()
        let lock = AppLock(defaults: defaults, authenticator: auth)
        auth.duringAuthentication = { lock.sceneChanged(.background) }
        await lock.unlock()
        #expect(lock.isLocked)
        #expect(!lock.isAuthenticating)
    }
}
