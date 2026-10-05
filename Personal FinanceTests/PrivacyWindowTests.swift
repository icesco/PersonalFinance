#if os(iOS)
import UIKit
import Testing
@testable import Personal_Finance

@MainActor
struct PrivacyWindowTests {
    @Test func nativeShieldHidesContentAndPreservesDraftAcrossLock() async throws {
        let name = "privacy-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let lock = AppLock(defaults: defaults, authenticator: AppLockTests.FakeAuthentication())
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = PrivacyController(lock: lock)
        window.rootViewController = controller
        window.alpha = 0.8
        let originalAlpha = window.alpha
        window.isHidden = false
        controller.view.layoutIfNeeded()
        controller.viewDidAppear(false)
        let draft = UITextField(frame: CGRect(x: 20, y: 100, width: 200, height: 40))
        draft.text = "Spesa non salvata: 12,50"
        controller.view.addSubview(draft)
        defer { controller.detach(); window.isHidden = true; window.rootViewController = nil }

        await lock.setEnabled(true)
        lock.sceneChanged(.inactive)
        controller.refresh()
        #expect(window.alpha == 0)
        #expect(window.accessibilityElementsHidden)
        #expect(scene.windows.contains { !$0.isHidden && $0.windowLevel > .alert })
        #expect(draft.text == "Spesa non salvata: 12,50")

        lock.sceneChanged(.active)
        controller.refresh()
        #expect(window.alpha == originalAlpha)
        #expect(!window.accessibilityElementsHidden)
        // A different scene becoming active must not expose this inactive window.
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: scene)
        lock.sceneChanged(.active)
        controller.refresh()
        #expect(window.alpha == 0)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        #expect(window.alpha == originalAlpha)

        lock.sceneChanged(.background)
        lock.sceneChanged(.active)
        controller.refresh()
        #expect(window.alpha == 0 && lock.isLocked)
        await lock.unlock()
        controller.refresh()
        #expect(window.alpha == originalAlpha && !window.accessibilityElementsHidden)
        #expect(draft.superview === controller.view)
        #expect(draft.text == "Spesa non salvata: 12,50")
    }
}
#endif
