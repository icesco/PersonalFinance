#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import FinanceCore
import Testing
@testable import Personal_Finance

@MainActor
struct MacWorkspaceTests {
    @Test(arguments: [false, true])
    func dockActionOpensExpenseWithMainWindowOpenOrClosed(closed: Bool) throws {
        let inbox = FinanceShortcutInbox()
        let delegate = SharedInvitationAppDelegate(inbox: inbox)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var reopened = false
        delegate.registerMainWindow(window) { reopened = true }
        window.orderFront(nil)
        if closed { window.close() }
        defer { window.close() }
        let menu = try #require(delegate.applicationDockMenu(NSApp))
        menu.performActionForItem(at: 0)
        #expect(inbox.pending == .expense(amount: "", description: ""))
        #expect(reopened == closed)
        if !closed { #expect(window.isVisible) }
    }

    @Test func draftRetainsBookAndInputsWhenMainWindowChangesBook() throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let original = Account(name: "Personale")
        let other = Account(name: "Famiglia")
        container.mainContext.insert(original)
        container.mainContext.insert(other)
        let state = AppStateManager(persistsSelection: false)
        state.selectedAccount = original
        state.quickTransactionType = .income
        state.quickTransactionIsPlanned = true
        state.quickTransactionPrefill = ("42,50", "Rimborso")
        let persistedBook = UserDefaults.standard.string(forKey: "selectedAccountID")
        let draft = state.windowSnapshot()
        state.selectedAccount = other
        state.quickTransactionType = .expense
        state.quickTransactionPrefill = nil

        #expect(draft.selectedAccount?.id == original.id)
        #expect(draft.quickTransactionType == .income)
        #expect(draft.quickTransactionIsPlanned)
        #expect(draft.quickTransactionPrefill?.amount == "42,50")
        #expect(draft.quickTransactionPrefill?.description == "Rimborso")
        #expect(UserDefaults.standard.string(forKey: "selectedAccountID") == persistedBook)
    }

    @Test func recurringWindowReceivesQueryAndPrivacyEnvironment() async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let state = AppStateManager(persistsSelection: false)
        let content = FinanceTaskContent(
            presented: NavigationStack { RecurringManagementView(contoIDs: []) },
            state: state, lock: AppLock(), storage: DataStorageManager.makeLocalTestStorage(),
            reminders: RecurrenceReminders(), router: NavigationRouter(), modelContext: container.mainContext
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        #expect(window.contentView?.fittingSize.width ?? 0 > 0)
    }

    enum DesktopTask: String, CaseIterable {
        case expense, income, transfer, transactionDetail, editTransaction, recurring
        case budgets, newBudget, editBudget, budgetDetail, newAccount, editAccount
        case reconcile, csvImport, csvExport, settings
    }

    @Test(arguments: DesktopTask.allCases)
    func everyDesktopTaskLoadsAndClosesWithItsFullEnvironment(route: DesktopTask) async throws {
        let container = try FinanceCoreModule.createModelContainer(enableCloudKit: false, inMemory: true)
        let context = container.mainContext
        let book = Account(name: "Prova finestre")
        let bank = Conto(name: "Banca", type: .checking, initialBalance: 1000)
        let savings = Conto(name: "Risparmi", type: .savings)
        context.insert(book)
        context.insert(bank)
        context.insert(savings)
        bank.account = book
        savings.account = book
        let transaction = FinanceTransaction(amount: 25, type: .expense,
            transactionDescription: "Ricorrenza di prova", isRecurring: true, recurrenceFrequency: .monthly)
        context.insert(transaction)
        transaction.setFromConto(bank)
        let budget = FinanceBudget(name: "Budget di prova", amount: 100, period: .monthly)
        context.insert(budget)
        budget.account = book
        try context.save()
        let state = AppStateManager(persistsSelection: false)
        state.selectedAccount = book
        state.quickTransactionType = route == .income ? .income : .expense
        let presented: AnyView
        switch route {
        case .expense, .income: presented = AnyView(QuickTransactionModal())
        case .transfer: presented = AnyView(CreateTransactionView(conto: nil, transactionType: .transfer))
        case .transactionDetail: presented = AnyView(NavigationStack { TransactionDetailView(transaction: transaction, showsCloseButton: true) })
        case .editTransaction: presented = AnyView(EditTransactionView(transaction: transaction))
        case .recurring: presented = AnyView(NavigationStack { RecurringManagementView(contoIDs: [bank.id]) })
        case .budgets: presented = AnyView(BudgetView())
        case .newBudget: presented = AnyView(CreateBudgetView(account: book))
        case .editBudget: presented = AnyView(CreateBudgetView(account: book, budget: budget))
        case .budgetDetail: presented = AnyView(BudgetDetailView(budget: budget))
        case .newAccount: presented = AnyView(CreateContoView(account: book))
        case .editAccount: presented = AnyView(EditContoView(conto: bank))
        case .reconcile: presented = AnyView(BalanceReconciliationView(account: book))
        case .csvImport: presented = AnyView(CSVImportView())
        case .csvExport: presented = AnyView(CSVExportView())
        case .settings: presented = AnyView(SettingsView())
        }
        let content = FinanceTaskContent(presented: presented, state: state, lock: AppLock(),
            storage: DataStorageManager.makeLocalTestStorage(), reminders: RecurrenceReminders(),
            router: NavigationRouter(), modelContext: context)
        let id = UUID()
        var showing = true
        FinanceTaskWindows.shared.insert(.init(title: route.rawValue, width: 800, height: 720,
            content: AnyView(content), onClose: { showing = false }), id: id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FinanceTaskWindow(id: id))
        defer { window.close(); FinanceTaskWindows.shared.finish(id) }
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        #expect(window.contentView?.fittingSize.width ?? 0 > 0)
        #expect(showing)
        window.performClose(nil)
        await Task.yield()
        #expect(!showing)
        #expect(FinanceTaskWindows.shared.task(for: id) == nil)
    }

