import SwiftUI

/// A separate native window covers presented sheets as well as the main view.
/// The financial view hierarchy stays mounted, preserving unsaved drafts.
private struct PrivacyWindowContent: View {
    let lock: AppLock
    var body: some View {
        Group {
            if lock.isLocked {
                AppLockScreen().environment(lock)
            } else {
                VStack(spacing: 16) {
                    FormiLogo(size: 72)
                    Text("Formi").font(.title.bold())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ForgiaPalette.canvas)
            }
        }
    }
}

#if os(iOS)
import UIKit

struct AppPrivacyGuard: UIViewControllerRepresentable {
    let lock: AppLock
    let concealed: Bool
    func makeUIViewController(context: Context) -> PrivacyController { PrivacyController(lock: lock) }
    func updateUIViewController(_ controller: PrivacyController, context: Context) { controller.refresh() }
    static func dismantleUIViewController(_ controller: PrivacyController, coordinator: ()) { controller.detach() }
}

@MainActor
final class PrivacyController: UIViewController {
    let lock: AppLock
    private weak var protectedWindow: UIWindow?
    private var cover: UIWindow?
    private var originalAlpha: CGFloat = 1
    private var originalAccessibilityHidden = false
    private var hidingContent = false
    private var sceneIsInactive = true

    init(lock: AppLock) { self.lock = lock; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); attach() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); attach() }

    private func attach() {
        guard let window = view.window, let scene = window.windowScene, protectedWindow !== window else { return }
        detach()
        protectedWindow = window
        sceneIsInactive = scene.activationState != .foregroundActive
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        cover.backgroundColor = .systemBackground
        cover.rootViewController = UIHostingController(rootView: PrivacyWindowContent(lock: lock))
        self.cover = cover
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(inactive), name: UIScene.willDeactivateNotification, object: scene)
        center.addObserver(self, selector: #selector(background), name: UIScene.didEnterBackgroundNotification, object: scene)
        center.addObserver(self, selector: #selector(active), name: UIScene.didActivateNotification, object: scene)
        center.addObserver(self, selector: #selector(disconnected), name: UIScene.didDisconnectNotification, object: scene)
        refresh()
    }

    @objc private func inactive() { sceneIsInactive = true; lock.sceneChanged(.inactive); refresh() }
    @objc private func background() { sceneIsInactive = true; lock.sceneChanged(.background); refresh() }
    @objc private func disconnected() { detach() }
    @objc private func active() { sceneIsInactive = false; lock.sceneChanged(.active); refresh() }

    func refresh() {
        guard let window = protectedWindow, let cover else { return }
        if lock.shouldConceal || (lock.isEnabled && sceneIsInactive) {
            if !hidingContent {
                originalAlpha = window.alpha
                originalAccessibilityHidden = window.accessibilityElementsHidden
                window.endEditing(true)
                hidingContent = true
            }
            cover.frame = window.windowScene?.coordinateSpace.bounds ?? window.bounds
            cover.isHidden = false
            window.alpha = 0
            window.accessibilityElementsHidden = true
        } else {
            restoreContent()
            cover.isHidden = true
        }
    }

    private func restoreContent() {
        guard hidingContent else { return }
        protectedWindow?.alpha = originalAlpha
        protectedWindow?.accessibilityElementsHidden = originalAccessibilityHidden
        hidingContent = false
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        restoreContent()
        cover?.isHidden = true
        cover?.rootViewController = nil
        cover = nil
        protectedWindow = nil
    }
}
#elseif os(macOS)
import AppKit

struct AppPrivacyGuard: NSViewRepresentable {
    let lock: AppLock
    let concealed: Bool
    func makeNSView(context: Context) -> PrivacyAnchor { PrivacyAnchor(lock: lock) }
    func updateNSView(_ view: PrivacyAnchor, context: Context) { view.refresh() }
    static func dismantleNSView(_ view: PrivacyAnchor, coordinator: ()) { view.detach() }
}

@MainActor
final class PrivacyAnchor: NSView {
    let lock: AppLock
    private weak var protectedWindow: NSWindow?
    private var cover: NSPanel?
    private var hiddenWindows: [(NSWindow, CGFloat, Bool)] = []

    init(lock: AppLock) { self.lock = lock; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else { return }
        protectedWindow = window
        let cover = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        cover.isFloatingPanel = false
        cover.hidesOnDeactivate = false
        cover.isReleasedWhenClosed = false
        cover.contentView = NSHostingView(rootView: PrivacyWindowContent(lock: lock))
        self.cover = cover
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(inactive), name: NSApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(active), name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: NSWindow.didResizeNotification, object: window)
        center.addObserver(self, selector: #selector(refresh), name: NSWindow.didMoveNotification, object: window)
        center.addObserver(self, selector: #selector(closing), name: NSWindow.willCloseNotification, object: window)
        refresh()
    }

    @objc private func inactive() { lock.sceneChanged(.inactive); refresh() }
    @objc private func active() { lock.sceneChanged(.active); refresh() }

    @objc private func closing() { detach() }

    @objc func refresh() {
        guard let window = protectedWindow, let cover else { return }
        if lock.shouldConceal {
            if hiddenWindows.isEmpty {
                window.makeFirstResponder(nil)
                // Include the attached sheet, whose content is outside the main window.
                hiddenWindows = ([window] + (window.childWindows ?? [])).map { ($0, $0.alphaValue, $0.contentView?.isAccessibilityHidden() ?? false) }
                window.addChildWindow(cover, ordered: .above)
            }
            cover.setFrame(window.frame, display: true)
            cover.orderFront(nil)
            for (protected, _, _) in hiddenWindows {
                protected.alphaValue = 0
                protected.contentView?.setAccessibilityHidden(true)
            }
        } else {
            restoreContent()
            window.removeChildWindow(cover)
            cover.orderOut(nil)
        }
    }

    private func restoreContent() {
        for (window, alpha, hidden) in hiddenWindows {
            window.alphaValue = alpha
            window.contentView?.setAccessibilityHidden(hidden)
        }
        hiddenWindows.removeAll()
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        restoreContent()
        if let cover { protectedWindow?.removeChildWindow(cover); cover.orderOut(nil) }
        cover = nil
        protectedWindow = nil
    }
}
#endif
