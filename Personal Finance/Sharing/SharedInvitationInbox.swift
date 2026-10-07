import Foundation
import Observation
import CloudKit
import FinanceCore

/// Platform callbacks only enqueue metadata. They never contact CloudKit.
@MainActor @Observable
final class SharedInvitationInbox {
    static let shared = SharedInvitationInbox()
    struct Entry: Identifiable {
        let scope: SharedBookScope
        let metadata: CKShare.Metadata
        var id: String { scope.key }
        var title: String { metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Libro condiviso" }
    }
    private(set) var pending: [Entry] = []
    var error: String?
    private let defaults: UserDefaults
    private let key = "forgia.pendingCloudInvitations.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.array(forKey: key) as? [Data] else { return }
        for data in stored {
            do {
                guard let metadata = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.Metadata.self, from: data) else { continue }
                let scope = try SharedBookInvitation.scope(metadata: metadata)
                if !pending.contains(where: { $0.id == scope.key }) { pending.append(Entry(scope: scope, metadata: metadata)) }
            } catch { self.error = "Un invito salvato non è leggibile. Apri nuovamente il link originale." }
        }
    }
    func receive(_ metadata: CKShare.Metadata) {
        do {
            let scope = try SharedBookInvitation.scope(metadata: metadata)
            var next = pending.filter { $0.id != scope.key }
            next.append(Entry(scope: scope, metadata: metadata))
            try persist(next)
            pending = next
        } catch { self.error = "L’invito non è stato salvato. Verifica che il link riguardi un libro Forgia e riaprilo." }
    }
    func remove(_ id: String) {
        do {
            let next = pending.filter { $0.id != id }
            try persist(next); pending = next
        } catch { self.error = "Non è stato possibile aggiornare gli inviti salvati." }
    }
    private func persist(_ entries: [Entry]) throws {
        let data = try entries.map { try NSKeyedArchiver.archivedData(withRootObject: $0.metadata, requiringSecureCoding: true) }
        defaults.set(data, forKey: key)
    }
}

#if os(iOS)
import UIKit
final class SharedInvitationAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let metadata = options.cloudKitShareMetadata { SharedInvitationInbox.shared.receive(metadata) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SharedInvitationSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharedInvitationInbox.shared.receive(cloudKitShareMetadata)
    }
}
final class SharedInvitationSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { SharedInvitationInbox.shared.receive(metadata) }
        if let shortcut = connectionOptions.shortcutItem { FinanceIconQuickAction.receive(shortcut.type) }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(FinanceIconQuickAction.receive(shortcutItem.type))
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharedInvitationInbox.shared.receive(cloudKitShareMetadata)
    }
}
#elseif os(macOS)
import AppKit
import SwiftUI
@MainActor
final class SharedInvitationAppDelegate: NSObject, NSApplicationDelegate {
    private let shortcutInbox: FinanceShortcutInbox
    private let mainWindows = NSHashTable<NSWindow>.weakObjects()
    private var openMainWindow: (() -> Void)?

    override convenience init() { self.init(inbox: .shared) }
    init(inbox: FinanceShortcutInbox) {
        shortcutInbox = inbox
        super.init()
    }

    func registerMainWindow(_ window: NSWindow, open: @escaping () -> Void) {
        mainWindows.add(window)
        openMainWindow = open
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Nuova spesa", action: #selector(newExpenseFromDock), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }

    @objc private func newExpenseFromDock(_ sender: Any?) {
        FinanceIconQuickAction.receive(FinanceIconQuickAction.newExpenseType, inbox: shortcutInbox)
        if let window = mainWindows.allObjects.first(where: { $0.isVisible || $0.isMiniaturized }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharedInvitationInbox.shared.receive(cloudKitShareMetadata)
    }
}

/// Capture the SwiftUI scene action so the Dock also works after the last window closes.
struct FinanceDockWindowBridge: NSViewRepresentable {
    let delegate: SharedInvitationAppDelegate
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ view: WindowProbe, context: Context) {
        view.register = { window in
            delegate.registerMainWindow(window) { openWindow(id: "finance") }
        }
        if let window = view.window { view.register?(window) }
    }

    final class WindowProbe: NSView {
        var register: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { register?(window) }
        }
    }
}
#endif
