//
//  Personal_FinanceApp.swift
//  Personal Finance
//
//  Created by Francesco Bianco on 24/08/25.
//

import SwiftUI
import SwiftData
import FinanceCore
import CloudKit

@main
struct Personal_FinanceApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SharedInvitationAppDelegate.self) private var invitationDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(SharedInvitationAppDelegate.self) private var invitationDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var recurrenceReminders = RecurrenceReminders()
    @State private var appLock = AppLock(onPrivacyChanged: { enabled in
        if enabled {
            WidgetSnapshotPublisher.redact()
            #if os(iOS)
            WatchPhoneBridge.shared.redact()
            #endif
        }
    })
    @State private var navigationRouter = NavigationRouter()
    @State private var dataStorageManager = DataStorageManager.shared
    @State private var cloudKitHelper = CloudKitHelper.shared
    @State private var isInitialized = false
    @State private var initializationError: Error?

    init() {
        ReminderNotificationRouter.shared.install()
        FinanceShortcuts.updateAppShortcutParameters()
        #if os(iOS)
        WatchPhoneBridge.shared.start()
        #endif
        if UserDefaults.standard.bool(forKey: AppLock.preferenceKey) || !UserDefaults.standard.bool(forKey: WidgetSnapshotPublisher.preferenceKey) {
            WidgetSnapshotPublisher.redact()
        }
    }

    var body: some Scene {
        WindowGroup(id: "finance") {
            Group {
                if !appLock.hasUnlockedInSession {
                    AppLockScreen()
                } else if let error = initializationError {
                    ErrorView(error: error) {
                        Task {
                            await initializeApp()
                        }
                    }
                } else if isInitialized, let container = dataStorageManager.currentContainer {
                    appContent
                        .id(dataStorageManager.containerGeneration)
                        .safeAreaInset(edge: .top) { SharedInvitationNotice() }
                        .environment(navigationRouter)
                        .environment(dataStorageManager)
                        .modelContainer(container)
                        .background { SharedBookRefreshObserver().environment(dataStorageManager) }
                        .overlay(alignment: .bottom) {
                            BackgroundOperationBanner()
                        }
                } else {
                    LoadingView()
                }
            }
            .background { AppPrivacyGuard(lock: appLock, concealed: appLock.shouldConceal) }
            .environment(recurrenceReminders)
            .environment(appLock)
            .onOpenURL { url in
                guard let route = FinanceWidgetRoute(url: url) else { return }
                do { try FinanceShortcutInbox.shared.submit(.widget(route)) }
                catch { FinanceShortcutInbox.shared.reportError("Completa la richiesta già aperta in Forgia.") }
            }
            .onChange(of: scenePhase) { _, phase in appLock.sceneChanged(phase) }
            .task {
                await initializeApp()
            }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        .commands { FinanceMacCommands() }
        #endif
    }
    
    // MARK: - App Initialization

    @ViewBuilder private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_SHARED_STATUS") {
            SharedBookStatusFixture()
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_RECURRENCE_END") {
            EditExpenseBudgetFixture(entry: .recurrence)
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_CREATE_EXPENSE_BUDGET") {
            EditExpenseBudgetFixture(entry: .create)
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_QUICK_EXPENSE_BUDGET") {
            EditExpenseBudgetFixture(entry: .quick)
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_EDIT_EXPENSE_BUDGET") {
            EditExpenseBudgetFixture()
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_BALANCE_RECONCILIATION") {
            BalanceReconciliationFixture()
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_CURRENCY_SELECTION") {
            CurrencySelectionFixture()
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_SHARED_LEAVE") {
            SharedBookLeaveFixture()
        } else if ProcessInfo.processInfo.arguments.contains("UITEST_SHARED_CONFLICT") {
            SharedBookConflictFixture()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }
    
    @MainActor
    private func initializeApp() async {
        do {
            // Check and perform migration if needed
            if dataStorageManager.needsMigration() {
                try dataStorageManager.performMigration()
            }
            
            // Initialize the container
            try await dataStorageManager.initializeContainer()
            
            isInitialized = true
            initializationError = nil
        } catch {
            print("Failed to initialize app: \(error)")
            initializationError = error
            isInitialized = false
        }
    }
}

// MARK: - Supporting Views

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Initializing Personal Finance...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ErrorView: View {
    let error: Error
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Initialization Failed")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
