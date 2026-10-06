#if os(macOS)
import AppKit
import Testing
@testable import Personal_Finance

@MainActor
struct MacPrivacyWindowTests {
    @Test func nativeShieldCoversChildWindowAndPreservesDraft() async throws {
        let name = "mac-privacy-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let lock = AppLock(defaults: defaults, authenticator: AppLockTests.FakeAuthentication())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let child = NSPanel(contentRect: window.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        child.isReleasedWhenClosed = false
        let anchor = PrivacyAnchor(lock: lock)
        let draft = NSTextField(string: "Spesa non salvata: 12,50")
        child.contentView = draft
        window.contentView = anchor
        window.addChildWindow(child, ordered: .above)
        window.alphaValue = 0.8
        child.alphaValue = 0.9
        let originalAlpha = window.alphaValue
        let childAlpha = child.alphaValue
        defer {
            anchor.detach()
            window.removeChildWindow(child)
            child.close()
            window.close()
        }

        await lock.setEnabled(true)
        lock.sceneChanged(.inactive)
        anchor.refresh()
        #expect(lock.isLocked)
        #expect(window.alphaValue == 0 && child.alphaValue == 0)
        #expect(anchor.isAccessibilityHidden() && draft.isAccessibilityHidden())
        #expect(window.childWindows?.contains { $0 !== child && $0.isVisible } == true)

        lock.sceneChanged(.active)
        anchor.refresh()
        #expect(window.alphaValue == 0)
        await lock.unlock()
        anchor.refresh()
        #expect(window.alphaValue == originalAlpha && child.alphaValue == childAlpha)
        #expect(!anchor.isAccessibilityHidden() && !draft.isAccessibilityHidden())
        #expect(child.contentView === draft)
        #expect(draft.stringValue == "Spesa non salvata: 12,50")
    }
}
#endif