    @Test func editsInNestedWindowsRefreshTheMainWindowImmediately() {
        let main = AppStateManager(persistsSelection: false)
        main.selectedAccount = Account(name: "Libro iniziale")
        let detail = main.windowSnapshot()
        let editor = detail.windowSnapshot()
        editor.triggerDataRefresh()
        #expect(editor.dataRefreshTrigger == 1)
        #expect(main.dataRefreshTrigger == 1)
        // The list refreshes while the detail stays open, and the editor never selects another book.
        #expect(main.selectedAccount === editor.selectedAccount)
    }

    @Test func independentTaskWindowsConcealTogetherAndKeepDrafts() async throws {
        let name = "mac-task-privacy-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let lock = AppLock(defaults: defaults, authenticator: AppLockTests.FakeAuthentication())
        let windows = (0..<2).map { _ in
            NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                     styleMask: [.titled], backing: .buffered, defer: false)
        }
        let anchors = windows.map { window in
            window.isReleasedWhenClosed = false
            let anchor = PrivacyAnchor(lock: lock)
            let draft = NSTextField(string: "Bozza non salvata")
            anchor.addSubview(draft)
            window.contentView = anchor
            return anchor
        }
        defer {
            for (window, anchor) in zip(windows, anchors) { anchor.detach(); window.close() }
        }
        await lock.setEnabled(true)
        lock.sceneChanged(.inactive)
        anchors.forEach { $0.refresh() }
        #expect(windows.allSatisfy { $0.alphaValue == 0 })
        #expect(anchors.allSatisfy { $0.isAccessibilityHidden() })
        lock.sceneChanged(.active)
        await lock.unlock()
        anchors.forEach { $0.refresh() }
        #expect(windows.allSatisfy { $0.alphaValue == 1 })
        #expect(anchors.allSatisfy { ($0.subviews.first as? NSTextField)?.stringValue == "Bozza non salvata" })
    }

    @Test func nativeWindowCloseReleasesPresentationAndAllowsReopening() async throws {
        let id = UUID()
        var showing = true
        FinanceTaskWindows.shared.insert(.init(title: "Bozza di prova", width: 640, height: 720,
            content: AnyView(Text("Importo non salvato: 12,50")), onClose: { showing = false }), id: id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FinanceTaskWindow(id: id))
        defer { window.close(); FinanceTaskWindows.shared.finish(id) }
        window.contentView?.layoutSubtreeIfNeeded()
        await Task.yield()
        #expect(showing)
        window.performClose(nil)
        await Task.yield()
        #expect(!showing)
        #expect(FinanceTaskWindows.shared.task(for: id) == nil)
    }

    @Test func finishingOneTaskKeepsAnotherDraftOpenAndRefreshesOnlyItsOrigin() {
        let first = UUID(), second = UUID()
        let state = AppStateManager(persistsSelection: false)
        var firstClosed = 0
        var secondClosed = 0
        let windows = FinanceTaskWindows()
        windows.insert(.init(title: "Spesa", width: 640, height: 720, content: AnyView(Text("Draft A")), onClose: {
            firstClosed += 1
            state.triggerDataRefresh()
        }), id: first)
        windows.insert(.init(title: "Budget", width: 640, height: 720, content: AnyView(Text("Draft B")), onClose: {
            secondClosed += 1
        }), id: second)
        windows.finish(first)
        windows.finish(first)
        #expect(firstClosed == 1)
        #expect(secondClosed == 0)
        #expect(state.dataRefreshTrigger == 1)
        #expect(windows.task(for: first) == nil)
        #expect(windows.task(for: second)?.title == "Budget")
        windows.finish(second)
        #expect(secondClosed == 1)
    }
}
#endif
