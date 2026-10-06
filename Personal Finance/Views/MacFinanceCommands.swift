#if os(macOS)
import SwiftUI
import AppKit
import Observation

@MainActor @Observable
private final class FinanceCommandWindow {
    weak var window: NSWindow?
    var hasSheet = false
}

@MainActor
struct FinanceMenuContext {
    let state: AppStateManager
    let lock: AppLock
    fileprivate let scope: FinanceCommandWindow
    var enabled: Bool {
        !lock.shouldConceal && !scope.hasSheet && scope.window != nil && scope.window?.attachedSheet == nil &&
        !state.showingQuickTransaction && !state.showingTransferSheet &&
        !state.showingAccountSelection && !state.showingAccountCreation
    }
    func newExpense() {
        guard enabled else { return }
        state.presentQuickTransaction()
    }
    func select(_ tab: AppTab) {
        guard enabled else { return }
        state.selectTab(tab)
    }
}

private struct FinanceMenuContextKey: FocusedValueKey {
    typealias Value = FinanceMenuContext
}
extension FocusedValues {
    var financeMenuContext: FinanceMenuContext? {
        get { self[FinanceMenuContextKey.self] }
        set { self[FinanceMenuContextKey.self] = newValue }
    }
}

struct FinanceMacCommands: Commands {
    @FocusedValue(\.financeMenuContext) private var context
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nuova spesa") { context?.newExpense() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(context?.enabled != true)
            Button("Nuova finestra") { openWindow(id: "finance") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Vai") {
            Group {
                Button("Oggi") { context?.select(.dashboard) }.keyboardShortcut("1", modifiers: .command)
                Button("Analisi") { context?.select(.analysis) }.keyboardShortcut("2", modifiers: .command)
                Button("Movimenti") { context?.select(.transactions) }.keyboardShortcut("3", modifiers: .command)
                Button("Pianifica") { context?.select(.planning) }.keyboardShortcut("4", modifiers: .command)
                Button("Impostazioni") { context?.select(.settings) }.keyboardShortcut("5", modifiers: .command)
                Button("Cerca movimenti") { context?.select(.search) }.keyboardShortcut("f", modifiers: .command)
            }
            .disabled(context?.enabled != true)
        }
    }
}

struct FinanceMacCommandScope: ViewModifier {
    @Environment(AppStateManager.self) private var state
    @Environment(AppLock.self) private var lock
    @State private var scope = FinanceCommandWindow()
    func body(content: Content) -> some View {
        content
            .background { FinanceCommandWindowProbe(scope: scope).frame(width: 0, height: 0) }
            .focusedSceneValue(\.financeMenuContext, FinanceMenuContext(state: state, lock: lock, scope: scope))
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification)) { notification in
                guard let window = notification.object as? NSWindow, window === scope.window else { return }
                scope.hasSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { notification in
                guard let window = notification.object as? NSWindow, window === scope.window else { return }
                scope.hasSheet = false
            }
    }
}

private struct FinanceCommandWindowProbe: NSViewRepresentable {
    let scope: FinanceCommandWindow
    func makeNSView(context: Context) -> Probe { Probe(scope: scope) }
    func updateNSView(_ view: Probe, context: Context) {}
    final class Probe: NSView {
        let scope: FinanceCommandWindow
        init(scope: FinanceCommandWindow) { self.scope = scope; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let currentWindow = window
            Task { @MainActor [weak self] in
                guard let self else { return }
                scope.window = currentWindow
                scope.hasSheet = currentWindow?.attachedSheet != nil
            }
        }
    }
}
#endif
