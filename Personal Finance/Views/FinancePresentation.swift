import SwiftUI
import SwiftData
import FinanceCore

// Long tasks use independent windows on Mac and retain their sheet behavior on iOS.
extension View {
    func financePresentation<Presented: View>(
        isPresented: Binding<Bool>, title: String,
        width: CGFloat = 640, height: CGFloat = 720, pinsBook: Bool = true,
        @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
        #if os(macOS)
        modifier(FinanceWindowPresentation(isPresented: isPresented, title: title,
                                          width: width, height: height, pinsBook: pinsBook, presented: content))
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    func financePresentation<Item: Identifiable, Presented: View>(
        item: Binding<Item?>, title: String,
        width: CGFloat = 640, height: CGFloat = 720,
        @ViewBuilder content: @escaping (Item) -> Presented
    ) -> some View {
        #if os(macOS)
        modifier(FinanceItemWindowPresentation(item: item, title: title,
                                               width: width, height: height, presented: content))
        #else
        sheet(item: item, content: content)
        #endif
    }
}

/// Dismiss the presented scene directly, even after its originating screen has disappeared.
struct FinanceTaskDoneButton: View {
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.financeTaskID) private var taskID
    #endif
    var body: some View {
        Button("Fine") {
            #if os(macOS)
            if let taskID { dismissWindow(id: "finance-task", value: taskID) }
            else { dismiss() }
            #else
            dismiss()
            #endif
        }
    }
}

#if os(macOS)
import AppKit

extension EnvironmentValues {
    @Entry var financeTaskID: UUID? = nil
}

@MainActor
final class FinanceTaskWindows {
    static let shared = FinanceTaskWindows()
    struct Task {
        let title: String
        let width: CGFloat
        let height: CGFloat
        let content: AnyView
        let onClose: () -> Void
    }
    private var tasks: [UUID: Task] = [:]
    func insert(_ task: Task, id: UUID) { tasks[id] = task }
    func task(for id: UUID) -> Task? { tasks[id] }
    func finish(_ id: UUID) {
        guard let task = tasks.removeValue(forKey: id) else { return }
        task.onClose()
    }
}

@MainActor
private struct FinanceWindowEnvironment: DynamicProperty {
    @Environment(AppStateManager.self) private var state
    @Environment(AppLock.self) private var lock
    @Environment(DataStorageManager.self) private var storage
    @Environment(RecurrenceReminders.self) private var reminders
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    var concealed: Bool { lock.shouldConceal }

    func register<Presented: View>(
        id: UUID, title: String, width: CGFloat, height: CGFloat,
        pinsBook: Bool = true, presented: Presented, onClose: @escaping () -> Void
    ) {
        let origin = state
        let root = FinanceTaskContent(
            presented: presented, state: pinsBook ? state.windowSnapshot() : state,
            lock: lock, storage: storage, reminders: reminders, router: router, modelContext: modelContext
        )
        FinanceTaskWindows.shared.insert(.init(
            title: title, width: width, height: height, content: AnyView(root),
            onClose: {
                onClose()
                origin.triggerDataRefresh()
            }
        ), id: id)
    }
}

private struct FinanceWindowPresentation<Presented: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let width: CGFloat
    let height: CGFloat
    let pinsBook: Bool
    @ViewBuilder let presented: () -> Presented
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private var windowEnvironment = FinanceWindowEnvironment()
    @State private var taskID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, _ in synchronize() }
            .onChange(of: windowEnvironment.concealed) { _, concealed in
                if !concealed { synchronize() }
            }
    }

    private func synchronize() {
        if isPresented, taskID == nil, !windowEnvironment.concealed {
            let id = UUID()
            taskID = id
            let presentation = $isPresented
            windowEnvironment.register(id: id, title: title, width: width, height: height,
                                       pinsBook: pinsBook, presented: presented()) {
                taskID = nil
                presentation.wrappedValue = false
            }
            openWindow(id: "finance-task", value: id)
        } else if !isPresented, let id = taskID {
            dismissWindow(id: "finance-task", value: id)
        }
    }
}

/// Capture each item as it opens. Selecting another row must never replace an unsaved draft.
private struct FinanceItemWindowPresentation<Item: Identifiable, Presented: View>: ViewModifier {
    @Binding var item: Item?
    let title: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let presented: (Item) -> Presented
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private var windowEnvironment = FinanceWindowEnvironment()
    @State private var taskIDs: [Item.ID: UUID] = [:]
    @State private var activeTaskID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id, initial: true) { _, _ in synchronize() }
            .onChange(of: windowEnvironment.concealed) { _, concealed in
                if !concealed { synchronize() }
            }
    }

    private func synchronize() {
        guard let value = item else {
            if let id = activeTaskID { dismissWindow(id: "finance-task", value: id) }
            return
        }
        guard !windowEnvironment.concealed else { return }
        let itemID = value.id
        if let id = taskIDs[itemID] {
            activeTaskID = id
            openWindow(id: "finance-task", value: id)
            return
        }
        let id = UUID()
        taskIDs[itemID] = id
        activeTaskID = id
        let selection = $item
        windowEnvironment.register(id: id, title: title, width: width, height: height, presented: presented(value)) {
            taskIDs[itemID] = nil
            if activeTaskID == id { activeTaskID = nil }
            if selection.wrappedValue?.id == itemID { selection.wrappedValue = nil }
        }
        openWindow(id: "finance-task", value: id)
    }
}

/// Environment modifiers must wrap both the task and its privacy modifier.
/// A modifier appended after injection cannot read the environment of its content.
struct FinanceTaskContent<Presented: View>: View {
    let presented: Presented
    let state: AppStateManager
    let lock: AppLock
    let storage: DataStorageManager
    let reminders: RecurrenceReminders
    let router: NavigationRouter
    let modelContext: ModelContext

    var body: some View {
        presented
            .modifier(FinanceTaskPrivacy())
            .environment(state)
            .environment(lock)
            .environment(storage)
            .environment(reminders)
            .environment(router)
            .environment(\.modelContext, modelContext)
            .environment(\.locale, Locale(identifier: "it_IT"))
            .environment(\.cardTint, state.themeManager.currentTheme.color)
            .environment(\.tintedBackgrounds, state.tintedBackgrounds)
            .tint(state.themeManager.currentTheme.color)
    }
}

private struct FinanceTaskPrivacy: ViewModifier {
    @Environment(AppLock.self) private var lock
    @Environment(DataStorageManager.self) private var storage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.financeTaskID) private var taskID
    func body(content: Content) -> some View {
        content
            .background { AppPrivacyGuard(lock: lock, concealed: lock.shouldConceal) }
            .overlay { if lock.isLocked { AppLockScreen() } }
            .onChange(of: storage.containerGeneration) { _, _ in
                if let taskID { dismissWindow(id: "finance-task", value: taskID) }
                else { dismiss() }
            }
    }
}

struct FinanceTaskWindow: View {
    let id: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let id, let task = FinanceTaskWindows.shared.task(for: id) {
            task.content
                .environment(\.financeTaskID, id)
                .frame(minWidth: min(task.width, 480), minHeight: 420)
                .frame(idealWidth: task.width, idealHeight: task.height)
                .navigationTitle(task.title)
                .background { FinanceTaskCloseObserver(id: id).frame(width: 0, height: 0) }
                .onDisappear { FinanceTaskWindows.shared.finish(id) }
        } else {
            ContentUnavailableView("Finestra non disponibile", systemImage: "macwindow")
                .toolbar { Button("Chiudi") { dismiss() } }
        }
    }
}

/// Titlebar close must release the draft even if SwiftUI retains the scene's view hierarchy.
private struct FinanceTaskCloseObserver: NSViewRepresentable {
    let id: UUID
    func makeNSView(context: Context) -> Anchor { Anchor(id: id) }
    func updateNSView(_ view: Anchor, context: Context) {}
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.detach() }

    final class Anchor: NSView {
        let id: UUID
        private var observer: NSObjectProtocol?
        init(id: UUID) { self.id = id; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [id] _ in
                MainActor.assumeIsolated { FinanceTaskWindows.shared.finish(id) }
            }
        }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
#endif
